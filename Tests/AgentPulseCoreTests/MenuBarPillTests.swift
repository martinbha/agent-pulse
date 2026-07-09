import Testing

@testable import AgentPulseCore

@Suite struct MenuBarPillTests {
    @Test func usageTextRoundsPercentage() {
        #expect(MenuBarPillBuilder.usageText(for: 42.4) == "42")
        #expect(MenuBarPillBuilder.usageText(for: 42.6) == "43")
        #expect(MenuBarPillBuilder.usageText(for: 0) == "0")
        #expect(MenuBarPillBuilder.usageText(for: 100) == "100")
    }

    @Test func usageTextIsPlaceholderWhenUnavailable() {
        #expect(MenuBarPillBuilder.usageText(for: nil) == "--")
    }

    @Test func combinedUsageJoinsFiveHourAndWeekly() {
        #expect(MenuBarPillBuilder.combinedUsageText(fiveHour: 0, weekly: 56) == "0/56")
        #expect(MenuBarPillBuilder.combinedUsageText(fiveHour: 34, weekly: nil) == "34/--")
        #expect(MenuBarPillBuilder.combinedUsageText(fiveHour: nil, weekly: 67) == "--/67")
        #expect(MenuBarPillBuilder.combinedUsageText(fiveHour: nil, weekly: nil) == "--/--")
    }

    @Test func pillCarriesLabelUsageAndState() {
        let pill = MenuBarPillBuilder.pill(agent: .claude, effectiveState: .working, fiveHour: 34, weekly: 67)

        #expect(pill.agent == .claude)
        #expect(pill.label == "Cl")
        #expect(pill.usageText == "34/67")
        #expect(pill.state == .working)
    }

    @Test func codexPillUsesCodexLabel() {
        let pill = MenuBarPillBuilder.pill(agent: .codex, effectiveState: .idle, fiveHour: nil, weekly: nil)

        #expect(pill.label == "Cx")
        #expect(pill.usageText == "--/--")
    }
}

@Suite struct PillStatusFillTests {
    @Test func idleAndUnknownUseBrandColor() {
        let brand = AgentKind.claude.brandAccentNSColor

        #expect(AgentPulseColors.pillStatusFill(for: .idle, brand: brand) == brand)
        #expect(AgentPulseColors.pillStatusFill(for: .unknown, brand: brand) == brand)
    }

    @Test func activeStatesUseFixedFills() {
        let brand = AgentKind.codex.brandAccentNSColor

        #expect(AgentPulseColors.pillStatusFill(for: .working, brand: brand) == AgentPulseColors.pillWorkingNS)
        #expect(AgentPulseColors.pillStatusFill(for: .done, brand: brand) == AgentPulseColors.pillDoneNS)
        #expect(AgentPulseColors.pillStatusFill(for: .failed, brand: brand) == AgentPulseColors.pillFailedNS)
        #expect(AgentPulseColors.pillStatusFill(for: .waiting, brand: brand) == AgentPulseColors.pillWaitingNS)
        #expect(AgentPulseColors.pillStatusFill(for: .stale, brand: brand) == AgentPulseColors.pillStaleNS)
    }
}
