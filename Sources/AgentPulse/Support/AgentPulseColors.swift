import AppKit
import SwiftUI

enum AgentPulseColors {
    static let claudeBrandAccent = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
    static let radiusPrimaryAccent = Color(red: 0.0 / 255.0, green: 182.0 / 255.0, blue: 239.0 / 255.0)
    static let workingStatus = Color(red: 0x3E / 255.0, green: 0x78 / 255.0, blue: 0xB2 / 255.0)
    static let staleStatus = Color(red: 0x57 / 255.0, green: 0x75 / 255.0, blue: 0x90 / 255.0)

    static let claudeBrandAccentNS = NSColor(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0, alpha: 1)
    static let radiusPrimaryAccentNS = NSColor(red: 0.0 / 255.0, green: 182.0 / 255.0, blue: 239.0 / 255.0, alpha: 1)
    static let workingStatusNS = NSColor(red: 0x3E / 255.0, green: 0x78 / 255.0, blue: 0xB2 / 255.0, alpha: 1)
    static let staleStatusNS = NSColor(red: 0x57 / 255.0, green: 0x75 / 255.0, blue: 0x90 / 255.0, alpha: 1)
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
