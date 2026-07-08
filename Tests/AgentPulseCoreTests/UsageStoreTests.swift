import Testing

@testable import AgentPulseCore

@MainActor
@Suite struct UsageStoreTests {
    @Test func refreshPopulatesSnapshotsAndLastUpdated() async {
        let defaults = UsageStoreFixtures.ephemeralDefaults()
        let (store, _, _) = UsageStoreFixtures.makeStore(
            claude: [UsageStoreFixtures.usage(.claude, fiveHour: 42, weekly: 67)],
            codex: [UsageStoreFixtures.usage(.codex, fiveHour: 12, weekly: 30)],
            defaults: defaults
        )

        await store.refresh()

        #expect(store.snapshot(for: .claude).fiveHour.usedPercentage == 42)
        #expect(store.snapshot(for: .codex).fiveHour.usedPercentage == 12)
        #expect(store.lastUpdated != nil)
        #expect(store.lastRefreshAttemptedAt != nil)
    }

    @Test func failedRefreshUpdatesAttemptButNotLastUpdated() async {
        let defaults = UsageStoreFixtures.ephemeralDefaults()
        let (store, _, _) = UsageStoreFixtures.makeStore(
            claude: [UsageStoreFixtures.failure(.claude, message: "Claude credentials not found.")],
            codex: [UsageStoreFixtures.failure(.codex, message: "codex is not installed or not on PATH.")],
            defaults: defaults
        )

        await store.refresh()

        #expect(store.lastUpdated == nil)
        #expect(store.lastRefreshAttemptedAt != nil)
        #expect(store.status(for: .claude).availability == .missingAuth)
        #expect(store.status(for: .codex).availability == .notInstalled)
    }

    @Test func transientFailureKeepsCachedNumbers() async {
        let defaults = UsageStoreFixtures.ephemeralDefaults()
        let (store, _, _) = UsageStoreFixtures.makeStore(
            claude: [
                UsageStoreFixtures.usage(.claude, fiveHour: 50, weekly: 60),
                UsageStoreFixtures.failure(.claude, message: "Claude usage endpoint returned HTTP 429."),
            ],
            codex: [UsageStoreFixtures.usage(.codex, fiveHour: 10, weekly: 20)],
            defaults: defaults
        )

        await store.refresh()
        await store.refresh()

        #expect(store.snapshot(for: .claude).fiveHour.usedPercentage == 50)
        #expect(store.snapshot(for: .claude).detail?.contains("Cached:") == true)
    }

    @Test func manualRefreshForcesCredentialRefreshAndClearsCache() async {
        let defaults = UsageStoreFixtures.ephemeralDefaults()
        let (store, claudeProbe, _) = UsageStoreFixtures.makeStore(
            claude: [
                UsageStoreFixtures.usage(.claude, fiveHour: 50, weekly: 60),
                UsageStoreFixtures.failure(.claude, message: "Claude credentials not found."),
            ],
            codex: [UsageStoreFixtures.usage(.codex, fiveHour: 10, weekly: 20)],
            defaults: defaults
        )

        await store.refresh()
        await store.refresh(trigger: .manual)

        // Manual refresh must not preserve the previous numbers; the real
        // failure surfaces, and the probe saw a manual trigger.
        #expect(store.snapshot(for: .claude).fiveHour.usedPercentage == nil)
        #expect(store.status(for: .claude).availability == .missingAuth)
        #expect(claudeProbe.manualTriggerCount == 1)
    }

    @Test func refreshIntervalPersists() {
        let defaults = UsageStoreFixtures.ephemeralDefaults()
        let (store, _, _) = UsageStoreFixtures.makeStore(claude: [], codex: [], defaults: defaults)

        store.setRefreshInterval(.tenMinutes)

        #expect(store.refreshInterval == .tenMinutes)

        let reloaded = UsageStore(
            probes: [:],
            userDefaults: defaults,
            startRefreshLoop: false
        )
        #expect(reloaded.refreshInterval == .tenMinutes)
    }

    @Test func concurrentRefreshIsIgnoredWhileInFlight() async {
        let defaults = UsageStoreFixtures.ephemeralDefaults()
        let (store, claudeProbe, _) = UsageStoreFixtures.makeStore(
            claude: [UsageStoreFixtures.usage(.claude, fiveHour: 42, weekly: 67)],
            codex: [UsageStoreFixtures.usage(.codex, fiveHour: 12, weekly: 30)],
            defaults: defaults
        )

        async let first: Void = store.refresh()
        async let second: Void = store.refresh()
        _ = await (first, second)

        // The guard drops one of the two overlapping refreshes.
        #expect(claudeProbe.fetchCount == 1)
    }
}
