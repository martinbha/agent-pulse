import Foundation

public enum BridgeSelfTestProtocol {
    public static let event = "AgentPulseSelfTest"
    public static let sessionPrefix = "agent-pulse-self-test:"
    public static let source = "hook"

    public static func sessionID(for identifier: String) -> String {
        sessionPrefix + identifier
    }

    public static func identifier(from sessionID: String?) -> String? {
        guard let sessionID, sessionID.hasPrefix(sessionPrefix) else {
            return nil
        }
        let identifier = String(sessionID.dropFirst(sessionPrefix.count))
        return identifier.isEmpty ? nil : identifier
    }
}

public struct BridgeSelfTestReceipt: Codable, Equatable, Sendable {
    public var identifier: String
    public var integration: String
    public var source: String
    public var event: String
    public var timestamp: String

    public init(
        identifier: String,
        integration: String,
        source: String,
        event: String,
        timestamp: String
    ) {
        self.identifier = identifier
        self.integration = integration
        self.source = source
        self.event = event
        self.timestamp = timestamp
    }
}

public struct BridgeSelfTestState: Codable, Equatable, Sendable {
    public var ok: Bool
    public var receipt: BridgeSelfTestReceipt?

    public init(ok: Bool, receipt: BridgeSelfTestReceipt?) {
        self.ok = ok
        self.receipt = receipt
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case receipt = "self_test"
    }
}

public enum BridgeSelfTestStage: String, Codable, Equatable, Sendable {
    case executable
    case input
    case configuration
    case connection
    case authorization
    case decode
    case ingestion
    case stateQuery = "state query"
    case cancelled
}

public struct BridgeSelfTestFailure: LocalizedError, Equatable, Sendable {
    public let stage: BridgeSelfTestStage
    public let message: String
    public let recovery: String

    public init(stage: BridgeSelfTestStage, message: String, recovery: String) {
        self.stage = stage
        self.message = message
        self.recovery = recovery
    }

    public var errorDescription: String? {
        "Self-test failed during \(stage.rawValue): \(message)"
    }

    public var recoverySuggestion: String? { recovery }
}

public struct BridgeSelfTestResult: Equatable, Sendable {
    public let identifier: String
    public let integration: String
    public let receipt: BridgeSelfTestReceipt

    public init(identifier: String, integration: String, receipt: BridgeSelfTestReceipt) {
        self.identifier = identifier
        self.integration = integration
        self.receipt = receipt
    }
}

public enum BridgeSelfTestStateQueryError: Error, Equatable, Sendable {
    case connection(String)
    case authorization
    case invalidResponse(String)
    case decode(String)
}

public enum BridgeSelfTestProcessError: LocalizedError, Equatable, Sendable {
    case launch(String)
    case terminated(Int32, String)
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .launch(let message):
            return message
        case .terminated(let status, let message):
            return message.isEmpty
                ? "The bridge exited with status \(status)."
                : "The bridge exited with status \(status): \(message)"
        case .timedOut(let timeout):
            return "The bridge did not exit within \(timeout.formatted()) seconds."
        }
    }
}

public struct BridgeSelfTestRunner {
    public typealias ConfigurationLoader = (URL) throws -> BridgeConfiguration
    public typealias InputBuilder = (String, String) throws -> Data
    public typealias ProcessLauncher = (URL, String, Data, TimeInterval) async throws -> Void
    public typealias StateQuery = (BridgeConfiguration) async throws -> BridgeSelfTestState
    public typealias Sleep = (TimeInterval) async throws -> Void

    public var executableURL: URL
    public var configurationURL: URL
    public var timeout: TimeInterval
    public var pollingInterval: TimeInterval

    private let configurationLoader: ConfigurationLoader
    private let inputBuilder: InputBuilder
    private let processLauncher: ProcessLauncher
    private let stateQuery: StateQuery
    private let sleep: Sleep
    private let now: () -> Date
    private let identifierProvider: () -> String

