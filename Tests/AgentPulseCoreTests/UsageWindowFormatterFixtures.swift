import Foundation

@testable import AgentPulseCore

enum UsageWindowFormatterFixtures {
    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    // 2026-01-07 16:30 UTC is a Wednesday.
    private static func sampleReset() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 7
        components.hour = 16
        components.minute = 30
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private static func window(_ kind: UsageWindowKind, used: Double?, reset: Date?) -> UsageWindow {
        UsageWindow(kind: kind, usedPercentage: used, resetsAt: reset)
    }

    static func fiveHourResetText() -> String? {
        UsageWindowFormatter.resetText(
            for: window(.fiveHour, used: 42, reset: sampleReset()),
            calendar: utcCalendar(),
            locale: posix
        )
    }

    static func weeklyResetText() -> String? {
        UsageWindowFormatter.resetText(
            for: window(.weekly, used: 67, reset: sampleReset()),
            calendar: utcCalendar(),
            locale: posix
        )
    }

    static func resetTextIsNilWithoutDate() -> Bool {
        UsageWindowFormatter.resetText(for: window(.fiveHour, used: 42, reset: nil)) == nil
    }

    static func detailLineFull() -> String? {
        UsageWindowFormatter.detailLine(
            for: window(.fiveHour, used: 42, reset: sampleReset()),
            calendar: utcCalendar(),
            locale: posix
        )
    }

    static func detailLinePercentOnly() -> String? {
        UsageWindowFormatter.detailLine(for: window(.fiveHour, used: 42, reset: nil))
    }

    static func detailLineIsNilWhenEmpty() -> Bool {
        UsageWindowFormatter.detailLine(for: window(.fiveHour, used: nil, reset: nil)) == nil
    }

    static func lastUpdatedRecent() -> String {
        UsageWindowFormatter.lastUpdatedText(Date(timeIntervalSinceNow: -120), now: Date())
    }

    static func lastUpdatedNil() -> String {
        UsageWindowFormatter.lastUpdatedText(nil)
    }
}
