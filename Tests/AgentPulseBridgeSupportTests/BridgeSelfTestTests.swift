import Testing

@testable import AgentPulseBridgeSupport

@Suite struct BridgeSelfTestTests {
    @Test func succeedsOnlyForTheExactCorrelatedReceipt() async throws {
        let clock = SelfTestClock()
        let states = SelfTestStateSequence([
            .init(ok: true, receipt: nil),
            .init(ok: true, receipt: SelfTestFixtures.receipt(identifier: "old")),
            .init(ok: true, receipt: SelfTestFixtures.receipt(identifier: "expected")),
        ])
        let launch = SelfTestLaunchCapture()
        let runner = SelfTestFixtures.runner(
            clock: clock,
            processLauncher: { _, integration, input, _ in
                launch.capture(integration: integration, input: input)
            },
            stateQuery: { _ in states.next() }
        )

        let result = try await runner.run(integration: "claude")
        let input = try #require(launch.decodedInput())

        #expect(result.identifier == "expected")
        #expect(result.integration == "claude")
        #expect(launch.integration == "claude")
        #expect(input["hook_event_name"] == BridgeSelfTestProtocol.event)
        #expect(input["session_id"] == BridgeSelfTestProtocol.sessionID(for: "expected"))
        #expect(states.queryCount == 3)
    }

    @Test func staleOrMismatchedReceiptCannotProduceSuccess() async {
        let clock = SelfTestClock()
        let states = SelfTestStateSequence([
            .init(ok: true, receipt: nil),
            .init(ok: true, receipt: SelfTestFixtures.receipt(identifier: "old")),
        ])
        let runner = SelfTestFixtures.runner(
            clock: clock,
            timeout: 0.2,
            stateQuery: { _ in states.next() }
        )

        let failure = await SelfTestFixtures.failure(from: runner, integration: "claude")

        #expect(failure?.stage == .ingestion)
        #expect(states.queryCount > 2)
    }

    @Test func reportsProcessLaunchFailureAtTheExecutableStage() async {
        let runner = SelfTestFixtures.runner(
            processLauncher: { _, _, _, _ in
                throw BridgeSelfTestProcessError.launch("Permission denied")
            }
        )

        let failure = await SelfTestFixtures.failure(from: runner, integration: "codex")

        #expect(failure?.stage == .executable)
        #expect(failure?.message.contains("Permission denied") == true)
    }

    @Test func reportsMissingExecutableAndInputEncodingSeparately() async {
        let missingExecutable = SelfTestFixtures.missingExecutableRunner()
        let invalidInput = SelfTestFixtures.runner(
            inputBuilder: { _, _ in
                throw BridgeConfigurationError.invalid("Synthetic input failure")
            }
        )

        let executableFailure = await SelfTestFixtures.failure(
            from: missingExecutable,
            integration: "claude"
        )
        let inputFailure = await SelfTestFixtures.failure(
            from: invalidInput,
            integration: "claude"
        )

        #expect(executableFailure?.stage == .executable)
        #expect(inputFailure?.stage == .input)
    }

    @Test func reportsStoppedServerAndStaleTokenDistinctly() async {
        let stopped = SelfTestFixtures.runner(
            stateQuery: { _ in
                throw BridgeSelfTestStateQueryError.connection("Connection refused")
            }
        )
        let unauthorized = SelfTestFixtures.runner(
            stateQuery: { _ in
                throw BridgeSelfTestStateQueryError.authorization
            }
        )

        let stoppedFailure = await SelfTestFixtures.failure(from: stopped, integration: "claude")
        let unauthorizedFailure = await SelfTestFixtures.failure(from: unauthorized, integration: "claude")

        #expect(stoppedFailure?.stage == .connection)
        #expect(unauthorizedFailure?.stage == .authorization)
    }

    @Test func reportsMalformedConfigurationAndResponseDistinctly() async {
        let malformedConfiguration = SelfTestFixtures.runner(
            configurationLoader: { _ in
                throw BridgeConfigurationError.invalid("invalid JSON")
            }
        )
        let malformedResponse = SelfTestFixtures.runner(
            stateQuery: { _ in
                throw BridgeSelfTestStateQueryError.decode("Expected object")
            }
        )

        let configurationFailure = await SelfTestFixtures.failure(
            from: malformedConfiguration,
            integration: "claude"
        )
        let responseFailure = await SelfTestFixtures.failure(
            from: malformedResponse,
            integration: "claude"
        )

        #expect(configurationFailure?.stage == .configuration)
        #expect(responseFailure?.stage == .decode)
    }

    @Test func reportsCorrelatedFieldOrTimestampMismatchAsIngestionFailure() async {
        let wrongSource = SelfTestStateSequence([
            .init(ok: true, receipt: nil),
            .init(
                ok: true,
                receipt: SelfTestFixtures.receipt(identifier: "expected", source: "manual")
            ),
        ])
        let staleTimestamp = SelfTestStateSequence([
            .init(ok: true, receipt: nil),
            .init(
                ok: true,
                receipt: SelfTestFixtures.receipt(
                    identifier: "expected",
                    timestamp: "2020-01-01T00:00:00.000Z"
                )
            ),
        ])

        let sourceFailure = await SelfTestFixtures.failure(
            from: SelfTestFixtures.runner(stateQuery: { _ in wrongSource.next() }),
            integration: "claude"
        )
        let timestampFailure = await SelfTestFixtures.failure(
            from: SelfTestFixtures.runner(stateQuery: { _ in staleTimestamp.next() }),
            integration: "claude"
        )

        #expect(sourceFailure?.stage == .ingestion)
        #expect(sourceFailure?.message.contains("fields") == true)
        #expect(timestampFailure?.stage == .ingestion)
        #expect(timestampFailure?.message.contains("timestamp") == true)
    }

    @Test func reportsPostLaunchQueryFailureAtTheStateQueryStage() async {
        let states = SelfTestStateSequence([
            .init(ok: true, receipt: nil),
        ])
        let runner = SelfTestFixtures.runner(
            stateQuery: { _ in
                if states.queryCount == 0 {
                    return states.next()
                }
                throw BridgeSelfTestStateQueryError.connection("Server stopped")
            }
        )

        let failure = await SelfTestFixtures.failure(from: runner, integration: "claude")

        #expect(failure?.stage == .stateQuery)
    }

    @Test func cancellationStopsPollingWithACancelledResult() async {
        let runner = SelfTestFixtures.runner(
            pollingInterval: 10,
            stateQuery: { _ in .init(ok: true, receipt: nil) },
            sleep: BridgeSelfTestRunner.sleep
        )
        let task = Task {
            try await runner.run(integration: "claude")
        }
        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation to stop the self-test")
        } catch let failure as BridgeSelfTestFailure {
            #expect(failure.stage == .cancelled)
        } catch {
            Issue.record("Expected a stage-specific cancellation result")
        }
    }

    @Test func cancellationDuringStateQueryUsesTheCancelledStage() async {
        let runner = SelfTestFixtures.runner(
            stateQuery: { _ in throw CancellationError() }
        )

        let failure = await SelfTestFixtures.failure(from: runner, integration: "claude")

        #expect(failure?.stage == .cancelled)
    }

    @Test func nativeProcessLaunchIsBoundedAndCancellationAware() async {
        #expect(await SelfTestFixtures.timedOutProcessOutcome() == .timedOut)
        #expect(await SelfTestFixtures.cancelledProcessOutcome() == .cancelled)
    }
}
