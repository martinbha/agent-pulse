import Darwin
import Foundation

enum JSONHookConfigurationOperation: Equatable {
    case install
    case remove
}

enum JSONHookConfigurationChangeKind: Equatable {
    case added
    case updated
    case removed
    case unchanged
}

struct JSONHookConfigurationChange: Equatable {
    var event: String
    var kind: JSONHookConfigurationChangeKind
    var ownedEntryCount: Int
}

enum JSONHookConfigurationBlocker: Error, Equatable {
    case readFailed(String)
    case invalidJSON
    case rootIsNotObject
    case unsupportedHookStructure(String)
    case targetIsNotWritable(String)
    case directoryCreationFailed(String)
    case backupFailed(String)
    case serializationFailed
    case permissionReadFailed(String)
    case permissionUpdateFailed(String)
    case replacementFailed(String)
}

struct JSONHookConfigurationResult: Equatable {
    var configurationURL: URL
    var resolvedTargetURL: URL
    var changes: [JSONHookConfigurationChange]
    var didWrite: Bool
    var backupURL: URL?
    var blocker: JSONHookConfigurationBlocker?

    var requiresWrite: Bool {
        changes.contains { $0.kind != .unchanged }
    }
}

struct JSONHookEventSpec: Equatable {
    var name: String
    var matcher: String?

    static let defaultIntegration = [
        JSONHookEventSpec(name: "SessionStart", matcher: nil),
        JSONHookEventSpec(name: "UserPromptSubmit", matcher: nil),
        JSONHookEventSpec(name: "PreToolUse", matcher: "*"),
        JSONHookEventSpec(name: "PostToolUse", matcher: "*"),
        JSONHookEventSpec(name: "PermissionRequest", matcher: "*"),
        JSONHookEventSpec(name: "Notification", matcher: nil),
        JSONHookEventSpec(name: "Stop", matcher: nil),
        JSONHookEventSpec(name: "StopFailure", matcher: nil),
        JSONHookEventSpec(name: "SubagentStop", matcher: nil),
        JSONHookEventSpec(name: "SessionEnd", matcher: nil),
    ]
}

struct JSONHookConfigurationManager {
    typealias BackupCopier = (URL, URL) throws -> Void

    let configurationURL: URL
    let bridgeExecutableURL: URL
    let agentArgument: String
    let eventSpecs: [JSONHookEventSpec]

    private let homeDirectory: URL
    private let fileManager: FileManager
    private let now: () -> Date
    private let backupCopier: BackupCopier

    init(
        configurationURL: URL,
        bridgeExecutableURL: URL,
        agentArgument: String,
        eventSpecs: [JSONHookEventSpec] = JSONHookEventSpec.defaultIntegration,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init,
        backupCopier: BackupCopier? = nil
    ) {
        self.configurationURL = configurationURL
        self.bridgeExecutableURL = bridgeExecutableURL
        self.agentArgument = agentArgument
        self.eventSpecs = eventSpecs
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
        self.now = now
        self.backupCopier = backupCopier ?? { source, destination in
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    func preview(_ operation: JSONHookConfigurationOperation) -> JSONHookConfigurationResult {
        reconcile(operation, shouldWrite: false)
    }

    func apply(_ operation: JSONHookConfigurationOperation) -> JSONHookConfigurationResult {
        reconcile(operation, shouldWrite: true)
    }

    private func reconcile(
        _ operation: JSONHookConfigurationOperation,
        shouldWrite: Bool
    ) -> JSONHookConfigurationResult {
        let targetURL = configurationURL.resolvingSymlinksInPath()
        let baseResult = JSONHookConfigurationResult(
            configurationURL: configurationURL,
            resolvedTargetURL: targetURL,
            changes: [],
            didWrite: false,
            backupURL: nil,
            blocker: nil
        )

        let loaded: LoadedConfiguration
        switch loadConfiguration(at: targetURL) {
        case .success(let value):
            loaded = value
        case .failure(let blocker):
            return blocked(baseResult, by: blocker)
        }

        let mutation: Mutation
        switch mutate(loaded.root, operation: operation) {
        case .success(let value):
            mutation = value
        case .failure(let blocker):
            return blocked(baseResult, by: blocker)
        }

        var result = baseResult
        result.changes = mutation.changes
        guard result.requiresWrite, shouldWrite else {
            return result
        }

        if loaded.exists, !fileManager.isWritableFile(atPath: targetURL.path) {
            return blocked(result, by: .targetIsNotWritable(targetURL.path))
        }

        let directory = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return blocked(result, by: .directoryCreationFailed(directory.path))
            }
        }

        if loaded.exists {
            let backupURL = makeBackupURL(for: targetURL)
            do {
                try backupCopier(targetURL, backupURL)
                result.backupURL = backupURL
            } catch {
                return blocked(result, by: .backupFailed(backupURL.path))
            }
        }

        let data: Data
        do {
            data = try serializedData(for: mutation.root)
        } catch {
            return blocked(result, by: .serializationFailed)
        }

        switch replaceTarget(
            at: targetURL,
            with: data,
            permissions: loaded.permissions ?? 0o600
        ) {
        case .success:
            result.didWrite = true
            return result
        case .failure(let blocker):
            return blocked(result, by: blocker)
        }
    }

