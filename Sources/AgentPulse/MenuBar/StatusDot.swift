import SwiftUI

struct StatusDot: View {
    var state: AgentState
    var size: CGFloat
    var innerColor: Color?

    @State private var workingPulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(outerColor)

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
        .shadow(color: shadowColor, radius: 2, y: 1)
        .onAppear(perform: updatePulse)
        .onChange(of: state) {
            updatePulse()
        }
    }

    private var outerColor: Color {
        guard state == .working else {
            return state.color
        }

        return state.color.opacity(workingPulse ? 1 : 0)
    }

    private var shadowColor: Color {
        guard state != .idle else {
            return state.color.opacity(0)
        }

        return state.color.opacity(state == .working ? (workingPulse ? 0.45 : 0) : 0.45)
    }

    private func updatePulse() {
        if state == .working {
            workingPulse = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                workingPulse = true
            }
        } else {
            workingPulse = false
        }
    }
}
