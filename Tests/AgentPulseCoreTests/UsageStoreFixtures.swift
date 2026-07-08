import Foundation

@testable import AgentPulseCore

/// A probe that yields a scripted sequence of snapshots (repeating the last),
/// so tests can drive multi-refresh scenarios deterministically.
final class FakeUsageProbe: UsageProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var scripted: [AgentUsageSnapshot]
    private var index = 0
    private(set) var manualTriggerCount = 0
    private(set) var fetchCount = 0

    init(_ scripted: [AgentUsageSnapshot]) {
        self.scripted = scripted
    }

    func fetch(trigger: RefreshTrigger) async -> AgentUsageSnapshot {
        lock.lock()
        defer { lock.unlock() }
        fetchCount += 1
        if trigger == .manual {
            manualTriggerCount += 1
        }
        let snapshot = scripted[min(index, scripted.count - 1)]
        index += 1
        return snapshot
    }
}

enum UsageStoreFixtures {
    static func usage(
        _ agent: AgentKind,
        fiveHour: Double,
        weekly: Double,
        detail: String? = nil
    ) -> AgentUsageSnapshot {
        AgentUsageSnapshot(
            agent: agent,
            fiveHour: UsageWindow(kind: .fiveHour, usedPercentage: fiveHour, resetsAt: nil, message: nil),
            weekly: UsageWindow(kind: .weekly, usedPercentage: weekly, resetsAt: nil, message: nil),
            detail: detail
        )
    }

    static func failure(_ agent: AgentKind, message: String) -> AgentUsageSnapshot {
        .failure(agent, message: message)
    }

    // MARK: - Merge logic (pure)

    static func mergePreservesPrevious(
        previous: AgentUsageSnapshot,
        current: AgentUsageSnapshot,
        preservedFailureCount: Int = 0,
        shouldPreservePrevious: Bool = true
    ) -> UsageSnapshotMerger.Result {
        UsageSnapshotMerger.merge(
            previous: previous,
            current: current,
            preservedFailureCount: preservedFailureCount,
            shouldPreservePrevious: shouldPreservePrevious
        )
    }

    // MARK: - Availability (pure)

    static func availability(for snapshot: AgentUsageSnapshot) -> UsageAvailability {
        UsageAvailabilityClassifier.status(for: snapshot).availability
    }

    // MARK: - Store scenarios (MainActor)

    @MainActor
    static func makeStore(
        claude: [AgentUsageSnapshot],
        codex: [AgentUsageSnapshot],
        defaults: UserDefaults
    ) -> (store: UsageStore, claudeProbe: FakeUsageProbe, codexProbe: FakeUsageProbe) {
        let claudeProbe = FakeUsageProbe(claude)
        let codexProbe = FakeUsageProbe(codex)
        let store = UsageStore(
            probes: [.claude: claudeProbe, .codex: codexProbe],
            userDefaults: defaults,
            startRefreshLoop: false
        )
        return (store, claudeProbe, codexProbe)
    }

    static func ephemeralDefaults() -> UserDefaults {
        UserDefaults(suiteName: "agent-pulse-tests-\(UUID().uuidString)")!
    }
}
