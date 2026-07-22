import AgentPulseBridgeSupport
import Foundation

@main
enum AgentPulseBridgeCommand {
    static func main() async {
        switch BridgeCommand.parse(Array(CommandLine.arguments.dropFirst())) {
        case .hook(let agent):
            await deliver(agent: agent)
        case .version:
            print(BridgeVersion.current())
        case .doctor(let agent):
            exit(await runDoctor(agent: agent))
        case .none:
            break
        }
    }

    private static func deliver(agent: String) async {
        var secrets: [String] = []
        do {
            let input = BridgeEventNormalizer.decodeInput(
                FileHandle.standardInput.readDataToEndOfFile()
            )
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let event = BridgeEventNormalizer.normalize(
                agent: agent,
                input: input,
                currentDirectory: FileManager.default.currentDirectoryPath,
                timestamp: formatter.string(from: Date()),
                hostBundleID: ProcessInfo.processInfo.environment["__CFBundleIdentifier"]
            )
            let configuration = try BridgeConfigurationLoader.load()
            secrets = [configuration.token]
            let request = try BridgeRequestFactory.make(
                event: event,
                configuration: configuration
            )
            try await BridgeHTTPClient().send(request)
        } catch {
            BridgeLogger().write(
                "Hook delivery failed: \(BridgeDiagnosticMessage.describe(error))",
                redacting: secrets
            )
        }
    }

    private static func runDoctor(agent requestedAgent: String?) async -> Int32 {
        print("Bridge version: \(BridgeVersion.current())")

        do {
            let configuration = try BridgeConfigurationLoader.load()
            print("Configuration: OK")

            let request = try BridgeRequestFactory.makeStateRequest(configuration: configuration)
            try await BridgeHTTPClient().send(request)
            print("Local server and authorization: OK")

            let integrations = requestedAgent.map { [$0] } ?? ["claude", "codex"]
            let runner = BridgeSelfTestRunner(
                executableURL: URL(fileURLWithPath: CommandLine.arguments[0])
            )
            for integration in integrations {
                do {
                    _ = try await runner.run(integration: integration)
                    print("Delivery self-test (\(integration)): OK")
                } catch let failure as BridgeSelfTestFailure {
                    print("Delivery self-test (\(integration)) failed at \(failure.stage.rawValue): \(failure.message)")
                    print("Recovery: \(failure.recovery)")
                    return BridgeDoctorExitCode.forSelfTestFailure(failure)
                }
            }
            return 0
        } catch {
            print("Doctor failed: \(BridgeDiagnosticMessage.describe(error))")
            return BridgeDoctorExitCode.forError(error)
        }
    }
}
