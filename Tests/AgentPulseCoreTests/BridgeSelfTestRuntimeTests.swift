import Testing

@testable import AgentPulseCore

@Suite struct BridgeSelfTestRuntimeTests {
    @Test @MainActor func recognizesSelfTestEventsWithoutClassifyingNormalEvents() throws {
        let receipt = try #require(BridgeSelfTestRuntimeFixtures.receipt())

        #expect(receipt.identifier == "correlation-1")
        #expect(receipt.integration == "codex")
        #expect(receipt.source == "hook")
        #expect(receipt.event == "AgentPulseSelfTest")
        #expect(!receipt.timestamp.isEmpty)
        #expect(!BridgeSelfTestRuntimeFixtures.normalEventCreatesReceipt())
    }

    @Test @MainActor func exposesTheTransientReceiptAlongsideEmptyNormalState() throws {
        let receipt = try #require(BridgeSelfTestRuntimeFixtures.receipt())
        let state = try BridgeSelfTestRuntimeFixtures.encodedState(receipt)

        #expect(state.hasNoAgents)
        #expect(state.identifier == "correlation-1")
    }
}
