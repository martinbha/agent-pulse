import AppKit
import Foundation
import UserNotifications

@MainActor
final class AgentNotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let verbProvider: WorkingVerbProvider

    init(
        center: UNUserNotificationCenter = .current(),
        verbProvider: WorkingVerbProvider = WorkingVerbProvider()
    ) {
        self.center = center
        self.verbProvider = verbProvider
        super.init()

        center.delegate = self
        center.removeAllDeliveredNotifications()
        requestAuthorization()
    }

    func handleTransition(
        agent: AgentKind,
        previousState: AgentState,
        newSnapshot: AgentStatusSnapshot,
        newState: AgentState
    ) {
        if previousState != .working && newState == .working {
            notify(agent: agent, action: "has begun", snapshot: newSnapshot)
        } else if previousState != .done && newState == .done {
            notify(agent: agent, action: "has finished", snapshot: newSnapshot)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }

        let userInfo = response.notification.request.content.userInfo
        guard
            let hostBundleID = userInfo[NotifierCommand.hostBundleIDUserInfoKey] as? String,
            !hostBundleID.isEmpty
        else {
            return
        }

        await HostAppOpener.open(bundleID: hostBundleID)
    }

    private func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    NSLog("Agent Pulse notification authorization failed: %@", error.localizedDescription)
                } else if !granted {
                    NSLog("Agent Pulse notifications were not granted")
                }
            }
        }
    }

    private func notify(agent: AgentKind, action: String, snapshot: AgentStatusSnapshot) {
        let verb = verbProvider.randomVerb()
        let command = NotifierCommand(
            title: "\(agent.notificationName) \(action) \(verb)",
            body: [snapshot.project, snapshot.event]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
            hostBundleID: snapshot.hostBundleID
        )

        if launchNotifierHelper(for: agent, command: command) {
            return
        }

        postDirectly(command, agent: agent)
    }

    /// Notifications go out through the agent's bundled helper app so the
    /// banner carries that agent's logo as its sender icon.
    private func launchNotifierHelper(for agent: AgentKind, command: NotifierCommand) -> Bool {
        guard let executableURL = Self.notifierExecutableURL(for: agent) else {
            return false
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = command.argumentList()

        do {
            try process.run()
            return true
        } catch {
            NSLog("Agent Pulse could not launch notifier helper: %@", error.localizedDescription)
            return false
        }
    }

    private static func notifierExecutableURL(for agent: AgentKind) -> URL? {
        let name = agent.notifierHelperName
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/\(name).app/Contents/MacOS/\(name)")

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            return nil
        }
        return url
    }

    /// Direct posting from the main app remains as the fallback when the
    /// helper bundles are unavailable (e.g. running straight from `swift build`).
    private func postDirectly(_ command: NotifierCommand, agent: AgentKind) {
        let content = UNMutableNotificationContent()
        content.title = command.title
        content.body = command.body
        content.sound = .default

        if let hostBundleID = command.hostBundleID, !hostBundleID.isEmpty {
            content.userInfo = [NotifierCommand.hostBundleIDUserInfoKey: hostBundleID]
        }

        let identifier = "agent-pulse-\(agent.rawValue)-\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { [center] error in
            if let error {
                Task { @MainActor in
                    NSLog("Agent Pulse notification failed: %@", error.localizedDescription)
                }
                return
            }

            // macOS banners stay on screen for roughly 5 seconds; removing the
            // delivered notification after that keeps it out of Notification Center
            // without cutting the banner short.
            Task {
                try? await Task.sleep(for: .seconds(8))
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        }
    }
}

private extension AgentKind {
    var notificationName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

    var notifierHelperName: String {
        switch self {
        case .claude:
            return "Agent Pulse Claude"
        case .codex:
            return "Agent Pulse Codex"
        }
    }
}
