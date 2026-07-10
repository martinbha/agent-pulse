import Foundation

@MainActor
final class AgentStatusStore: ObservableObject {
    @Published private(set) var snapshots: [AgentKind: AgentStatusSnapshot]
    @Published private(set) var lastError: String?
    @Published var now = Date()

    let staleAfter: TimeInterval
    let doneFadeAfter: TimeInterval

    private let persistence: StatePersistence

    init(
        persistence: StatePersistence = StatePersistence(),
        staleAfter: TimeInterval = 300,
        doneFadeAfter: TimeInterval = 20
    ) {
        self.persistence = persistence
        self.staleAfter = staleAfter
        self.doneFadeAfter = doneFadeAfter

        let loaded = (try? persistence.load()) ?? [:]
        var initial: [AgentKind: AgentStatusSnapshot] = [:]
        for agent in AgentKind.allCases {
            initial[agent] = loaded[agent].map(Self.restored(_:)) ?? .idle(agent: agent)
        }
        self.snapshots = initial
    }

    /// After a restart there is no live agent session, so a restored
    /// in-progress state (`working`/`waiting`) would immediately read as stale.
    /// Start those idle and wait for fresh events; terminal states are kept
    /// (`done` fades to idle on its own).
    private static func restored(_ snapshot: AgentStatusSnapshot) -> AgentStatusSnapshot {
        switch snapshot.state {
        case .working, .waiting:
            return .idle(agent: snapshot.agent)
        default:
            return snapshot
        }
    }

    var orderedSnapshots: [AgentStatusSnapshot] {
        AgentKind.allCases.compactMap { snapshots[$0] }
    }

    func ingest(_ event: AgentEvent) {
        guard !shouldIgnore(event) else {
            return
        }
        snapshots[event.agent] = AgentStatusSnapshot(event: event)
        save()
    }

    /// A `SubagentStop` can arrive *after* the main turn's `Stop` (a subagent
    /// finishing late). It means work is winding down, so it may keep an
    /// active agent alive but must never resurrect a settled one back to
    /// "working" — that left agents aging into stale while actually idle.
    private func shouldIgnore(_ event: AgentEvent) -> Bool {
        guard event.event == "SubagentStop" else {
            return false
        }
        let current = snapshots[event.agent]?.state
        return current != .working && current != .stale
    }

    func clearCompleted() {
        for agent in AgentKind.allCases {
            guard let snapshot = snapshots[agent] else {
                continue
            }

            let effectiveState = snapshot.effectiveState(
                now: now,
                staleAfter: staleAfter,
                doneFadeAfter: doneFadeAfter
            )

            if effectiveState == .done || effectiveState == .stale || effectiveState == .failed {
                snapshots[agent] = .idle(agent: agent)
            }
        }
        save()
    }

    func effectiveState(for snapshot: AgentStatusSnapshot) -> AgentState {
        snapshot.effectiveState(
            now: now,
            staleAfter: staleAfter,
            doneFadeAfter: doneFadeAfter
        )
    }

    func tick() {
        now = Date()
    }

    private func save() {
        do {
            try persistence.save(snapshots)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

