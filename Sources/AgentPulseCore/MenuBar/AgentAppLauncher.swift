import AppKit

/// Opens each agent's desktop app from the dropdown and tracks transient
/// "app not found" feedback for rows whose app could not be opened.
@MainActor
final class AgentAppLauncher: ObservableObject {
    @Published private(set) var unavailableAgents: Set<AgentKind> = []

    private let resolveAppURL: (String) -> URL?
    private let openApp: (String) async -> Bool
    private let feedbackDuration: Duration
    private var feedbackTasks: [AgentKind: Task<Void, Never>] = [:]

    init(
        resolveAppURL: @escaping (String) -> URL? = { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        },
        openApp: @escaping (String) async -> Bool = { bundleID in
            await HostAppOpener.open(bundleID: bundleID)
        },
        feedbackDuration: Duration = .milliseconds(2500)
    ) {
        self.resolveAppURL = resolveAppURL
        self.openApp = openApp
        self.feedbackDuration = feedbackDuration
    }

    /// Bundle IDs to try for an agent's desktop app, in priority order. The
    /// OpenAI desktop app has shipped under both identifiers, so the first
    /// installed candidate wins.
    static func bundleIDCandidates(for agent: AgentKind) -> [String] {
        switch agent {
        case .claude:
            return ["com.anthropic.claudefordesktop"]
        case .codex:
            return ["com.openai.codex", "com.openai.chat"]
        }
    }

    @discardableResult
    func open(_ agent: AgentKind) async -> Bool {
        let installedBundleID = Self.bundleIDCandidates(for: agent).first { candidate in
            resolveAppURL(candidate) != nil
        }

        if let installedBundleID, await openApp(installedBundleID) {
            return true
        }

        markUnavailable(agent)
        return false
    }

    private func markUnavailable(_ agent: AgentKind) {
        unavailableAgents.insert(agent)
        feedbackTasks[agent]?.cancel()
        feedbackTasks[agent] = Task { [weak self, feedbackDuration] in
            try? await Task.sleep(for: feedbackDuration)
            guard !Task.isCancelled else {
                return
            }
            self?.unavailableAgents.remove(agent)
        }
    }
}
