import SwiftUI

struct AgentStatusPanel: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var store: AgentStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 10) {
                ForEach(store.orderedSnapshots) { snapshot in
                    AgentStatusRow(
                        snapshot: snapshot,
                        effectiveState: store.effectiveState(for: snapshot),
                        now: store.now
                    )
                }
            }

            Divider()

            SettingsSummary(runtime: runtime)

            Divider()

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

            HStack {
                Button {
                    runtime.copyStateJSON()
                } label: {
                    Label("Copy State", systemImage: "doc.on.doc")
                }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Pulse")
                    .font(.headline)
                Text(runtime.serverStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

