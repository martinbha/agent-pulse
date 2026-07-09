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
}
