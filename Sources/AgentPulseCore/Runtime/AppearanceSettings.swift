import AppKit
import SwiftUI

/// The single settings-aware source of brand colors. Every live brand-accent
/// lookup (menu bar pills, dropdown bars, status dots) routes through here, so
/// a custom color is applied everywhere or nowhere. Status colors are fixed and
/// are not part of this store.
@MainActor
final class AppearanceSettings: ObservableObject {
    @Published private var colors: [AgentKind: RGBColor]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var loaded: [AgentKind: RGBColor] = [:]
        for agent in AgentKind.allCases {
            if let hex = defaults.string(forKey: Self.key(for: agent)), let color = RGBColor(hex: hex) {
                loaded[agent] = color
            } else {
                loaded[agent] = .default(for: agent)
            }
        }
        self.colors = loaded
    }

    func rgb(for agent: AgentKind) -> RGBColor {
        colors[agent] ?? .default(for: agent)
    }

    func color(for agent: AgentKind) -> Color {
        rgb(for: agent).color
    }

    func nsColor(for agent: AgentKind) -> NSColor {
        rgb(for: agent).nsColor
    }

    func isDefault(for agent: AgentKind) -> Bool {
        rgb(for: agent) == .default(for: agent)
    }

    func setRGB(_ rgb: RGBColor, for agent: AgentKind) {
        guard colors[agent] != rgb else { return }
        colors[agent] = rgb
        defaults.set(rgb.hex, forKey: Self.key(for: agent))
    }

    func setColor(_ color: Color, for agent: AgentKind) {
        setRGB(RGBColor(color: color), for: agent)
    }

    func resetColor(for agent: AgentKind) {
        guard !isDefault(for: agent) else { return }
        colors[agent] = .default(for: agent)
        defaults.removeObject(forKey: Self.key(for: agent))
    }

    /// A binding for SwiftUI `ColorPicker`s that reads/writes the stored color.
    func binding(for agent: AgentKind) -> Binding<Color> {
        Binding(
            get: { self.color(for: agent) },
            set: { self.setColor($0, for: agent) }
        )
    }

    private static func key(for agent: AgentKind) -> String {
        "appearance.brandColor.\(agent.rawValue)"
    }
}
