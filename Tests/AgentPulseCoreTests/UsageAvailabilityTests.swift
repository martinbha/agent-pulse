import Testing

@testable import AgentPulseCore

@Suite struct UsageAvailabilityTests {
    @Test func usagePresentIsAvailable() {
        let snapshot = UsageStoreFixtures.usage(.claude, fiveHour: 42, weekly: 67)

        #expect(UsageStoreFixtures.availability(for: snapshot) == .available)
    }

    @Test func loadingPlaceholderIsLoading() {
        #expect(UsageStoreFixtures.availability(for: .loading(.claude)) == .loading)
    }

    @Test func claudeMissingCredentialsIsMissingAuth() {
        let snapshot = UsageStoreFixtures.failure(.claude, message: "Claude credentials not found.")

        #expect(UsageStoreFixtures.availability(for: snapshot) == .missingAuth)
    }

    @Test func claudeKeychainDenialIsAccessDenied() {
        let snapshot = UsageStoreFixtures.failure(.claude, message: "Claude Keychain access denied.")

        #expect(UsageStoreFixtures.availability(for: snapshot) == .accessDenied)
    }

    @Test func claudeExpiredSessionIsSessionExpired() {
        let snapshot = UsageStoreFixtures.failure(.claude, message: "Claude session expired; log in again.")

        #expect(UsageStoreFixtures.availability(for: snapshot) == .sessionExpired)
    }

    @Test func codexNotInstalledIsNotInstalled() {
        let snapshot = UsageStoreFixtures.failure(.codex, message: "codex is not installed or not on PATH.")

        #expect(UsageStoreFixtures.availability(for: snapshot) == .notInstalled)
    }

    @Test func codexNotLoggedInIsNotLoggedIn() {
        let snapshot = UsageStoreFixtures.failure(.codex, message: "You are not logged in. Please log in.")

        #expect(UsageStoreFixtures.availability(for: snapshot) == .notLoggedIn)
    }

    @Test func unknownMessageIsError() {
        let snapshot = UsageStoreFixtures.failure(.codex, message: "something exploded")

        #expect(UsageStoreFixtures.availability(for: snapshot) == .error("something exploded"))
    }
}

@Suite struct UsageSnapshotMergerTests {
    @Test func freshUsageReplacesPrevious() {
        let previous = UsageStoreFixtures.usage(.claude, fiveHour: 10, weekly: 20)
        let current = UsageStoreFixtures.usage(.claude, fiveHour: 30, weekly: 40)

        let result = UsageStoreFixtures.mergePreservesPrevious(previous: previous, current: current)

        #expect(!result.preservedPrevious)
        #expect(result.hasFreshUsageData)
        #expect(result.snapshot.fiveHour.usedPercentage == 30)
    }

    @Test func rateLimitFailurePreservesPrevious() {
        let previous = UsageStoreFixtures.usage(.codex, fiveHour: 10, weekly: 20)
        let current = UsageStoreFixtures.failure(.codex, message: "Codex usage endpoint returned HTTP 429.")

        let result = UsageStoreFixtures.mergePreservesPrevious(previous: previous, current: current)

        #expect(result.preservedPrevious)
        #expect(!result.hasFreshUsageData)
        #expect(result.snapshot.fiveHour.usedPercentage == 10)
        #expect(result.snapshot.detail?.contains("Cached:") == true)
    }

    @Test func firstClaudeAuthFailurePreservesButSecondSurfaces() {
        let previous = UsageStoreFixtures.usage(.claude, fiveHour: 10, weekly: 20)
        let current = UsageStoreFixtures.failure(.claude, message: "Claude authentication failed.")

        let first = UsageStoreFixtures.mergePreservesPrevious(
            previous: previous, current: current, preservedFailureCount: 0
        )
        #expect(first.preservedPrevious)

        let second = UsageStoreFixtures.mergePreservesPrevious(
            previous: previous, current: current, preservedFailureCount: 1
        )
        #expect(!second.preservedPrevious)
        #expect(second.snapshot.fiveHour.usedPercentage == nil)
    }

    @Test func codexAuthFailureDoesNotPreserve() {
        let previous = UsageStoreFixtures.usage(.codex, fiveHour: 10, weekly: 20)
        let current = UsageStoreFixtures.failure(.codex, message: "not logged in")

        let result = UsageStoreFixtures.mergePreservesPrevious(previous: previous, current: current)

        #expect(!result.preservedPrevious)
    }

    @Test func forcedRefreshNeverPreserves() {
        let previous = UsageStoreFixtures.usage(.claude, fiveHour: 10, weekly: 20)
        let current = UsageStoreFixtures.failure(.claude, message: "Claude authentication failed.")

        let result = UsageStoreFixtures.mergePreservesPrevious(
            previous: previous, current: current, shouldPreservePrevious: false
        )

        #expect(!result.preservedPrevious)
    }

    @Test func noPreviousDataCannotPreserve() {
        let previous = AgentUsageSnapshot.loading(.claude)
        let current = UsageStoreFixtures.failure(.claude, message: "Claude authentication failed.")

        let result = UsageStoreFixtures.mergePreservesPrevious(previous: previous, current: current)

        #expect(!result.preservedPrevious)
    }
}
