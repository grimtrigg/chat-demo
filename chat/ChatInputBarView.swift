import Foundation
import SwiftUI

struct ChatInputBarView: View {
    enum SendButtonState {
        case disabled
        case enabled(action: () -> Void)
        
        var isEnabled: Bool {
            switch self {
            case .disabled: false
            case .enabled: true
            }
        }
        
        var action: (() -> Void)? {
            switch self {
            case .disabled: nil
            case .enabled(let action): action
            }
        }
    }
    
    @Namespace private var animation
    @State private var shimmer = false
    
    @Binding var text: String
    let sendButtonState: SendButtonState
    
    var body: some View {
        TextField("Type a message...", text: $text)
            .textFieldStyle(.plain)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.1))
            )
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .cyan.opacity(0.18), radius: shimmer ? 12 : 6, y: 1)
                    .overlay(
                        Capsule()
                            .stroke(LinearGradient(gradient: Gradient(colors: [Color.cyan.opacity(0.2), Color.white.opacity(0.15), Color.blue.opacity(0.25)]), startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: shimmer ? 2 : 1)
                    )
                    .scaleEffect(shimmer ? 1.012 : 1.0)
            )
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    shimmer.toggle()
                }
            }
    }
}
