import Foundation

enum BridgeEventNormalizer {
    private static let stateByEvent = [
        "SessionStart": "idle",
        "UserPromptSubmit": "working",
        "PreToolUse": "working",
        "PostToolUse": "working",
        "PermissionRequest": "waiting",
        "Notification": "waiting",
        "SubagentStop": "working",
        "Stop": "done",
        "StopFailure": "failed",
        "SessionEnd": "idle",
    ]

    static func decodeInput(_ data: Data) -> [String: Any] {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return [:]
        }

        return dictionary
    }

    static func normalize(
        agent: String,
        input: [String: Any],
        currentDirectory: String,
        timestamp: String,
        hostBundleID: String?
    ) -> BridgeEvent {
        let event = firstNonemptyString(
            in: input,
            keys: ["hook_event_name", "hookEventName", "event_name", "event"]
        ) ?? "Unknown"
        let cwd = firstNonemptyString(
            in: input,
            keys: ["cwd", "project_dir", "projectDir", "workspace", "repo"]
        ) ?? currentDirectory

        return BridgeEvent(
            agent: agent,
            state: stateByEvent[event] ?? "working",
            event: event,
            sessionID: firstNonemptyString(in: input, keys: ["session_id", "sessionId"]),
            cwd: cwd,
            project: projectName(for: cwd),
            timestamp: timestamp,
            source: "hook",
            hostBundleID: normalized(hostBundleID)
        )
    }

    private static func firstNonemptyString(in input: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = normalized(input[key] as? String) {
                return value
            }
        }
        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func projectName(for cwd: String) -> String? {
        guard !cwd.isEmpty else {
            return nil
        }

        var normalizedCWD = cwd
        while normalizedCWD.count > 1 && normalizedCWD.hasSuffix("/") {
            normalizedCWD.removeLast()
        }
        if normalizedCWD == "/" {
            return "/"
        }
        return URL(fileURLWithPath: normalizedCWD).lastPathComponent
    }
}
