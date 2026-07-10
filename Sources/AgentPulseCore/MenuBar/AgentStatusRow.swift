import SwiftUI

struct AgentStatusRow: View {
    var snapshot: AgentStatusSnapshot
    var effectiveState: AgentState
    var usage: AgentUsageSnapshot
    var availability: UsageAvailability
    var accent: Color
    var now: Date

    private let dotSize: CGFloat = 12
    private let detailIndent: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Baseline-aligned so the dot tracks the title text itself; the
            // display font's uneven line box makes plain center alignment sit
            // the dot visibly high.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: dotSize, height: dotSize)
                    // Rest the circle on the baseline, centered on the title's
                    // cap-height band.
                    .alignmentGuide(.firstTextBaseline) { _ in dotSize - 1 }
                Text(snapshot.agent.displayName)
                    .agentPulseFont(size: 15)
                Spacer()
                Text(effectiveState.displayName)
                    .agentPulseFont(size: 11)
                    .foregroundStyle(effectiveState.color)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(snapshot.project ?? "No project")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .agentPulseFont(size: 11)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.event) · \(relativeTime)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .agentPulseFont(size: 11)
                .foregroundStyle(.secondary)

                usageSection
                    .padding(.top, 2)
            }
            .padding(.leading, detailIndent)
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        if hasUsageData {
            VStack(alignment: .leading, spacing: 8) {
                UsageBar(label: "5h", window: usage.fiveHour, accent: accent)
                UsageBar(label: "Week", window: usage.weekly, accent: accent)
            }
        } else if let message = availabilityText {
            HStack(spacing: 6) {
                Image(systemName: unavailableIcon)
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .agentPulseFont(size: 11)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading usage…")
            }
            .agentPulseFont(size: 11)
            .foregroundStyle(.secondary)
        }
    }

    private var hasUsageData: Bool {
        usage.fiveHour.usedPercentage != nil || usage.weekly.usedPercentage != nil
    }

    private var availabilityText: String? {
        UsageWindowFormatter.availabilityMessage(availability)
    }

    private var unavailableIcon: String {
        switch availability {
        case .accessDenied:
            return "lock.fill"
        case .notInstalled:
            return "questionmark.app"
        default:
            return "exclamationmark.triangle"
        }
    }

    private var relativeTime: String {
        guard snapshot.updatedAt != .distantPast else {
            return "never"
        }

        return RelativeTimeFormatter.shared.localizedString(for: snapshot.updatedAt, relativeTo: now)
    }
}