    private func loadConfiguration(
        at targetURL: URL
    ) -> Result<LoadedConfiguration, JSONHookConfigurationBlocker> {
        let exists = fileManager.fileExists(atPath: targetURL.path)
        guard exists else {
            return .success(LoadedConfiguration(root: [:], exists: false, permissions: nil))
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
        guard !data.isEmpty else {
            return .success(LoadedConfiguration(root: [:], exists: true, permissions: permissions))
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .failure(.invalidJSON)
        }

        guard let root = object as? [String: Any] else {
            return .failure(.rootIsNotObject)
        }
        return .success(LoadedConfiguration(root: root, exists: true, permissions: permissions))
    }

    private func mutate(
        _ originalRoot: [String: Any],
        operation: JSONHookConfigurationOperation
    ) -> Result<Mutation, JSONHookConfigurationBlocker> {
        var root = originalRoot
        var hooks: [String: Any]

        if let existingHooks = root["hooks"] {
            guard let object = existingHooks as? [String: Any] else {
                return .failure(.unsupportedHookStructure("hooks"))
            }
            hooks = object
        } else {
            hooks = [:]
        }

        let requiredByName = Dictionary(uniqueKeysWithValues: eventSpecs.map { ($0.name, $0) })
        var changes: [JSONHookConfigurationChange] = []

        for event in hooks.keys.sorted() where requiredByName[event] == nil {
            guard let groups = hooks[event] as? [Any] else { continue }
            let cleaned = cleanOwnedEntries(from: groups)
            guard cleaned.ownedEntryCount > 0 else { continue }

            if cleaned.groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = cleaned.groups
            }
            changes.append(
                JSONHookConfigurationChange(
                    event: event,
                    kind: .removed,
                    ownedEntryCount: cleaned.ownedEntryCount
                )
            )
        }

        for spec in eventSpecs {
            let desired = desiredGroup(for: spec)
            let existingValue = hooks[spec.name]
            let groups: [Any]
            if let existingValue {
                guard let existingGroups = existingValue as? [Any] else {
                    return .failure(.unsupportedHookStructure("hooks.\(spec.name)"))
                }
                groups = existingGroups
            } else {
                groups = []
            }

            let cleaned = cleanOwnedEntries(from: groups)
            if operation == .install, cleaned.containsUnsupportedGroupShape {
                return .failure(.unsupportedHookStructure("hooks.\(spec.name)"))
            }

            switch operation {
            case .install:
                if cleaned.ownedEntryCount == 1,
                   let exactIndex = cleaned.exactDesiredGroupIndex,
                   dictionariesEqual(groups[exactIndex] as? [String: Any], desired) {
                    changes.append(
                        JSONHookConfigurationChange(
                            event: spec.name,
                            kind: .unchanged,
                            ownedEntryCount: 1
                        )
                    )
                    continue
                }

                var updatedGroups = cleaned.groups
                updatedGroups.append(desired)
                hooks[spec.name] = updatedGroups
                changes.append(
                    JSONHookConfigurationChange(
                        event: spec.name,
                        kind: cleaned.ownedEntryCount == 0 ? .added : .updated,
                        ownedEntryCount: cleaned.ownedEntryCount
                    )
                )

            case .remove:
                guard cleaned.ownedEntryCount > 0 else { continue }
                if cleaned.groups.isEmpty {
                    hooks.removeValue(forKey: spec.name)
                } else {
                    hooks[spec.name] = cleaned.groups
                }
                changes.append(
                    JSONHookConfigurationChange(
                        event: spec.name,
                        kind: .removed,
                        ownedEntryCount: cleaned.ownedEntryCount
                    )
                )
            }
        }

        if operation == .remove, changes.isEmpty {
            changes.append(
                JSONHookConfigurationChange(event: "hooks", kind: .unchanged, ownedEntryCount: 0)
            )
        }

        if hooks.isEmpty {
            if root["hooks"] != nil, !changes.allSatisfy({ $0.kind == .unchanged }) {
                root.removeValue(forKey: "hooks")
            }
        } else {
            root["hooks"] = hooks
        }

        return .success(Mutation(root: root, changes: changes))
    }

