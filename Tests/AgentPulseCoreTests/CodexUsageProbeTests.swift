import Testing

@testable import AgentPulseCore

@Suite struct CodexJSONRPCFramingTests {
    @Test func writesNewlineTerminatedSingleLineJSON() {
        let line = CodexUsageFixtures.framedLine()

        #expect(line == "{\"id\":7}\n")
    }
}

@Suite struct CodexJSONRPCReadingTests {
    @Test func skipsUnrelatedLinesUntilMatchingID() async {
        let value = await CodexUsageFixtures.matchedResponseValue()

        #expect(value == "matched")
    }

    @Test func matchesStringEncodedIDs() async {
        #expect(await CodexUsageFixtures.matchesStringIDs())
    }

    @Test func surfacesErrorPayloadMessage() async {
        let message = await CodexUsageFixtures.errorPayloadMessage()

        #expect(message == "not logged in")
    }

    @Test func reportsClosedStreamWithoutResponse() async {
        let message = await CodexUsageFixtures.closedStreamMessage()

        #expect(message == "Codex app-server closed before returning response id 9.")
    }

    @Test func timesOutAndInvokesTerminator() async {
        let outcome = await CodexUsageFixtures.timeoutOutcome()

        #expect(outcome.timedOut)
        #expect(outcome.terminatorCalls == 1)
    }
}

@Suite struct CodexWindowParsingTests {
    @Test func parsesUsedPercentAndEpochReset() {
        let window = CodexUsageFixtures.parsedFullWindow()

        #expect(window.used == 41.5)
        #expect(window.resetEpoch == 1_767_225_600)
    }

    @Test func windowWithoutUsedPercentIsRejected() {
        #expect(CodexUsageFixtures.windowWithoutUsedPercentIsNil())
    }

    @Test func coercesStringEncodedNumbers() {
        let window = CodexUsageFixtures.windowWithStringNumbersParses()

        #expect(window.used == 41.5)
        #expect(window.resetEpoch == 1_767_225_600)
    }

    @Test func numericValueHandlesAllShapes() {
        let values = CodexUsageFixtures.numericCoercions()

        #expect(values[0] == 41.5)
        #expect(values[1] == 42.0)
        #expect(values[2] == 43.5)
        #expect(values[3] == nil)
        #expect(values[4] == nil)
    }
}
