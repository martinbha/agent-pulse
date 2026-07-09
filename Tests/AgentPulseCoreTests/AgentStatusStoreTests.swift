import Testing

@testable import AgentPulseCore

@MainActor
@Suite struct AgentStatusStoreLoadTests {
    @Test func restoresWorkingAsIdle() {
        #expect(AgentStatusStoreFixtures.restoredState(from: .working) == .idle)
    }

    @Test func restoresWaitingAsIdle() {
        #expect(AgentStatusStoreFixtures.restoredState(from: .waiting) == .idle)
    }

    @Test func keepsIdle() {
        #expect(AgentStatusStoreFixtures.restoredState(from: .idle) == .idle)
    }

    @Test func keepsDone() {
        #expect(AgentStatusStoreFixtures.restoredState(from: .done) == .done)
    }

    @Test func keepsFailed() {
        #expect(AgentStatusStoreFixtures.restoredState(from: .failed) == .failed)
    }
}
