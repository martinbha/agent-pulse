import AppKit
import SwiftUI

enum AgentPulseColors {
    static let workingStatus = Color(red: 0xFF / 255.0, green: 0x74 / 255.0, blue: 0xD4 / 255.0)
    static let doneStatus = Color(red: 0x04 / 255.0, green: 0x8A / 255.0, blue: 0x81 / 255.0)
    static let staleStatus = Color(red: 0xCD / 255.0, green: 0xA2 / 255.0, blue: 0xAB / 255.0)

    static let workingStatusNS = NSColor(red: 0xFF / 255.0, green: 0x74 / 255.0, blue: 0xD4 / 255.0, alpha: 1)
    static let doneStatusNS = NSColor(red: 0x04 / 255.0, green: 0x8A / 255.0, blue: 0x81 / 255.0, alpha: 1)
    static let staleStatusNS = NSColor(red: 0xCD / 255.0, green: 0xA2 / 255.0, blue: 0xAB / 255.0, alpha: 1)

    // Work-status fill for the split menu bar pill's left half. Fixed hues so
    // each state reads the same across agents; idle falls back to the brand
    // color at the call site so an inactive pill looks uniform.
    static let pillWorkingNS = NSColor(red: 0x34 / 255.0, green: 0xC7 / 255.0, blue: 0x59 / 255.0, alpha: 1)
    static let pillDoneNS = NSColor(red: 0x8E / 255.0, green: 0x5C / 255.0, blue: 0xD9 / 255.0, alpha: 1)
    static let pillFailedNS = NSColor(red: 0xE5 / 255.0, green: 0x3A / 255.0, blue: 0x35 / 255.0, alpha: 1)
    static let pillWaitingNS = NSColor(red: 0xF5 / 255.0, green: 0xA6 / 255.0, blue: 0x23 / 255.0, alpha: 1)
    static let pillStaleNS = NSColor(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0, alpha: 1)

    /// Left-half fill for a pill in the given work state. Idle/unknown return
    /// the passed brand color so the pill appears as one solid color.
    static func pillStatusFill(for state: AgentState, brand: NSColor) -> NSColor {
        switch state {
        case .idle, .unknown:
            return brand
        case .working:
            return pillWorkingNS
        case .done:
            return pillDoneNS
        case .failed:
            return pillFailedNS
        case .waiting:
            return pillWaitingNS
        case .stale:
            return pillStaleNS
        }
    }

    static func pillStatusFill(for state: AgentState, brand: Color) -> Color {
        switch state {
        case .idle, .unknown:
            return brand
        case .working:
            return Color(nsColor: pillWorkingNS)
        case .done:
            return Color(nsColor: pillDoneNS)
        case .failed:
            return Color(nsColor: pillFailedNS)
        case .waiting:
            return Color(nsColor: pillWaitingNS)
        case .stale:
            return Color(nsColor: pillStaleNS)
        }
    }
}

extension AgentKind {
    /// The default brand accent. Live rendering resolves colors through
    /// `AppearanceSettings` (which supports customization); this is the
    /// fallback and the reset target, sourced from `RGBColor.default(for:)`.
    var brandAccent: Color {
        RGBColor.default(for: self).color
    }

    var brandAccentNSColor: NSColor {
        RGBColor.default(for: self).nsColor
    }
}
