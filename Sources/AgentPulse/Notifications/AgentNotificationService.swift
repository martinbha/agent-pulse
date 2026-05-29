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
        [.banner, .list, .sound]
    }

    private func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Agent Pulse notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                NSLog("Agent Pulse notifications were not granted")
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

        let request = UNNotificationRequest(
            identifier: "agent-pulse-\(agent.rawValue)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                NSLog("Agent Pulse notification failed: \(error.localizedDescription)")
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
