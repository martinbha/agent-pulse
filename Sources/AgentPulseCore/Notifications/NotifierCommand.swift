import UserNotifications

/// Payload the main app hands to a notifier helper via argv, and the helper
/// parses back on launch. A launch without a parseable command means the
/// system started the helper for a notification interaction instead.
public struct NotifierCommand: Equatable, Sendable {
    public static let hostBundleIDUserInfoKey = "hostBundleID"
    public static let requestAuthorizationArgument = "--request-authorization"
    public static let authorizationStatusArgument = "--authorization-status"

    public var title: String
    public var body: String
    public var hostBundleID: String?
    public var requestsAuthorization: Bool

    public init(
        title: String,
        body: String,
        hostBundleID: String? = nil,
        requestsAuthorization: Bool = false
    ) {
        self.title = title
        self.body = body
        // Normalized here so every consumer can treat presence as usable.
        self.hostBundleID = hostBundleID.flatMap { $0.isEmpty ? nil : $0 }
        self.requestsAuthorization = requestsAuthorization
    }

    public func argumentList() -> [String] {
        var arguments = ["--title", title, "--body", body]
        if let hostBundleID {
            arguments += ["--host-bundle-id", hostBundleID]
        }
        if requestsAuthorization {
            arguments.append(Self.requestAuthorizationArgument)
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
            hostBundleID: values["--host-bundle-id"],
            requestsAuthorization: arguments.contains(Self.requestAuthorizationArgument)
        )
    }
}

public enum NotifierAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    public init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .unknown
        }
    }
}

public enum NotifierAuthorizationAction: Equatable, Sendable {
    case post
    case request
    case deny
}

public enum NotifierAuthorizationPolicy {
    public static func action(
        for status: NotifierAuthorizationStatus,
        requestsAuthorization: Bool
    ) -> NotifierAuthorizationAction {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .post
        case .notDetermined:
            return requestsAuthorization ? .request : .deny
        case .denied, .unknown:
            return .deny
        }
    }
}
