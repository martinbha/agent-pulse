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

    private func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    NSLog("Agent Pulse notification authorization failed: %{public}@", error.localizedDescription)
                } else if !granted {
                    NSLog("Agent Pulse notifications were not granted")
                }
            }
        }
    }

    private func notify(agent: AgentKind, action: String, snapshot: AgentStatusSnapshot) {
        let verb = verbProvider.randomVerb()
        let content = UNMutableNotificationContent()
        content.title = "\(agent.notificationName) \(action) \(verb)"
        content.body = [snapshot.project, snapshot.event]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        content.sound = .default

        let identifier = "agent-pulse-\(agent.rawValue)-\(UUID().uuidString)"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        center.add(request) { [center] error in
            if let error {
                Task { @MainActor in
                    NSLog("Agent Pulse notification failed: %{public}@", error.localizedDescription)
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
}
