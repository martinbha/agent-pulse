import SwiftUI

struct AgentStatusRow: View {
    var snapshot: AgentStatusSnapshot
    var effectiveState: AgentState
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
            }
        }
    }

    private var relativeTime: String {
        guard snapshot.updatedAt != .distantPast else {
            return "never"
        }

        return RelativeTimeFormatter.shared.localizedString(for: snapshot.updatedAt, relativeTo: now)
    }
}
