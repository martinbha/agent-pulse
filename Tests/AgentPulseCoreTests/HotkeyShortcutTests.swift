import Testing

@testable import AgentPulseCore

@Suite struct HotkeyShortcutTests {
    // Carbon modifier bit flags: cmd=256, shift=512, option=2048, control=4096.
    @Test func carbonModifiersMapCommandShift() {
        let shortcut = HotkeyFixtures.shortcut(keyCode: 18, command: true, shift: true)

        #expect(shortcut.carbonModifiers == 256 + 512)
    }

    @Test func carbonModifiersMapOptionControl() {
        let shortcut = HotkeyFixtures.shortcut(keyCode: 18, option: true, control: true)

        #expect(shortcut.carbonModifiers == 2048 + 4096)
    }

    @Test func displayStringUsesGlyphsInConventionalOrder() {
        let shortcut = HotkeyFixtures.shortcut(keyCode: 0, command: true, control: true)

        #expect(shortcut.displayString == "⌃⌘A")
    }

    @Test func displayStringForDefault() {
        // macOS convention orders modifiers ⌃⌥⇧⌘ (command last).
        #expect(HotkeyShortcut.default.displayString == "⇧⌘1")
    }

    @Test func hasModifierRequiresAtLeastOne() {
        #expect(HotkeyFixtures.shortcut(keyCode: 18, command: true).hasModifier)
        #expect(!HotkeyFixtures.shortcut(keyCode: 18).hasModifier)
    }

    @Test func defaultIsCommandShiftOne() {
        #expect(HotkeyShortcut.default.keyCode == 18)
        #expect(HotkeyShortcut.default.carbonModifiers == 256 + 512)
    }
}

@MainActor
@Suite struct HotkeySettingsTests {
    @Test func customShortcutPersistsAcrossReload() {
        let custom = HotkeyFixtures.shortcut(keyCode: 8, command: true, option: true)

        let reloaded = HotkeyFixtures.persistRoundTrip(custom)

        #expect(reloaded == custom)
    }

    @Test func startsAtDefault() {
        let settings = HotkeyFixtures.freshSettings()

        #expect(settings.isDefault)
        #expect(settings.shortcut == .default)
    }

    @Test func resetRestoresDefault() {
        #expect(HotkeyFixtures.isDefaultAfterReset())
    }
}
