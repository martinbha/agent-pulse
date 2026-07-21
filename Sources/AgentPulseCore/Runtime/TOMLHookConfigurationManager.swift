import Darwin
import Foundation

enum TOMLHookConfigurationOperation: Equatable {
    case install
    case remove
}

enum TOMLHookConfigurationChangeKind: Equatable {
    case added
    case updated
    case removed
    case unchanged
}

struct TOMLHookConfigurationChange: Equatable {
    var kind: TOMLHookConfigurationChangeKind
    var managedBlockCount: Int
    var legacyBlockCount: Int
}

enum TOMLHookMarkerError: Error, Equatable {
    case unexpectedEnd
    case nestedBegin
    case duplicateRegion
    case unterminatedRegion
}

enum TOMLHookConfigurationBlocker: Error, Equatable {
    case readFailed(String)
    case malformedMarkers(TOMLHookMarkerError)
    case targetIsNotWritable(String)
    case directoryCreationFailed(String)
    case backupFailed(String)
    case permissionReadFailed(String)
    case permissionUpdateFailed(String)
    case replacementFailed(String)
}

struct TOMLHookConfigurationResult: Equatable {
    var configurationURL: URL
    var resolvedTargetURL: URL
    var change: TOMLHookConfigurationChange
    var didWrite: Bool
    var backupURL: URL?
    var blocker: TOMLHookConfigurationBlocker?

    var requiresWrite: Bool {
        change.kind != .unchanged
    }
}

struct TOMLHookEventSpec: Equatable {
    var name: String
    var matcher: String?

    static let supportedIntegration = [
        TOMLHookEventSpec(name: "SessionStart", matcher: "startup|resume|clear|compact"),
        TOMLHookEventSpec(name: "UserPromptSubmit", matcher: nil),
        TOMLHookEventSpec(name: "PreToolUse", matcher: "*"),
        TOMLHookEventSpec(name: "PostToolUse", matcher: "*"),
        TOMLHookEventSpec(name: "PermissionRequest", matcher: "*"),
        TOMLHookEventSpec(name: "Stop", matcher: nil),
    ]
}

struct TOMLHookConfigurationManager {
    typealias BackupCopier = (URL, URL) throws -> Void

    static let beginMarker = "# BEGIN agent-pulse"
    static let endMarker = "# END agent-pulse"

    let configurationURL: URL
    let bridgeExecutableURL: URL
    let agentArgument: String

    private let homeDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let backupCopier: BackupCopier

    init(
        configurationURL: URL,
        bridgeExecutableURL: URL,
        agentArgument: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        backupCopier: BackupCopier? = nil
    ) {
        self.configurationURL = configurationURL
        self.bridgeExecutableURL = bridgeExecutableURL
        self.agentArgument = agentArgument
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.backupCopier = backupCopier ?? { source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func preview(_ operation: TOMLHookConfigurationOperation) -> TOMLHookConfigurationResult {
        reconcile(operation, shouldWrite: false)
    }

    func apply(_ operation: TOMLHookConfigurationOperation) -> TOMLHookConfigurationResult {
        reconcile(operation, shouldWrite: true)
    }

    private func reconcile(
        _ operation: TOMLHookConfigurationOperation,
        shouldWrite: Bool
    ) -> TOMLHookConfigurationResult {
        let targetURL = configurationURL.resolvingSymlinksInPath()
        var result = TOMLHookConfigurationResult(
            configurationURL: configurationURL,
            resolvedTargetURL: targetURL,
            change: TOMLHookConfigurationChange(
                kind: .unchanged,
                managedBlockCount: 0,
                legacyBlockCount: 0
            ),
            didWrite: false,
            backupURL: nil,
            blocker: nil
        )

        let loaded: LoadedConfiguration
        switch loadConfiguration(at: targetURL) {
        case .success(let value):
            loaded = value
        case .failure(let blocker):
            result.blocker = blocker
            return result
        }

        let mutation: Mutation
        switch mutate(loaded.data, operation: operation) {
        case .success(let value):
            mutation = value
        case .failure(let blocker):
            result.blocker = blocker
            return result
        }

        result.change = mutation.change
        guard result.requiresWrite, shouldWrite else {
            return result
        }

        if loaded.exists, !fileManager.isWritableFile(atPath: targetURL.path) {
            result.blocker = .targetIsNotWritable(targetURL.path)
            return result
        }

        let directory = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                result.blocker = .directoryCreationFailed(directory.path)
                return result
            }
        }

        if loaded.exists {
            let backupURL = makeBackupURL(for: targetURL)
            do {
                try backupCopier(targetURL, backupURL)
                result.backupURL = backupURL
            } catch {
                result.blocker = .backupFailed(backupURL.path)
                return result
            }
        }

        switch replaceTarget(
            at: targetURL,
            with: mutation.data,
            permissions: loaded.permissions ?? 0o600
        ) {
        case .success:
            result.didWrite = true
        case .failure(let blocker):
            result.blocker = blocker
        }
        return result
    }

