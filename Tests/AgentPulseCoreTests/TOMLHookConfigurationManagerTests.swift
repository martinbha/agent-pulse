import Testing

@testable import AgentPulseCore

@Suite struct TOMLHookConfigurationManagerTests {
    @Test func lifecyclePreservesUnmanagedBytesPermissionsAndBackups() throws {
        let snapshot = try TOMLHookConfigurationFixtures.lifecycle()

        #expect(snapshot.previewChange == .added)
        #expect(!snapshot.previewDidWrite)
        #expect(snapshot.previewKeptOriginal)
        #expect(snapshot.firstDidWrite)
        #expect(snapshot.backupRestoresOriginal)
        #expect(snapshot.unmanagedPrefixPreserved)
        #expect(snapshot.installedEvents == TOMLHookEventSpec.supportedIntegration.map(\.name))
        #expect(!snapshot.containsUnsupportedEvents)
        #expect(snapshot.installedPermissions == 0o640)
        #expect(!snapshot.secondDidWrite)
        #expect(snapshot.secondChange == .unchanged)
        #expect(!snapshot.secondCreatedBackup)
        #expect(snapshot.removalDidWrite)
        #expect(snapshot.removalRestoredOriginal)
        #expect(snapshot.removalPermissions == 0o640)
        #expect(!snapshot.repeatedRemovalDidWrite)
    }

    @Test func missingAndEmptyFilesUseSafePermissionsAndExpectedBackups() throws {
        let snapshot = try TOMLHookConfigurationFixtures.missingAndEmpty()

        #expect(snapshot.missingDidWrite)
        #expect(!snapshot.missingCreatedBackup)
        #expect(snapshot.missingPermissions == 0o600)
        #expect(snapshot.emptyDidWrite)
        #expect(snapshot.emptyBackupIsEmpty)
        #expect(snapshot.emptyPermissions == 0o644)
    }

    @Test func outdatedBlockIsReplacedWithoutReformattingNeighbors() throws {
        let snapshot = try TOMLHookConfigurationFixtures.outdatedBlock()

        #expect(snapshot.didWrite)
        #expect(snapshot.change == .updated)
        #expect(snapshot.prefixPreserved)
        #expect(snapshot.suffixPreserved)
        #expect(snapshot.installedEvents == TOMLHookEventSpec.supportedIntegration.map(\.name))
        #expect(snapshot.removedOutdatedContent)
    }

    @Test func malformedMarkerLayoutsNeverMutateTheFile() throws {
        for snapshot in try TOMLHookConfigurationFixtures.malformedMarkers() {
            #expect(snapshot.blocker == .malformedMarkers(snapshot.expectedError))
            #expect(!snapshot.didWrite)
            #expect(!snapshot.createdBackup)
            #expect(snapshot.contentsUnchanged)
        }
    }

    @Test func exactHistoricalBlocksAreMigratedAndDeduplicated() throws {
        let snapshot = try TOMLHookConfigurationFixtures.legacyMigration()

        #expect(snapshot.didWrite)
        #expect(snapshot.change == .updated)
        #expect(snapshot.legacyBlockCount == 2)
        #expect(snapshot.managedBlockCount == 1)
        #expect(snapshot.installedEvents == TOMLHookEventSpec.supportedIntegration.map(\.name))
        #expect(snapshot.removedLegacyPath)
        #expect(snapshot.removedUnsupportedEvents)
        #expect(snapshot.prefixPreserved)
        #expect(snapshot.suffixPreserved)
        #expect(!snapshot.repeatedDidWrite)
    }

    @Test func backupFailurePreventsMutation() throws {
        let snapshot = try TOMLHookConfigurationFixtures.backupFailure()

        guard case .backupFailed = snapshot.blocker else {
            Issue.record("Expected a structured backup failure")
            return
        }
        #expect(!snapshot.didWrite)
        #expect(snapshot.contentsUnchanged)
    }

    @Test func readOnlyTargetIsBlockedBeforeBackup() throws {
        let snapshot = try TOMLHookConfigurationFixtures.readOnlyTarget()

        guard case .targetIsNotWritable = snapshot.blocker else {
            Issue.record("Expected a structured read-only failure")
            return
        }
        #expect(!snapshot.didWrite)
        #expect(!snapshot.createdBackup)
        #expect(snapshot.contentsUnchanged)
    }

    @Test func symlinkIsPreservedWhileItsTargetIsUpdated() throws {
        let snapshot = try TOMLHookConfigurationFixtures.symlinkTarget()

        #expect(snapshot.didWrite)
        #expect(snapshot.resolvedTargetMatches)
        #expect(snapshot.symlinkDestination == "../../shared/config.toml")
        #expect(snapshot.targetContainsBlock)
        #expect(snapshot.targetPermissions == 0o600)
    }
}
