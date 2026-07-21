import AgentPulseBridgeSupport
import Foundation

@main
enum AgentPulseBridgeCommand {
    static func main() async {
        guard let agent = CommandLine.arguments.dropFirst().first,
              !agent.isEmpty,
              !agent.hasPrefix("--")
        else {
            return
        }

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
            let request = try BridgeRequestFactory.make(
                event: event,
                configuration: configuration
            )
            let (_, response) = try await URLSession.shared.data(for: request)
            try BridgeResponseValidator.validate(response)
        } catch {
            // Hook delivery is best-effort and must never block the host command.
        }
    }
}
