import Foundation

enum ActiveAgentSelection: String, CaseIterable, Identifiable, Sendable {
    case both
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .both:
            return "Both"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

    var agents: [AgentKind] {
        switch self {
        case .both:
            return AgentKind.allCases
        case .claude:
            return [.claude]
        case .codex:
            return [.codex]
        }
    }
}

@MainActor
final class ActiveAgentSettings: ObservableObject {
    @Published private(set) var selection: ActiveAgentSelection

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.string(forKey: Keys.selection),
           let selection = ActiveAgentSelection(rawValue: stored) {
            self.selection = selection
        } else {
            self.selection = .both
            defaults.set(ActiveAgentSelection.both.rawValue, forKey: Keys.selection)
        }
    }

    var activeAgents: [AgentKind] {
        selection.agents
    }

    func isActive(_ agent: AgentKind) -> Bool {
        activeAgents.contains(agent)
    }

    @discardableResult
    func setSelection(_ selection: ActiveAgentSelection) -> Bool {
        guard self.selection != selection else {
            return false
        }

        self.selection = selection
        defaults.set(selection.rawValue, forKey: Keys.selection)
        return true
    }

    private enum Keys {
        static let selection = "agents.activeSelection"
    }
}
