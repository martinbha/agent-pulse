import Foundation

@testable import AgentPulseCore

struct JSONHookLifecycleSnapshot {
    var previewRequiresWrite: Bool
    var previewDidWrite: Bool
    var previewKeptFileUnchanged: Bool
    var firstDidWrite: Bool
    var firstBackupRestoresOriginal: Bool
    var secondDidWrite: Bool
    var secondBackupCreated: Bool
    var secondKeptFileUnchanged: Bool
    var unknownSettingsPreserved: Bool
    var unrelatedHooksPreserved: Bool
    var installedEventCount: Int
    var installedOwnedEntryCount: Int
    var permissions: Int
    var removalDidWrite: Bool
    var repeatedRemovalDidWrite: Bool
    var ownedEntriesAfterRemoval: Int
}

struct JSONHookMigrationSnapshot {
    var didWrite: Bool
    var change: JSONHookConfigurationChange?
    var ownedEntryCount: Int
    var legacyEntryCount: Int
    var unrelatedEntryCount: Int
}

struct JSONHookSymlinkSnapshot {
    var didWrite: Bool
    var symlinkDestination: String?
    var resolvedTargetMatches: Bool
    var targetContainsHooks: Bool
    var targetPermissions: Int
    var backupRestoresOriginal: Bool
}

struct JSONHookBlockedSnapshot {
    var blocker: JSONHookConfigurationBlocker?
    var contentsUnchanged: Bool
    var backupCreated: Bool
    var didWrite: Bool
}

struct JSONHookMissingSnapshot {
    var didWrite: Bool
    var backupCreated: Bool
    var permissions: Int
    var repeatedDidWrite: Bool
}

enum JSONHookConfigurationFixtures {
    private static let agentArgument = "worker"

    static func installAndRemovalLifecycle() throws -> JSONHookLifecycleSnapshot {
        try withLayout(homeName: "owner's home") { layout in
            let originalObject: [String: Any] = [
                "theme": "dark",
                "nested": ["kept": true, "number": 7],
                "hooks": [
                    "PreToolUse": [[
                        "matcher": "Read",
                        "hooks": [[
                            "type": "command",
                            "command": "/usr/bin/printf unrelated",
                        ]],
                    ]],
                    "CustomEvent": [[
                        "hooks": [[
                            "type": "command",
                            "command": "/usr/bin/true",
                        ]],
                    ]],
                ],
            ]
            let originalData = try writeJSON(originalObject, to: layout.configuration)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o640],
                ofItemAtPath: layout.configuration.path
            )

            let manager = makeManager(layout)
            let preview = manager.preview(.install)
            let previewContents = try Data(contentsOf: layout.configuration)
            let first = manager.apply(.install)
            let installedData = try Data(contentsOf: layout.configuration)
            let installedObject = try readJSON(at: layout.configuration)
            let second = manager.apply(.install)
            let secondData = try Data(contentsOf: layout.configuration)

            let removal = manager.apply(.remove)
            let removedObject = try readJSON(at: layout.configuration)
            let repeatedRemoval = manager.apply(.remove)

