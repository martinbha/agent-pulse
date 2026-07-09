import Testing

@testable import AgentPulseCore

@Suite struct MenuBarPillLayoutTests {
    @Test func sectionWidthsUseTheWidestLabelAndUsage() {
        let pills = [
            MenuBarPillLayoutFixtures.pill(.claude, usage: "100/56"),
            MenuBarPillLayoutFixtures.pill(.codex, usage: "1/47"),
        ]

        let widths = MenuBarPillLayoutFixtures.widths(pills)
        let pad = MenuBarPillLayoutFixtures.padding

        // "Cl"/"Cx" are both 2 chars; widest usage is "100/56" (6 chars).
        #expect(widths.label == (2 * 6 + pad).rounded(.up))
        #expect(widths.usage == (6 * 6 + pad).rounded(.up))
    }

    @Test func widthsAreUniformRegardlessOfPerPillText() {
        // Section widths come from the widest values, so both pills render the
        // same total width and the labels line up consistently.
        let widePills = [
            MenuBarPillLayoutFixtures.pill(.claude, usage: "100/56"),
            MenuBarPillLayoutFixtures.pill(.codex, usage: "1/47"),
        ]
        let narrowPills = [
            MenuBarPillLayoutFixtures.pill(.claude, usage: "1/2"),
            MenuBarPillLayoutFixtures.pill(.codex, usage: "1/47"),
        ]

        let wide = MenuBarPillLayoutFixtures.widths(widePills)
        let narrow = MenuBarPillLayoutFixtures.widths(narrowPills)

        // Same label width for both sets; usage width tracks the widest usage.
        #expect(wide.label == narrow.label)
        #expect(wide.usage > narrow.usage)
    }

    @Test func emptyPillsProduceOnlyPadding() {
        let widths = MenuBarPillLayoutFixtures.widths([])

        #expect(widths.label == MenuBarPillLayoutFixtures.padding)
        #expect(widths.usage == MenuBarPillLayoutFixtures.padding)
    }
}
