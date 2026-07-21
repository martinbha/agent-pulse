import Foundation

@testable import AgentPulseBridgeSupport

struct BridgeLogSnapshot: Equatable {
    var current: String
    var backup: String
    var permissions: Int
    var directoryPermissions: Int
}

enum BridgeDiagnosticsFixtures {
    static func loggingSnapshot() throws -> BridgeLogSnapshot {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("bridge.log")
        let logger = BridgeLogger(fileURL: fileURL, maximumBytes: 90)
        logger.write(
            "request token=secret-token failed with a deliberately long first message",
            redacting: ["secret-token"],
            timestamp: Date(timeIntervalSince1970: 0)
        )
        logger.write(
            "second failure causes rotation",
            timestamp: Date(timeIntervalSince1970: 1)
        )

        let current = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let backup = (try? String(contentsOf: fileURL.appendingPathExtension("1"), encoding: .utf8)) ?? ""
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let directoryPermissions = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        return BridgeLogSnapshot(
            current: current,
            backup: backup,
            permissions: permissions,
            directoryPermissions: directoryPermissions
        )
    }

    static func diagnosticMessage(for code: URLError.Code) -> String {
        BridgeDiagnosticMessage.describe(URLError(code))
    }
}
