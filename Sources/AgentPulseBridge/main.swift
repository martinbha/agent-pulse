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
        case .doctor:
            exit(await runDoctor())
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
            let (_, response) = try await URLSession.shared.data(for: request)
            try BridgeResponseValidator.validate(response)
        } catch {
            BridgeLogger().write(
                "Hook delivery failed: \(BridgeDiagnosticMessage.describe(error))",
                redacting: secrets
            )
        }
    }

    private static func runDoctor() async -> Int32 {
        print("Bridge version: \(BridgeVersion.current())")

        do {
            let configuration = try BridgeConfigurationLoader.load()
            print("Configuration: OK")

            let request = try BridgeRequestFactory.makeStateRequest(configuration: configuration)
            let (_, response) = try await URLSession.shared.data(for: request)
            try BridgeResponseValidator.validate(response)
            print("Local server and authorization: OK")
            return 0
        } catch {
            print("Doctor failed: \(BridgeDiagnosticMessage.describe(error))")
            return 1
        }
    }
}
