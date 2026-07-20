import Foundation

enum AgentPulseVersion {
    static var current: String {
        resolved(
            bundleVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
    }

    static func resolved(bundleVersion: String?) -> String {
        guard let bundleVersion else {
            return "development"
        }

        let trimmed = bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "development" : trimmed
    }
}
