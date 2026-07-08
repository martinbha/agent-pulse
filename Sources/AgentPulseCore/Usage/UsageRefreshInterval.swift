import Foundation

enum UsageRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    var id: Int { rawValue }

    var duration: TimeInterval { TimeInterval(rawValue) }

    var label: String {
        switch self {
        case .manual:
            return "Manual"
        case .oneMinute:
            return "1 minute"
        case .twoMinutes:
            return "2 minutes"
        case .fiveMinutes:
            return "5 minutes"
        case .tenMinutes:
            return "10 minutes"
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        }
    }

    static let defaultValue: UsageRefreshInterval = .fiveMinutes
}
