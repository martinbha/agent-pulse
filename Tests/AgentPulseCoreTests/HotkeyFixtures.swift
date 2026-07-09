import AppKit

@testable import AgentPulseCore

enum HotkeyFixtures {
    static func shortcut(
        keyCode: Int,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) -> HotkeyShortcut {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return HotkeyShortcut(keyCode: keyCode, modifierFlags: Int(flags.rawValue))
    }

    @MainActor
    static func persistRoundTrip(_ shortcut: HotkeyShortcut) -> HotkeyShortcut {
        let defaults = UserDefaults(suiteName: "agent-pulse-hotkey-\(UUID().uuidString)")!
        HotkeySettings(defaults: defaults).setShortcut(shortcut)
        return HotkeySettings(defaults: defaults).shortcut
    }

    @MainActor
    static func freshSettings() -> HotkeySettings {
        HotkeySettings(defaults: UserDefaults(suiteName: "agent-pulse-hotkey-\(UUID().uuidString)")!)
    }

    @MainActor
    static func isDefaultAfterReset() -> Bool {
        let defaults = UserDefaults(suiteName: "agent-pulse-hotkey-\(UUID().uuidString)")!
        let settings = HotkeySettings(defaults: defaults)
        settings.setShortcut(shortcut(keyCode: 2, command: true, option: true))
        settings.reset()
        return settings.isDefault
    }
}
