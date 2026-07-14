import AgentPulseCore
import AppKit
import UserNotifications

/// Posts one notification handed over via argv and exits once the banner has
/// been shown and cleaned up. The system also launches this helper when its
/// notification is clicked; that launch carries no command and only handles
/// the click. Each agent's helper bundle wraps this same executable, so the
/// banner's sender icon is that agent's logo.
final class NotifierDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let command = NotifierCommand.parse(Array(CommandLine.arguments.dropFirst()))

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be in place before launch finishes so a click that relaunched
        // this helper still delivers its notification response.
        center.delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let command {
            post(command)
        } else {
            // Launched for a notification interaction; didReceive arrives
            // right away. The deadline covers stray launches with nothing
            // to deliver.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exit(0)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let hostBundleID = response.notification.request.content.userInfo[
               NotifierCommand.hostBundleIDUserInfoKey
           ] as? String,
           !hostBundleID.isEmpty {
            await HostAppOpener.open(bundleID: hostBundleID)
        }

        // A posting instance keeps running so its own timed cleanup still
        // removes the notification it owns.
        if command == nil {
            exit(0)
        }
    }

    private func post(_ command: NotifierCommand) {
        removeStaleDeliveredNotifications()

        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, error in
            if let error {
                NSLog("Agent Pulse notifier authorization failed: %{public}@", error.localizedDescription)
            }
            guard granted else {
                exit(0)
            }

            let content = UNMutableNotificationContent()
            content.title = command.title
            content.body = command.body
            content.sound = .default
            if let hostBundleID = command.hostBundleID, !hostBundleID.isEmpty {
                content.userInfo = [NotifierCommand.hostBundleIDUserInfoKey: hostBundleID]
            }

            let request = UNNotificationRequest(
                identifier: "agent-pulse-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            center.add(request) { error in
                if let error {
                    NSLog("Agent Pulse notifier failed to post: %{public}@", error.localizedDescription)
                    exit(1)
                }

                // Banners hide after ~5 seconds; removing the delivered
                // notification afterwards keeps Notification Center empty
                // without cutting the banner short.
                DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                    center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                        exit(0)
                    }
                }
            }
        }
    }

    /// A helper instance that dies before its timed cleanup leaves a stray
    /// notification behind; sweep old ones on the next post.
    private func removeStaleDeliveredNotifications() {
        center.getDeliveredNotifications { [center] delivered in
            let stale = delivered
                .filter { $0.date < Date(timeIntervalSinceNow: -15) }
                .map(\.request.identifier)
            if !stale.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: stale)
            }
        }
    }
}

let delegate = NotifierDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
