import Testing

@testable import AgentPulseCore

@Suite struct JSONHookConfigurationManagerTests {
    @Test func installPreviewApplyAndRemovalAreSafeAndIdempotent() throws {
        let snapshot = try JSONHookConfigurationFixtures.installAndRemovalLifecycle()

        #expect(snapshot.previewRequiresWrite)
        #expect(!snapshot.previewDidWrite)
        #expect(snapshot.previewKeptFileUnchanged)
        #expect(snapshot.firstDidWrite)
        #expect(snapshot.firstBackupRestoresOriginal)
        #expect(!snapshot.secondDidWrite)
        #expect(!snapshot.secondBackupCreated)
        #expect(snapshot.secondKeptFileUnchanged)
        #expect(snapshot.unknownSettingsPreserved)
        #expect(snapshot.unrelatedHooksPreserved)
        #expect(snapshot.installedOwnedEntryCount == snapshot.installedEventCount)
        #expect(snapshot.permissions == 0o640)
        #expect(snapshot.removalDidWrite)
        #expect(!snapshot.repeatedRemovalDidWrite)
        #expect(snapshot.ownedEntriesAfterRemoval == 0)
    }

    @Test func migratesLegacyCommandsAndDeduplicatesOwnedEntries() throws {
        let snapshot = try JSONHookConfigurationFixtures.migratesLegacyAndDuplicateEntries()

        #expect(snapshot.didWrite)
        #expect(snapshot.change?.kind == .updated)
        #expect(snapshot.change?.ownedEntryCount == 3)
        #expect(snapshot.ownedEntryCount == JSONHookEventSpec.defaultIntegration.count)
        #expect(snapshot.legacyEntryCount == 0)
        #expect(snapshot.unrelatedEntryCount == 1)
    }

    @Test func resolvesSymlinkWithoutReplacingIt() throws {
        let snapshot = try JSONHookConfigurationFixtures.preservesSymlinkAndTargetPermissions()

        #expect(snapshot.didWrite)
        #expect(snapshot.symlinkDestination == "../../shared/settings.json")
        #expect(snapshot.resolvedTargetMatches)
        #expect(snapshot.targetContainsHooks)
        #expect(snapshot.targetPermissions == 0o600)
        #expect(snapshot.backupRestoresOriginal)
    }

    @Test func invalidJSONIsNeverOverwritten() throws {
        let snapshot = try JSONHookConfigurationFixtures.invalidJSONIsBlocked()

        #expect(snapshot.blocker == .invalidJSON)
        #expect(snapshot.contentsUnchanged)
        #expect(!snapshot.backupCreated)
        #expect(!snapshot.didWrite)
    }

    @Test func unsupportedRequiredEventShapeIsBlocked() throws {
        let snapshot = try JSONHookConfigurationFixtures.unsupportedStructureIsBlocked()

        #expect(snapshot.blocker == .unsupportedHookStructure("hooks.PreToolUse"))
        #expect(snapshot.contentsUnchanged)
        #expect(!snapshot.backupCreated)
        #expect(!snapshot.didWrite)
    }

    @Test func nonObjectRootIsBlocked() throws {
        let snapshot = try JSONHookConfigurationFixtures.nonObjectRootIsBlocked()

        #expect(snapshot.blocker == .rootIsNotObject)
        #expect(snapshot.contentsUnchanged)
        #expect(!snapshot.backupCreated)
        #expect(!snapshot.didWrite)
    }

    @Test func backupFailurePreventsMutation() throws {
        let snapshot = try JSONHookConfigurationFixtures.backupFailureIsBlocked()

        guard case .backupFailed = snapshot.blocker else {
            Issue.record("Expected a structured backup failure")
            return
        }
        #expect(snapshot.contentsUnchanged)
        #expect(!snapshot.didWrite)
    }

    @Test func readOnlyTargetIsBlocked() throws {
        let snapshot = try JSONHookConfigurationFixtures.readOnlyTargetIsBlocked()

        guard case .targetIsNotWritable = snapshot.blocker else {
            Issue.record("Expected a structured read-only failure")
            return
        }
        #expect(snapshot.contentsUnchanged)
        #expect(!snapshot.backupCreated)
        #expect(!snapshot.didWrite)
    }

    @Test func missingConfigurationUsesSecureDefaultsWithoutBackup() throws {
        let snapshot = try JSONHookConfigurationFixtures.installsMissingConfigurationSecurely()

        #expect(snapshot.didWrite)
        #expect(!snapshot.backupCreated)
        #expect(snapshot.permissions == 0o600)
        #expect(!snapshot.repeatedDidWrite)
    }

    @Test func emptyConfigurationIsBackedUpAndKeepsPermissions() throws {
        let snapshot = try JSONHookConfigurationFixtures.installsEmptyConfigurationWithBackup()

        #expect(snapshot.didWrite)
        #expect(snapshot.backupCreated)
        #expect(snapshot.permissions == 0o644)
        #expect(!snapshot.repeatedDidWrite)
    }
}
