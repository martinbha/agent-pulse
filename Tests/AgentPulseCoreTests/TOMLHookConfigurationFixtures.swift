import Foundation

@testable import AgentPulseCore

struct TOMLHookLifecycleSnapshot {
    var previewChange: TOMLHookConfigurationChangeKind
    var previewDidWrite: Bool
    var previewKeptOriginal: Bool
    var firstDidWrite: Bool
    var backupRestoresOriginal: Bool
    var unmanagedPrefixPreserved: Bool
    var installedEvents: [String]
    var containsUnsupportedEvents: Bool
    var installedPermissions: Int
    var secondDidWrite: Bool
    var secondChange: TOMLHookConfigurationChangeKind
    var secondCreatedBackup: Bool
    var removalDidWrite: Bool
    var removalRestoredOriginal: Bool
    var removalPermissions: Int
    var repeatedRemovalDidWrite: Bool
}

struct TOMLHookMissingSnapshot {
    var missingDidWrite: Bool
    var missingCreatedBackup: Bool
    var missingPermissions: Int
    var emptyDidWrite: Bool
    var emptyBackupIsEmpty: Bool
    var emptyPermissions: Int
}

struct TOMLHookUpdateSnapshot {
    var didWrite: Bool
    var change: TOMLHookConfigurationChangeKind
    var prefixPreserved: Bool
    var suffixPreserved: Bool
    var installedEvents: [String]
    var removedOutdatedContent: Bool
}

struct TOMLHookMalformedSnapshot {
    var expectedError: TOMLHookMarkerError
    var blocker: TOMLHookConfigurationBlocker?
    var didWrite: Bool
    var createdBackup: Bool
    var contentsUnchanged: Bool
}

struct TOMLHookMigrationSnapshot {
    var didWrite: Bool
    var change: TOMLHookConfigurationChangeKind
    var legacyBlockCount: Int
    var managedBlockCount: Int
    var installedEvents: [String]
    var removedLegacyPath: Bool
    var removedUnsupportedEvents: Bool
    var prefixPreserved: Bool
    var suffixPreserved: Bool
    var repeatedDidWrite: Bool
}

struct TOMLHookBlockedSnapshot {
    var blocker: TOMLHookConfigurationBlocker?
    var didWrite: Bool
    var createdBackup: Bool
    var contentsUnchanged: Bool
}

struct TOMLHookSymlinkSnapshot {
    var didWrite: Bool
    var resolvedTargetMatches: Bool
    var symlinkDestination: String?
    var targetContainsBlock: Bool
    var targetPermissions: Int
}

enum TOMLHookConfigurationFixtures {
    static func lifecycle() throws -> TOMLHookLifecycleSnapshot {
        try withLayout(homeName: "owner's home") { layout in
            let original = """
            # personal settings\r
            model = "local"\r
            retries = [1, 2, 3]\r
            ui.theme = "dark"
            """
            try write(original, to: layout.configuration, permissions: 0o640)
            let manager = makeManager(layout)

            let preview = manager.preview(.install)
            let previewContents = try contents(of: layout.configuration)
            let first = manager.apply(.install)
            let installed = try contents(of: layout.configuration)
            let second = manager.apply(.install)
            let removal = manager.apply(.remove)
            let removed = try contents(of: layout.configuration)
            let removalPermissions = permissions(at: layout.configuration)
            let repeatedRemoval = manager.apply(.remove)

            return TOMLHookLifecycleSnapshot(
                previewChange: preview.change.kind,
                previewDidWrite: preview.didWrite,
                previewKeptOriginal: previewContents == original,
                firstDidWrite: first.didWrite,
                backupRestoresOriginal: first.backupURL.flatMap { try? contents(of: $0) } == original,
                unmanagedPrefixPreserved: installed.hasPrefix(original + "\r\n"),
                installedEvents: rootEventNames(in: installed),
                containsUnsupportedEvents: installed.contains("StopFailure")
                    || installed.contains("SubagentStop"),
                installedPermissions: permissions(at: layout.configuration),
                secondDidWrite: second.didWrite,
                secondChange: second.change.kind,
                secondCreatedBackup: second.backupURL != nil,
                removalDidWrite: removal.didWrite,
                removalRestoredOriginal: removed == original,
                removalPermissions: removalPermissions,
                repeatedRemovalDidWrite: repeatedRemoval.didWrite
            )
        }
    }

