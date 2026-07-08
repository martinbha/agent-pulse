import Testing

@testable import AgentPulseCore

@Suite struct RGBColorTests {
    @Test func parsesSixDigitHex() {
        let color = RGBColor(hex: "#D97757")

        #expect(color?.red == 217.0 / 255.0)
        #expect(color?.green == 119.0 / 255.0)
        #expect(color?.blue == 87.0 / 255.0)
    }

    @Test func parsesWithoutLeadingHash() {
        #expect(RGBColor(hex: "00B6EF") == RGBColor.codexDefault)
    }

    @Test func rejectsMalformedHex() {
        #expect(RGBColor(hex: "xyz") == nil)
        #expect(RGBColor(hex: "#12345") == nil)
        #expect(RGBColor(hex: "#GGGGGG") == nil)
        #expect(RGBColor(hex: "") == nil)
    }

    @Test func hexRoundTrips() {
        #expect(RGBColor(hex: "#1A2B3C")?.hex == "#1A2B3C")
        #expect(RGBColor.claudeDefault.hex == "#D97757")
        #expect(RGBColor.codexDefault.hex == "#00B6EF")
    }

    @Test func defaultsMatchBrandColors() {
        #expect(RGBColor.default(for: .claude) == .claudeDefault)
        #expect(RGBColor.default(for: .codex) == .codexDefault)
    }
}

@MainActor
@Suite struct AppearanceSettingsTests {
    @Test func startsAtBrandDefaults() {
        let settings = AppearanceFixtures.freshSettings()

        #expect(settings.isDefault(for: .claude))
        #expect(settings.isDefault(for: .codex))
        #expect(settings.rgb(for: .claude) == .claudeDefault)
    }

    @Test func settingCustomColorMarksNonDefault() {
        let settings = AppearanceFixtures.freshSettings()
        let custom = RGBColor(hex: "#112233")!

        settings.setRGB(custom, for: .claude)

        #expect(settings.rgb(for: .claude) == custom)
        #expect(!settings.isDefault(for: .claude))
        // The other agent is unaffected.
        #expect(settings.isDefault(for: .codex))
    }

    @Test func resetRestoresDefault() {
        let settings = AppearanceFixtures.freshSettings()
        settings.setRGB(RGBColor(hex: "#112233")!, for: .codex)

        settings.resetColor(for: .codex)

        #expect(settings.isDefault(for: .codex))
        #expect(settings.rgb(for: .codex) == .codexDefault)
    }

    @Test func customColorPersistsAcrossReload() {
        let hex = AppearanceFixtures.persistedHexAfterReload(agent: .claude, hex: "#445566")

        #expect(hex == "#445566")
    }
}
