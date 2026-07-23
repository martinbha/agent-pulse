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
        guard let hostBundleID = NotifierCommand.hostBundleID(from: userInfo) else {
            return
        }

        await HostAppOpener.open(bundleID: hostBundleID)
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
        // Exit code 2 = no notification permission, 1 = posting failed
        // (see AgentPulseNotifier); surface those, since a spawned helper
        // failing is otherwise invisible to the main app.
        process.terminationHandler = { process in
            if process.terminationStatus != 0 {
                NSLog(
                    "Agent Pulse notifier helper for %@ exited with status %d",
                    agent.rawValue,
                    process.terminationStatus
                )
            }
        }

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
        center.getNotificationSettings { [center] settings in
            let status = NotifierAuthorizationStatus(settings.authorizationStatus)
            guard NotifierAuthorizationPolicy.action(
                for: status,
                requestsAuthorization: false
            ) == .post else {
                return
            }

            let identifier = "agent-pulse-\(agent.rawValue)-\(UUID().uuidString)"
            let request = UNNotificationRequest(
                identifier: identifier,
                content: command.makeNotificationContent(),
                trigger: nil
            )

            center.add(request) { [center] error in
                if let error {
                    Task { @MainActor in
                        NSLog("Agent Pulse notification failed: %@", error.localizedDescription)
                    }
                    return
                }

                Task {
                    try? await Task.sleep(
                        for: .seconds(NotificationTiming.bannerDismissalDelay)
                    )
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                }
            }
        }
    }
}

extension AgentKind {
    var notificationName: String {
        switch self {
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        }
    }

    /// Must stay in sync with the helper bundles assembled by
    /// scripts/build-app-bundle; a mismatch silently degrades to the
    /// direct-posting fallback.
    var notifierHelperName: String {
        switch self {
        case .claude:
            return "Agent Pulse Claude"
        case .codex:
            return "Agent Pulse Codex"
        }
    }
}