    static func missingAndEmpty() throws -> TOMLHookMissingSnapshot {
        try withLayout { layout in
            let manager = makeManager(layout)
            let missing = manager.apply(.install)
            let missingPermissions = permissions(at: layout.configuration)

            try FileManager.default.removeItem(at: layout.configuration)
            try write("", to: layout.configuration, permissions: 0o644)
            let empty = manager.apply(.install)

            return TOMLHookMissingSnapshot(
                missingDidWrite: missing.didWrite,
                missingCreatedBackup: missing.backupURL != nil,
                missingPermissions: missingPermissions,
                emptyDidWrite: empty.didWrite,
                emptyBackupIsEmpty: empty.backupURL.flatMap { try? Data(contentsOf: $0) }?.isEmpty
                    == true,
                emptyPermissions: permissions(at: layout.configuration)
            )
        }
    }

    static func outdatedBlock() throws -> TOMLHookUpdateSnapshot {
        try withLayout { layout in
            let prefix = "# keep this comment\nvalues = [\"a\", \"b\"]\n\n"
            let outdated = """
            # BEGIN agent-pulse
            [[hooks.StopFailure]]
            [[hooks.StopFailure.hooks]]
            command = "obsolete"
            # END agent-pulse
            """
            let suffix = "\n[ui]\ncompact=true\n"
            try write(prefix + outdated + suffix, to: layout.configuration)

            let result = makeManager(layout).apply(.install)
            let updated = try contents(of: layout.configuration)
            return TOMLHookUpdateSnapshot(
                didWrite: result.didWrite,
                change: result.change.kind,
                prefixPreserved: updated.hasPrefix(prefix),
                suffixPreserved: updated.hasSuffix(suffix),
                installedEvents: rootEventNames(in: updated),
                removedOutdatedContent: !updated.contains("obsolete")
            )
        }
    }

    static func malformedMarkers() throws -> [TOMLHookMalformedSnapshot] {
        let malformed: [(String, TOMLHookMarkerError)] = [
            ("# END agent-pulse\n", .unexpectedEnd),
            ("# BEGIN agent-pulse\n# BEGIN agent-pulse\n# END agent-pulse\n", .nestedBegin),
            (
                "# BEGIN agent-pulse\n# END agent-pulse\n# BEGIN agent-pulse\n# END agent-pulse\n",
                .duplicateRegion
            ),
            ("# BEGIN agent-pulse\n[[hooks.Stop]]\n", .unterminatedRegion),
        ]

        return try malformed.map { fixture, expectedError in
            try withLayout { layout in
                try write(fixture, to: layout.configuration)
                let result = makeManager(layout).apply(.install)
                return TOMLHookMalformedSnapshot(
                    expectedError: expectedError,
                    blocker: result.blocker,
                    didWrite: result.didWrite,
                    createdBackup: result.backupURL != nil,
                    contentsUnchanged: try contents(of: layout.configuration) == fixture
                )
            }
        }
    }

    static func legacyMigration() throws -> TOMLHookMigrationSnapshot {
        try withLayout { layout in
            let prefix = "# hand-maintained\nfeature.enabled = true\n\n"
            let legacy = legacyBlock(
                executable: "$HOME/.agent-pulse/agent-pulse-hook",
                agentArgument: "worker"
            )
            let suffix = "[display]\nstyle = \"compact\"\n"
            try write(prefix + legacy + "\n\n" + legacy + "\n\n" + suffix, to: layout.configuration)

            let manager = makeManager(layout)
            let result = manager.apply(.install)
            let updated = try contents(of: layout.configuration)
            let repeated = manager.apply(.install)
            return TOMLHookMigrationSnapshot(
                didWrite: result.didWrite,
                change: result.change.kind,
                legacyBlockCount: result.change.legacyBlockCount,
                managedBlockCount: occurrences(
                    of: TOMLHookConfigurationManager.beginMarker,
                    in: updated
                ),
                installedEvents: rootEventNames(in: updated),
                removedLegacyPath: !updated.contains(".agent-pulse/agent-pulse-hook worker"),
                removedUnsupportedEvents: !updated.contains("StopFailure")
                    && !updated.contains("SubagentStop"),
                prefixPreserved: updated.hasPrefix(prefix),
                suffixPreserved: updated.hasSuffix(suffix),
                repeatedDidWrite: repeated.didWrite
            )
        }
    }

