import Foundation

struct AgentEvent: Codable, Equatable, Sendable {
    var agent: AgentKind
    var state: AgentState
    var event: String
    var sessionID: String?
    var cwd: String?
    var project: String?
    var timestamp: Date?
    var source: String?
    var hostBundleID: String?

    enum CodingKeys: String, CodingKey {
        case agent
        case state
        case event
        case sessionID = "session_id"
        case cwd
        case project
        case timestamp
        case source
        case hostBundleID = "host_bundle_id"
    }

    var resolvedProject: String? {
        if let project, !project.isEmpty {
            return project
        }

        guard let cwd, !cwd.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    var resolvedTimestamp: Date {
        timestamp ?? Date()
    }
}

