import SwiftUI

struct AgentPulseConfigView: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var hotkeySettings: HotkeySettings
    @ObservedObject var setup: SetupWorkflow
    var openSetup: () -> Void

    var body: some View {
        ScrollView {
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Launch at Login")
                        .agentPulseFont(size: 15)
                    LaunchAtLoginControl(workflow: setup, showsTitle: false)
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
                    Text("Delivery Self-Test")
                        .agentPulseFont(size: 15)

                    Text("Runs the installed bridge through the authenticated local server without changing agent status or sending a notification.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        deliveryTestButton(.claude)
                        deliveryTestButton(.codex)
                        Spacer()
                    }

                    ForEach(AgentKind.allCases) { agent in
                        if let notice = setup.testNotices[agent] {
                            Label(
                                notice.message,
                                systemImage: notice.kind == .success
                                    ? "checkmark.circle.fill"
                                    : "xmark.octagon.fill"
                            )
                            .foregroundStyle(notice.kind == .success ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true)

                            if let recovery = notice.recovery {
                                Text(recovery)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview Events")
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
        }
        .frame(width: 460)
        .agentPulseFont(size: 13)
        .task {
            if setup.snapshot == nil {
                await setup.refresh()
            }
        }
    }

    private func deliveryTestButton(_ agent: AgentKind) -> some View {
        Button {
            Task { await setup.perform(.test(agent)) }
        } label: {
            if setup.activeOperation == .test(agent) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Testing \(agent.displayName)")
                }
            } else {
                Label(
                    "Test \(agent.displayName)",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
            }
        }
        .disabled(
            setup.activeOperation != nil
                || setup.isRefreshing
                || !isConfigured(agent)
        )
        .help(
            isConfigured(agent)
                ? "Run the installed bridge delivery test."
                : "Set up this integration before testing delivery."
        )
    }

    private func isConfigured(_ agent: AgentKind) -> Bool {
        guard let integration = setup.snapshot?.integrations.first(where: {
            $0.agent == agent
        }) else {
            return false
        }
        return SetupIntegrationOperations.canTest(integration)
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
