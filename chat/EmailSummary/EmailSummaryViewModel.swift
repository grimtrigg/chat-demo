import Combine
import Foundation
import FoundationModels
import GoogleSignIn
import SwiftUI

extension EmailSummaryViewModel {
    enum Action {
        case system(SystemAction)
        case user(UserAction)
        case workflowOutput(WorkflowOutputAction)
    }
    
    enum SystemAction {
        case onAppear
    }
    
    enum UserAction {
        case signInTapped
        case retryTapped
    }
    
    enum WorkflowOutputAction {
        case signInResult(Result<Void, Error>)
        case emailsFetched(Result<[GmailAPIClient.Email], Error>)
        case partialSummaryResult(Result<([GmailAPIClient.Email], String), Error>)
        case summaryResult(Result<([GmailAPIClient.Email], String), Error>)
    }
}

extension EmailSummaryViewModel {
    enum Effect {
        case workflowInput(WorkflowInputEffect)
        case haptic(HapticEffect)
        case analytics(AnalyticsEffect)
    }
    
    enum WorkflowInputEffect {
        case signIn
        case fetchEmails
        case summarize(emails: [GmailAPIClient.Email])
    }
    
    enum HapticEffect {}
    enum AnalyticsEffect {}
}

final class EmailSummaryViewModelFactory {
    static func make() -> EmailSummaryViewModel {
        let session = ChatLanguageModelSession()
        return EmailSummaryViewModel(
            session: session
        )
    }
}

final class EmailSummaryViewModel: ObservableObject {
    struct State: Equatable {
        enum Screen: Equatable {
            case signedOut
            case fetching
            case summarizing(
                emails: [GmailAPIClient.Email],
                partialSummary: String
            )
            case finished(
                emails: [GmailAPIClient.Email],
                summary: String
            )
            case error(message: String)
        }
        
        var screen: Screen = .signedOut
        
        var canSignIn: Bool {
            if case .signedOut = screen { return true }
            return false
        }
        var canRetry: Bool {
            if case .error = screen { return true }
            return false
        }
        var isFinished: Bool {
            if case .finished = screen { return true }
            return false
        }
    }
    
    @Published var state = State()
    
    private let session: LanguageModelSessionProtocol
    private let actionStream: AsyncStream<Action>
    private let actionContinuation: AsyncStream<Action>.Continuation
    
    init(
        session: LanguageModelSessionProtocol
    ) {
        self.session = session
        let (stream, continuation) = AsyncStream<Action>.makeStream()
        self.actionStream = stream
        self.actionContinuation = continuation
        bindToActionStream(actionStream: stream)
    }
    
    func onAppear() {
        actionContinuation.yield(.system(.onAppear))
    }
    
    func onSignInTapped() {
        actionContinuation.yield(.user(.signInTapped))
    }
    
    func onRetryTapped() {
        actionContinuation.yield(.user(.retryTapped))
    }
    
    private func bindToActionStream(
        actionStream: AsyncStream<Action>
    ) {
        Task { [weak self] in
            guard let self else { return }
            for await action in actionStream {
                let old = state
                let (new, effects) = reduce(action: action, state: old)
                state = new
                effects.forEach { [weak self] in
                    guard let self else { return }
                    handleEffect(effect: $0, oldState: old, newState: new)
                }
            }
        }
    }
}

extension EmailSummaryViewModel {
    fileprivate func reduce(
        action: Action,
        state: State
    ) -> (State, [Effect]) {
        var newState = state
        var effects = [Effect]()
        
        switch action {
        case .system(let systemAction):
            switch systemAction {
            case .onAppear:
                if GIDSignIn.sharedInstance.currentUser != nil {
                    newState.screen = .fetching
                    effects.append(.workflowInput(.fetchEmails))
                } else {
                    newState.screen = .signedOut
                }
            }
            
        case .user(let userAction):
            switch userAction {
            case .signInTapped:
                newState.screen = .fetching
                effects.append(.workflowInput(.signIn))
            case .retryTapped:
                newState.screen = .signedOut
            }
            
        case .workflowOutput(let workflowOutputAction):
            switch workflowOutputAction {
            case .signInResult(let result):
                switch result {
                case .success:
                    newState.screen = .fetching
                    effects.append(.workflowInput(.fetchEmails))
                case .failure(let error):
                    newState.screen = .error(message: error.localizedDescription)
                }
                
            case .emailsFetched(let result):
                switch result {
                case .success(let emails):
                    newState.screen = .summarizing(emails: emails, partialSummary: "")
                    effects.append(.workflowInput(.summarize(emails: emails)))
                case .failure(let error):
                    newState.screen = .error(message: error.localizedDescription)
                }
                
            case .partialSummaryResult(let result):
                switch result {
                case .success(let data):
                    let (emails, partialSummary) = data
                    newState.screen = .summarizing(emails: emails, partialSummary: partialSummary)
                case .failure(let error):
                    newState.screen = .error(message: error.localizedDescription)
                }
                
            case .summaryResult(let result):
                switch result {
                case .success(let data):
                    let (emails, summary) = data
                    newState.screen = .finished(emails: emails, summary: summary)
                case .failure(let error):
                    newState.screen = .error(message: error.localizedDescription)
                }
            }
        }
        
        return (newState, effects)
    }
    