            return JSONHookLifecycleSnapshot(
                previewRequiresWrite: preview.requiresWrite,
                previewDidWrite: preview.didWrite,
                previewKeptFileUnchanged: previewContents == originalData,
                firstDidWrite: first.didWrite,
                firstBackupRestoresOriginal: first.backupURL.flatMap { try? Data(contentsOf: $0) } == originalData,
                secondDidWrite: second.didWrite,
                secondBackupCreated: second.backupURL != nil,
                secondKeptFileUnchanged: secondData == installedData,
                unknownSettingsPreserved: installedObject["theme"] as? String == "dark"
                    && (installedObject["nested"] as? [String: Any])?["number"] as? Int == 7,
                unrelatedHooksPreserved: commandCount(
                    containing: "/usr/bin/printf unrelated",
                    in: installedObject
                ) == 1 && commandCount(containing: "/usr/bin/true", in: installedObject) == 1,
                installedEventCount: JSONHookEventSpec.defaultIntegration.count,
                installedOwnedEntryCount: ownedCommandCount(in: installedObject),
                permissions: permissions(at: layout.configuration),
                removalDidWrite: removal.didWrite,
                repeatedRemovalDidWrite: repeatedRemoval.didWrite,
                ownedEntriesAfterRemoval: ownedCommandCount(in: removedObject)
            )
        }
    }

    static func migratesLegacyAndDuplicateEntries() throws -> JSONHookMigrationSnapshot {
        try withLayout { layout in
            let legacy = layout.home.appendingPathComponent(".agent-pulse/agent-pulse-hook").path
            let current = layout.bridge.path
            let object: [String: Any] = [
                "hooks": [
                    "PreToolUse": [[
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "command": "$HOME/.agent-pulse/agent-pulse-hook \(agentArgument)"],
                            ["type": "command", "command": "\(legacy) \(agentArgument)"],
                            ["type": "command", "command": "\(current) \(agentArgument)", "timeout": 9],
                            ["type": "command", "command": "/usr/bin/true"],
                        ],
                    ]],
                ],
            ]
            try writeJSON(object, to: layout.configuration)

            let result = makeManager(layout).apply(.install)
            let updated = try readJSON(at: layout.configuration)
            return JSONHookMigrationSnapshot(
                didWrite: result.didWrite,
                change: result.changes.first { $0.event == "PreToolUse" },
                ownedEntryCount: ownedCommandCount(in: updated),
                legacyEntryCount: commandCount(containing: ".agent-pulse/agent-pulse-hook", in: updated),
                unrelatedEntryCount: commandCount(containing: "/usr/bin/true", in: updated)
            )
        }
    }

    static func preservesSymlinkAndTargetPermissions() throws -> JSONHookSymlinkSnapshot {
        try withLayout { layout in
            let targetDirectory = layout.root.appendingPathComponent("shared", isDirectory: true)
            try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
            let target = targetDirectory.appendingPathComponent("settings.json")
            let originalData = try writeJSON(["kept": true], to: target)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)

            try FileManager.default.createDirectory(
                at: layout.configuration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let relativeTarget = "../../shared/settings.json"
            try FileManager.default.createSymbolicLink(
                atPath: layout.configuration.path,
                withDestinationPath: relativeTarget
            )

            let result = makeManager(layout).apply(.install)
            let targetObject = try readJSON(at: target)
            return JSONHookSymlinkSnapshot(
                didWrite: result.didWrite,
                symlinkDestination: try? FileManager.default.destinationOfSymbolicLink(
                    atPath: layout.configuration.path
                ),
                resolvedTargetMatches: result.resolvedTargetURL.standardizedFileURL
                    == target.standardizedFileURL,
                targetContainsHooks: targetObject["hooks"] != nil,
                targetPermissions: permissions(at: target),
                backupRestoresOriginal: result.backupURL.flatMap { try? Data(contentsOf: $0) } == originalData
            )
        }
    }

    static func invalidJSONIsBlocked() throws -> JSONHookBlockedSnapshot {
        try withLayout { layout in
            let original = Data("{not-json".utf8)
            try createParent(of: layout.configuration)
            try original.write(to: layout.configuration)
            let result = makeManager(layout).apply(.install)
            return blockedSnapshot(result, original: original, configuration: layout.configuration)
        }
    }

    static func unsupportedStructureIsBlocked() throws -> JSONHookBlockedSnapshot {
        try withLayout { layout in
            let original = try writeJSON(["hooks": ["PreToolUse": "invalid"]], to: layout.configuration)
            let result = makeManager(layout).apply(.install)
            return blockedSnapshot(result, original: original, configuration: layout.configuration)
        }
    }

    static func nonObjectRootIsBlocked() throws -> JSONHookBlockedSnapshot {
        try withLayout { layout in
            let original = try writeJSON(["not", "an", "object"], to: layout.configuration)
            let result = makeManager(layout).apply(.install)
            return blockedSnapshot(result, original: original, configuration: layout.configuration)
        }
    }

    static func backupFailureIsBlocked() throws -> JSONHookBlockedSnapshot {
        try withLayout { layout in
            let original = try writeJSON(["kept": true], to: layout.configuration)
            let manager = makeManager(layout, backupCopier: { _, _ in
                throw FixtureError.backupFailed
            })
            let result = manager.apply(.install)
            return blockedSnapshot(result, original: original, configuration: layout.configuration)
        }
    }

    static func readOnlyTargetIsBlocked() throws -> JSONHookBlockedSnapshot {
        try withLayout { layout in
            let original = try writeJSON(["kept": true], to: layout.configuration)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o400],
                ofItemAtPath: layout.configuration.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: layout.configuration.path
                )
            }
            let result = makeManager(layout).apply(.install)
            return blockedSnapshot(result, original: original, configuration: layout.configuration)
        }
    }

    static func installsMissingConfigurationSecurely() throws -> JSONHookMissingSnapshot {
        try withLayout { layout in
            let manager = makeManager(layout)
            let first = manager.apply(.install)
            let second = manager.apply(.install)
            return JSONHookMissingSnapshot(
                didWrite: first.didWrite,
                backupCreated: first.backupURL != nil,
                permissions: permissions(at: layout.configuration),
                repeatedDidWrite: second.didWrite
            )
        }
    }

    static func installsEmptyConfigurationWithBackup() throws -> JSONHookMissingSnapshot {
        try withLayout { layout in
            try createParent(of: layout.configuration)
            try Data().write(to: layout.configuration)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: layout.configuration.path
            )

            let manager = makeManager(layout)
            let first = manager.apply(.install)
            let second = manager.apply(.install)
            return JSONHookMissingSnapshot(
                didWrite: first.didWrite,
                backupCreated: first.backupURL.flatMap { try? Data(contentsOf: $0) }?.isEmpty == true,
                permissions: permissions(at: layout.configuration),
                repeatedDidWrite: second.didWrite
            )
        }
    }

    private static func makeManager(
        _ layout: Layout,
        backupCopier: JSONHookConfigurationManager.BackupCopier? = nil
    ) -> JSONHookConfigurationManager {
        JSONHookConfigurationManager(
            configurationURL: layout.configuration,
            bridgeExecutableURL: layout.bridge,
            agentArgument: agentArgument,
            homeDirectory: layout.home,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            backupCopier: backupCopier
        )
    }

    private static func blockedSnapshot(
        _ result: JSONHookConfigurationResult,
        original: Data,
        configuration: URL
    ) -> JSONHookBlockedSnapshot {
        JSONHookBlockedSnapshot(
            blocker: result.blocker,
            contentsUnchanged: (try? Data(contentsOf: configuration)) == original,
            backupCreated: result.backupURL != nil,
            didWrite: result.didWrite
        )
    }

    @discardableResult
    private static func writeJSON(_ object: Any, to url: URL) throws -> Data {
        try createParent(of: url)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
        return data
    }

    private static func readJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private static func createParent(of url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private static func ownedCommandCount(in root: [String: Any]) -> Int {
        commandStrings(in: root).filter { command in
            command.contains("agent-pulse-hook") && command.hasSuffix(" \(agentArgument)")
        }.count
    }

    private static func commandCount(containing fragment: String, in root: [String: Any]) -> Int {
        commandStrings(in: root).filter { $0.contains(fragment) }.count
    }

    private static func commandStrings(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        return hooks.values.flatMap { eventValue -> [String] in
            guard let groups = eventValue as? [Any] else { return [] }
            return groups.flatMap { groupValue -> [String] in
                guard let group = groupValue as? [String: Any],
                      let handlers = group["hooks"] as? [Any] else { return [] }
                return handlers.compactMap { ($0 as? [String: Any])?["command"] as? String }
            }
        }
    }

    private static func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return ((attributes?[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o777
    }

    private static func withLayout<T>(
        homeName: String = "home",
        _ body: (Layout) throws -> T
    ) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("json-hook-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(homeName, isDirectory: true)
        let configuration = home.appendingPathComponent(".client/settings.json")
        let bridge = home.appendingPathComponent(".agent-pulse/bin/agent-pulse-hook")
        return try body(Layout(root: root, home: home, configuration: configuration, bridge: bridge))
    }

    private struct Layout {
        var root: URL
        var home: URL
        var configuration: URL
        var bridge: URL
    }

    private enum FixtureError: Error {
        case backupFailed
    }
}