    private func loadConfiguration(
        at targetURL: URL
    ) -> Result<LoadedConfiguration, TOMLHookConfigurationBlocker> {
        let exists = fileManager.fileExists(atPath: targetURL.path)
        guard exists else {
            return .success(LoadedConfiguration(data: Data(), exists: false, permissions: nil))
        }

        let data: Data
        do {
            data = try Data(contentsOf: targetURL)
        } catch {
            return .failure(.readFailed(targetURL.path))
        }

        guard let permissions = filePermissions(at: targetURL) else {
            return .failure(.permissionReadFailed(targetURL.path))
        }
        return .success(LoadedConfiguration(data: data, exists: true, permissions: permissions))
    }

    private func mutate(
        _ originalData: Data,
        operation: TOMLHookConfigurationOperation
    ) -> Result<Mutation, TOMLHookConfigurationBlocker> {
        let bytes = Array(originalData)
        let markerRegion: MarkerRegion?
        switch findMarkerRegion(in: bytes) {
        case .success(let value):
            markerRegion = value
        case .failure(let error):
            return .failure(.malformedMarkers(error))
        }

        let legacyRegions = findLegacyRegions(in: bytes, excluding: markerRegion?.range)
        let newline = preferredNewline(in: bytes)
        let desired = Array(managedBlock(newline: newline).utf8)
        var replacements: [Replacement] = []

        switch operation {
        case .install:
            if let markerRegion {
                replacements.append(
                    Replacement(
                        range: markerRegion.range,
                        bytes: markerRegion.leading + desired + markerRegion.trailing
                    )
                )
                replacements.append(contentsOf: legacyRegions.map {
                    Replacement(range: $0, bytes: [])
                })
            } else if let firstLegacy = legacyRegions.first {
                replacements.append(
                    Replacement(
                        range: firstLegacy,
                        bytes: desired + terminalBytes(atEndOf: firstLegacy, in: bytes)
                    )
                )
                replacements.append(contentsOf: legacyRegions.dropFirst().map {
                    Replacement(range: $0, bytes: [])
                })
            } else {
                var appended = bytes
                if !appended.isEmpty {
                    appended += newline
                }
                appended += desired
                return .success(
                    Mutation(
                        data: Data(appended),
                        change: TOMLHookConfigurationChange(
                            kind: .added,
                            managedBlockCount: 0,
                            legacyBlockCount: 0
                        )
                    )
                )
            }

        case .remove:
            if let markerRegion {
                replacements.append(Replacement(range: markerRegion.range, bytes: []))
            }
            replacements.append(contentsOf: legacyRegions.map {
                Replacement(range: $0, bytes: [])
            })
        }

        let updated = applying(replacements, to: bytes)
        let kind: TOMLHookConfigurationChangeKind
        if updated == bytes {
            kind = .unchanged
        } else {
            switch operation {
            case .install:
                kind = markerRegion == nil && legacyRegions.isEmpty ? .added : .updated
            case .remove:
                kind = .removed
            }
        }

        return .success(
            Mutation(
                data: Data(updated),
                change: TOMLHookConfigurationChange(
                    kind: kind,
                    managedBlockCount: markerRegion == nil ? 0 : 1,
                    legacyBlockCount: legacyRegions.count
                )
            )
        )
    }

    private func findMarkerRegion(
        in bytes: [UInt8]
    ) -> Result<MarkerRegion?, TOMLHookMarkerError> {
        let begin = Array(Self.beginMarker.utf8)
        let end = Array(Self.endMarker.utf8)
        var openStart: Int?
        var completed: MarkerRegion?

        for line in lines(in: bytes) {
            let content = trimmedLine(Array(bytes[line.content]))
            if content == begin {
                if openStart != nil {
                    return .failure(.nestedBegin)
                }
                if completed != nil {
                    return .failure(.duplicateRegion)
                }
                openStart = line.full.lowerBound
            } else if content == end {
                guard let start = openStart else {
                    return .failure(.unexpectedEnd)
                }
                if completed != nil {
                    return .failure(.duplicateRegion)
                }
                let leading = precedingTerminal(before: start, in: bytes)
                completed = MarkerRegion(
                    range: leading.range.lowerBound..<line.full.upperBound,
                    leading: leading.bytes,
                    trailing: Array(bytes[line.terminal])
                )
                openStart = nil
            }
        }

        if openStart != nil {
            return .failure(.unterminatedRegion)
        }
        return .success(completed)
    }

