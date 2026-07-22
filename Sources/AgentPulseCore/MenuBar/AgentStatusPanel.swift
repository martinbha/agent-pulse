import AppKit
import SwiftUI

struct AgentStatusPanel: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var store: AgentStatusStore
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var appLauncher: AgentAppLauncher
    var openSetup: () -> Void
    var openConfig: () -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            VStack(spacing: 12) {
                ForEach(Array(store.orderedSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                    if index > 0 {
                        Divider()
                    }
                    AgentStatusRow(
                        snapshot: snapshot,
                        effectiveState: store.effectiveState(for: snapshot),
                        usage: usageStore.snapshot(for: snapshot.agent),
                        availability: usageStore.status(for: snapshot.agent).availability,
                        accent: appearance.color(for: snapshot.agent),
                        now: store.now,
                        isAppUnavailable: appLauncher.unavailableAgents.contains(snapshot.agent),
                        openApp: {
                            openAgentApp(snapshot.agent)
                        }
                    )
                }
            }

            Divider()

            HStack {
                Button {
                    openSetup()
                } label: {
                    Label("Setup", systemImage: "checklist")
                }

                Button {
                    openConfig()
                } label: {
                    Label("Settings", systemImage: "gearshape")
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
        .agentPulseFont(size: 13)
    }

    private func openAgentApp(_ agent: AgentKind) {
        Task {
            if await appLauncher.open(agent) {
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentPulseHeaderLogo()

            VStack(alignment: .leading, spacing: 2) {
                Text("Agent Pulse")
                    .agentPulseFont(size: 16)
                Text(UsageWindowFormatter.lastUpdatedText(usageStore.lastUpdated, now: store.now))
                    .agentPulseFont(size: 11)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await usageStore.refresh(trigger: .manual) }
            } label: {
                // Fixed footprint so swapping between the icon and the spinner
                // can't nudge the header (and thus the dropdown) size.
                ZStack {
                    if usageStore.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(usageStore.isRefreshing)
            .help("Refresh usage")
        }
    }
}

private struct AgentPulseHeaderLogo: View {
    var body: some View {
        if let image = AgentPulseImages.appIcon(size: NSSize(width: 32, height: 32)) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: "waveform.path.ecg")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)
        }
    }
}
