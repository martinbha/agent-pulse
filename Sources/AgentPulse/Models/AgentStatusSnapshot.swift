import Foundation

struct AgentStatusSnapshot: Codable, Equatable, Identifiable, Sendable {
    var agent: AgentKind
    var state: AgentState
    var event: String
    var sessionID: String?
    var cwd: String?
    var project: String?
    var updatedAt: Date
    var source: String?

    var id: AgentKind { agent }

    static func idle(agent: AgentKind) -> AgentStatusSnapshot {
        AgentStatusSnapshot(
            agent: agent,
            state: .idle,
            event: "Idle",
            sessionID: nil,
            cwd: nil,
            project: nil,
            updatedAt: .distantPast,
            source: nil
        )
    }

    init(
        agent: AgentKind,
        state: AgentState,
        event: String,
        sessionID: String?,
        cwd: String?,
        project: String?,
        updatedAt: Date,
        source: String?
    ) {
        self.agent = agent
        self.state = state
        self.event = event
        self.sessionID = sessionID
        self.cwd = cwd
        self.project = project
        self.updatedAt = updatedAt
        self.source = source
    }

    init(event: AgentEvent) {
        self.init(
            agent: event.agent,
            state: event.state,
            event: event.event,
            sessionID: event.sessionID,
            cwd: event.cwd,
            project: event.resolvedProject,
            updatedAt: event.resolvedTimestamp,
            source: event.source
        )
    }

    func effectiveState(now: Date, staleAfter: TimeInterval, doneFadeAfter: TimeInterval) -> AgentState {
        let age = now.timeIntervalSince(updatedAt)

        if state == .working && age > staleAfter {
            return .stale
        }

        if state == .done && age > doneFadeAfter {
            return .idle
        }

        return state
    }
}

