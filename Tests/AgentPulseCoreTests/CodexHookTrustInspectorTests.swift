import Testing

@testable import AgentPulseCore

@Suite struct CodexHookTrustInspectorTests {
    @Test func reportsEveryOwnedEnabledHookAsVerified() {
        let health = CodexHookTrustFixtures.classify(
            statuses: Array(repeating: "trusted", count: 6)
        )

        #expect(health == .verified(trusted: 6, managed: 0, total: 6))
    }

    @Test func acceptsPolicyManagedHooksAsVerified() {
        let health = CodexHookTrustFixtures.classify(
            statuses: ["trusted", "managed", "trusted", "managed", "trusted", "managed"]
        )

        #expect(health == .verified(trusted: 3, managed: 3, total: 6))
    }

    @Test func reportsUntrustedAndModifiedHooksForReview() {
        let health = CodexHookTrustFixtures.classify(
            statuses: ["trusted", "untrusted", "modified", "trusted", "trusted", "trusted"]
        )

        #expect(health == .needsReview(untrusted: 1, modified: 1, total: 6))
    }

    @Test func reportsDisabledHooksBeforeTrust() {
        let health = CodexHookTrustFixtures.classify(
            statuses: Array(repeating: "trusted", count: 6),
            disabledIndexes: [2, 5]
        )

        #expect(health == .disabled(disabled: 2, total: 6))
    }

    @Test func reportsMissingOwnedHooksAndIgnoresOtherCommands() {
        let health = CodexHookTrustFixtures.classify(
            statuses: Array(repeating: "trusted", count: 4),
            includeUnrelatedHook: true
        )

        #expect(health == .missing(found: 4, expected: 6))
    }

    @Test func surfacesConfigurationErrorsAndMalformedResponsesAsUnavailable() {
        let errorHealth = CodexHookTrustInspector.classify(
            payload: [
                "result": [
                    "data": [[
                        "hooks": [],
                        "errors": [["message": "configuration could not be loaded"]],
                    ]],
                ],
            ],
            bridgeExecutableURL: CodexHookTrustFixtures.bridgeURL,
            agentArgument: "codex"
        )
        let malformedHealth = CodexHookTrustInspector.classify(
            payload: ["result": [:]],
            bridgeExecutableURL: CodexHookTrustFixtures.bridgeURL,
            agentArgument: "codex"
        )

        #expect(errorHealth == .unavailable("configuration could not be loaded"))
        #expect(
            malformedHealth
                == .unavailable("The hook status response did not contain result.data.")
        )
    }

    @Test func unavailableExecutableProducesUnknownStatus() async {
        let health = await CodexHookTrustFixtures.unavailableExecutableHealth()

        guard case .unavailable = health else {
            Issue.record("Expected a missing executable to produce unavailable trust status.")
            return
        }
    }
}
