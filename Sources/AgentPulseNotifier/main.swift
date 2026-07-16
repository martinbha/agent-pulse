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
    private var exitWorkItem: DispatchWorkItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must be in place before launch finishes so a click that relaunched
        // this helper still delivers its notification response.
        center.delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        removeStaleDeliveredNotifications()

        if let command {
            post(command)
            // Normal posting exits well before this; the deadline covers an
            // unanswered first-run permission prompt holding the process open.
            scheduleExit(after: NotificationTiming.posterDeadline)
        } else {
            // Launched for a notification interaction; didReceive arrives
            // right away and cancels this deadline while it works.
            scheduleExit(after: NotificationTiming.interactionDeadline)
        }
    }

    /// The deadline is cancellable so an in-flight click handler is never
    /// torn down mid-open.
    private func scheduleExit(after delay: TimeInterval) {
        let work = DispatchWorkItem { exit(0) }
        exitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
        exitWorkItem?.cancel()

        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let hostBundleID = NotifierCommand.hostBundleID(
               from: response.notification.request.content.userInfo
           ) {
            await HostAppOpener.open(bundleID: hostBundleID)
        }

        // A posting instance keeps running so its own timed cleanup still
        // removes the notification it owns.
        if command == nil {
            exit(0)
        }
    }

    // Exit codes surfaced to the main app: 2 = no permission, 1 = post failed.
    private func post(_ command: NotifierCommand) {
        center.requestAuthorization(options: [.alert, .sound]) { [center] granted, error in
            if let error {
                NSLog("Agent Pulse notifier authorization failed: %@", error.localizedDescription)
                exit(2)
            }
            guard granted else {
                NSLog("Agent Pulse notifier notifications were not granted")
                exit(2)
            }

            let request = UNNotificationRequest(
                identifier: "agent-pulse-\(UUID().uuidString)",
                content: command.makeNotificationContent(),
                trigger: nil
            )

            center.add(request) { error in
                if let error {
                    NSLog("Agent Pulse notifier failed to post: %@", error.localizedDescription)
                    exit(1)
                }

                let queue = DispatchQueue.global()
                queue.asyncAfter(deadline: .now() + NotificationTiming.bannerDismissalDelay) {
                    center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                }
                queue.asyncAfter(
                    deadline: .now() + NotificationTiming.bannerDismissalDelay
                        + NotificationTiming.posterExitGrace
                ) {
                    exit(0)
                }
            }
        }
    }

    /// A helper instance that dies before its timed cleanup leaves a stray
    /// notification behind; sweep old ones on the next post.
    private func removeStaleDeliveredNotifications() {
        center.getDeliveredNotifications { [center] delivered in
            let stale = delivered
                .filter { $0.date < Date(timeIntervalSinceNow: -NotificationTiming.staleSweepAge) }
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