    private func cleanOwnedEntries(from groups: [Any]) -> CleanedGroups {
        var cleanedGroups: [Any] = []
        var ownedEntryCount = 0
        var exactDesiredGroupIndex: Int?
        var containsUnsupportedGroupShape = false

        for (index, value) in groups.enumerated() {
            guard var group = value as? [String: Any] else {
                cleanedGroups.append(value)
                containsUnsupportedGroupShape = true
                continue
            }
            guard let hookValue = group["hooks"] else {
                cleanedGroups.append(group)
                continue
            }
            guard let handlers = hookValue as? [Any] else {
                cleanedGroups.append(group)
                containsUnsupportedGroupShape = true
                continue
            }

            var remainingHandlers: [Any] = []
            var ownedInGroup = 0
            for handlerValue in handlers {
                if let handler = handlerValue as? [String: Any], isOwned(handler: handler) {
                    ownedEntryCount += 1
                    ownedInGroup += 1
                } else {
                    remainingHandlers.append(handlerValue)
                }
            }

            if ownedInGroup == 1,
               ownedEntryCount == 1,
               remainingHandlers.isEmpty {
                exactDesiredGroupIndex = index
            } else if ownedInGroup > 0 {
                exactDesiredGroupIndex = nil
            }

            if ownedInGroup == 0 {
                cleanedGroups.append(group)
            } else if remainingHandlers.isEmpty,
                      Set(group.keys).isSubset(of: Set(["hooks", "matcher"])) {
                continue
            } else {
                group["hooks"] = remainingHandlers
                cleanedGroups.append(group)
            }
        }

        return CleanedGroups(
            groups: cleanedGroups,
            ownedEntryCount: ownedEntryCount,
            exactDesiredGroupIndex: exactDesiredGroupIndex,
            containsUnsupportedGroupShape: containsUnsupportedGroupShape
        )
    }

    private func desiredGroup(for spec: JSONHookEventSpec) -> [String: Any] {
        var group: [String: Any] = [
            "hooks": [[
                "type": "command",
                "command": "\(shellQuoted(bridgeExecutableURL.standardizedFileURL.path)) \(agentArgument)",
                "timeout": 2,
            ]],
        ]
        if let matcher = spec.matcher {
            group["matcher"] = matcher
        }
        return group
    }

    private func isOwned(handler: [String: Any]) -> Bool {
        guard let command = handler["command"] as? String,
              let executable = executablePath(from: command) else {
            return false
        }

        let current = bridgeExecutableURL.standardizedFileURL.path
        let legacy = homeDirectory
            .appendingPathComponent(".agent-pulse/agent-pulse-hook")
            .standardizedFileURL.path
        return executable == current || executable == legacy
    }

    private func executablePath(from command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.lastIndex(where: { $0.isWhitespace }) else {
            return nil
        }

        let argument = trimmed[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard argument == agentArgument else {
            return nil
        }

        var executable = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        if executable.count >= 2,
           let first = executable.first,
           first == executable.last,
           (first == "\"" || first == "'") {
            executable.removeFirst()
            executable.removeLast()
            if first == "'" {
                executable = executable.replacingOccurrences(of: "'\\''", with: "'")
            }
        } else if executable.contains(where: { $0.isWhitespace }) {
            return nil
        }

        let home = homeDirectory.standardizedFileURL.path
        if executable == "$HOME" || executable == "${HOME}" || executable == "~" {
            executable = home
        } else if executable.hasPrefix("$HOME/") {
            executable = home + executable.dropFirst("$HOME".count)
        } else if executable.hasPrefix("${HOME}/") {
            executable = home + executable.dropFirst("${HOME}".count)
        } else if executable.hasPrefix("~/") {
            executable = home + executable.dropFirst(1)
        }

        return URL(fileURLWithPath: executable).standardizedFileURL.path
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func dictionariesEqual(_ lhs: [String: Any]?, _ rhs: [String: Any]) -> Bool {
        guard let lhs else { return false }
        return NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }

    private func serializedData(for root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        data.append(0x0A)
        return data
    }

    private func replaceTarget(
        at targetURL: URL,
        with data: Data,
        permissions: Int
    ) -> Result<Void, JSONHookConfigurationBlocker> {
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

    private func blocked(
        _ result: JSONHookConfigurationResult,
        by blocker: JSONHookConfigurationBlocker
    ) -> JSONHookConfigurationResult {
        var blocked = result
        blocked.blocker = blocker
        return blocked
    }

    private struct LoadedConfiguration {
        var root: [String: Any]
        var exists: Bool
        var permissions: Int?
    }

    private struct Mutation {
        var root: [String: Any]
        var changes: [JSONHookConfigurationChange]
    }

    private struct CleanedGroups {
        var groups: [Any]
        var ownedEntryCount: Int
        var exactDesiredGroupIndex: Int?
        var containsUnsupportedGroupShape: Bool
    }
}
