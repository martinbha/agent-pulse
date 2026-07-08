import AppKit
import SwiftUI

/// A plain sRGB color used for the customizable brand accents. Kept as a small
/// value type so it round-trips to a hex string for persistence and is easy to
/// compare in tests (unlike `Color`/`NSColor`).
struct RGBColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var hex: String {
        func component(_ value: Double) -> String {
            String(format: "%02X", Int((min(max(value, 0), 1) * 255).rounded()))
        }
        return "#\(component(red))\(component(green))\(component(blue))"
    }

    init?(hex: String) {
        var string = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        string = string.uppercased()
        guard string.count == 6, let value = Int(string, radix: 16) else {
            return nil
        }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        red = Double(converted.redComponent)
        green = Double(converted.greenComponent)
        blue = Double(converted.blueComponent)
    }

    init(color: Color) {
        self.init(nsColor: NSColor(color))
    }
}

extension RGBColor {
    static let claudeDefault = RGBColor(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
    static let codexDefault = RGBColor(red: 0.0 / 255.0, green: 182.0 / 255.0, blue: 239.0 / 255.0)

    static func `default`(for agent: AgentKind) -> RGBColor {
        switch agent {
        case .claude:
            return claudeDefault
        case .codex:
            return codexDefault
        }
    }
}
