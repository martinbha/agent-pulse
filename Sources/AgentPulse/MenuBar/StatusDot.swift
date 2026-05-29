import SwiftUI

struct StatusDot: View {
    var state: AgentState
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(.primary.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: state.color.opacity(state == .idle ? 0 : 0.45), radius: 2, y: 1)
    }
}

