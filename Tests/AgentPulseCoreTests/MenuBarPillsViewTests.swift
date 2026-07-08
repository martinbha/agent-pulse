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

        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, usedPercentage: 34)]
        let oneWidth = view.fittingWidth()

        view.pills = [
            MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, usedPercentage: 34),
            MenuBarPillBuilder.pill(agent: .codex, effectiveState: .idle, usedPercentage: 40),
        ]
        let twoWidth = view.fittingWidth()

        #expect(oneWidth > 0)
        #expect(twoWidth > oneWidth)
    }

    @Test func intrinsicSizeMatchesFittingWidth() {
        let view = MenuBarPillsView()
        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .working, usedPercentage: 100)]

        #expect(view.intrinsicContentSize.width == view.fittingWidth())
    }

    @Test func wideUsageMakesWiderPill() {
        // A three-digit usage number must not clip: the pill sizing accounts
        // for the longest of label/usage in each half.
        let view = MenuBarPillsView()

        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, usedPercentage: 5)]
        let narrow = view.fittingWidth()

        view.pills = [MenuBarPillBuilder.pill(agent: .claude, effectiveState: .idle, usedPercentage: 100)]
        let wide = view.fittingWidth()

        #expect(wide > narrow)
    }
}
