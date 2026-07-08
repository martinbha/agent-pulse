import SwiftUI

struct AgentStatusRow: View {
    var snapshot: AgentStatusSnapshot
    var effectiveState: AgentState
    var usage: AgentUsageSnapshot
    var availability: UsageAvailability
    var now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusDot(state: effectiveState, size: 16, innerColor: snapshot.agent.brandAccent)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(snapshot.agent.displayName)
                        .font(.headline)
                    Spacer()
                    Text(effectiveState.displayName)
                        .font(.caption)
                        .foregroundStyle(effectiveState.color)
                }

                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(snapshot.project ?? "No project")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("\(snapshot.event) · \(relativeTime)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                usageSection
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        if hasUsageData {
            VStack(alignment: .leading, spacing: 4) {
                UsageBar(label: "5h", window: usage.fiveHour, accent: snapshot.agent.brandAccent)
                UsageBar(label: "Week", window: usage.weekly, accent: snapshot.agent.brandAccent)
            }
        } else if let message = availabilityText {
            HStack(spacing: 6) {
                Image(systemName: unavailableIcon)
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading usage…")
            }
            .font(.caption)
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
