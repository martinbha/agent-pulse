import SwiftUI

struct AgentPulseConfigView: View {
    @ObservedObject var runtime: AgentPulseRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Divider()

            SettingsSummary(runtime: runtime)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Test Events")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button {
                        runtime.sendTestEvent(agent: .claude)
                    } label: {
                        Label("Claude", systemImage: "paperplane")
                    }

                    Button {
                        runtime.sendTestEvent(agent: .codex)
                    } label: {
                        Label("Codex", systemImage: "paperplane")
                    }

                    Spacer()

                    Button {
                        runtime.clearCompleted()
                    } label: {
                        Label("Clear", systemImage: "checkmark.circle")
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
