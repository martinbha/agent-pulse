import AppKit
import SwiftUI

struct LaunchAtLoginControl: View {
    @ObservedObject var workflow: SetupWorkflow
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let health = workflow.snapshot?.launchAtLogin {
                HStack(spacing: 10) {
                    if showsTitle {
                        Label("Launch at Login", systemImage: "power")
                            .agentPulseFont(size: 16)
                    }

                    Spacer()

                    statusBadge(for: health)

                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { LaunchAtLoginPresentation.isOn(health) },
                            set: { enabled in
                                guard enabled != LaunchAtLoginPresentation.isOn(health) else {
                                    return
                                }
                                Task {
                                    await workflow.perform(.setLaunchAtLogin(enabled))
                                }
                            }
                        )
                    )
                    .labelsHidden()
                    .disabled(
                        workflow.activeOperation != nil
                            || workflow.isRefreshing
                            || !LaunchAtLoginPresentation.canChange(health)
                    )
                    .accessibilityLabel("Launch Agent Pulse at Login")
                }

                Text(LaunchAtLoginPresentation.guidance(health))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .requiresApproval = health {
                    Button("Open Login Items Settings") {
                        LoginItemsSettings.open()
                    }
                }

                if let notice = workflow.launchAtLoginNotice {
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
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking Launch at Login…")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusBadge(for health: LaunchAtLoginHealth) -> some View {
        let color: Color
        switch health {
        case .enabled:
            color = .green
        case .requiresApproval:
            color = .orange
        case .notFound:
            color = .red
        case .notRegistered, .unavailable:
            color = .secondary
        }

        return Text(LaunchAtLoginPresentation.label(health))
            .agentPulseFont(size: 11)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

enum LoginItemsSettings {
    @MainActor
    static func open() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
