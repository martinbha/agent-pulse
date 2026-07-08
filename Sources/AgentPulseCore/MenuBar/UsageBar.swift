import SwiftUI

/// A single usage window rendered as a labeled progress bar with a trailing
/// "42% · resets 4:30 PM" detail.
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

            ProgressView(value: UsageWindowFormatter.fraction(window.usedPercentage))
                .progressViewStyle(.linear)
                .tint(accent)

            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var detail: String {
        UsageWindowFormatter.detailLine(for: window) ?? "--"
    }
}
