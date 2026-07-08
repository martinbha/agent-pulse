import Foundation

enum RefreshTrigger: Sendable {
    case automatic
    case manual
}

enum UsageWindowKind: String, Sendable {
    case fiveHour = "5h"
    case weekly = "Week"
}

struct UsageWindow: Identifiable, Sendable, Equatable {
    let kind: UsageWindowKind
    var usedPercentage: Double?
    var resetsAt: Date?
    var message: String?

    var id: String { kind.rawValue }

    static func placeholder(_ kind: UsageWindowKind, message: String = "Loading…") -> UsageWindow {
        UsageWindow(kind: kind, usedPercentage: nil, resetsAt: nil, message: message)
    }
}

struct AgentUsageSnapshot: Sendable, Equatable {
    let agent: AgentKind
    var fiveHour: UsageWindow
    var weekly: UsageWindow
    var detail: String?

    static func loading(_ agent: AgentKind) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            agent: agent,
            fiveHour: .placeholder(.fiveHour),
            weekly: .placeholder(.weekly),
            detail: nil
        )
    }

    static func failure(_ agent: AgentKind, message: String) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            agent: agent,
            fiveHour: UsageWindow(kind: .fiveHour, usedPercentage: nil, resetsAt: nil, message: message),
            weekly: UsageWindow(kind: .weekly, usedPercentage: nil, resetsAt: nil, message: message),
            detail: nil
        )
    }
}