    fileprivate func handleEffect(
        effect: Effect,
        oldState: State,
        newState: State
    ) {
        switch effect {
        case .workflowInput(let workflowInputEffect):
            switch workflowInputEffect {
            case .signIn:
                guard
                    let rootVc = UIApplication.shared.connectedScenes
                        .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                        .first
                else {
                    actionContinuation.yield(
                        .workflowOutput(.signInResult(.failure(URLError(.userAuthenticationRequired)))))
                    return
                }
                
                GIDSignIn.sharedInstance.signIn(
                    withPresenting: rootVc,
                    hint: nil,
                    additionalScopes: [
                        "https://www.googleapis.com/auth/gmail.readonly"
                    ]
                ) { [weak self] result, error in
                    guard let self else { return }
                    
                    if let error {
                        actionContinuation.yield(.workflowOutput(.signInResult(.failure(error))))
                        return
                    }
                    
                    actionContinuation.yield(.workflowOutput(.signInResult(.success(()))))
                }
                
            case .fetchEmails:
                Task {
                    do {
                        let token = try await validToken()
                        let gmail = GmailAPIClient(token: token)
                        let now = Date()
                        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
                        let df = DateFormatter()
                        df.dateFormat = "yyyy/MM/dd HH:mm:ss"
                        df.timeZone = TimeZone(secondsFromGMT: 0)
                        let afterEpoch = Int(twentyFourHoursAgo.timeIntervalSince1970)
                        let query = "after:\(afterEpoch)"
                        let ids = try await gmail.listAllMessages(query: query, limit: 300)
                        let emails = try await withThrowingTaskGroup(of: GmailAPIClient.Email.self) { group in
                            for id in ids {
                                group.addTask {
                                    try await gmail.loadMessage(id: id)
                                }
                            }
                            return try await group.reduce(into: []) { $0.append($1) }
                        }
                        actionContinuation.yield(.workflowOutput(.emailsFetched(.success(emails))))
                    } catch {
                        print(error)
                        actionContinuation.yield(.workflowOutput(.emailsFetched(.failure(error))))
                    }
                }
                
            case .summarize(let emails):
                Task {
                    do {
                        // shorten for apple llm context window, to prevent error
                        let prefixedForContextWindow = emails.prefix(20)
                        let body = prefixedForContextWindow
                            .map { "- \($0.subject) (\($0.from)): \($0.snippet)" }
                            .joined(separator: "\n")
                        let prompt = """
                            These are the user's emails from today:
                            \n\(body)\n\nSummarize these in one paragraph.
                        """
                        var final = ""
                        for try await chunk in session.stream(prompt: prompt) {
                            final = chunk
                            actionContinuation.yield(.workflowOutput(.summaryResult(.success((emails, chunk)))))
                        }
                        actionContinuation.yield(.workflowOutput(.summaryResult(.success((emails, final)))))
                    } catch {
                        print(error)
                        actionContinuation.yield(.workflowOutput(.summaryResult(.failure(error))))
                    }
                }
            }
            
        case .haptic:
            break
            
        case .analytics:
            break
        }
    }
    
    fileprivate func validToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw URLError(.userAuthenticationRequired)
        }
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { refreshedUser, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let tokenStr = refreshedUser?.accessToken.tokenString {
                    continuation.resume(returning: tokenStr)
                } else {
                    continuation.resume(throwing: URLError(.userAuthenticationRequired))
                }
            }
        }
    }
}
