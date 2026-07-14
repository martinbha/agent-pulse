import Foundation

@testable import AgentPulseCore

enum AgentStatusStoreFixtures {
    /// Persists a snapshot in the given state, builds a fresh store over the
    /// same file, and returns the restored state for that agent.
    @MainActor
    static func restoredState(from state: AgentState, agent: AgentKind = .claude) -> AgentState {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pulse-store-\(UUID().uuidString).json")
        let persistence = StatePersistence(fileURL: url)

        let persisted = AgentStatusSnapshot(
            agent: agent,
            state: state,
            event: "PreToolUse",
            sessionID: nil,
            cwd: nil,
            project: "demo",
            updatedAt: Date(timeIntervalSinceNow: -600),
            source: nil
        )
        try? persistence.save([agent: persisted])

        let store = AgentStatusStore(persistence: persistence)
        return store.snapshots[agent]?.state ?? .unknown
    }

    /// Builds a store with the agent in `initialState` (via a first event when
    /// non-idle), ingests a SubagentStop, and returns the resulting state.
    @MainActor
    static func stateAfterSubagentStop(from initialState: AgentState) -> AgentState {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pulse-store-\(UUID().uuidString).json")
        let store = AgentStatusStore(persistence: StatePersistence(fileURL: url))

        if initialState != .idle {
            store.ingest(event(state: initialState, name: "PreToolUse"))
        }
        store.ingest(event(state: .working, name: "SubagentStop"))
        return store.snapshots[.claude]?.state ?? .unknown
    }

    /// Ingests a done event carrying a host bundle id, rebuilds the store over
    /// the same file, and returns the restored value.
    @MainActor
    static func restoredHostBundleID(_ hostBundleID: String?) -> String? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pulse-store-\(UUID().uuidString).json")
        let persistence = StatePersistence(fileURL: url)

        let store = AgentStatusStore(persistence: persistence)
        store.ingest(
            AgentEvent(
                agent: .claude,
                state: .done,
                event: "Stop",
                sessionID: nil,
                cwd: nil,
                project: "demo",
                timestamp: Date(),
                source: "test",
                hostBundleID: hostBundleID
            )
        )

        let restored = AgentStatusStore(persistence: persistence)
        return restored.snapshots[.claude]?.hostBundleID
    }

    private static func event(state: AgentState, name: String) -> AgentEvent {
        AgentEvent(
            agent: .claude,
            state: state,
            event: name,
            sessionID: nil,
            cwd: nil,
            project: "demo",
            timestamp: Date(),
            source: "test"
        )
    }
}
