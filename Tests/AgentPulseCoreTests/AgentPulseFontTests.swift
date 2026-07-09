import Testing

@testable import AgentPulseCore

@Suite struct AgentPulseFontTests {
    @Test func customFontRegistersAndResolves() {
        #expect(FontFixtures.isAvailable)
        #expect(FontFixtures.resolvedFontName == "KeepCalm-Medium")
    }
}
