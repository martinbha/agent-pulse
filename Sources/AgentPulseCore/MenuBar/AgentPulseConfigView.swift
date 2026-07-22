import SwiftUI

struct AgentPulseConfigView: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var hotkeySettings: HotkeySettings
    var openSetup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Integrations")
                        .agentPulseFont(size: 15)
                    Text("Install, repair, or remove local tool connections.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Open Setup") {
                    openSetup()
                }
            }

            Divider()

            UsageRefreshSettings(usageStore: usageStore)

            Divider()

            BrandColorSettings(appearance: appearance)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Overlay Shortcut")
                    .agentPulseFont(size: 15)
                HStack {
                    Text("Toggle pinned overlay")
                        .foregroundStyle(.secondary)
                    Spacer()
                    HotkeyRecorder(settings: hotkeySettings)
                }
                .agentPulseFont(size: 12)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Test Events")
                    .agentPulseFont(size: 15)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            runtime.sendTestEvent(agent: .claude)
                        } label: {
                            Label("Start Claude", systemImage: "play.circle")
                        }

                        Button {
                            runtime.sendTestEvent(agent: .codex)
                        } label: {
                            Label("Start Codex", systemImage: "play.circle")
                        }

                        Spacer()
                    }

                    HStack(spacing: 8) {
                        Button {
                            runtime.stopTestEvent(agent: .claude)
                        } label: {
                            Label("Stop Claude", systemImage: "stop.circle")
                        }

                        Button {
                            runtime.stopTestEvent(agent: .codex)
                        } label: {
                            Label("Stop Codex", systemImage: "stop.circle")
                        }

                        Spacer()

                        Button {
                            runtime.clearCompleted()
                        } label: {
                            Label("Clear", systemImage: "checkmark.circle")
                        }
                    }
                }
            }

        }
        .padding(20)
        .frame(width: 460)
        .agentPulseFont(size: 13)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent Pulse Settings")
                .agentPulseFont(size: 20)
            Text(runtime.serverStatus)
                .agentPulseFont(size: 13)
                .foregroundStyle(.secondary)
        }
    }
}
