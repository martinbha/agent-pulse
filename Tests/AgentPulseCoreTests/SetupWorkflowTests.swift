import Testing

@testable import AgentPulseCore

@Suite struct SetupWorkflowTests {
    @Test @MainActor func presentationPolicyCoversFreshPartialAndMigrationStates() {
        let snapshot = SetupWorkflowFixtures.presentationStates()

        #expect(snapshot.fresh)
        #expect(!snapshot.partial)
        #expect(!snapshot.complete)
        #expect(snapshot.outdated)
        #expect(snapshot.invalid)
        #expect(snapshot.translocated)
        #expect(!snapshot.optionalMissingBridge)
        #expect(snapshot.configuredMissingBridge)
    }

    @Test func availableIntegrationOperationsFollowHookHealth() {
        let snapshot = SetupWorkflowFixtures.integrationOperations()

        #expect(snapshot.missing == [.setUp(.claude)])
        #expect(snapshot.current == [.remove(.claude)])
        #expect(snapshot.outdated == [.repair(.claude), .remove(.claude)])
        #expect(snapshot.invalid.isEmpty)
        #expect(snapshot.unavailable.isEmpty)
    }

    @Test @MainActor func welcomeStatePersistsAndSuccessfulMutationRefreshesHealth() async {
        let snapshot = await SetupWorkflowFixtures.successfulMutation()

        #expect(snapshot.executed == [.setUp(.claude)])
        #expect(snapshot.inspectionCount == 2)
        #expect(snapshot.noticeKind == .success)
        #expect(snapshot.noticeMessage == "Finished")
        #expect(snapshot.isOperationComplete)
        #expect(snapshot.hasSeenWelcome)
    }

    @Test @MainActor func failedMutationProvidesRecoveryAndRefreshesHealth() async {
        let snapshot = await SetupWorkflowFixtures.failedMutation()

        #expect(snapshot.inspectionCount == 1)
        #expect(snapshot.noticeKind == .failure)
        #expect(snapshot.noticeMessage == "The configuration is read-only.")
        #expect(snapshot.noticeRecovery == "Restore write access, then retry.")
        #expect(snapshot.isOperationComplete)
    }

    @Test @MainActor func translocationPreventsConfigurationMutation() async {
        let snapshot = await SetupWorkflowFixtures.translocatedMutation()

        #expect(snapshot.executed.isEmpty)
        #expect(snapshot.inspectionCount == 1)
        #expect(snapshot.noticeKind == .failure)
        #expect(snapshot.noticeRecovery?.contains("/Applications") == true)
    }

    @Test @MainActor func bridgeFailureIncludesAConcreteRecoveryStep() async throws {
        let snapshot = try await SetupWorkflowFixtures.missingBundledBridgeFailure()

        #expect(snapshot.message.contains("version is missing or invalid"))
        #expect(snapshot.recovery.contains("complete Agent Pulse app bundle"))
    }
}
