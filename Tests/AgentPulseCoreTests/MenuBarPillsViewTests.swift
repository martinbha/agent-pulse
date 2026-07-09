import AppKit
import Testing

@testable import AgentPulseCore

@MainActor
@Suite struct MenuBarPillsViewTests {
    @Test func widthIsZeroWithoutPills() {
        let view = MenuBarPillsView()

        #expect(view.fittingWidth() == 0)
    }

    @Test func widthGrowsWithEachPill() {
        let view = MenuBarPillsView()

        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, fiveHour: 34, weekly: nil)]
        let oneWidth = view.fittingWidth()

        view.pills = [
            MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, fiveHour: 34, weekly: nil),
            MenuBarPillBuilder.pill(agent: .codex, effectiveState: .idle, fiveHour: 40, weekly: nil),
        ]
        let twoWidth = view.fittingWidth()

        #expect(oneWidth > 0)
        #expect(twoWidth > oneWidth)
    }

    @Test func intrinsicSizeMatchesFittingWidth() {
        let view = MenuBarPillsView()
        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .working, fiveHour: 100, weekly: nil)]

        #expect(view.intrinsicContentSize.width == view.fittingWidth())
    }

    @Test func wideUsageMakesWiderPill() {
        // A three-digit usage number must not clip: the pill sizing accounts
        // for the longest of label/usage in each half.
        let view = MenuBarPillsView()

        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, fiveHour: 5, weekly: nil)]
        let narrow = view.fittingWidth()

        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, fiveHour: 100, weekly: nil)]
        let wide = view.fittingWidth()

        #expect(wide > narrow)
    }
}
