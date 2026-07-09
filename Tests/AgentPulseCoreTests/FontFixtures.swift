import AppKit

@testable import AgentPulseCore

enum FontFixtures {
    static var isAvailable: Bool {
        AgentPulseFont.isAvailable
    }

    static var resolvedFontName: String {
        AgentPulseFont.nsFont(size: 12).fontName
    }
}
