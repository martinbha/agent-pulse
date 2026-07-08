import Foundation

@testable import AgentPulseCore

enum AppearanceFixtures {
    @MainActor
    static func freshSettings() -> AppearanceSettings {
        AppearanceSettings(defaults: UserDefaults(suiteName: "agent-pulse-appearance-\(UUID().uuidString)")!)
    }

    /// Sets a custom color, builds a second settings instance over the same
    /// defaults, and returns the reloaded color's hex — proving persistence.
    @MainActor
    static func persistedHexAfterReload(agent: AgentKind, hex: String) -> String? {
        let defaults = UserDefaults(suiteName: "agent-pulse-appearance-\(UUID().uuidString)")!
        let settings = AppearanceSettings(defaults: defaults)
        guard let rgb = RGBColor(hex: hex) else {
            return nil
        }
        settings.setRGB(rgb, for: agent)

        let reloaded = AppearanceSettings(defaults: defaults)
        return reloaded.rgb(for: agent).hex
    }
}
