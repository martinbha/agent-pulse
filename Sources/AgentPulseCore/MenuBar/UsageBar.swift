import SwiftUI

/// A single usage window rendered as a labeled bar with a trailing
/// "42% · 3h 06m" detail. Uses a plain capsule fill (not `ProgressView`) so it
/// renders at its final width immediately without an animated sweep each time
/// the dropdown opens.
struct UsageBar: View {
    let label: String
    let window: UsageWindow
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)

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

            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .transaction { $0.animation = nil }
    }

    private var fraction: CGFloat {
        CGFloat(UsageWindowFormatter.fraction(window.usedPercentage))
    }

    private var detail: String {
        UsageWindowFormatter.detailLine(for: window) ?? "--"
    }
}
