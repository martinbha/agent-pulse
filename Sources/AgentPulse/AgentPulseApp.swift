import SwiftUI

@main
struct AgentPulseApp: App {
    @StateObject private var runtime = AgentPulseRuntime()

    var body: some Scene {
        MenuBarExtra("Agent Pulse", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Agent Pulse")
                    .font(.headline)
                Text(runtime.serverStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                Button("Clear Completed") {
                    runtime.clearCompleted()
                }
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 260)
        }
        .menuBarExtraStyle(.window)
    }
}
