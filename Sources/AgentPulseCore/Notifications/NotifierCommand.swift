import UserNotifications

/// Payload the main app hands to a notifier helper via argv, and the helper
/// parses back on launch. A launch without a parseable command means the
/// system started the helper for a notification interaction instead.
public struct NotifierCommand: Equatable, Sendable {
    public static let hostBundleIDUserInfoKey = "hostBundleID"

    public var title: String
    public var body: String
    public var hostBundleID: String?

    public init(title: String, body: String, hostBundleID: String? = nil) {
        self.title = title
        self.body = body
        // Normalized here so every consumer can treat presence as usable.
        self.hostBundleID = hostBundleID.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func argumentList() -> [String] {
        var arguments = ["--title", title, "--body", body]
        if let hostBundleID {
            arguments += ["--host-bundle-id", hostBundleID]
        }
        return arguments
    }

    /// Single source of the notification payload for both the notifier
    /// helpers and the main app's direct-posting fallback.
    public func makeNotificationContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let hostBundleID {
            content.userInfo = [Self.hostBundleIDUserInfoKey: hostBundleID]
        }
        return content
    }

    public static func hostBundleID(from userInfo: [AnyHashable: Any]) -> String? {
        guard
            let value = userInfo[hostBundleIDUserInfoKey] as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    public static func parse(_ arguments: [String]) -> NotifierCommand? {
        var values: [String: String] = [:]
        var index = 0
        while index + 1 < arguments.count {
            let key = arguments[index]
            if key.hasPrefix("--") {
                values[key] = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
        }

        guard let title = values["--title"] else {
            return nil
        }

        return NotifierCommand(
            title: title,
            body: values["--body"] ?? "",
            hostBundleID: values["--host-bundle-id"]
        )
    }
}
