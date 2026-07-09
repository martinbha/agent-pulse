import SwiftUI

/// Color wells for the Claude and Codex brand accents, each with a
/// reset-to-default. Status colors are intentionally not customizable.
struct BrandColorSettings: View {
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colors")
                .agentPulseFont(size: 15)

            ForEach(AgentKind.allCases) { agent in
                HStack(spacing: 10) {
                    ColorPicker(
                        selection: appearance.binding(for: agent),
                        supportsOpacity: false
                    ) {
                        Text(agent.displayName)
                    }

                    Spacer()

                    Button("Reset") {
                        appearance.resetColor(for: agent)
                    }
                    .disabled(appearance.isDefault(for: agent))
                }
            }
        }
    }
}
