import AppKit
import CoreText
import SwiftUI

/// The bundled display font, registered once per process. Every text style in
/// the app routes through here so the custom font applies uniformly, with a
/// graceful fall back to the system font if the file is missing.
enum AgentPulseFont {
    static let postScriptName = "KeepCalm-Medium"

    /// Registers the bundled font (idempotent) and reports whether it resolved.
    static let isAvailable: Bool = {
        for url in candidateURLs {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: postScriptName, size: 12) != nil
    }()

    static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if isAvailable, let font = NSFont(name: postScriptName, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func font(size: CGFloat) -> Font {
        isAvailable ? .custom(postScriptName, fixedSize: size) : .system(size: size)
    }

    private static var candidateURLs: [URL] {
        [
            Bundle.main.url(forResource: "KeepCalm-Medium", withExtension: "ttf"),
            sourceResourceURL,
        ].compactMap { $0 }
    }

    private static var sourceResourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // AgentPulseCore
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("KeepCalm-Medium.ttf")
    }
}

extension View {
    /// Applies the custom font at the given point size.
    func agentPulseFont(size: CGFloat) -> some View {
        font(AgentPulseFont.font(size: size))
    }
}
