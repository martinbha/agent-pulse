import Foundation
import AgentPulseBridgeSupport

struct OKResponse: Codable {
    var ok: Bool
}

struct ErrorResponse: Codable {
    var ok: Bool
    var error: String
}

struct HealthResponse: Codable {
    var ok: Bool
    var app: String
    var version: String
}

struct AgentStateResponse: Codable {
    var agent: AgentKind
    var state: AgentState
    var effectiveState: AgentState
    var event: String
    var sessionID: String?
    var cwd: String?
    var project: String?
    var updatedAt: Date
    var source: String?

    enum CodingKeys: String, CodingKey {
        case agent
        case state
        case effectiveState = "effective_state"
        case event
        case sessionID = "session_id"
        case cwd
        case project
        case updatedAt = "updated_at"
        case source
    }
}

struct ServerStateResponse: Codable {
    var ok: Bool
    var agents: [AgentStateResponse]
    var selfTest: BridgeSelfTestReceipt?

    enum CodingKeys: String, CodingKey {
        case ok
        case agents
        case selfTest = "self_test"
    }

    @MainActor
    init(store: AgentStatusStore?, selfTest: BridgeSelfTestReceipt? = nil) {
        self.ok = true
        self.selfTest = selfTest
        self.agents = store?.orderedSnapshots.map { snapshot in
            AgentStateResponse(
                agent: snapshot.agent,
                state: snapshot.state,
                effectiveState: store?.effectiveState(for: snapshot) ?? snapshot.state,
                event: snapshot.event,
                sessionID: snapshot.sessionID,
                cwd: snapshot.cwd,
                project: snapshot.project,
                updatedAt: snapshot.updatedAt,
                source: snapshot.source
            )
        } ?? []
    }
}
