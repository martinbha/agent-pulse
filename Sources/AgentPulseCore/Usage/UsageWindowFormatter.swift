import Foundation

/// Pure formatting helpers for rendering usage windows in the dropdown.
enum UsageWindowFormatter {
    /// Whole-percent text like "42%", or nil when no usage is available.
    static func percentText(_ usedPercentage: Double?) -> String? {
        guard let usedPercentage else {
            return nil
        }
        return "\(Int(usedPercentage))%"
    }

    /// Progress-bar fill in 0...1, clamped. Missing usage reads as empty.
    static func fraction(_ usedPercentage: Double?) -> Double {
        guard let usedPercentage else {
            return 0
        }
        return min(max(usedPercentage / 100, 0), 1)
    }

    /// Time remaining until a window resets, e.g. "4d 5h 30m", "3h 06m", "05m",
    /// or "<1m" when under a minute (or already reset).
    static func resetCountdown(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now).rounded(.down)))
        if seconds < 60 {
            return "<1m"
        }

        let totalMinutes = seconds / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        var parts: [String] = []
        if days > 0 {
            parts.append("\(days)d")
        }
        if hours > 0 || days > 0 {
            parts.append("\(hours)h")
        }
        parts.append(String(format: "%02dm", minutes))
        return parts.joined(separator: " ")
    }

    /// Combined "42% · 3h 06m", or whichever part is available.
    static func detailLine(for window: UsageWindow, now: Date = .now) -> String? {
        let parts = [
            percentText(window.usedPercentage),
            window.resetsAt.map { resetCountdown($0, now: now) },
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
