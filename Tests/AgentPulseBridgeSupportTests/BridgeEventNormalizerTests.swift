import Testing

@testable import AgentPulseBridgeSupport

@Suite struct BridgeEventNormalizerTests {
    @Test func mapsKnownEventAndPayloadFields() {
        let event = BridgeEventNormalizer.normalize(
            agent: "sample",
            input: [
                "hook_event_name": "PermissionRequest",
                "session_id": "session-1",
                "cwd": "/tmp/example-project",
            ],
            currentDirectory: "/tmp/fallback",
            timestamp: "2026-07-20T10:30:00Z",
            hostBundleID: "com.example.host"
        )

        #expect(event.agent == "sample")
        #expect(event.state == "waiting")
        #expect(event.event == "PermissionRequest")
        #expect(event.sessionID == "session-1")
        #expect(event.cwd == "/tmp/example-project")
        #expect(event.project == "example-project")
        #expect(event.timestamp == "2026-07-20T10:30:00Z")
        #expect(event.source == "hook")
        #expect(event.hostBundleID == "com.example.host")
    }

    @Test func usesAlternatePayloadKeysInPriorityOrder() {
        let event = BridgeEventNormalizer.normalize(
            agent: "sample",
            input: [
                "event": "Stop",
                "event_name": "PreToolUse",
                "workspace": "/tmp/workspace",
                "repo": "/tmp/repo",
                "sessionId": "session-2",
            ],
            currentDirectory: "/tmp/fallback",
            timestamp: "now",
            hostBundleID: nil
        )

        #expect(event.event == "PreToolUse")
        #expect(event.state == "working")
        #expect(event.cwd == "/tmp/workspace")
        #expect(event.project == "workspace")
        #expect(event.sessionID == "session-2")
    }

    @Test func malformedOrEmptyInputUsesSafeFallbacks() {
        for value in [nil, "not json", "[]"] as [String?] {
            let input = BridgeEventFixtures.decodedInput(from: value)
            let event = BridgeEventNormalizer.normalize(
                agent: "sample",
                input: input,
                currentDirectory: "/tmp/fallback",
                timestamp: "now",
                hostBundleID: ""
            )

            #expect(event.event == "Unknown")
            #expect(event.state == "working")
            #expect(event.cwd == "/tmp/fallback")
            #expect(event.project == "fallback")
            #expect(event.hostBundleID == nil)
        }
    }

    @Test func mapsEveryKnownStateTransition() {
        let expected = [
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

        for (name, state) in expected {
            let event = BridgeEventNormalizer.normalize(
                agent: "sample",
                input: ["hook_event_name": name],
                currentDirectory: "/",
                timestamp: "now",
                hostBundleID: nil
            )
            #expect(event.state == state)
            #expect(event.project == "/")
        }
    }

    @Test func encodesServerCompatibleKeys() throws {
        let event = BridgeEventNormalizer.normalize(
            agent: "sample",
            input: ["hook_event_name": "Stop", "sessionId": "session-3"],
            currentDirectory: "/tmp/project",
            timestamp: "2026-07-20T10:30:00Z",
            hostBundleID: "com.example.host"
        )

        let object = try BridgeEventFixtures.encodedObject(for: event)

        #expect(object["session_id"] as? String == "session-3")
        #expect(object["host_bundle_id"] as? String == "com.example.host")
        #expect(object["sessionID"] == nil)
        #expect(object["hostBundleID"] == nil)
    }
}