    public init(
        executableURL: URL,
        configurationURL: URL = BridgeConfigurationLoader.defaultURL,
        timeout: TimeInterval = 3,
        pollingInterval: TimeInterval = 0.1,
        configurationLoader: @escaping ConfigurationLoader = BridgeConfigurationLoader.load,
        inputBuilder: @escaping InputBuilder = BridgeSelfTestRunner.makeInput,
        processLauncher: @escaping ProcessLauncher = BridgeSelfTestRunner.launch,
        stateQuery: @escaping StateQuery = BridgeSelfTestRunner.queryState,
        sleep: @escaping Sleep = BridgeSelfTestRunner.sleep,
        now: @escaping () -> Date = Date.init,
        identifierProvider: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.executableURL = executableURL
        self.configurationURL = configurationURL
        self.timeout = timeout
        self.pollingInterval = pollingInterval
        self.configurationLoader = configurationLoader
        self.inputBuilder = inputBuilder
        self.processLauncher = processLauncher
        self.stateQuery = stateQuery
        self.sleep = sleep
        self.now = now
        self.identifierProvider = identifierProvider
    }

    public func run(integration: String) async throws -> BridgeSelfTestResult {
        try checkCancellation()

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw failure(
                .executable,
                "The installed bridge is missing or cannot be executed at \(executableURL.path).",
                "Repair the local bridge in Setup, then run the test again."
            )
        }

        let configuration: BridgeConfiguration
        do {
            configuration = try configurationLoader(configurationURL)
        } catch {
            throw failure(
                .configuration,
                BridgeDiagnosticMessage.describe(error),
                "Repair the local bridge configuration in Setup, then run the test again."
            )
        }

        do {
            _ = try await stateQuery(configuration)
        } catch is CancellationError {
            throw cancelledFailure()
        } catch {
            throw mapQueryError(error, initial: true)
        }

        let identifier = identifierProvider()
        let input: Data
        do {
            input = try inputBuilder(integration, identifier)
        } catch {
            throw failure(
                .input,
                "The synthetic hook input could not be encoded: \(error.localizedDescription)",
                "Retry the test. If this repeats, reinstall the current app version."
            )
        }

        let startedAt = now()
        do {
            try await processLauncher(executableURL, integration, input, timeout)
        } catch is CancellationError {
            throw cancelledFailure()
        } catch {
            throw failure(
                .executable,
                error.localizedDescription,
                "Repair the local bridge in Setup, then run the test again."
            )
        }

        let deadline = startedAt.addingTimeInterval(timeout)
        while now() <= deadline {
            try checkCancellation()

            let state: BridgeSelfTestState
            do {
                state = try await stateQuery(configuration)
            } catch is CancellationError {
                throw cancelledFailure()
            } catch {
                throw mapQueryError(error, initial: false)
            }

            if let receipt = state.receipt, receipt.identifier == identifier {
                try validate(
                    receipt,
                    integration: integration,
                    startedAt: startedAt
                )
                return BridgeSelfTestResult(
                    identifier: identifier,
                    integration: integration,
                    receipt: receipt
                )
            }

            do {
                try await sleep(pollingInterval)
            } catch is CancellationError {
                throw cancelledFailure()
            } catch {
                throw failure(
                    .stateQuery,
                    error.localizedDescription,
                    "Retry the test after confirming Agent Pulse remains open."
                )
            }
        }

