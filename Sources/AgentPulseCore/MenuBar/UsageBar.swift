import SwiftUI

/// A single usage window shown in two tiers: a stats row (label on the left,
/// used percentage + time-remaining countdown on the right) above a full-width
/// bar. The plain capsule fill (not `ProgressView`) renders at its final width
/// immediately, with no animated sweep each time the dropdown opens.
struct UsageBar: View {
    let label: String
    let window: UsageWindow
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .agentPulseFont(size: 11)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(stats)
                    .agentPulseFont(size: 11)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 5)
        }
        .transaction { $0.animation = nil }
    }

    private var fraction: CGFloat {
        CGFloat(UsageWindowFormatter.fraction(window.usedPercentage))
    }

    private var stats: String {
        UsageWindowFormatter.detailLine(for: window) ?? "--"
    }
}
