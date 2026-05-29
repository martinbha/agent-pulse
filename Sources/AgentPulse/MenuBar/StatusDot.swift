import SwiftUI

private let innerDotScale: CGFloat = 0.44

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
                    .frame(width: size * innerDotScale, height: size * innerDotScale)
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.18), lineWidth: 0.5)
                    }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: shadowColor, radius: 2, y: 1)
    }

    private var shadowColor: Color {
        guard state != .idle else {
            return state.color.opacity(0)
        }

        return state.color.opacity(0.45)
    }
}
