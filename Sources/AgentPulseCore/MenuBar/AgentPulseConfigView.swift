import SwiftUI

struct AgentPulseConfigView: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            SettingsSummary(runtime: runtime)

            Divider()

            BrandColorSettings(appearance: appearance)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Test Events")
                    .font(.headline)

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

            Divider()

            HStack {
                Button {
                    runtime.copyStateJSON()
                } label: {
                    Label("Copy State", systemImage: "doc.on.doc")
                }

                Spacer()
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent Pulse Config")
                .font(.title2.bold())
            Text(runtime.serverStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
