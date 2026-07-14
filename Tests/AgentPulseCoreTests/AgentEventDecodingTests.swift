import Testing

@testable import AgentPulseCore

@Suite struct AgentEventDecodingTests {
    @Test func decodesHostBundleID() {
        let event = AgentEventFixtures.decodedEvent(
            fromJSON: """
            {"agent": "claude", "state": "working", "event": "PreToolUse", "host_bundle_id": "com.googlecode.iterm2"}
            """
        )
        #expect(event?.hostBundleID == "com.googlecode.iterm2")
    }

    @Test func decodesNullHostBundleIDAsNil() {
        let event = AgentEventFixtures.decodedEvent(
            fromJSON: """
            {"agent": "codex", "state": "done", "event": "Stop", "host_bundle_id": null}
            """
        )
        #expect(event != nil)
        #expect(event?.hostBundleID == nil)
    }

    @Test func decodesMissingHostBundleIDAsNil() {
        let event = AgentEventFixtures.decodedEvent(
            fromJSON: """
            {"agent": "claude", "state": "working", "event": "PreToolUse"}
            """
        )
        #expect(event != nil)
        #expect(event?.hostBundleID == nil)
    }
}
