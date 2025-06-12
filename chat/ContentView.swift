import SwiftUI

struct ContentView: View {
    private enum Constants {
        static let scrollDeadZone: CGFloat = 18
    }
    
    @StateObject private var viewModel: ChatViewModel
    @Namespace private var glassNameSpace
    
    @State private var barMode: BarMode = .expanded
    @State private var lastScrollY: CGFloat = .zero

    private enum BarMode {
        case expanded
        case compact
    }
    
    init(
        viewModel: ChatViewModel
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
            .safeAreaInset(edge: .bottom) {
                inputField
                    .padding()
                    .animation(.spring(), value: viewModel.state.canSendMessage)
            }
    }
    
    private var content: some View {
        List {
            ForEach(viewModel.state.messagges) { message in
                messageView(message)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onScrollPhaseChange { oldPhase, newPhase, ctx in
            let y = ctx.geometry.contentOffset.y
            
            switch newPhase {
            case .interacting:
                lastScrollY = y
                
            case .animating, .tracking, .idle, .decelerating:
                break
            }
            
            switch oldPhase {
            case .interacting, .decelerating:
                let yDiff = abs(y - lastScrollY)
                let exceedsDeadZone = yDiff > Constants.scrollDeadZone
                guard exceedsDeadZone else { return }
                
                let isScrollingDown = y > lastScrollY
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    barMode = isScrollingDown ? .compact : .expanded
                }
                
            case .animating, .idle, .tracking:
                break
            }
        }
    }
    
    @ViewBuilder
    private func messageView(
        _ message: ChatMessage
    ) -> some View {
        switch message {
        case .assistant(let data):
            assistantMessageView(data)

        case .user(let data):
            userMessageView(data)
        }
    }
    
    private func assistantMessageView(
        _ data: AssistantMessageData
    ) -> some View {
        HStack {
            if let content = data.state.content {
                Text(content)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(alignment: .leading)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
            } else {
                ProgressView()
            }
            
            Spacer(minLength: 50)
        }
    }
    
    private func userMessageView(
        _ data: UserMessageData
    ) -> some View {
        HStack {
            Spacer(minLength: 50)

            Text(data.content)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(alignment: .trailing)
                .foregroundColor(.white)
                .glassEffect(
                    .regular.tint(.accentColor),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
    }
    
    @ViewBuilder
    private var inputField: some View {
        switch barMode {
        case .expanded:
            expandedBar
            
        case .compact:
            compactBar
        }
    }
    
    private var expandedBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack {
                ChatInputBarView(
                    text: .init(
                        get: { viewModel.state.userInput },
                        set: viewModel.onUserEditInput
                    ),
                    sendButtonState: viewModel.state.canSendMessage
                    ? .enabled(action: viewModel.onSendTapped)
                    : .disabled
                )
                .frame(height: 44)
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .glassEffectID("bar", in: glassNameSpace)
                .glassEffectTransition(.matchedGeometry)
                
                Button {
                    viewModel.onSendTapped()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            viewModel.state.canSendMessage
                            ? .blue
                            : .gray
                        )
                }
                .disabled(!viewModel.state.canSendMessage)
                .frame(width: 44, height: 44)
                .buttonStyle(.glass)
                .glassEffectID("send", in: glassNameSpace)
                .glassEffectUnion(id: "bar", namespace: glassNameSpace)
            }
        }
    }
    
    private var compactBar: some View {
        Button {
            withAnimation(.spring()) { barMode = .expanded }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 36))
                .padding(6)
        }
        .glassEffect(.regular.tint(.accentColor), in: .circle)
    }
}

#Preview {
    ContentView(viewModel: ChatViewModelFactory.make())
}

