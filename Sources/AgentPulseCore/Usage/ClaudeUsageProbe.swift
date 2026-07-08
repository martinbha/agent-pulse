import Foundation

/// Fetches Claude's current 5-hour and weekly usage windows using the
/// credentials resolved by `ClaudeCredentialLoader`.
///
/// Desktop-sourced tokens refreshed by us are only remembered in memory (the
/// loader never writes Claude Desktop state); the cache is bypassed as soon as
/// Desktop itself provides a fresh token.
final class ClaudeUsageProbe: @unchecked Sendable {
    private let credentialLoader: ClaudeCredentialLoader
    private let apiClient: ClaudeAPIClient
    private let lock = NSLock()
    private var desktopCredentialsCache: ClaudeCredentialResult?

    init(
        credentialLoader: ClaudeCredentialLoader = ClaudeCredentialLoader(),
        apiClient: ClaudeAPIClient = ClaudeAPIClient()
    ) {
        self.credentialLoader = credentialLoader
        self.apiClient = apiClient
    }

    func fetch(trigger: RefreshTrigger = .automatic) async -> AgentUsageSnapshot {
        do {
            if trigger == .manual {
                setCachedDesktopCredentials(nil)
            }

            let resolution = credentialLoader.resolveCredentials(refreshKeychainAccess: trigger == .manual)
            guard var credentials = resolution.credentials else {
                if let issue = resolution.issue {
                    throw ProcessRunnerError.invalidResponse(issue.message)
                }
                throw ProcessRunnerError.invalidResponse("Claude credentials not found.")
            }

            if credentialLoader.needsRefresh(credentials.oauth) {
                if credentials.source == .environment {
                    // setup-token style credentials have no refresh flow; use them as-is
                } else if let cached = cachedDesktopCredentials(), !credentialLoader.needsRefresh(cached.oauth) {
                    credentials = cached
                } else if credentials.oauth.refreshToken != nil {
                    credentials = try await refreshAndRemember(credentials)
                } else {
                    throw ProcessRunnerError.invalidResponse("Claude session expired; log in again.")
                }
            } else if credentials.source == .desktop {
                // Desktop refreshed its own token; drop our in-memory copy.
                setCachedDesktopCredentials(nil)
            }

            var usage: ClaudeUsageResponse
            do {
                usage = try await apiClient.fetchUsage(credentials.oauth.accessToken)
            } catch let error as ProcessRunnerError {
                if shouldRetryAfterAuthenticationError(error),
                   credentials.source != .environment,
                   credentials.oauth.refreshToken != nil {
                    credentials = try await refreshAndRemember(credentials)
                    usage = try await apiClient.fetchUsage(credentials.oauth.accessToken)
                } else {
                    throw error
                }
            }

            return AgentUsageSnapshot(
                agent: .claude,
                fiveHour: UsageWindow(
                    kind: .fiveHour,
                    usedPercentage: usage.fiveHour?.utilization,
                    resetsAt: Self.parseISODate(usage.fiveHour?.resetsAt),
                    message: usage.fiveHour == nil ? "No 5h limit returned." : nil
                ),
                weekly: UsageWindow(
                    kind: .weekly,
                    usedPercentage: usage.sevenDay?.utilization,
                    resetsAt: Self.parseISODate(usage.sevenDay?.resetsAt),
                    message: usage.sevenDay == nil ? "No weekly limit returned." : nil
                ),
                detail: credentials.oauth.subscriptionType.map(Self.formatSubscriptionType(_:))
            )
        } catch {
            return .failure(.claude, message: error.localizedDescription)
        }
    }

    private func refreshAndRemember(_ credentials: ClaudeCredentialResult) async throws -> ClaudeCredentialResult {
        let refreshed = try await apiClient.refreshToken(credentials, credentialLoader)
        if refreshed.source == .desktop {
            setCachedDesktopCredentials(refreshed)
        }
        return refreshed
    }

    private func cachedDesktopCredentials() -> ClaudeCredentialResult? {
        lock.lock()
        defer { lock.unlock() }
        return desktopCredentialsCache
    }

    private func setCachedDesktopCredentials(_ credentials: ClaudeCredentialResult?) {
        lock.lock()
        defer { lock.unlock() }
        desktopCredentialsCache = credentials
    }

