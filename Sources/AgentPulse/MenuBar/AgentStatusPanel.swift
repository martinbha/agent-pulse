import SwiftUI

struct AgentStatusPanel: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var store: AgentStatusStore
    var openConfig: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

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

            HStack {
                Button {
                    openConfig()
                } label: {
                    Label("Config", systemImage: "gearshape")
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
        .frame(width: 360, height: 260)
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