    private func lines(in bytes: [UInt8]) -> [Line] {
        var result: [Line] = []
        var index = 0

        while index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
                index += 1
            }
            let contentEnd = index
            if index < bytes.count {
                if bytes[index] == 0x0D, index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    index += 2
                } else {
                    index += 1
                }
            }
            result.append(
                Line(
                    content: start..<contentEnd,
                    terminal: contentEnd..<index,
                    full: start..<index
                )
            )
        }
        return result
    }

    private func trimmedLine(_ bytes: [UInt8]) -> [UInt8] {
        var lower = 0
        var upper = bytes.count
        while lower < upper, bytes[lower] == 0x20 || bytes[lower] == 0x09 {
            lower += 1
        }
        while upper > lower, bytes[upper - 1] == 0x20 || bytes[upper - 1] == 0x09 {
            upper -= 1
        }
        return Array(bytes[lower..<upper])
    }

    private func findLegacyRegions(
        in bytes: [UInt8],
        excluding excludedRange: Range<Int>?
    ) -> [Range<Int>] {
        let candidates = legacyBlocks()
            .map { Array($0.utf8) }
            .sorted { $0.count > $1.count }
        var regions: [Range<Int>] = []

        for candidate in candidates where !candidate.isEmpty && candidate.count <= bytes.count {
            var index = 0
            while index + candidate.count <= bytes.count {
                let end = index + candidate.count
                let range = index..<end
                let startsAtLineBoundary = index == 0 || bytes[index - 1] == 0x0A || bytes[index - 1] == 0x0D
                let endsAtLineBoundary = end == bytes.count || bytes[end] == 0x0A || bytes[end] == 0x0D
                let overlapsExcluded = excludedRange.map { $0.overlaps(range) } ?? false
                let overlapsKnown = regions.contains { $0.overlaps(range) }

                if startsAtLineBoundary,
                   endsAtLineBoundary,
                   !overlapsExcluded,
                   !overlapsKnown,
                   Array(bytes[range]) == candidate {
                    var ownedEnd = end
                    if ownedEnd < bytes.count, bytes[ownedEnd] == 0x0D {
                        ownedEnd += 1
                        if ownedEnd < bytes.count, bytes[ownedEnd] == 0x0A {
                            ownedEnd += 1
                        }
                    } else if ownedEnd < bytes.count, bytes[ownedEnd] == 0x0A {
                        ownedEnd += 1
                    }
                    regions.append(index..<ownedEnd)
                    index = ownedEnd
                } else {
                    index += 1
                }
            }
        }
        return regions.sorted { $0.lowerBound < $1.lowerBound }
    }

    private func legacyBlocks() -> [String] {
        let currentAbsolute = bridgeExecutableURL.standardizedFileURL.path
        let legacyAbsolute = homeDirectory
            .appendingPathComponent(".agent-pulse/agent-pulse-hook")
            .standardizedFileURL.path
        let executableForms = [
            "$HOME/.agent-pulse/bin/agent-pulse-hook",
            "${HOME}/.agent-pulse/bin/agent-pulse-hook",
            "~/.agent-pulse/bin/agent-pulse-hook",
            "$HOME/.agent-pulse/agent-pulse-hook",
            "${HOME}/.agent-pulse/agent-pulse-hook",
            "~/.agent-pulse/agent-pulse-hook",
            currentAbsolute,
            legacyAbsolute,
        ]
        let historicalEvents = TOMLHookEventSpec.supportedIntegration + [
            TOMLHookEventSpec(name: "StopFailure", matcher: nil),
            TOMLHookEventSpec(name: "SubagentStop", matcher: nil),
        ]
        var blocks: [String] = []

        for newline in ["\n", "\r\n"] {
            for executable in executableForms {
                blocks.append(
                    hookTables(
                        eventSpecs: historicalEvents,
                        command: "\(executable) \(agentArgument)",
                        newline: newline
                    )
                )
                blocks.append(
                    hookTables(
                        eventSpecs: TOMLHookEventSpec.supportedIntegration,
                        command: "\(executable) \(agentArgument)",
                        newline: newline
                    )
                )
            }
        }
        return blocks
    }

    private func managedBlock(newline: [UInt8]) -> String {
        let separator = String(decoding: newline, as: UTF8.self)
        let command = "\(shellQuoted(bridgeExecutableURL.standardizedFileURL.path)) \(agentArgument)"
        return [
            Self.beginMarker,
            hookTables(
                eventSpecs: TOMLHookEventSpec.supportedIntegration,
                command: command,
                newline: separator
            ),
            Self.endMarker,
        ].joined(separator: separator)
    }

    private func hookTables(
        eventSpecs: [TOMLHookEventSpec],
        command: String,
        newline: String
    ) -> String {
        eventSpecs.map { spec in
            var lines = ["[[hooks.\(spec.name)]]"]
            if let matcher = spec.matcher {
                lines.append("matcher = \"\(tomlEscaped(matcher))\"")
            }
            lines += [
                "[[hooks.\(spec.name).hooks]]",
                "type = \"command\"",
                "command = \"\(tomlEscaped(command))\"",
                "timeout = 2",
                "statusMessage = \"Updating Agent Pulse\"",
            ]
            return lines.joined(separator: newline)
        }.joined(separator: newline + newline)
    }

    private func tomlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func preferredNewline(in bytes: [UInt8]) -> [UInt8] {
        for index in bytes.indices {
            if bytes[index] == 0x0D {
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    return [0x0D, 0x0A]
                }
                return [0x0D]
            }
            if bytes[index] == 0x0A {
                return [0x0A]
            }
        }
        return [0x0A]
    }

    private func precedingTerminal(
        before index: Int,
        in bytes: [UInt8]
    ) -> (range: Range<Int>, bytes: [UInt8]) {
        if index >= 2, bytes[index - 2] == 0x0D, bytes[index - 1] == 0x0A {
            return (index - 2..<index, [0x0D, 0x0A])
        }
        if index >= 1, bytes[index - 1] == 0x0A || bytes[index - 1] == 0x0D {
            return (index - 1..<index, [bytes[index - 1]])
        }
        return (index..<index, [])
    }

    private func terminalBytes(atEndOf range: Range<Int>, in bytes: [UInt8]) -> [UInt8] {
        guard range.upperBound > range.lowerBound else { return [] }
        if range.upperBound >= 2,
           bytes[range.upperBound - 2] == 0x0D,
           bytes[range.upperBound - 1] == 0x0A {
            return [0x0D, 0x0A]
        }
        let last = bytes[range.upperBound - 1]
        return last == 0x0A || last == 0x0D ? [last] : []
    }

    private func applying(_ replacements: [Replacement], to bytes: [UInt8]) -> [UInt8] {
        guard !replacements.isEmpty else { return bytes }
        let ordered = replacements.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var result: [UInt8] = []
        var cursor = 0

        for replacement in ordered {
            guard replacement.range.lowerBound >= cursor else { continue }
            result += bytes[cursor..<replacement.range.lowerBound]
            result += replacement.bytes
            cursor = replacement.range.upperBound
        }
        result += bytes[cursor..<bytes.count]
        return result
    }

    private func replaceTarget(
        at targetURL: URL,
        with data: Data,
        permissions: Int
    ) -> Result<Void, TOMLHookConfigurationBlocker> {
        let temporary = targetURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(targetURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }

        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            return .failure(.replacementFailed(targetURL.path))
        }

        do {
            try fileManager.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: temporary.path
            )
        } catch {
            return .failure(.permissionUpdateFailed(targetURL.path))
        }

        let renameResult = temporary.path.withCString { temporaryPath in
            targetURL.path.withCString { targetPath in
                Darwin.rename(temporaryPath, targetPath)
            }
        }
        guard renameResult == 0 else {
            return .failure(.replacementFailed(targetURL.path))
        }
        return .success(())
    }

    private func makeBackupURL(for targetURL: URL) -> URL {
        let milliseconds = Int(now().timeIntervalSince1970 * 1_000)
        return targetURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(targetURL.lastPathComponent).agent-pulse-backup-\(milliseconds)-\(UUID().uuidString)"
            )
    }

    private func filePermissions(at url: URL) -> Int? {
        guard let value = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
            as? NSNumber else {
            return nil
        }
        return value.intValue & 0o777
    }

    private struct LoadedConfiguration {
        var data: Data
        var exists: Bool
        var permissions: Int?
    }

    private struct Mutation {
        var data: Data
        var change: TOMLHookConfigurationChange
    }

    private struct Line {
        var content: Range<Int>
        var terminal: Range<Int>
        var full: Range<Int>
    }

    private struct MarkerRegion {
        var range: Range<Int>
        var leading: [UInt8]
        var trailing: [UInt8]
    }

    private struct Replacement {
        var range: Range<Int>
        var bytes: [UInt8]
    }
}
