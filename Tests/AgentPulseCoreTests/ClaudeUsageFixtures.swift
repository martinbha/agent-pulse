import Foundation

@testable import AgentPulseCore

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Returns the call number (1-based) after incrementing.
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

enum ClaudeUsageFixtures {
    static let usageJSON = """
    {
      "five_hour": { "utilization": 42.5, "resets_at": "2026-01-01T10:00:00.000Z" },
      "seven_day": { "utilization": 67.0, "resets_at": "2026-01-05T00:00:00Z" }
    }
    """

    static let fiveHourOnlyJSON = """
    {
      "five_hour": { "utilization": 10.0, "resets_at": "2026-01-01T10:00:00Z" }
    }
    """

    static func decodedUsage(_ json: String) -> ClaudeUsageResponse? {
        try? JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(json.utf8))
    }

    static func fiveHourUtilization(_ json: String) -> Double? {
        decodedUsage(json)?.fiveHour?.utilization
    }

    static func weeklyUtilization(_ json: String) -> Double? {
        decodedUsage(json)?.sevenDay?.utilization
    }

    static func weeklyIsMissing(_ json: String) -> Bool {
        guard let decoded = decodedUsage(json) else {
            return false
        }
        return decoded.sevenDay == nil
    }

    static func parsesISODate(_ value: String) -> Bool {
        ClaudeUsageProbe.parseISODate(value) != nil
    }

    static func isoDatesParseToSameInstant(_ lhs: String, _ rhs: String) -> Bool {
        guard
            let left = ClaudeUsageProbe.parseISODate(lhs),
            let right = ClaudeUsageProbe.parseISODate(rhs)
        else {
            return false
        }
        return abs(left.timeIntervalSince(right)) < 0.002
    }

    // MARK: - Probe scenarios

    static func fetchWithValidFileCredentials() async -> AgentUsageSnapshot {
        let loader = validFileLoader()
        let probe = ClaudeUsageProbe(credentialLoader: loader, apiClient: successClient())
        return await probe.fetch()
    }

    static func fetchWithoutCredentials() async -> AgentUsageSnapshot {
        let loader = ClaudeCredentialFixtures.makeLoader()
        let probe = ClaudeUsageProbe(credentialLoader: loader, apiClient: successClient())
        return await probe.fetch()
    }

    /// First usage call fails with an auth error; the probe must refresh once
    /// and retry. Returns the snapshot and the refresh-call count.
    static func fetchRetriesAfterAuthFailure() async -> (snapshot: AgentUsageSnapshot, refreshCalls: Int) {
        let refreshCounter = CallCounter()
        let usageCounter = CallCounter()

        let client = ClaudeAPIClient(
            refreshToken: { credentials, _ in
                _ = refreshCounter.increment()
                var updated = credentials
                updated.oauth.accessToken = "refreshed-token"
                updated.oauth.expiresAt = farFutureExpiryMs()
                return updated
            },
            fetchUsage: { _ in
                if usageCounter.increment() == 1 {
                    throw ProcessRunnerError.invalidResponse("Claude authentication failed.")
                }
                return Self.decodedUsage(Self.usageJSON)!
            }
        )

        let probe = ClaudeUsageProbe(credentialLoader: validFileLoader(), apiClient: client)
        let snapshot = await probe.fetch()
        return (snapshot, refreshCounter.count)
    }

    /// Environment tokens have no expiry and no refresh flow; the probe must
    /// use them as-is. Returns the snapshot and the refresh-call count.
    static func fetchWithEnvironmentToken() async -> (snapshot: AgentUsageSnapshot, refreshCalls: Int) {
        let refreshCounter = CallCounter()
        let client = ClaudeAPIClient(
            refreshToken: { credentials, _ in
                _ = refreshCounter.increment()
                return credentials
            },
            fetchUsage: { _ in Self.decodedUsage(Self.usageJSON)! }
        )

        let loader = ClaudeCredentialFixtures.makeLoader(environmentToken: "env-token")
        let probe = ClaudeUsageProbe(credentialLoader: loader, apiClient: client)
        let snapshot = await probe.fetch()
        return (snapshot, refreshCounter.count)
    }

    static func fetchWithExpiredNonRefreshableCredentials() async -> String? {
        let json = credentialsFileJSON(expiresAtMs: 1000, refreshToken: nil)
        let loader = ClaudeCredentialFixtures.makeLoader(fileJSON: json)
        let probe = ClaudeUsageProbe(credentialLoader: loader, apiClient: successClient())
        let snapshot = await probe.fetch()
        return snapshot.fiveHour.message
    }

    /// Desktop-sourced credentials are expired on disk; after one refresh the
    /// probe must reuse the in-memory result on the next fetch instead of
    /// refreshing again. Returns the refresh-call count after two fetches.
    static func desktopRefreshCountAcrossTwoFetches() async -> Int {
        let refreshCounter = CallCounter()
        let client = ClaudeAPIClient(
            refreshToken: { credentials, _ in
                _ = refreshCounter.increment()
                var updated = credentials
                updated.oauth.accessToken = "refreshed-desktop-token"
                updated.oauth.expiresAt = farFutureExpiryMs()
                return updated
            },
            fetchUsage: { _ in Self.decodedUsage(Self.usageJSON)! }
        )

        let expiredDesktopCache = """
        {
          "user:sessions:claude_code:abc": {
            "token": "stale-desktop-token",
            "refreshToken": "desktop-refresh",
            "expiresAt": 1000
          }
        }
        """
        let loader = ClaudeCredentialFixtures.makeLoader(
            desktopTokenCacheJSON: expiredDesktopCache,
            desktopPassword: "test-password"
        )

        let probe = ClaudeUsageProbe(credentialLoader: loader, apiClient: client)
        _ = await probe.fetch()
        _ = await probe.fetch()
        return refreshCounter.count
    }

    static func formatTier(_ raw: String) -> String {
        ClaudeUsageProbe.formatSubscriptionType(raw)
    }

    // MARK: - Private helpers

    private static func successClient() -> ClaudeAPIClient {
        ClaudeAPIClient(
            refreshToken: { credentials, _ in credentials },
            fetchUsage: { _ in Self.decodedUsage(Self.usageJSON)! }
        )
    }

    private static func validFileLoader() -> ClaudeCredentialLoader {
        ClaudeCredentialFixtures.makeLoader(
            fileJSON: credentialsFileJSON(expiresAtMs: farFutureExpiryMs(), refreshToken: "file-refresh")
        )
    }

    private static func credentialsFileJSON(expiresAtMs: Double, refreshToken: String?) -> String {
        let refreshField = refreshToken.map { "\"refreshToken\": \"\($0)\"," } ?? ""
        return """
        {
          "claudeAiOauth": {
            "accessToken": "file-token",
            \(refreshField)
            "expiresAt": \(expiresAtMs),
            "subscriptionType": "claude_max"
          }
        }
        """
    }

    private static func farFutureExpiryMs() -> Double {
        (Date().timeIntervalSince1970 + 3600) * 1000
    }
}
