import Testing

@testable import AgentPulseCore

@Suite struct AgentEventTests {
    @Test func resolvedProjectPrefersExplicitProject() {
        let event = TestFixtures.event(cwd: "/Users/example/dev/agent-pulse", project: "custom-name")

        #expect(event.resolvedProject == "custom-name")
    }

    @Test func resolvedProjectFallsBackToCwdBasename() {
        let event = TestFixtures.event(cwd: "/Users/example/dev/agent-pulse", project: nil)

        #expect(event.resolvedProject == "agent-pulse")
    }
}

@Suite struct AgentStatusSnapshotTests {
    @Test func effectiveStateMarksSilentWorkingAsStale() {
        let snapshot = TestFixtures.snapshot(state: .working, event: "PreToolUse", age: 600)

        #expect(TestFixtures.effectiveState(of: snapshot) == .stale)
    }

    @Test func effectiveStateFadesDoneToIdle() {
        let snapshot = TestFixtures.snapshot(state: .done, event: "Stop", age: 60)

        #expect(TestFixtures.effectiveState(of: snapshot) == .idle)
    }

    @Test func effectiveStateKeepsRecentWorking() {
        let snapshot = TestFixtures.snapshot(state: .working, event: "PostToolUse", age: 10)

        #expect(TestFixtures.effectiveState(of: snapshot) == .working)
    }
}
