import Foundation

/// Decides whether a failed refresh should keep showing the previous usage
/// numbers (tagged "Cached") instead of blanking to `--`.
///
/// Preserving is limited so genuine auth changes still surface: rate-limit
/// failures are always preserved (they are transient by nature), and a single
/// transient Claude auth hiccup is preserved once before the real error shows.
enum UsageSnapshotMerger {
    struct Result: Equatable {
        let snapshot: AgentUsageSnapshot
        let preservedPrevious: Bool
        let hasFreshUsageData: Bool
    }

    static func merge(
        previous: AgentUsageSnapshot,
        current: AgentUsageSnapshot,
        preservedFailureCount: Int,
        shouldPreservePrevious: Bool = true
    ) -> Result {
        guard shouldPreservePrevious,
              shouldPreserve(
                  previous: previous,
                  current: current,
                  preservedFailureCount: preservedFailureCount
              )
        else {
            return Result(
                snapshot: current,
                preservedPrevious: false,
                hasFreshUsageData: hasUsageData(current)
            )
        }

        return Result(
            snapshot: snapshotWithCacheDetail(previous: previous, current: current),
            preservedPrevious: true,
            hasFreshUsageData: false
        )
    }

    static func hasUsageData(_ snapshot: AgentUsageSnapshot) -> Bool {
        snapshot.fiveHour.usedPercentage != nil || snapshot.weekly.usedPercentage != nil
    }

    private static func shouldPreserve(
        previous: AgentUsageSnapshot,
        current: AgentUsageSnapshot,
        preservedFailureCount: Int
    ) -> Bool {
        guard !hasUsageData(current) else {
            return false
        }
        guard hasUsageData(previous) else {
            return false
        }

        let message = (current.fiveHour.message ?? current.weekly.message ?? "").lowercased()
        if message.contains("http 429") || message.contains("rate limit") {
            return true
        }

        guard current.agent == .claude, preservedFailureCount == 0 else {
            return false
        }

        return isTransientClaudeAuthFailure(message)
    }

    private static func snapshotWithCacheDetail(
        previous: AgentUsageSnapshot,
        current: AgentUsageSnapshot
    ) -> AgentUsageSnapshot {
        var snapshot = previous
        let message = current.fiveHour.message ?? current.weekly.message ?? "refresh failed"
        snapshot.detail = cachedDetail(previous.detail, message: message)
        return snapshot
    }

    private static func cachedDetail(_ detail: String?, message: String) -> String {
        let existingParts = detail?
            .components(separatedBy: " · ")
            .filter { !$0.hasPrefix("Cached:") } ?? []
        return (existingParts + ["Cached: \(message)"]).joined(separator: " · ")
    }

    private static func isTransientClaudeAuthFailure(_ message: String) -> Bool {
        message.contains("credentials not found")
            || message.contains("credentials could not be read")
            || message.contains("authentication failed")
            || message.contains("session expired")
    }
}
