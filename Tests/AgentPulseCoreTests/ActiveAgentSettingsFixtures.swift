import Foundation

@testable import AgentPulseCore

enum ActiveAgentSettingsFixtures {
    static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "agent-pulse-active-agents-\(UUID().uuidString)")!
    }
}
