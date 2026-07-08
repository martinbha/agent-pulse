import Foundation

/// Pure formatting helpers for rendering usage windows in the dropdown.
enum UsageWindowFormatter {
    /// Whole-percent text like "42%", or nil when no usage is available.
    static func percentText(_ usedPercentage: Double?) -> String? {
        guard let usedPercentage else {
            return nil
        }
        return "\(Int(usedPercentage.rounded()))%"
    }

    /// Progress-bar fill in 0...1, clamped. Missing usage reads as empty.
    static func fraction(_ usedPercentage: Double?) -> Double {
        guard let usedPercentage else {
            return 0
        }
        return min(max(usedPercentage / 100, 0), 1)
    }

    /// "resets 4:30 PM" for the 5-hour window (clock time) or "resets Tue" for
    /// the weekly window (weekday), or nil when no reset time is known.
    static func resetText(
        for window: UsageWindow,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        guard let resetsAt = window.resetsAt else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        switch window.kind {
        case .fiveHour:
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        case .weekly:
            formatter.setLocalizedDateFormatFromTemplate("EEE")
        }

        return "resets \(formatter.string(from: resetsAt))"
    }

    /// Combined "42% · resets 4:30 PM", or whichever part is available.
    static func detailLine(
        for window: UsageWindow,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String? {
        let parts = [
            percentText(window.usedPercentage),
            resetText(for: window, calendar: calendar, locale: locale),
        ].compactMap { $0 }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func lastUpdatedText(_ lastUpdated: Date?, now: Date = .now) -> String {
        guard let lastUpdated else {
            return "Not updated yet"
        }
        let relative = RelativeTimeFormatter.shared.localizedString(for: lastUpdated, relativeTo: now)
        return "Updated \(relative)"
    }

    /// User-facing reason a usage number is missing, or nil when usage is
    /// available or still loading.
    static func availabilityMessage(_ availability: UsageAvailability) -> String? {
        switch availability {
        case .loading, .available:
            return nil
        case .missingAuth, .notLoggedIn:
            return "Not logged in"
        case .accessDenied:
            return "Keychain access denied"
        case .sessionExpired:
            return "Session expired — log in again"
        case .notInstalled:
            return "CLI not found"
        case .error(let message):
            return message
        }
    }
}
