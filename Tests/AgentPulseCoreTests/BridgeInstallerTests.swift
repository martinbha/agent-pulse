import Testing

@testable import AgentPulseCore

@Suite struct BridgeInstallerTests {
    @Test func installsAtStablePathWithSecurePermissionsAndIsIdempotent() throws {
        let snapshot = try BridgeInstallerFixtures.installLifecycle()

        #expect(snapshot.initialStatus == .missing)
        #expect(snapshot.installedStatus == .current(version: "1.0.0"))
        #expect(snapshot.repeatedStatus == .current(version: "1.0.0"))
        #expect(snapshot.executableContents == "bridge-v1")
        #expect(snapshot.executablePath.hasSuffix("/.agent-pulse/bin/agent-pulse-hook"))
        #expect(snapshot.executablePermissions == 0o755)
        #expect(snapshot.rootPermissions == 0o700)
        #expect(snapshot.binPermissions == 0o700)
        #expect(snapshot.configPermissions == 0o600)
        #expect(snapshot.replacementCountAfterInstall == 2)
        #expect(snapshot.replacementCountAfterRepeat == 2)
    }

    @Test func detectsAndUpgradesOutdatedBridge() throws {
        let snapshot = try BridgeInstallerFixtures.upgradeLifecycle()

        #expect(
            snapshot.outdatedStatus
                == .outdated(installedVersion: "1.0.0", bundledVersion: "2.0.0")
        )
        #expect(snapshot.upgradedStatus == .current(version: "2.0.0"))
        #expect(snapshot.executableContents == "bridge-v2")
    }

    @Test func repairsExecutablePermissions() throws {
        let snapshot = try BridgeInstallerFixtures.repairLifecycle()

        #expect(snapshot.damagedStatus == .damaged(
            reason: "The installed bridge permissions are not 0755."
        ))
        #expect(snapshot.repairedStatus == .current(version: "1.0.0"))
        #expect(snapshot.executablePermissions == 0o755)
    }

    @Test func removalKeepsUnrelatedFiles() throws {
        let snapshot = try BridgeInstallerFixtures.removalScope()

        #expect(!snapshot.executableExists)
        #expect(!snapshot.versionExists)
        #expect(snapshot.configExists)
        #expect(snapshot.unrelatedRootFileExists)
        #expect(snapshot.unrelatedBinFileExists)
    }

    @Test func interruptedReplacementKeepsPreviousExecutable() throws {
        let snapshot = try BridgeInstallerFixtures.interruptedReplacement()

        guard case .some(.replacementFailed(_)) = snapshot.error else {
            Issue.record("Expected a structured atomic replacement failure")
            return
        }
        #expect(snapshot.executableContents == "bridge-v1")
        #expect(snapshot.installedVersion == "1.0.0")
        #expect(snapshot.temporaryFileCount == 0)
    }

    @Test func rejectsAppTranslocationBeforeMutation() throws {
        let snapshot = try BridgeInstallerFixtures.translocationRejection()

        #expect(snapshot.classified)
        guard case .some(.appTranslocated(_)) = snapshot.error else {
            Issue.record("Expected an App Translocation failure")
            return
        }
        #expect(!snapshot.installationRootExists)
    }

    @Test func reportsDirectoryCreationFailure() throws {
        let error = try BridgeInstallerFixtures.blockedDirectoryError()

        guard case .directoryCreationFailed = error else {
            Issue.record("Expected a structured directory creation failure")
            return
        }
    }

    @Test func reportsPermissionDeniedFailure() throws {
        let error = try BridgeInstallerFixtures.permissionDeniedError()

        guard case .directoryCreationFailed = error else {
            Issue.record("Expected a structured permission-denied failure")
            return
        }
    }

    @Test @MainActor func writesOwnerOnlyConfiguration() throws {
        let permissions = try BridgeInstallerFixtures.settingsPermissions()

        #expect(permissions.directory == 0o700)
        #expect(permissions.configuration == 0o600)
    }
}
