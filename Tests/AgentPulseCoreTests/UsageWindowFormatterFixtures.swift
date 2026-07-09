import Foundation

@testable import AgentPulseCore

enum UsageWindowFormatterFixtures {
    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private static func window(_ kind: UsageWindowKind, used: Double?, resetInSeconds: Double?) -> UsageWindow {
        UsageWindow(
            kind: kind,
            usedPercentage: used,
            resetsAt: resetInSeconds.map { now.addingTimeInterval($0) }
        )
    }

    // MARK: - Reset countdown

    static func countdownDaysHoursMinutes() -> String {
        UsageWindowFormatter.resetCountdown(now.addingTimeInterval(4 * 86_400 + 5 * 3_600 + 30 * 60), now: now)
    }

    static func countdownHoursMinutes() -> String {
        UsageWindowFormatter.resetCountdown(now.addingTimeInterval(3 * 3_600 + 6 * 60), now: now)
    }

    static func countdownMinutesOnly() -> String {
        UsageWindowFormatter.resetCountdown(now.addingTimeInterval(5 * 60), now: now)
    }

    static func countdownUnderAMinute() -> String {
        UsageWindowFormatter.resetCountdown(now.addingTimeInterval(30), now: now)
    }

    static func countdownAlreadyReset() -> String {
        UsageWindowFormatter.resetCountdown(now.addingTimeInterval(-100), now: now)
    }

    // MARK: - Detail line

    static func detailLineFull() -> String? {
        UsageWindowFormatter.detailLine(for: window(.weekly, used: 42, resetInSeconds: 3 * 3_600 + 6 * 60), now: now)
    }

    static func detailLinePercentOnly() -> String? {
        UsageWindowFormatter.detailLine(for: window(.fiveHour, used: 42, resetInSeconds: nil), now: now)
    }

    static func detailLineIsNilWhenEmpty() -> Bool {
        UsageWindowFormatter.detailLine(for: window(.fiveHour, used: nil, resetInSeconds: nil), now: now) == nil
    }

    // MARK: - Header

    static func lastUpdatedRecent() -> String {
        UsageWindowFormatter.lastUpdatedText(Date(timeIntervalSinceNow: -120), now: Date())
    }

    static func lastUpdatedNil() -> String {
        UsageWindowFormatter.lastUpdatedText(nil)
    }
}
