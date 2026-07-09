import Foundation

@testable import AgentPulseCore

enum MenuBarPillLayoutFixtures {
    // A deterministic stand-in for text measurement: width ∝ character count.
    static func measure(_ text: String) -> CGFloat {
        CGFloat(text.count) * 6
    }

    static func pill(_ agent: AgentKind, usage: String) -> MenuBarPill {
        MenuBarPill(agent: agent, label: agent.pillLabel, usageText: usage, state: .idle)
    }

    static func widths(_ pills: [MenuBarPill]) -> (label: Double, usage: Double) {
        let widths = MenuBarPillLayout.sectionWidths(pills: pills, measure: measure)
        return (Double(widths.label), Double(widths.usage))
    }

    static var padding: Double {
        Double(MenuBarPillLayout.horizontalPadding) * 2
    }
}
