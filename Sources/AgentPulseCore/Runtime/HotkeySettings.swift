import Foundation

/// Stores the configurable global-hotkey shortcut that toggles the pinned
/// overlay, persisted in UserDefaults.
@MainActor
final class HotkeySettings: ObservableObject {
    @Published private(set) var shortcut: HotkeyShortcut

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let keyCode = defaults.object(forKey: Keys.keyCode) as? Int,
           let modifiers = defaults.object(forKey: Keys.modifiers) as? Int {
            shortcut = HotkeyShortcut(keyCode: keyCode, modifierFlags: modifiers)
        } else {
            shortcut = .default
        }
    }

    func setShortcut(_ newShortcut: HotkeyShortcut) {
        guard shortcut != newShortcut else { return }
        shortcut = newShortcut
        defaults.set(newShortcut.keyCode, forKey: Keys.keyCode)
        defaults.set(newShortcut.modifierFlags, forKey: Keys.modifiers)
    }

    func reset() {
        setShortcut(.default)
        defaults.removeObject(forKey: Keys.keyCode)
        defaults.removeObject(forKey: Keys.modifiers)
    }

    var isDefault: Bool {
        shortcut == .default
    }

    private enum Keys {
        static let keyCode = "hotkey.keyCode"
        static let modifiers = "hotkey.modifiers"
    }
}
