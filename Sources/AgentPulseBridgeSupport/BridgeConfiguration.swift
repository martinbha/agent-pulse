import Foundation

public struct BridgeConfiguration: Codable, Equatable, Sendable {
    public var port: UInt16
    public var token: String
}

public enum BridgeConfigurationError: LocalizedError, Equatable {
    case unreadable(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "Bridge configuration is not readable at \(path)."
        case .invalid(let reason):
            return "Bridge configuration is invalid: \(reason)"
        }
    }
}

public enum BridgeConfigurationLoader {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-pulse", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public static func load(from url: URL = defaultURL) throws -> BridgeConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BridgeConfigurationError.unreadable(url.path)
        }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> BridgeConfiguration {
        let configuration: BridgeConfiguration
        do {
            configuration = try JSONDecoder().decode(BridgeConfiguration.self, from: data)
        } catch {
            throw BridgeConfigurationError.invalid(error.localizedDescription)
        }

        guard configuration.port > 0 else {
            throw BridgeConfigurationError.invalid("port must be greater than zero")
        }
        guard !configuration.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeConfigurationError.invalid("token must not be empty")
        }
        return configuration
    }
}
