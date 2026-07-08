import Foundation

enum AgentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    var shortName: String {
        switch self {
        case .claude:
            return "C"
        case .codex:
            return "X"
        }
    }

    /// Two-letter label shown in the menu bar pill.
    var pillLabel: String {
        switch self {
        case .claude:
            return "Cl"
        case .codex:
            return "Cx"
        }
    }
}

