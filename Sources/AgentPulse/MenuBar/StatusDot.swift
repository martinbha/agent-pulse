import SwiftUI

struct StatusDot: View {
    var state: AgentState
    var size: CGFloat
    var innerColor: Color?

    var body: some View {
        ZStack {
            Circle()
                .fill(state.color)

            Circle()
                .stroke(.primary.opacity(0.14), lineWidth: 0.5)

            if let innerColor {
                Circle()
                    .fill(innerColor)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.18), lineWidth: 0.5)
                    }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: state.color.opacity(state == .idle ? 0 : 0.45), radius: 2, y: 1)
    }
}
