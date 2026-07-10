import Foundation

/// Owns per-agent usage snapshots and keeps them fresh on a fixed-interval
/// poll. Work-status tracking (hook events) is handled separately by
/// `AgentStatusStore`; this store only concerns usage windows.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshots: [AgentKind: AgentUsageSnapshot]
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastRefreshAttemptedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshInterval: UsageRefreshInterval

    private let probes: [AgentKind: any UsageProbing]
    private let userDefaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var preservedFailureCounts: [AgentKind: Int] = [:]

    private let refreshIntervalDefaultsKey = "usage.refreshInterval"

    init(
        probes: [AgentKind: any UsageProbing] = [
            .claude: ClaudeUsageProbe(),
            .codex: CodexUsageProbe(),
        ],
        userDefaults: UserDefaults = .standard,
        startRefreshLoop: Bool = true
    ) {
        self.probes = probes
        self.userDefaults = userDefaults

        var initial: [AgentKind: AgentUsageSnapshot] = [:]
        for agent in AgentKind.allCases {
            initial[agent] = .loading(agent)
        }
        self.snapshots = initial

        let storedInterval = userDefaults.integer(forKey: refreshIntervalDefaultsKey)
        self.refreshInterval = UsageRefreshInterval(rawValue: storedInterval) ?? .defaultValue

        if startRefreshLoop {
            self.startRefreshLoop()
        }
    }

    deinit {
        refreshTask?.cancel()
    }

    var orderedSnapshots: [AgentUsageSnapshot] {
        AgentKind.allCases.compactMap { snapshots[$0] }
    }

    func snapshot(for agent: AgentKind) -> AgentUsageSnapshot {
        snapshots[agent] ?? .loading(agent)
    }

    func status(for agent: AgentKind) -> AgentUsageStatus {
        UsageAvailabilityClassifier.status(for: snapshot(for: agent))
    }

    func setRefreshInterval(_ interval: UsageRefreshInterval) {
        guard refreshInterval != interval else {
            return
        }
        refreshInterval = interval
        userDefaults.set(interval.rawValue, forKey: refreshIntervalDefaultsKey)
        startRefreshLoop()
    }

    /// Triggers a one-off refresh. `.manual` re-resolves credentials from
    /// scratch (re-attempting previously denied Keychain access) and clears the
    /// cached-value preservation so stale numbers can't mask a fixed login.
    func refresh(trigger: RefreshTrigger = .automatic) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let shouldForceCredentialRefresh = trigger == .manual
        let previous = snapshots

        if shouldForceCredentialRefresh {
            // Keep showing the current numbers while the fetch runs — blanking
            // to a loading placeholder mid-refresh makes the dropdown collapse
            // and re-expand. The merge below still replaces them wholesale.
            for agent in AgentKind.allCases {
                preservedFailureCounts[agent] = 0
            }
        }

        let fetched = await withTaskGroup(of: (AgentKind, AgentUsageSnapshot).self) { group in
            for agent in AgentKind.allCases {
                guard let probe = probes[agent] else { continue }
                group.addTask {
                    (agent, await probe.fetch(trigger: trigger))
                }
            }

            var results: [AgentKind: AgentUsageSnapshot] = [:]
            for await (agent, snapshot) in group {
                results[agent] = snapshot
            }
            return results
        }

        var anyFresh = false
        for agent in AgentKind.allCases {
            guard let current = fetched[agent] else { continue }
            let previousSnapshot = previous[agent] ?? .loading(agent)

            let result = UsageSnapshotMerger.merge(
                previous: previousSnapshot,
                current: current,
                preservedFailureCount: preservedFailureCounts[agent, default: 0],
                shouldPreservePrevious: !shouldForceCredentialRefresh
            )

            if result.preservedPrevious {
                preservedFailureCounts[agent, default: 0] += 1
            } else {
                preservedFailureCounts[agent] = 0
            }

            snapshots[agent] = result.snapshot
            anyFresh = anyFresh || result.hasFreshUsageData
        }

        let now = Date()
        lastRefreshAttemptedAt = now
        if anyFresh {
            lastUpdated = now
        }
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh()
            guard let self, self.refreshInterval != .manual else {
                return
            }
            while !Task.isCancelled {
                let seconds = self.refreshInterval.duration
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }
}