        throw failure(
            .ingestion,
            "The local server did not report the correlated event within \(timeout.formatted()) seconds.",
            "Keep Agent Pulse open, repair the integration, and run the test again."
        )
    }

    public static func makeInput(integration: String, identifier: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "hook_event_name": BridgeSelfTestProtocol.event,
                "session_id": BridgeSelfTestProtocol.sessionID(for: identifier),
                "cwd": FileManager.default.currentDirectoryPath,
                "integration": integration,
            ],
            options: [.sortedKeys]
        )
    }

    public static func queryState(
        configuration: BridgeConfiguration
    ) async throws -> BridgeSelfTestState {
        do {
            let request = try BridgeRequestFactory.makeStateRequest(configuration: configuration)
            let data = try await BridgeHTTPClient().data(for: request)
            do {
                let state = try JSONDecoder().decode(BridgeSelfTestState.self, from: data)
                guard state.ok else {
                    throw BridgeSelfTestStateQueryError.invalidResponse(
                        "The local state response reported a failure."
                    )
                }
                return state
            } catch let error as BridgeSelfTestStateQueryError {
                throw error
            } catch {
                throw BridgeSelfTestStateQueryError.decode(error.localizedDescription)
            }
        } catch let error as BridgeRequestError {
            switch error {
            case .rejected(401), .rejected(403):
                throw BridgeSelfTestStateQueryError.authorization
            default:
                throw BridgeSelfTestStateQueryError.invalidResponse(error.localizedDescription)
            }
        } catch let error as URLError {
            if Task.isCancelled || error.code == .cancelled {
                throw CancellationError()
            }
            throw BridgeSelfTestStateQueryError.connection(error.localizedDescription)
        }
    }

    public static func launch(
        executableURL: URL,
        integration: String,
        input: Data,
        timeout: TimeInterval
    ) async throws {
        let controller = BridgeSelfTestProcessController()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                let process = Process()
                let stdin = Pipe()
                process.executableURL = executableURL
                process.arguments = [integration]
                process.standardInput = stdin
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    controller.started(process)
                } catch {
                    throw BridgeSelfTestProcessError.launch(error.localizedDescription)
                }

                stdin.fileHandleForWriting.write(input)
                try? stdin.fileHandleForWriting.close()

                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline && !controller.isCancelled {
                    usleep(20_000)
                }

                if controller.isCancelled {
                    controller.stop()
                    throw CancellationError()
                }
                if process.isRunning {
                    controller.stop()
                    throw BridgeSelfTestProcessError.timedOut(timeout)
                }
                guard process.terminationStatus == 0 else {
                    throw BridgeSelfTestProcessError.terminated(
                        process.terminationStatus,
                        ""
                    )
                }
            }.value
        } onCancel: {
            controller.cancel()
        }
    }

    public static func sleep(_ interval: TimeInterval) async throws {
        guard interval > 0 else {
            await Task.yield()
            return
        }
        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }

    private func validate(
        _ receipt: BridgeSelfTestReceipt,
        integration: String,
        startedAt: Date
    ) throws {
        guard receipt.integration == integration,
              receipt.source == BridgeSelfTestProtocol.source,
              receipt.event == BridgeSelfTestProtocol.event
        else {
            throw failure(
                .ingestion,
                "The correlated event did not preserve its integration, source, and event fields.",
                "Repair the bridge and integration, then run the test again."
            )
        }

        guard let timestamp = Self.parseTimestamp(receipt.timestamp),
              timestamp >= startedAt.addingTimeInterval(-1),
              timestamp <= now().addingTimeInterval(1)
        else {
            throw failure(
                .ingestion,
                "The correlated event contained a missing or stale timestamp.",
                "Confirm the Mac clock is correct, then run the test again."
            )
        }
    }

    private func mapQueryError(_ error: Error, initial: Bool) -> BridgeSelfTestFailure {
        guard let error = error as? BridgeSelfTestStateQueryError else {
            return failure(
                initial ? .connection : .stateQuery,
                error.localizedDescription,
                "Confirm Agent Pulse is open and retry the test."
            )
        }

        switch error {
        case .connection(let message):
            return failure(
                initial ? .connection : .stateQuery,
                message,
                "Confirm Agent Pulse is open and the local server is listening, then retry."
            )
        case .authorization:
            return failure(
                .authorization,
                "The local server rejected the bridge token.",
                "Repair the local bridge configuration in Setup, then retry."
            )
        case .invalidResponse(let message):
            return failure(
                .stateQuery,
                message,
                "Restart Agent Pulse and retry the test."
            )
        case .decode(let message):
            return failure(
                .decode,
                "The local state response could not be decoded: \(message)",
                "Restart Agent Pulse and ensure the bridge and app versions match."
            )
        }
    }

    private func checkCancellation() throws {
        if Task.isCancelled {
            throw cancelledFailure()
        }
    }

    private func cancelledFailure() -> BridgeSelfTestFailure {
        failure(.cancelled, "The self-test was cancelled.", "Run the test again when ready.")
    }

    private func failure(
        _ stage: BridgeSelfTestStage,
        _ message: String,
        _ recovery: String
    ) -> BridgeSelfTestFailure {
        BridgeSelfTestFailure(stage: stage, message: message, recovery: recovery)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

private final class BridgeSelfTestProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func started(_ process: Process) {
        let shouldStop = lock.withLock {
            self.process = process
            return cancelled
        }
        if shouldStop {
            stop()
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
        }
        stop()
    }

    func stop() {
        let process = lock.withLock { self.process }
        guard let process, process.isRunning else { return }
        process.terminate()
        usleep(50_000)
        if process.isRunning {
            process.interrupt()
        }
    }
}
