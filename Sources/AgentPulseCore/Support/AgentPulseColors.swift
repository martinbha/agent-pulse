import AppKit
import SwiftUI

enum AgentPulseColors {
    static let claudeBrandAccent = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
    static let radiusPrimaryAccent = Color(red: 0.0 / 255.0, green: 182.0 / 255.0, blue: 239.0 / 255.0)
    static let workingStatus = Color(red: 0xFF / 255.0, green: 0x74 / 255.0, blue: 0xD4 / 255.0)
    static let doneStatus = Color(red: 0x04 / 255.0, green: 0x8A / 255.0, blue: 0x81 / 255.0)
    static let staleStatus = Color(red: 0xCD / 255.0, green: 0xA2 / 255.0, blue: 0xAB / 255.0)

    static let claudeBrandAccentNS = NSColor(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0, alpha: 1)
    static let radiusPrimaryAccentNS = NSColor(red: 0.0 / 255.0, green: 182.0 / 255.0, blue: 239.0 / 255.0, alpha: 1)
    static let workingStatusNS = NSColor(red: 0xFF / 255.0, green: 0x74 / 255.0, blue: 0xD4 / 255.0, alpha: 1)
    static let doneStatusNS = NSColor(red: 0x04 / 255.0, green: 0x8A / 255.0, blue: 0x81 / 255.0, alpha: 1)
    static let staleStatusNS = NSColor(red: 0xCD / 255.0, green: 0xA2 / 255.0, blue: 0xAB / 255.0, alpha: 1)
}

extension AgentKind {
    var brandAccent: Color {
        switch self {
        case .claude:
            return AgentPulseColors.claudeBrandAccent
        case .codex:
            return AgentPulseColors.radiusPrimaryAccent
        }
    }

    var brandAccentNSColor: NSColor {
        switch self {
        case .claude:
            return AgentPulseColors.claudeBrandAccentNS
        case .codex:
            return AgentPulseColors.radiusPrimaryAccentNS
        }
    }
}
