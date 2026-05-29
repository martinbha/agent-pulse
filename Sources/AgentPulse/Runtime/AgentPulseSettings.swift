import Foundation

@MainActor
final class AgentPulseSettings: ObservableObject {
    static let defaultPort: UInt16 = 37462

    @Published private(set) var port: UInt16
    @Published private(set) var token: String
    @Published private(set) var bridgeConfigPath: String

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.bridgeConfigPath = Self.bridgeConfigURL.path

        let storedPort = defaults.integer(forKey: Keys.port)
        if storedPort > 0 && storedPort <= UInt16.max {
            self.port = UInt16(storedPort)
        } else {
            self.port = Self.defaultPort
            defaults.set(Int(Self.defaultPort), forKey: Keys.port)
        }

        if let storedToken = defaults.string(forKey: Keys.token), !storedToken.isEmpty {
            self.token = storedToken
        } else {
            let generated = Self.generateToken()
            self.token = generated
            defaults.set(generated, forKey: Keys.token)
        }

        writeBridgeConfig()
    }

    func regenerateToken() {
        let generated = Self.generateToken()
        token = generated
        defaults.set(generated, forKey: Keys.token)
        writeBridgeConfig()
    }

    private static func generateToken() -> String {
        "\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    private func writeBridgeConfig() {
        let config = BridgeConfig(port: port, token: token)

        do {
            let directory = Self.bridgeConfigURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try AgentPulseJSON.encoder.encode(config)
            try data.write(to: Self.bridgeConfigURL, options: .atomic)
        } catch {
            // Hook delivery must remain best-effort; the UI still exposes token copy actions.
        }
    }

    private static var bridgeConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-pulse", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private enum Keys {
        static let port = "agentPulse.port"
        static let token = "agentPulse.token"
    }

    private struct BridgeConfig: Codable {
        var port: UInt16
        var token: String
    }
}
