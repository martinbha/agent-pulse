import Foundation

@testable import AgentPulseCore

// The Command Line Tools ship Testing.framework without the _Testing_Foundation
// cross-import overlay, so files importing Testing must not import Foundation.
// Fixtures that need Foundation types (Date) live here instead.
enum TestFixtures {
    static func event(
        agent: AgentKind = .claude,
        state: AgentState = .working,
        event: String = "PreToolUse",
        cwd: String? = nil,
        project: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            agent: agent,
            state: state,
            event: event,
            sessionID: nil,
            cwd: cwd,
            project: project,
            timestamp: nil,
            source: nil
        )
    }

    static func snapshot(
        agent: AgentKind = .claude,
        state: AgentState,
        event: String,
        age: Double
    ) -> AgentStatusSnapshot {
        AgentStatusSnapshot(
            agent: agent,
            state: state,
            event: event,
            sessionID: nil,
            cwd: nil,
            project: nil,
            updatedAt: Date(timeIntervalSinceNow: -age),
            source: nil
        )
    }

    static func effectiveState(
        of snapshot: AgentStatusSnapshot,
        staleAfter: Double = 300,
        doneFadeAfter: Double = 20
    ) -> AgentState {
        snapshot.effectiveState(now: Date(), staleAfter: staleAfter, doneFadeAfter: doneFadeAfter)
    }
}
