import Foundation

@testable import AgentPulseCore

enum NotificationPreferencesFixtures {
    static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "agent-pulse-notification-preferences-\(UUID().uuidString)")!
    }
}
