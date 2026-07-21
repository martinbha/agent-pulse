import Foundation

public enum BridgeCommand: Equatable, Sendable {
    case hook(agent: String)
    case version
    case doctor
    case none

    public static func parse(_ arguments: [String]) -> BridgeCommand {
        guard let first = arguments.first, !first.isEmpty else {
            return .none
        }
        switch first {
        case "--version":
            return .version
        case "--doctor":
            return .doctor
        default:
            return first.hasPrefix("--") ? .none : .hook(agent: first)
        }
    }
}

public enum BridgeVersion {
    public static func current(
        executableURL: URL = URL(fileURLWithPath: CommandLine.arguments[0]),
        bundleVersion: String? = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
    ) -> String {
        let sidecarURL = executableURL.appendingPathExtension("version")
        let sidecarVersion = try? String(contentsOf: sidecarURL, encoding: .utf8)
        return resolved(sidecarVersion: sidecarVersion, bundleVersion: bundleVersion)
    }

    public static func resolved(sidecarVersion: String?, bundleVersion: String?) -> String {
        for candidate in [sidecarVersion, bundleVersion] {
            guard let candidate else { continue }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return "development"
    }
}
