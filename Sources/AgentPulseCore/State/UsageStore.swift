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
    private let activeAgentsProvider: @MainActor () -> [AgentKind]
    private var refreshTask: Task<Void, Never>?
    private var refreshingAgents: Set<AgentKind> = []
    private var pendingRefreshAgents: Set<AgentKind> = []
    private var preservedFailureCounts: [AgentKind: Int] = [:]

    private let refreshIntervalDefaultsKey = "usage.refreshInterval"

    init(
        probes: [AgentKind: any UsageProbing] = [
            .claude: ClaudeUsageProbe(),
            .codex: CodexUsageProbe(),
        ],
        userDefaults: UserDefaults = .standard,
        activeAgentsProvider: @escaping @MainActor () -> [AgentKind] = {
            AgentKind.allCases
        },
        startRefreshLoop: Bool = true
    ) {
        self.probes = probes
        self.userDefaults = userDefaults
        self.activeAgentsProvider = activeAgentsProvider

        var initial: [AgentKind: AgentUsageSnapshot] = [:]
        for agent in AgentKind.allCases {
            initial[agent] = .loading(agent)
        }
        self.snapshots = initial

        self.refreshInterval = Self.loadRefreshInterval(
            from: userDefaults,
            key: refreshIntervalDefaultsKey
        )

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
    func refresh(
        trigger: RefreshTrigger = .automatic,
        agents requestedAgents: [AgentKind]? = nil
    ) async {
        guard !isRefreshing else {
            if let requestedAgents {
                pendingRefreshAgents.formUnion(
                    requestedAgents.filter { !refreshingAgents.contains($0) }
                )
            }
            return
        }
        isRefreshing = true

        let activeAgents = activeAgentsProvider()
        let activeSet = Set(activeAgents)
        let agents = (requestedAgents ?? activeAgents).filter(activeSet.contains)
        refreshingAgents = Set(agents)
        let shouldForceCredentialRefresh = trigger == .manual
        let previous = snapshots

        if shouldForceCredentialRefresh {
            // Keep showing the current numbers while the fetch runs — blanking
            // to a loading placeholder mid-refresh makes the dropdown collapse
            // and re-expand. The merge below still replaces them wholesale.
            for agent in agents {
                preservedFailureCounts[agent] = 0
            }
        }

        let fetched = await withTaskGroup(of: (AgentKind, AgentUsageSnapshot).self) { group in
            for agent in agents {
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
        for agent in agents {
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

        refreshingAgents = []
        isRefreshing = false

        let pendingAgents = activeAgentsProvider().filter {
            pendingRefreshAgents.contains($0)
        }
        pendingRefreshAgents = []
        if !pendingAgents.isEmpty {
            await refresh(agents: pendingAgents)
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

    private static func loadRefreshInterval(from userDefaults: UserDefaults, key: String) -> UsageRefreshInterval {
        guard let storedRawValue = userDefaults.object(forKey: key) as? NSNumber,
              let interval = UsageRefreshInterval(rawValue: storedRawValue.intValue)
        else {
            userDefaults.set(UsageRefreshInterval.defaultValue.rawValue, forKey: key)
            return .defaultValue
        }

        return interval
    }
}
