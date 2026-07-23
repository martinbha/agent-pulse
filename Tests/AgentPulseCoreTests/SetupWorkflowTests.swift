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
        #expect(snapshot.current == [.test(.claude), .remove(.claude)])
        #expect(snapshot.currentCanTest)
        #expect(!snapshot.missingCanTest)
        #expect(snapshot.outdated == [.repair(.claude), .remove(.claude)])
        #expect(snapshot.invalid.isEmpty)
        #expect(snapshot.unavailable.isEmpty)
    }

    @Test func integrationStateRequiresBridgeHostAndAReceivedEvent() {
        let snapshot = SetupWorkflowFixtures.integrationStates()

        #expect(snapshot.connected == .connected)
        #expect(snapshot.waitingForEvent == .waitingForEvent)
        #expect(snapshot.bridgeUnavailable == .bridgeUnavailable)
        #expect(snapshot.hostUnavailable == .hostUnavailable)
        #expect(snapshot.missing == .notSetUp)
        #expect(snapshot.outdated == .needsRepair)
        #expect(snapshot.invalid == .needsReview)
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

    @Test @MainActor func selfTestResultRemainsAvailableAndRefreshesHealth() async {
        let snapshot = await SetupWorkflowFixtures.successfulSelfTest()

        #expect(snapshot.executed == [.test(.codex)])
        #expect(snapshot.inspectionCount == 1)
        #expect(snapshot.noticeKind == .success)
        #expect(snapshot.noticeMessage == "Delivery verified")
    }

    @Test @MainActor func notificationTestResultRemainsAvailableAndRefreshesHealth() async {
        let snapshot = await SetupWorkflowFixtures.successfulNotificationTest()

        #expect(snapshot.executed == [.testNotification(.claude)])
        #expect(snapshot.inspectionCount == 1)
        #expect(snapshot.noticeKind == .success)
        #expect(snapshot.noticeMessage == "Notification delivered")
    }

    @Test @MainActor func externalRefreshClearsNotificationMutationNotice() async {
        let snapshot = await SetupWorkflowFixtures.notificationNoticeLifecycle()

        #expect(snapshot.noticeAfterOperation?.kind == .success)
        #expect(snapshot.noticeAfterExternalRefresh == nil)
    }

    @Test @MainActor func externalRefreshClearsLaunchAtLoginMutationNotice() async {
        let snapshot = await SetupWorkflowFixtures.launchAtLoginNoticeLifecycle()

        #expect(snapshot.noticeAfterOperation?.kind == .success)
        #expect(snapshot.noticeAfterExternalRefresh == nil)
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
