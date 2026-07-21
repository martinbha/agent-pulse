import Foundation

public enum BridgeDiagnosticMessage {
    public static func describe(_ error: Error) -> String {
        if let configurationError = error as? BridgeConfigurationError {
            return configurationError.localizedDescription
        }
        if let requestError = error as? BridgeRequestError {
            switch requestError {
            case .rejected(401), .rejected(403):
                return "The local server rejected the bridge token. Run setup repair."
            default:
                return requestError.localizedDescription
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "The local server timed out."
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return "The local server is not reachable. Make sure Agent Pulse is running."
            default:
                return "The local request failed: \(urlError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}

public enum BridgeDoctorExitCode {
    public static let generalFailure: Int32 = 1
    public static let invalidConfiguration: Int32 = 2
    public static let serverUnavailable: Int32 = 3
    public static let authorizationFailure: Int32 = 4
    public static let invalidServerResponse: Int32 = 5

    public static func forError(_ error: Error) -> Int32 {
        if error is BridgeConfigurationError {
            return invalidConfiguration
        }
        if let requestError = error as? BridgeRequestError {
            switch requestError {
            case .rejected(401), .rejected(403):
                return authorizationFailure
            case .invalidEndpoint, .invalidResponse, .rejected:
                return invalidServerResponse
            }
        }
        if error is URLError {
            return serverUnavailable
        }
        return generalFailure
    }
}

public struct BridgeLogger: Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Agent Pulse", isDirectory: true)
            .appendingPathComponent("bridge.log")
    }

    public var fileURL: URL
    public var maximumBytes: Int

    public init(fileURL: URL = defaultURL, maximumBytes: Int = 128 * 1_024) {
        self.fileURL = fileURL
        self.maximumBytes = maximumBytes
    }

    public func write(
        _ message: String,
        redacting secrets: [String] = [],
        timestamp: Date = Date()
    ) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )

            let redacted = Self.redact(message, secrets: secrets)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let data = Data("\(formatter.string(from: timestamp)) \(redacted)\n".utf8)

            try rotateIfNeeded(adding: data.count)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Diagnostics are best-effort and must never affect hook execution.
        }
    }

    public static func redact(_ message: String, secrets: [String]) -> String {
        secrets.reduce(message) { result, secret in
            guard !secret.isEmpty else { return result }
            return result.replacingOccurrences(of: secret, with: "<redacted>")
        }
    }

    private func rotateIfNeeded(adding byteCount: Int) throws {
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?
            .intValue ?? 0
        guard currentSize + byteCount > maximumBytes else {
            return
        }

        let backupURL = fileURL.appendingPathExtension("1")
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.moveItem(at: fileURL, to: backupURL)
        }
    }
}
