import Foundation

/// Derived availability of an agent's usage data, classified from the snapshot
/// so the UI can render a precise state (a number, a spinner, or a reason).
enum UsageAvailability: Equatable, Sendable {
    case loading
    case available
    case missingAuth
    case accessDenied
    case sessionExpired
    case notInstalled
    case notLoggedIn
    case error(String)

    var hasUsage: Bool {
        self == .available
    }
}

struct AgentUsageStatus: Equatable, Sendable {
    let agent: AgentKind
    let availability: UsageAvailability
    let message: String?
}

enum UsageAvailabilityClassifier {
    static func status(for snapshot: AgentUsageSnapshot) -> AgentUsageStatus {
        if snapshot.fiveHour.usedPercentage != nil || snapshot.weekly.usedPercentage != nil {
            return AgentUsageStatus(agent: snapshot.agent, availability: .available, message: nil)
        }

        let message = snapshot.fiveHour.message ?? snapshot.weekly.message
        guard let message else {
            return AgentUsageStatus(agent: snapshot.agent, availability: .loading, message: nil)
        }

        if message == "Loading…" {
            return AgentUsageStatus(agent: snapshot.agent, availability: .loading, message: nil)
        }

        switch snapshot.agent {
        case .claude:
            return classifyClaude(agent: snapshot.agent, message: message)
        case .codex:
            return classifyCodex(agent: snapshot.agent, message: message)
        }
    }

    private static func classifyClaude(agent: AgentKind, message: String) -> AgentUsageStatus {
        let normalized = message.lowercased()

        if normalized.contains("credentials not found")
            || normalized.contains("credentials could not be read") {
            return AgentUsageStatus(agent: agent, availability: .missingAuth, message: message)
        }
        if normalized.contains("keychain access denied") {
            return AgentUsageStatus(agent: agent, availability: .accessDenied, message: message)
        }
        if normalized.contains("session expired")
            || normalized.contains("authentication failed") {
            return AgentUsageStatus(agent: agent, availability: .sessionExpired, message: message)
        }

        return AgentUsageStatus(agent: agent, availability: .error(message), message: message)
    }

    private static func classifyCodex(agent: AgentKind, message: String) -> AgentUsageStatus {
        let normalized = message.lowercased()

        if normalized.contains("not installed or not on path") {
            return AgentUsageStatus(agent: agent, availability: .notInstalled, message: message)
        }
        if normalized.contains("not logged in")
            || normalized.contains("please log in") {
            return AgentUsageStatus(agent: agent, availability: .notLoggedIn, message: message)
        }

        return AgentUsageStatus(agent: agent, availability: .error(message), message: message)
    }
}
