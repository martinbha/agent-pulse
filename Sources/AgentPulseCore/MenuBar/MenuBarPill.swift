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
    /// Formats the 5-hour usage percentage as a plain integer, or "--" when no
    /// usage is available (not logged in, fetch failed, still loading).
    static func usageText(for usedPercentage: Double?) -> String {
        guard let usedPercentage else {
            return "--"
        }
        return String(Int(usedPercentage.rounded()))
    }

    static func pill(
        agent: AgentKind,
        effectiveState: AgentState,
        usedPercentage: Double?
    ) -> MenuBarPill {
        MenuBarPill(
            agent: agent,
            label: agent.pillLabel,
            usageText: usageText(for: usedPercentage),
            state: effectiveState
        )
    }
}
