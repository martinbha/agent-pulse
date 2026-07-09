import Foundation

/// One menu bar pill: an agent's two-letter label, its 5-hour usage number,
/// and the effective work state that colors the pill's left half.
struct MenuBarPill: Equatable, Sendable {
    let agent: AgentKind
    let label: String
    let usageText: String
    let state: AgentState
}

enum MenuBarPillBuilder {
    /// Formats a usage percentage as a plain integer, or "--" when no usage is
    /// available (not logged in, fetch failed, still loading).
    static func usageText(for usedPercentage: Double?) -> String {
        guard let usedPercentage else {
            return "--"
        }
        return String(Int(usedPercentage.rounded()))
    }

    /// The pill's right-half text: 5-hour and weekly usage as "5h/weekly",
    /// e.g. "0/56" or "--/--".
    static func combinedUsageText(fiveHour: Double?, weekly: Double?) -> String {
        "\(usageText(for: fiveHour))/\(usageText(for: weekly))"
    }

    static func pill(
        agent: AgentKind,
        effectiveState: AgentState,
        fiveHour: Double?,
        weekly: Double?
    ) -> MenuBarPill {
        MenuBarPill(
            agent: agent,
            label: agent.pillLabel,
            usageText: combinedUsageText(fiveHour: fiveHour, weekly: weekly),
            state: effectiveState
        )
    }
}
