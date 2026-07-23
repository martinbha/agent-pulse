import AppKit
import Foundation

struct CodexHookTrustInspector {
    static let expectedEventNames: Set<String> = [
        "sessionStart",
        "userPromptSubmit",
        "preToolUse",
        "postToolUse",
        "permissionRequest",
        "stop",
    ]

    private static let responseTimeout: Duration = .seconds(4)

    let executableURL: URL
    let workingDirectory: URL
    let bridgeExecutableURL: URL

    func inspect() async -> HookTrustHealth {
        do {
            return try await query()
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func query() async throws -> HookTrustHealth {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let terminator = HookTrustProcessTerminator(process: process)

        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "untrusted", "app-server", "--stdio"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessRunner.environment()

        try process.run()
        defer {
            try? stdin.fileHandleForWriting.close()
            terminator.terminate()
        }

        let lines = stdout.fileHandleForReading.bytes.lines

        try writeJSONLine([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "agent-pulse",
                    "version": AgentPulseVersion.current,
                ],
                "capabilities": [:],
            ],
        ], to: stdin.fileHandleForWriting)

        _ = try await readJSONRPCResponse(
            withID: 1,
            from: lines,
            timeout: Self.responseTimeout,
            onTimeout: { terminator.terminate() }
        )

        try writeJSONLine([
            "method": "initialized",
            "params": [:],
        ], to: stdin.fileHandleForWriting)

        try writeJSONLine([
            "id": 2,
            "method": "hooks/list",
            "params": [
                "cwds": [workingDirectory.path],
            ],
        ], to: stdin.fileHandleForWriting)

        let payload = try await readJSONRPCResponse(
            withID: 2,
            from: lines,
            timeout: Self.responseTimeout,
            onTimeout: { terminator.terminate() }
        )
        return Self.classify(
            payload: payload,
            bridgeExecutableURL: bridgeExecutableURL,
            agentArgument: AgentKind.codex.rawValue
        )
    }

    static func classify(
        payload: [String: Any],
        bridgeExecutableURL: URL,
        agentArgument: String
    ) -> HookTrustHealth {
        guard
            let result = payload["result"] as? [String: Any],
            let entries = result["data"] as? [[String: Any]]
        else {
            return .unavailable("The hook status response did not contain result.data.")
        }

        let errors = entries
            .flatMap { $0["errors"] as? [[String: Any]] ?? [] }
            .compactMap { $0["message"] as? String }
        if !errors.isEmpty {
            return .unavailable(errors.joined(separator: " "))
        }

        let expectedCommand = "\(shellQuoted(bridgeExecutableURL.standardizedFileURL.path)) \(agentArgument)"
        let hooks = entries
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .filter { hook in
                guard
                    hook["handlerType"] as? String == "command",
                    hook["command"] as? String == expectedCommand,
                    let eventName = hook["eventName"] as? String
                else {
                    return false
                }
                return expectedEventNames.contains(eventName)
            }

        let expectedCount = expectedEventNames.count
        guard hooks.count == expectedCount else {
            return .missing(found: hooks.count, expected: expectedCount)
        }

        let disabledCount = hooks.filter { ($0["enabled"] as? Bool) != true }.count
        if disabledCount > 0 {
            return .disabled(disabled: disabledCount, total: hooks.count)
        }

        var trustedCount = 0
        var managedCount = 0
        var untrustedCount = 0
        var modifiedCount = 0
        for hook in hooks {
            switch hook["trustStatus"] as? String {
            case "trusted": trustedCount += 1
            case "managed": managedCount += 1
            case "untrusted": untrustedCount += 1
            case "modified": modifiedCount += 1
            default:
                return .unavailable("The hook status response contained an unknown trust state.")
            }
        }

        if untrustedCount > 0 || modifiedCount > 0 {
            return .needsReview(
                untrusted: untrustedCount,
                modified: modifiedCount,
                total: hooks.count
            )
        }
        return .verified(
            trusted: trustedCount,
            managed: managedCount,
            total: hooks.count
        )
    }

    @MainActor
    static func live(
        workingDirectory: URL,
        bridgeExecutableURL: URL,
        fileManager: FileManager = .default
    ) -> CodexHookTrustInspector? {
        for bundleID in AgentAppLauncher.bundleIDCandidates(for: .codex) {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
            ) else {
                continue
            }
            for relativePath in ["Contents/Resources/codex", "Contents/MacOS/codex"] {
                let executableURL = applicationURL.appendingPathComponent(relativePath)
                if fileManager.isExecutableFile(atPath: executableURL.path) {
                    return CodexHookTrustInspector(
                        executableURL: executableURL,
                        workingDirectory: workingDirectory,
                        bridgeExecutableURL: bridgeExecutableURL
                    )
                }
            }
        }

        guard let executable = ProcessRunner.which("codex") else {
            return nil
        }
        return CodexHookTrustInspector(
            executableURL: URL(fileURLWithPath: executable),
            workingDirectory: workingDirectory,
            bridgeExecutableURL: bridgeExecutableURL
        )
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private final class HookTrustProcessTerminator: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(process: Process) {
        self.process = process
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard process.isRunning else { return }
        process.terminate()
    }
}
