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

    @Test func opensFirstInstalledCandidate() async {
        var openedBundleIDs: [String] = []
        let launcher = AgentAppLauncher(
            resolveAppURL: { bundleID in
                bundleID == "com.openai.chat" ? AgentAppLauncherFixtures.chatGPTAppURL : nil
            },
            openApp: { bundleID in
                openedBundleIDs.append(bundleID)
                return true
            }
        )

        #expect(await launcher.open(.codex))
        #expect(openedBundleIDs == ["com.openai.chat"])
        #expect(launcher.unavailableAgents.isEmpty)
    }

    @Test func marksAgentUnavailableWhenNoCandidateIsInstalled() async {
        let launcher = AgentAppLauncher(
            resolveAppURL: { _ in nil },
            openApp: { _ in
                Issue.record("should not attempt to open an uninstalled app")
                return false
            }
        )

        #expect(await launcher.open(.claude) == false)
        #expect(launcher.unavailableAgents == [.claude])
    }

    @Test func marksAgentUnavailableWhenOpeningFails() async {
        let launcher = AgentAppLauncher(
            resolveAppURL: { _ in AgentAppLauncherFixtures.claudeAppURL },
            openApp: { _ in false }
        )

        #expect(await launcher.open(.claude) == false)
        #expect(launcher.unavailableAgents == [.claude])
    }

    @Test func clearsUnavailableFeedbackAfterFeedbackDuration() async throws {
        let launcher = AgentAppLauncher(
            resolveAppURL: { _ in nil },
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