    static func backupFailure() throws -> TOMLHookBlockedSnapshot {
        try withLayout { layout in
            let original = "setting = true\n"
            try write(original, to: layout.configuration)
            let result = makeManager(layout, backupCopier: { _, _ in
                throw FixtureError.backupFailed
            }).apply(.install)
            return blockedSnapshot(result, original: original, configuration: layout.configuration)
        }
    }

    static func readOnlyTarget() throws -> TOMLHookBlockedSnapshot {
        try withLayout { layout in
            let original = "setting = true\n"
            try write(original, to: layout.configuration, permissions: 0o400)
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

    static func symlinkTarget() throws -> TOMLHookSymlinkSnapshot {
        try withLayout { layout in
            let target = layout.root.appendingPathComponent("shared/config.toml")
            try write("setting = true\n", to: target, permissions: 0o600)
            try FileManager.default.createDirectory(
                at: layout.configuration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(
                atPath: layout.configuration.path,
                withDestinationPath: "../../shared/config.toml"
            )

            let result = makeManager(layout).apply(.install)
            return TOMLHookSymlinkSnapshot(
                didWrite: result.didWrite,
                resolvedTargetMatches: result.resolvedTargetURL.standardizedFileURL
                    == target.standardizedFileURL,
                symlinkDestination: try? FileManager.default.destinationOfSymbolicLink(
                    atPath: layout.configuration.path
                ),
                targetContainsBlock: try contents(of: target).contains(
                    TOMLHookConfigurationManager.beginMarker
                ),
                targetPermissions: permissions(at: target)
            )
        }
    }

    private static func blockedSnapshot(
        _ result: TOMLHookConfigurationResult,
        original: String,
        configuration: URL
    ) -> TOMLHookBlockedSnapshot {
        TOMLHookBlockedSnapshot(
            blocker: result.blocker,
            didWrite: result.didWrite,
            createdBackup: result.backupURL != nil,
            contentsUnchanged: (try? contents(of: configuration)) == original
        )
    }

    private static func makeManager(
        _ layout: Layout,
        backupCopier: TOMLHookConfigurationManager.BackupCopier? = nil
    ) -> TOMLHookConfigurationManager {
        TOMLHookConfigurationManager(
            configurationURL: layout.configuration,
            bridgeExecutableURL: layout.bridge,
            agentArgument: "worker",
            homeDirectory: layout.home,
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            backupCopier: backupCopier
        )
    }

    private static func rootEventNames(in contents: String) -> [String] {
        contents.split(whereSeparator: \.isNewline).compactMap { line in
            let value = String(line)
            guard value.hasPrefix("[[hooks."), value.hasSuffix("]]"),
                  !value.dropFirst("[[hooks.".count).dropLast(2).contains(".hooks") else {
                return nil
            }
            return String(value.dropFirst("[[hooks.".count).dropLast(2))
        }
    }

    private static func legacyBlock(executable: String, agentArgument: String) -> String {
        let events: [(String, String?)] = [
            ("SessionStart", "startup|resume|clear|compact"),
            ("UserPromptSubmit", nil),
            ("PreToolUse", "*"),
            ("PostToolUse", "*"),
            ("PermissionRequest", "*"),
            ("Stop", nil),
            ("StopFailure", nil),
            ("SubagentStop", nil),
        ]
        return events.map { event, matcher in
            var lines = ["[[hooks.\(event)]]"]
            if let matcher {
                lines.append("matcher = \"\(matcher)\"")
            }
            lines += [
                "[[hooks.\(event).hooks]]",
                "type = \"command\"",
                "command = \"\(executable) \(agentArgument)\"",
                "timeout = 2",
                "statusMessage = \"Updating Agent Pulse\"",
            ]
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private static func write(
        _ contents: String,
        to url: URL,
        permissions: Int = 0o600
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions],
            ofItemAtPath: url.path
        )
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
            .appendingPathComponent("toml-hook-manager-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent(homeName, isDirectory: true)
        let configuration = home.appendingPathComponent(".client/config.toml")
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
