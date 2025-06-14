import Combine
import Foundation
import FoundationModels

struct UserMessageData: Equatable {
    let id: String
    let content: String
}

struct AssistantMessageData: Equatable {
    let id: String
    var state: MessageState
    
    enum MessageState: Equatable {
        case loading
        case error(content: String?)
        case streaming(content: String)
        case finished(content: String)
        
        var content: String? {
            switch self {
            case .loading:
                nil
            case .error(let optionalContent):
                optionalContent
            case .streaming(let content),
                .finished(let content):
                content
            }
        }
    }
}

struct ChatMessagePairing: Equatable {
    let user: UserMessageData
    let assistant: AssistantMessageData
}

enum ChatMessage: Equatable, Identifiable {
    case user(UserMessageData)
    case assistant(AssistantMessageData)
}

extension ChatMessage {
    var id: String {
        switch self {
        case .user(let data): data.id
        case .assistant(let data): data.id
        }
    }
    
    var assistantData: AssistantMessageData? {
        switch self {
        case .user: nil
        case .assistant(let data): data
        }
    }
}

extension ChatViewModel {
    enum Action {
        case system(SystemAction)
        case user(UserAction)
        case workflowOutput(WorkflowOutputAction)
    }
    
    enum SystemAction {
        case onAppear
    }
    
    enum UserAction {
        case inputChanged(newInput: String)
        case sendTapped
    }
    
    enum WorkflowOutputAction {
        case assistantStreamResponseReceived(
            pairing: ChatMessagePairing,
            assistantContent: String
        )
        case assistantStreamResponseFinished(
            pairing: ChatMessagePairing,
            assistantContent: String
        )
        case assistantStreamResponseError(
            pairing: ChatMessagePairing
        )
    }
}

extension ChatViewModel {
    enum Effect {
        case workflowInput(WorkflowInputEffect)
        case haptic(HapticEffect)
        case analytics(AnalyticsEffect)
    }
    
    enum WorkflowInputEffect {
        case generateResponse(
            pairing: ChatMessagePairing
        )
    }
    
    enum HapticEffect { }
    enum AnalyticsEffect { }
}

final class ChatViewModelFactory {
    static func make() -> ChatViewModel {
        let session = ChatLanguageModelSession()
        return ChatViewModel(
            session: session
        )
    }
}

final class ChatViewModel: ObservableObject {
    struct State: Equatable {
        var userInput = ""
        var messagges: [ChatMessage] = []
        
        var canSendMessage: Bool {
            let hasUserInput = !userInput.isEmpty
            let assistantMessagesAreFinished = messagges
                .compactMap(\.assistantData?.state)
                .allSatisfy { state in
                    switch state {
                    case .error, .finished: true
                    case .loading, .streaming: false
                    }
                }
            return hasUserInput && assistantMessagesAreFinished
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
        
        bindToActionStream(
            actionStream: stream
        )
    }
    
    func onAppear() {
        actionContinuation.yield(.system(.onAppear))
    }
    
    func onUserEditInput(_ newInput: String) {
        actionContinuation.yield(.user(.inputChanged(newInput: newInput)))
    }
    
    func onSendTapped() {
        actionContinuation.yield(.user(.sendTapped))
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

private extension ChatViewModel {
    func reduce(
        action: Action,
        state: State
    ) -> (State, [Effect]) {
        var newState = state
        var effects = [Effect]()
        
        switch action {
        case .system(let systemAction):
            switch systemAction {
            case .onAppear:
                break
            }
            
        case .user(let userAction):
            switch userAction {
            case .sendTapped:
                let userMessageContent = newState.userInput
                let userMessage = UserMessageData(
                    id: UUID().uuidString,
                    content: userMessageContent
                )
                let assistantMessage = AssistantMessageData(
                    id: UUID().uuidString,
                    state: .loading
                )
                let pairing = ChatMessagePairing(
                    user: userMessage,
                    assistant: assistantMessage
                )
                
                newState.messagges.append(.user(userMessage))
                newState.messagges.append(.assistant(assistantMessage))
                newState.userInput = ""
                
                effects.append(.workflowInput(.generateResponse(pairing: pairing)))
                
            case .inputChanged(let newInput):
                newState.userInput = newInput
            }
            
        case .workflowOutput(let workflowOutputAction):
            switch workflowOutputAction {
            case .assistantStreamResponseReceived(let pairing, let assistantContent):
                guard let index = newState.messagges.firstIndex(where: {
                    $0.id == pairing.assistant.id
                }) else { break }
                
                if index < newState.messagges.count,
                   case .assistant(var assistantMessageData) = newState.messagges[index],
                   assistantMessageData.id == pairing.assistant.id {
                    assistantMessageData.state = .streaming(content: assistantContent)
                    newState.messagges[index] = .assistant(assistantMessageData)
                } else {
                    newState.messagges.append(.assistant(
                        AssistantMessageData(
                            id: pairing.assistant.id,
                            state: .streaming(content: assistantContent)
                        )
                    ))
                }
                
            case .assistantStreamResponseFinished(let pairing, let assistantContent):
                guard let index = newState.messagges.firstIndex(where: {
                    $0.id == pairing.assistant.id
                }) else { break }
                
                if index < newState.messagges.count,
                   case .assistant(var assistantMessageData) = newState.messagges[index],
                   assistantMessageData.id == pairing.assistant.id {
                    assistantMessageData.state = .finished(content: assistantContent)
                    newState.messagges[index] = .assistant(assistantMessageData)
                } else {
                    newState.messagges.append(.assistant(
                        AssistantMessageData(
                            id: pairing.assistant.id,
                            state: .finished(content: assistantContent)
                        )
                    ))
                }
                
            case .assistantStreamResponseError(let pairing):
                guard let index = newState.messagges.firstIndex(where: {
                    $0.id == pairing.assistant.id
                }) else { break }
                
                if index < newState.messagges.count,
                   case .assistant(var assistantMessageData) = newState.messagges[index],
                   assistantMessageData.id == pairing.assistant.id {
                    let currentContent = assistantMessageData.state.content
                    assistantMessageData.state = .error(content: currentContent)
                    newState.messagges[index] = .assistant(assistantMessageData)
                } else {
                    newState.messagges.append(.assistant(
                        AssistantMessageData(
                            id: pairing.assistant.id,
                            state: .error(content: nil)
                        )
                    ))
                }
            }
        }
        
        return (newState, effects)
    }
    
    func handleEffect(
        effect: Effect,
        oldState: State,
        newState: State
    ) {
        switch effect {
        case .workflowInput(let workflowInputEffect):
            switch workflowInputEffect {
            case .generateResponse(let pairing):
                let stream = session.stream(prompt: pairing.user.content)
                
                Task {
                    do {
                        var finalContent = ""
                        for try await token in stream {
                            finalContent = token
                            actionContinuation.yield(
                                .workflowOutput(
                                    .assistantStreamResponseReceived(
                                        pairing: pairing,
                                        assistantContent: token
                                    )
                                )
                            )
                        }
                        actionContinuation.yield(
                            .workflowOutput(
                                .assistantStreamResponseFinished(
                                    pairing: pairing,
                                    assistantContent: finalContent
                                )
                            )
                        )
                    } catch {
                        actionContinuation.yield(
                            .workflowOutput(
                                .assistantStreamResponseError(
                                    pairing: pairing
                                )
                            )
                        )
                    }
                }
            }
            
        case .haptic(let hapticEffect):
            break
            
        case .analytics(let analyticsEffect):
            break
        }
    }
}