    func shouldRetryAfterAuthenticationError(_ error: ProcessRunnerError) -> Bool {
        guard case .invalidResponse(let message) = error else {
            return false
        }
        return message == "Claude authentication failed."
    }

    static func parseISODate(_ isoString: String?) -> Date? {
        guard let isoString else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            return date
        }

        // The usage endpoint returns microsecond-precision fractions
        // (e.g. ".348861+00:00"), which ISO8601DateFormatter rejects; trim
        // to millisecond precision and retry.
        guard let normalized = normalizeFractionalSeconds(isoString) else {
            return nil
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: normalized)
    }

    private static func normalizeFractionalSeconds(_ value: String) -> String? {
        guard let dotIndex = value.firstIndex(of: ".") else {
            return nil
        }

        let start = value.index(after: dotIndex)
        var end = start
        while end < value.endIndex, value[end].isNumber {
            end = value.index(after: end)
        }

        let digits = value[start..<end]
        guard digits.count > 3 else {
            return nil
        }
        return String(value[..<start] + digits.prefix(3) + value[end...])
    }

    static func formatSubscriptionType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "claude_max", "max":
            return "Max"
        case "claude_pro", "pro":
            return "Pro"
        case "api", "claude_api":
            return "API"
        default:
            return raw
        }
    }

    // MARK: - Live API calls

    static func liveRefreshToken(
        _ credentials: ClaudeCredentialResult,
        credentialLoader: ClaudeCredentialLoader
    ) async throws -> ClaudeCredentialResult {
        guard let refreshToken = credentials.oauth.refreshToken else {
            return credentials
        }

        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProcessRunnerError.invalidResponse("Claude refresh endpoint returned an invalid response.")
        }

        if http.statusCode == 400 || http.statusCode == 401 {
            throw ProcessRunnerError.invalidResponse("Claude session expired; log in again.")
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw ProcessRunnerError.invalidResponse("Claude token refresh failed with HTTP \(http.statusCode).")
        }

        let payload = try JSONDecoder().decode(ClaudeRefreshResponse.self, from: data)
        guard let accessToken = payload.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty else {
            throw ProcessRunnerError.invalidResponse("Claude token refresh returned no access token.")
        }

        var updated = credentials
        updated.oauth.accessToken = accessToken
        if let refreshToken = payload.refreshToken {
            updated.oauth.refreshToken = refreshToken
        }
        if let expiresIn = payload.expiresIn {
            updated.oauth.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
        }
        credentialLoader.saveCredentials(updated)
        return updated
    }

    static func liveFetchUsage(with accessToken: String) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AgentPulse", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProcessRunnerError.invalidResponse("Claude usage endpoint returned an invalid response.")
            }

            switch http.statusCode {
            case 200 ..< 300:
                return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            case 401, 403:
                throw ProcessRunnerError.invalidResponse("Claude authentication failed.")
            default:
                throw ProcessRunnerError.invalidResponse("Claude usage endpoint returned HTTP \(http.statusCode).")
            }
        } catch let error as ProcessRunnerError {
            throw error
        } catch {
            throw ProcessRunnerError.invalidResponse("Claude usage request failed: \(error.localizedDescription)")
        }
    }
}

struct ClaudeAPIClient: Sendable {
    let refreshToken: @Sendable (ClaudeCredentialResult, ClaudeCredentialLoader) async throws -> ClaudeCredentialResult
    let fetchUsage: @Sendable (String) async throws -> ClaudeUsageResponse

    init(
        refreshToken: @escaping @Sendable (ClaudeCredentialResult, ClaudeCredentialLoader) async throws -> ClaudeCredentialResult = { try await ClaudeUsageProbe.liveRefreshToken($0, credentialLoader: $1) },
        fetchUsage: @escaping @Sendable (String) async throws -> ClaudeUsageResponse = { try await ClaudeUsageProbe.liveFetchUsage(with: $0) }
    ) {
        self.refreshToken = refreshToken
        self.fetchUsage = fetchUsage
    }
}

struct ClaudeUsageResponse: Decodable, Sendable {
    let fiveHour: ClaudeQuotaData?
    let sevenDay: ClaudeQuotaData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeQuotaData: Decodable, Sendable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ClaudeRefreshResponse: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
