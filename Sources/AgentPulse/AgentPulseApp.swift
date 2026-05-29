import SwiftUI

@main
struct AgentPulseApp: App {
    var body: some Scene {
        MenuBarExtra("Agent Pulse", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Agent Pulse")
                    .font(.headline)
                Text("Status plumbing is coming online.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
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

