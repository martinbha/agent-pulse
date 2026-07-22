import Foundation

@testable import AgentPulseBridgeSupport

final class SelfTestClock {
    private(set) var date = Date(timeIntervalSince1970: 1_800_000_000)

    func now() -> Date { date }

    func sleep(_ interval: TimeInterval) async throws {
        date.addTimeInterval(interval)
        await Task.yield()
    }
}

final class SelfTestStateSequence {
    private let states: [BridgeSelfTestState]
    private(set) var queryCount = 0

    init(_ states: [BridgeSelfTestState]) {
        self.states = states
    }

    func next() -> BridgeSelfTestState {
        defer { queryCount += 1 }
        return states[min(queryCount, states.count - 1)]
    }
}

final class SelfTestLaunchCapture {
    private(set) var integration: String?
    private var input: Data?

    func capture(integration: String, input: Data) {
        self.integration = integration
        self.input = input
    }

    func decodedInput() -> [String: String]? {
        guard let input else { return nil }
        return try? JSONSerialization.jsonObject(with: input) as? [String: String]
    }
}

enum SelfTestFixtures {
    enum ProcessOutcome: Equatable {
        case timedOut
        case cancelled
        case other
    }

    static let executableURL = URL(fileURLWithPath: "/bin/echo")
    static let configuration = BridgeConfiguration(port: 37_462, token: "token")
    static let timestamp = "2027-01-15T08:00:00.000Z"

    static func receipt(
        identifier: String,
        integration: String = "claude",
        source: String = BridgeSelfTestProtocol.source,
        event: String = BridgeSelfTestProtocol.event,
        timestamp: String = timestamp
    ) -> BridgeSelfTestReceipt {
        BridgeSelfTestReceipt(
            identifier: identifier,
            integration: integration,
            source: source,
            event: event,
            timestamp: timestamp
        )
    }

    static func runner(
        clock: SelfTestClock = SelfTestClock(),
        timeout: TimeInterval = 1,
        pollingInterval: TimeInterval = 0.1,
        configurationLoader: @escaping BridgeSelfTestRunner.ConfigurationLoader = { _ in configuration },
        inputBuilder: @escaping BridgeSelfTestRunner.InputBuilder = BridgeSelfTestRunner.makeInput,
        processLauncher: @escaping BridgeSelfTestRunner.ProcessLauncher = { _, _, _, _ in },
        stateQuery: @escaping BridgeSelfTestRunner.StateQuery = { _ in
            .init(ok: true, receipt: receipt(identifier: "expected"))
        },
        sleep: BridgeSelfTestRunner.Sleep? = nil
    ) -> BridgeSelfTestRunner {
        BridgeSelfTestRunner(
            executableURL: executableURL,
            timeout: timeout,
            pollingInterval: pollingInterval,
            configurationLoader: configurationLoader,
            inputBuilder: inputBuilder,
            processLauncher: processLauncher,
            stateQuery: stateQuery,
            sleep: sleep ?? clock.sleep,
            now: clock.now,
            identifierProvider: { "expected" }
        )
    }

    static func missingExecutableRunner() -> BridgeSelfTestRunner {
        var runner = runner()
        runner.executableURL = URL(fileURLWithPath: "/missing/agent-pulse-hook")
        return runner
    }

    static func failure(
        from runner: BridgeSelfTestRunner,
        integration: String
    ) async -> BridgeSelfTestFailure? {
        do {
            _ = try await runner.run(integration: integration)
            return nil
        } catch let failure as BridgeSelfTestFailure {
            return failure
        } catch {
            return nil
        }
    }

    static func timedOutProcessOutcome() async -> ProcessOutcome {
        do {
            try await BridgeSelfTestRunner.launch(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                integration: "5",
                input: Data(),
                timeout: 0.05
            )
            return .other
        } catch BridgeSelfTestProcessError.timedOut {
            return .timedOut
        } catch {
            return .other
        }
    }

    static func cancelledProcessOutcome() async -> ProcessOutcome {
        let task = Task {
            try await BridgeSelfTestRunner.launch(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                integration: "5",
                input: Data(),
                timeout: 10
            )
        }
        await Task.yield()
        task.cancel()

        do {
            try await task.value
            return .other
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .other
        }
    }
}
