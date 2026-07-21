import Testing

@testable import AgentPulseCore

@Suite struct SetupHealthTests {
    @Test func applicationLocationClassificationCoversInstallAndDevelopmentLayouts() {
        let snapshot = SetupHealthFixtures.applicationLocations()

        guard case .applications = snapshot.systemApplications else {
            Issue.record("Expected a system Applications install")
            return
        }
        guard case .userApplications = snapshot.userApplications else {
            Issue.record("Expected a user Applications install")
            return
        }
        guard case .other = snapshot.otherBundle else {
            Issue.record("Expected a bundle outside Applications")
            return
        }
        guard case .unbundled = snapshot.unbundled else {
            Issue.record("Expected a development executable")
            return
        }
        guard case .translocated = snapshot.translocated else {
            Issue.record("Expected App Translocation to be detected")
            return
        }
    }

    @Test func setupTransitionsProduceStableRepairRecommendations() {
        let snapshot = SetupHealthFixtures.setupTransitions()

        #expect(snapshot.translocatedAction == .moveApplication)
        #expect(snapshot.serverFailureAction == .restartLocalServer)
        #expect(snapshot.missingBridgeAction == .installBridge)
        #expect(snapshot.missingHostAction == .installHost(.codex))
        #expect(snapshot.missingHooksAction == .installIntegration(.claude))
        #expect(snapshot.completedAction == .none)
        #expect(snapshot.outdatedBridgeAction == .repairBridge)
        #expect(snapshot.duplicatedHooksAction == .repairIntegration(.codex))
        #expect(snapshot.invalidHooksAction == .reviewIntegrationConfiguration(.codex))
        #expect(snapshot.unsafeConfigurationAction == .reviewIntegrationConfiguration(.codex))
        #expect(snapshot.unsafeIntegrationAction == .reviewIntegrationConfiguration(.codex))
        #expect(snapshot.removedHooksAction == .installIntegration(.codex))
        #expect(snapshot.signInAction == .signIn(.claude))
        #expect(snapshot.testAction == .testIntegration(.claude))
        #expect(snapshot.notificationAction == .requestNotificationPermission)
        #expect(snapshot.loginAction == .approveLaunchAtLogin)
        #expect(snapshot.completeBlockingIssue == nil)
        #expect(snapshot.lastEventName == "Stop")
        #expect(snapshot.lastEventAge == 60)
    }

    @Test func bridgeAndConfigurationResultsMapToSharedStatuses() {
        let snapshot = SetupHealthFixtures.adapters()

        #expect(snapshot.missingBridge == .missing)
        #expect(snapshot.currentBridge == .current(version: "1.0.0"))
        #expect(
            snapshot.outdatedBridge
                == .outdated(installedVersion: "0.9.0", bundledVersion: "1.0.0")
        )
        guard case .unreadable = snapshot.unreadableBridge else {
            Issue.record("Expected an unreadable bridge status")
            return
        }
        guard case .invalid = snapshot.invalidBridge else {
            Issue.record("Expected an invalid bridge status")
            return
        }
        #expect(snapshot.missingJSON == .missing)
        #expect(snapshot.currentJSON == .current)
        #expect(snapshot.duplicateJSON == .duplicated(ownedEntryCount: 2))
        guard case .invalid = snapshot.invalidJSON else {
            Issue.record("Expected an invalid JSON configuration status")
            return
        }
        #expect(snapshot.missingTOML == .missing)
        #expect(snapshot.currentTOML == .current)
        #expect(snapshot.duplicateTOML == .duplicated(ownedEntryCount: 2))
        guard case .invalid = snapshot.invalidTOML else {
            Issue.record("Expected an invalid TOML configuration status")
            return
        }
    }

    @Test func asynchronousInspectionIsSideEffectFreeAndSanitizesDiagnostics() async {
        let snapshot = await SetupHealthFixtures.asynchronousInspection()

        #expect(snapshot.inspectedAtEpoch == 1_800_000_000)
        guard case .applications = snapshot.application else {
            Issue.record("Expected the injected application status")
            return
        }
        #expect(snapshot.serverIsHealthy)
        #expect(snapshot.bridge == .current(version: "1.0.0"))
        guard case .available = snapshot.firstHost else {
            Issue.record("Expected the injected host status")
            return
        }
        #expect(snapshot.secondHooks == .current)
        #expect(snapshot.firstUsage == .error)
        #expect(snapshot.notifications == .authorized)
        #expect(snapshot.launchAtLogin == .enabled)
        guard case .received(let event, _, let age) = snapshot.lastEvent else {
            Issue.record("Expected a recent integration event")
            return
        }
        #expect(event == "Working")
        #expect(age == 45)
        #expect(!snapshot.diagnosticsContainSecret)
        #expect(snapshot.inputsUnchanged)
    }
}
