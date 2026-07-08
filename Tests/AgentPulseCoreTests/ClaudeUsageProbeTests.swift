import Testing

@testable import AgentPulseCore

@Suite struct ClaudeUsageDecodingTests {
    @Test func decodesBothWindows() {
        #expect(ClaudeUsageFixtures.fiveHourUtilization(ClaudeUsageFixtures.usageJSON) == 42.5)
        #expect(ClaudeUsageFixtures.weeklyUtilization(ClaudeUsageFixtures.usageJSON) == 67.0)
    }

    @Test func toleratesMissingWeeklyWindow() {
        #expect(ClaudeUsageFixtures.fiveHourUtilization(ClaudeUsageFixtures.fiveHourOnlyJSON) == 10.0)
        #expect(ClaudeUsageFixtures.weeklyIsMissing(ClaudeUsageFixtures.fiveHourOnlyJSON))
    }

    @Test func parsesISODatesWithAndWithoutFractionalSeconds() {
        #expect(ClaudeUsageFixtures.parsesISODate("2026-01-01T10:00:00.000Z"))
        #expect(ClaudeUsageFixtures.parsesISODate("2026-01-01T10:00:00Z"))
        #expect(!ClaudeUsageFixtures.parsesISODate("not-a-date"))
    }

    @Test func parsesMicrosecondPrecisionOffsetsFromLiveAPI() {
        // Shape observed from the live usage endpoint.
        #expect(ClaudeUsageFixtures.parsesISODate("2026-07-08T08:00:00.348861+00:00"))
        #expect(ClaudeUsageFixtures.isoDatesParseToSameInstant(
            "2026-01-01T10:00:00.500000Z",
            "2026-01-01T10:00:00.500Z"
        ))
    }
}

@Suite struct ClaudeUsageProbeTests {
    @Test func mapsUsageIntoSnapshot() async {
        let snapshot = await ClaudeUsageFixtures.fetchWithValidFileCredentials()

        #expect(snapshot.agent == .claude)
        #expect(snapshot.fiveHour.usedPercentage == 42.5)
        #expect(snapshot.fiveHour.resetsAt != nil)
        #expect(snapshot.fiveHour.message == nil)
        #expect(snapshot.weekly.usedPercentage == 67.0)
        #expect(snapshot.detail == "Max")
    }

    @Test func missingCredentialsProduceFailureSnapshot() async {
        let snapshot = await ClaudeUsageFixtures.fetchWithoutCredentials()

        #expect(snapshot.fiveHour.usedPercentage == nil)
        #expect(snapshot.fiveHour.message == "Claude credentials not found.")
        #expect(snapshot.weekly.message == "Claude credentials not found.")
    }

    @Test func retriesOnceAfterAuthFailure() async {
        let result = await ClaudeUsageFixtures.fetchRetriesAfterAuthFailure()

        #expect(result.refreshCalls == 1)
        #expect(result.snapshot.fiveHour.usedPercentage == 42.5)
    }

    @Test func environmentTokenIsNeverRefreshed() async {
        let result = await ClaudeUsageFixtures.fetchWithEnvironmentToken()

        #expect(result.refreshCalls == 0)
        #expect(result.snapshot.fiveHour.usedPercentage == 42.5)
    }

    @Test func expiredSessionWithoutRefreshTokenReportsExpiry() async {
        let message = await ClaudeUsageFixtures.fetchWithExpiredNonRefreshableCredentials()

        #expect(message == "Claude session expired; log in again.")
    }

    @Test func desktopRefreshIsRememberedInMemory() async {
        let refreshCalls = await ClaudeUsageFixtures.desktopRefreshCountAcrossTwoFetches()

        #expect(refreshCalls == 1)
    }
}

@Suite struct ClaudeSubscriptionFormattingTests {
    @Test func knownTiersAreFormatted() {
        #expect(ClaudeUsageFixtures.formatTier("claude_max") == "Max")
        #expect(ClaudeUsageFixtures.formatTier("claude_pro") == "Pro")
        #expect(ClaudeUsageFixtures.formatTier("api") == "API")
    }

    @Test func unknownTierPassesThrough() {
        #expect(ClaudeUsageFixtures.formatTier("claude_team") == "claude_team")
    }
}
