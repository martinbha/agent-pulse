import SwiftUI

struct SettingsSummary: View {
    @ObservedObject var runtime: AgentPulseRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Endpoint", systemImage: "network")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(runtime.endpoint)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack {
                Label("Token", systemImage: "key")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(runtime.maskedToken)
                    .monospaced()
                    .textSelection(.enabled)
            }

            HStack {
                Label("Config", systemImage: "gearshape")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(runtime.settings.bridgeConfigPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button {
                    runtime.copyEndpoint()
                } label: {
                    Label("Endpoint", systemImage: "doc.on.doc")
                }

                Button {
                    runtime.copyToken()
                } label: {
                    Label("Token", systemImage: "doc.on.doc")
                }

                Spacer()

                Button(role: .destructive) {
                    runtime.regenerateToken()
                } label: {
                    Label("Rotate", systemImage: "arrow.clockwise")
                }
            }
        }
        .font(.caption)
    }
}
