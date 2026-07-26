import Testing

@testable import AgentPulseCore

@MainActor
@Suite struct ActiveAgentSettingsTests {
    @Test func missingPreferenceDefaultsToBothAgents() {
        let defaults = ActiveAgentSettingsFixtures.makeDefaults()

        let settings = ActiveAgentSettings(defaults: defaults)

        #expect(settings.selection == .both)
        #expect(settings.activeAgents == [.claude, .codex])
    }

    @Test(arguments: ["", "unknown", "CLAUDE"])
    func invalidPreferenceFallsBackToBothAgents(storedValue: String) {
        let defaults = ActiveAgentSettingsFixtures.makeDefaults()
        defaults.set(storedValue, forKey: "agents.activeSelection")

        let settings = ActiveAgentSettings(defaults: defaults)

        #expect(settings.selection == .both)
        #expect(defaults.string(forKey: "agents.activeSelection") == "both")
    }

    @Test(arguments: [
        ActiveAgentSelection.both,
        ActiveAgentSelection.claude,
        ActiveAgentSelection.codex,
    ])
    func selectionPersistsAcrossReloads(selection: ActiveAgentSelection) {
        let defaults = ActiveAgentSettingsFixtures.makeDefaults()
        let settings = ActiveAgentSettings(defaults: defaults)

        settings.setSelection(selection)
        let reloaded = ActiveAgentSettings(defaults: defaults)

        #expect(reloaded.selection == selection)
        #expect(reloaded.activeAgents == selection.agents)
    }

    @Test func singleAgentSelectionsGateOtherAgents() {
        let settings = ActiveAgentSettings(defaults: ActiveAgentSettingsFixtures.makeDefaults())

        settings.setSelection(.claude)
        #expect(settings.isActive(.claude))
        #expect(!settings.isActive(.codex))

        settings.setSelection(.codex)
        #expect(!settings.isActive(.claude))
        #expect(settings.isActive(.codex))
    }
}
