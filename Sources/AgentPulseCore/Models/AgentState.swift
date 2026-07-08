import SwiftUI

enum AgentState: String, CaseIterable, Codable, Sendable {
    case idle
    case working
    case waiting
    case done
    case failed
    case stale
    case unknown

    var displayName: String {
        switch self {
        case .idle:
            return "Idle"
        case .working:
            return "Working"
        case .waiting:
            return "Waiting"
        case .done:
            return "Done"
        case .failed:
            return "Failed"
        case .stale:
            return "Stale"
        case .unknown:
            return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .working:
            return AgentPulseColors.workingStatus
        case .waiting:
            return .yellow
        case .done:
            return AgentPulseColors.doneStatus
        case .failed:
            return .red
        case .stale:
            return AgentPulseColors.staleStatus
        case .unknown:
            return .gray
        }
    }
}
