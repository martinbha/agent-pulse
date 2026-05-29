import Foundation

@MainActor
final class AgentPulseSettings: ObservableObject {
    static let defaultPort: UInt16 = 37462

    @Published private(set) var port: UInt16
    @Published private(set) var token: String

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

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
    }

    func regenerateToken() {
        let generated = Self.generateToken()
        token = generated
        defaults.set(generated, forKey: Keys.token)
    }

    private static func generateToken() -> String {
        "\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    private enum Keys {
        static let port = "agentPulse.port"
        static let token = "agentPulse.token"
    }
}

