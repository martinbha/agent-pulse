import Testing

@testable import AgentPulseCore

@MainActor
@Suite struct AgentAppLauncherTests {
    @Test func everyAgentHasBundleIDCandidates() {
        for agent in AgentKind.allCases {
            #expect(!AgentAppLauncher.bundleIDCandidates(for: agent).isEmpty)
        }
    }

    @Test func codexPrefersCodexBundleIDOverLegacyChatApp() {
        #expect(AgentAppLauncher.bundleIDCandidates(for: .codex) == ["com.openai.codex", "com.openai.chat"])
    }

    @Test func stopsAtFirstCandidateThatOpens() async {
        var openedBundleIDs: [String] = []
        let launcher = AgentAppLauncher(openApp: { bundleID in
            openedBundleIDs.append(bundleID)
            return true
        })

        #expect(await launcher.open(.codex))
        #expect(openedBundleIDs == ["com.openai.codex"])
        #expect(launcher.unavailableAgents.isEmpty)
    }

    @Test func fallsBackToNextCandidateWhenOpenFails() async {
        var openedBundleIDs: [String] = []
        let launcher = AgentAppLauncher(openApp: { bundleID in
            openedBundleIDs.append(bundleID)
            return bundleID == "com.openai.chat"
        })

        #expect(await launcher.open(.codex))
        #expect(openedBundleIDs == ["com.openai.codex", "com.openai.chat"])
        #expect(launcher.unavailableAgents.isEmpty)
    }

    @Test func marksAgentUnavailableWhenEveryCandidateFailsToOpen() async {
        let launcher = AgentAppLauncher(openApp: { _ in false })

        #expect(await launcher.open(.claude) == false)
        #expect(launcher.unavailableAgents == [.claude])
    }

    @Test func successClearsUnavailableFeedbackImmediately() async {
        var shouldOpenSucceed = false
        let launcher = AgentAppLauncher(openApp: { _ in shouldOpenSucceed })

        await launcher.open(.claude)
        #expect(launcher.unavailableAgents == [.claude])

        shouldOpenSucceed = true
        #expect(await launcher.open(.claude))
        #expect(launcher.unavailableAgents.isEmpty)
    }

    @Test func clearsUnavailableFeedbackAfterFeedbackDuration() async throws {
        let launcher = AgentAppLauncher(
            openApp: { _ in false },
            feedbackDuration: .milliseconds(20)
        )

        await launcher.open(.codex)
        #expect(launcher.unavailableAgents == [.codex])

        for _ in 0..<50 where !launcher.unavailableAgents.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(launcher.unavailableAgents.isEmpty)
    }
}
