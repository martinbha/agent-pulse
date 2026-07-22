import AppKit
import SwiftUI

struct SetupView: View {
    @ObservedObject var runtime: AgentPulseRuntime
    @ObservedObject var workflow: SetupWorkflow

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let notice = workflow.notice {
                        operationNotice(notice)
                    }

                    if let snapshot = workflow.snapshot {
                        setupSummary(snapshot)
                        bridgeCard(snapshot)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Integrations")
                                .agentPulseFont(size: 18)

                            ForEach(snapshot.integrations) { integration in
                                integrationCard(
                                    integration,
                                    mutationsBlocked: isTranslocated(snapshot.application)
                                )
                            }
                        }

                        advancedSection(snapshot)
                    } else {
                        loadingState
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 640, idealWidth: 700, minHeight: 540, idealHeight: 640)
        .agentPulseFont(size: 13)
        .task {
            await workflow.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let image = AgentPulseImages.appIcon(size: NSSize(width: 46, height: 46)) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Set Up Agent Pulse")
                    .agentPulseFont(size: 22)
                Text("Connect your local coding tools without editing configuration files.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await workflow.refresh() }
            } label: {
                if workflow.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .disabled(workflow.isRefreshing || workflow.activeOperation != nil)
        }
        .padding(20)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Checking your local setup…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }

    @ViewBuilder
    private func setupSummary(_ snapshot: SetupHealthSnapshot) -> some View {
        if let issue = snapshot.blockingIssue {
            messageCard(
                title: "Action required",
                message: issue.message,
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange
            ) {
                recommendedAction(for: snapshot)
            }
        } else if snapshot.recommendedAction == .none {
            messageCard(
                title: "Setup is complete",
                message: "The local bridge and configured integrations are healthy.",
                systemImage: "checkmark.circle.fill",
                tint: .green
            ) {
                EmptyView()
            }
        } else {
            messageCard(
                title: "Setup is partially complete",
                message: recommendedMessage(snapshot.recommendedAction),
                systemImage: "info.circle.fill",
                tint: .blue
            ) {
                recommendedAction(for: snapshot)
            }
        }
    }

    private func bridgeCard(_ snapshot: SetupHealthSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Local bridge", systemImage: "point.3.connected.trianglepath.dotted")
                    .agentPulseFont(size: 16)
                Spacer()
                statusBadge(bridgeLabel(snapshot.bridge), tone: bridgeTone(snapshot.bridge))
            }

            Text("The bridge receives local hook events from each coding tool and delivers them only to Agent Pulse on this Mac. Integration hooks tell each tool when to call it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch snapshot.bridge {
            case .missing:
                operationButton(.installBridge)
            case .outdated, .unreadable, .invalid:
                operationButton(.repairBridge)
            case .current:
                EmptyView()
            }
        }
        .setupCard()
    }

    private func integrationCard(
        _ integration: IntegrationHealthSnapshot,
        mutationsBlocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Circle()
                    .fill(runtime.appearance.color(for: integration.agent))
                    .frame(width: 10, height: 10)
                Text(integration.agent.displayName)
                    .agentPulseFont(size: 16)
                Spacer()
                statusBadge(
                    integrationStatusLabel(integration),
                    tone: integrationTone(integration)
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                statusRow(
                    "Installed",
                    hostLabel(integration.host),
                    icon: hostIcon(integration.host)
                )
                statusRow(
                    "Login and usage",
                    usageLabel(integration.usage),
                    icon: usageIcon(integration.usage)
                )
                statusRow(
                    "Hooks",
                    hookLabel(integration.hooks),
                    icon: hookIcon(integration.hooks)
                )
                statusRow(
                    "Last event",
                    eventLabel(integration.lastEvent),
                    icon: eventIcon(integration.lastEvent)
                )
            }

            if let guidance = integrationGuidance(integration) {
                Text(guidance)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            let operations = SetupIntegrationOperations.available(for: integration)
            if !operations.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(operations.enumerated()), id: \.offset) { _, operation in
                        operationButton(operation)
                    }
                }
                .disabled(mutationsBlocked)
            }
        }
        .setupCard()
    }

    private func advancedSection(_ snapshot: SetupHealthSnapshot) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                advancedRow("Endpoint", value: runtime.endpoint)
                advancedRow("Bearer token", value: runtime.maskedToken, monospaced: true)
                advancedRow("Bridge config", value: runtime.settings.bridgeConfigPath)

                HStack(spacing: 8) {
                    Button {
                        runtime.copyEndpoint()
                    } label: {
                        Label("Copy Endpoint", systemImage: "doc.on.doc")
                    }

                    Button {
                        runtime.copyToken()
                    } label: {
                        Label("Copy Token", systemImage: "key")
                    }

                    Button {
                        runtime.copyStateJSON()
                    } label: {
                        Label("Copy Raw State", systemImage: "curlybraces")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        runtime.regenerateToken()
                    } label: {
                        Label("Rotate Token", systemImage: "arrow.clockwise")
                    }
                }

                Button {
                    Pasteboard.copy(
                        SetupHealthDiagnosticsRenderer.lines(for: snapshot)
                            .joined(separator: "\n")
                    )
                } label: {
                    Label("Copy Setup Diagnostics", systemImage: "stethoscope")
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Advanced connection details", systemImage: "gearshape.2")
                .agentPulseFont(size: 15)
        }
        .setupCard()
    }

    private func advancedRow(
        _ title: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
            if monospaced {
                Text(value)
                    .monospaced()
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .textSelection(.enabled)
            }
        }
    }

    private func operationNotice(_ notice: SetupOperationNotice) -> some View {
        messageCard(
            title: notice.kind == .success ? "Finished" : "Setup failed",
            message: [notice.message, notice.recovery].compactMap { $0 }.joined(separator: " "),
            systemImage: notice.kind == .success ? "checkmark.circle.fill" : "xmark.octagon.fill",
            tint: notice.kind == .success ? .green : .red
        ) {
            Button("Dismiss") {
                workflow.dismissNotice()
            }
        }
    }

    private func messageCard<Actions: View>(
        title: String,
        message: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .agentPulseFont(size: 15)
                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
            actions()
        }
        .padding(14)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func recommendedAction(for snapshot: SetupHealthSnapshot) -> some View {
        switch snapshot.recommendedAction {
        case .installBridge:
            operationButton(.installBridge)
        case .repairBridge:
            operationButton(.repairBridge)
        case .moveApplication:
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([snapshot.application.bundleURL])
            }
        case .reviewIntegrationConfiguration(let agent):
            Button("Show Configuration") {
                revealConfiguration(for: agent)
            }
        case .restartLocalServer:
            Button("Quit Agent Pulse") {
                NSApplication.shared.terminate(nil)
            }
        case .installHost(let agent), .signIn(let agent):
            Button("Open \(agent.displayName)") {
                Task { _ = await runtime.appLauncher.open(agent) }
            }
        case .installIntegration,
             .repairIntegration,
             .testIntegration,
             .requestNotificationPermission,
             .openNotificationSettings,
             .approveLaunchAtLogin,
             .none:
            EmptyView()
        }
    }

    private func operationButton(_ operation: SetupOperation) -> some View {
        Button(role: isRemoval(operation) ? .destructive : nil) {
            Task { await workflow.perform(operation) }
        } label: {
            if workflow.activeOperation == operation {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation.title)
                }
            } else {
                Text(operation.title)
            }
        }
        .disabled(workflow.activeOperation != nil || workflow.isRefreshing)
    }

    private func statusRow(_ title: String, _ value: String, icon: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Label(value, systemImage: icon)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusBadge(_ text: String, tone: SetupTone) -> some View {
        Text(text)
            .agentPulseFont(size: 11)
            .foregroundStyle(tone.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tone.color.opacity(0.12), in: Capsule())
    }

    private func revealConfiguration(for agent: AgentKind) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url: URL
        switch agent {
        case .claude:
            url = home.appendingPathComponent(".claude/settings.json")
        case .codex:
            url = home.appendingPathComponent(".codex/config.toml")
        }

        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func recommendedMessage(_ action: SetupRecommendedAction) -> String {
        switch action {
        case .installHost(let agent): return "Install \(agent.displayName) before enabling its integration."
        case .installIntegration(let agent): return "Set up \(agent.displayName) when you want its work status in the menu bar."
        case .repairIntegration(let agent): return "Repair the existing \(agent.displayName) hooks to match this version."
        case .reviewIntegrationConfiguration(let agent): return "Review the existing \(agent.displayName) configuration before changing it."
        case .signIn(let agent): return "Sign in to \(agent.displayName) to display usage."
        case .testIntegration(let agent): return "Use \(agent.displayName) once, then refresh to confirm its first hook event."
        case .requestNotificationPermission: return "Notifications can be enabled later when you first need them."
        case .openNotificationSettings: return "Notifications are currently disabled in System Settings."
        case .approveLaunchAtLogin: return "Launch at Login requires approval in System Settings."
        case .moveApplication: return "Move Agent Pulse into an Applications folder before changing integrations."
        case .restartLocalServer: return "Restart Agent Pulse so the local event server can start cleanly."
        case .installBridge: return "Install the local bridge before enabling integration hooks."
        case .repairBridge: return "Repair the local bridge so it matches this version of Agent Pulse."
        case .none: return "Setup is complete."
        }
    }

    private func integrationGuidance(_ integration: IntegrationHealthSnapshot) -> String? {
        switch integration.recommendedAction {
        case .installHost:
            return "Install \(integration.agent.displayName), then refresh this window."
        case .signIn:
            return "Sign in through \(integration.agent.displayName), then refresh usage."
        case .testIntegration:
            return "No hook event has arrived yet. Use \(integration.agent.displayName) once, then refresh."
        case .reviewIntegrationConfiguration:
            if case .invalid(let reason) = integration.hooks {
                return "Agent Pulse left this configuration unchanged: \(reason)"
            }
            return "Review the existing configuration before retrying."
        default:
            return nil
        }
    }

    private func integrationStatusLabel(_ integration: IntegrationHealthSnapshot) -> String {
        switch integration.hooks {
        case .current: return "Connected"
        case .missing: return "Not set up"
        case .outdated: return "Needs repair"
        case .duplicated: return "Needs repair"
        case .invalid: return "Needs review"
        }
    }

    private func integrationTone(_ integration: IntegrationHealthSnapshot) -> SetupTone {
        switch integration.hooks {
        case .current: return .good
        case .missing: return .neutral
        case .outdated, .duplicated: return .warning
        case .invalid: return .bad
        }
    }

    private func bridgeLabel(_ health: BridgeHealth) -> String {
        switch health {
        case .missing: return "Not installed"
        case .current(let version): return "Ready · v\(version)"
        case .outdated: return "Outdated"
        case .unreadable, .invalid: return "Needs repair"
        }
    }

    private func bridgeTone(_ health: BridgeHealth) -> SetupTone {
        switch health {
        case .current: return .good
        case .missing: return .neutral
        case .outdated: return .warning
        case .unreadable, .invalid: return .bad
        }
    }

    private func hostLabel(_ health: IntegrationHostHealth) -> String {
        switch health {
        case .available(let location): return location.lastPathComponent
        case .unavailable: return "Not found"
        }
    }

    private func hostIcon(_ health: IntegrationHostHealth) -> String {
        if case .available = health { return "checkmark.circle.fill" }
        return "minus.circle"
    }

    private func hookLabel(_ health: HookConfigurationHealth) -> String {
        switch health {
        case .missing: return "Not configured"
        case .current: return "Current"
        case .outdated: return "Outdated"
        case .duplicated(let count): return "\(count) duplicate entries"
        case .invalid(let reason): return reason
        }
    }

    private func hookIcon(_ health: HookConfigurationHealth) -> String {
        switch health {
        case .current: return "checkmark.circle.fill"
        case .missing: return "minus.circle"
        case .outdated, .duplicated: return "exclamationmark.triangle.fill"
        case .invalid: return "xmark.octagon.fill"
        }
    }

    private func usageLabel(_ health: SetupUsageHealth) -> String {
        switch health {
        case .loading: return "Checking…"
        case .available: return "Available"
        case .missingAuth: return "Sign-in not found"
        case .accessDenied: return "Access denied"
        case .sessionExpired: return "Session expired"
        case .notInstalled: return "Tool not installed"
        case .notLoggedIn: return "Not signed in"
        case .error: return "Unavailable"
        }
    }

    private func usageIcon(_ health: SetupUsageHealth) -> String {
        switch health {
        case .available: return "checkmark.circle.fill"
        case .loading: return "clock"
        case .missingAuth, .notInstalled, .notLoggedIn: return "minus.circle"
        case .accessDenied, .sessionExpired, .error: return "exclamationmark.triangle.fill"
        }
    }

    private func eventLabel(_ health: LastIntegrationEventHealth) -> String {
        switch health {
        case .never:
            return "No event received"
        case .received(let event, let timestamp, _):
            let relative = RelativeTimeFormatter.shared.localizedString(
                for: timestamp,
                relativeTo: Date()
            )
            return "\(event) · \(relative)"
        }
    }

    private func eventIcon(_ health: LastIntegrationEventHealth) -> String {
        if case .received = health { return "checkmark.circle.fill" }
        return "clock"
    }

    private func isTranslocated(_ health: ApplicationLocationHealth) -> Bool {
        if case .translocated = health { return true }
        return false
    }

    private func isRemoval(_ operation: SetupOperation) -> Bool {
        if case .remove = operation { return true }
        return false
    }
}

private enum SetupTone {
    case good
    case neutral
    case warning
    case bad

    var color: Color {
        switch self {
        case .good: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .bad: return .red
        }
    }
}

private extension View {
    func setupCard() -> some View {
        padding(16)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}
