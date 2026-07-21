import Foundation

@testable import AgentPulseCore

struct BridgeInstallSnapshot {
    var initialStatus: BridgeInstallationStatus
    var installedStatus: BridgeInstallationStatus
    var repeatedStatus: BridgeInstallationStatus
    var executableContents: String
    var executablePath: String
    var executablePermissions: Int
    var rootPermissions: Int
    var binPermissions: Int
    var configPermissions: Int
    var replacementCountAfterInstall: Int
    var replacementCountAfterRepeat: Int
}

struct BridgeUpgradeSnapshot {
    var outdatedStatus: BridgeInstallationStatus
    var upgradedStatus: BridgeInstallationStatus
    var executableContents: String
}

struct BridgeRepairSnapshot {
    var damagedStatus: BridgeInstallationStatus
    var repairedStatus: BridgeInstallationStatus
    var executablePermissions: Int
}

struct BridgeRemovalSnapshot {
    var executableExists: Bool
    var versionExists: Bool
    var configExists: Bool
    var unrelatedRootFileExists: Bool
    var unrelatedBinFileExists: Bool
}

struct BridgeInterruptedReplacementSnapshot {
    var error: BridgeInstallationError?
    var executableContents: String
    var installedVersion: String
    var statusAfterInterruption: BridgeInstallationStatus
    var repairedStatus: BridgeInstallationStatus
    var temporaryFileCount: Int
}

struct BridgeInvalidExecutableSnapshot {
    var damagedStatus: BridgeInstallationStatus
    var repairedStatus: BridgeInstallationStatus
    var bundledError: BridgeInstallationError?
}

struct BridgeTranslocationSnapshot {
    var classified: Bool
    var error: BridgeInstallationError?
    var installationRootExists: Bool
}

enum BridgeInstallerFixtures {
    static func installLifecycle() throws -> BridgeInstallSnapshot {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            try FileManager.default.createDirectory(
                at: layout.home.appendingPathComponent(".agent-pulse"),
                withIntermediateDirectories: true
            )
            let config = layout.home.appendingPathComponent(".agent-pulse/config.json")
            try Data("secret".utf8).write(to: config)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: config.path
            )

            var replacementCount = 0
            let installer = BridgeInstaller(
                homeDirectory: layout.home,
                bundleURL: layout.bundle,
                checkpointHandler: { _ in replacementCount += 1 }
            )
            let initialStatus = try installer.status()
            let installedStatus = try installer.install()
            let countAfterInstall = replacementCount
            let repeatedStatus = try installer.install()

            return BridgeInstallSnapshot(
                initialStatus: initialStatus,
                installedStatus: installedStatus,
                repeatedStatus: repeatedStatus,
                executableContents: try String(
                    contentsOf: installer.paths.installedExecutable,
                    encoding: .utf8
                ),
                executablePath: installer.paths.installedExecutable.path,
                executablePermissions: permissions(at: installer.paths.installedExecutable),
                rootPermissions: permissions(at: installer.paths.rootDirectory),
                binPermissions: permissions(at: installer.paths.binDirectory),
                configPermissions: permissions(at: installer.paths.configuration),
                replacementCountAfterInstall: countAfterInstall,
                replacementCountAfterRepeat: replacementCount
            )
        }
    }

    static func upgradeLifecycle() throws -> BridgeUpgradeSnapshot {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            try installer.install()

            try writeBundle(layout.bundle, version: "2.0.0", executable: "bridge-v2")
            let outdatedStatus = try installer.status()
            let upgradedStatus = try installer.upgrade()
            return BridgeUpgradeSnapshot(
                outdatedStatus: outdatedStatus,
                upgradedStatus: upgradedStatus,
                executableContents: try String(
                    contentsOf: installer.paths.installedExecutable,
                    encoding: .utf8
                )
            )
        }
    }

    static func repairLifecycle() throws -> BridgeRepairSnapshot {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            try installer.install()
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: installer.paths.installedExecutable.path
            )

            let damagedStatus = try installer.status()
            let repairedStatus = try installer.repair()
            return BridgeRepairSnapshot(
                damagedStatus: damagedStatus,
                repairedStatus: repairedStatus,
                executablePermissions: permissions(at: installer.paths.installedExecutable)
            )
        }
    }

    static func removalScope() throws -> BridgeRemovalSnapshot {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            try installer.install()

            try Data("config".utf8).write(to: installer.paths.configuration)
            let unrelatedRoot = installer.paths.rootDirectory.appendingPathComponent("keep-me")
            let unrelatedBin = installer.paths.binDirectory.appendingPathComponent("keep-me-too")
            try Data("root".utf8).write(to: unrelatedRoot)
            try Data("bin".utf8).write(to: unrelatedBin)
            try installer.remove()

            return BridgeRemovalSnapshot(
                executableExists: FileManager.default.fileExists(
                    atPath: installer.paths.installedExecutable.path
                ),
                versionExists: FileManager.default.fileExists(
                    atPath: installer.paths.installedVersion.path
                ),
                configExists: FileManager.default.fileExists(
                    atPath: installer.paths.configuration.path
                ),
                unrelatedRootFileExists: FileManager.default.fileExists(atPath: unrelatedRoot.path),
                unrelatedBinFileExists: FileManager.default.fileExists(atPath: unrelatedBin.path)
            )
        }
    }

    static func interruptedReplacement() throws -> BridgeInterruptedReplacementSnapshot {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            let initialInstaller = BridgeInstaller(
                homeDirectory: layout.home,
                bundleURL: layout.bundle
            )
            try initialInstaller.install()
            try writeBundle(layout.bundle, version: "2.0.0", executable: "bridge-v2")

            let interruptedInstaller = BridgeInstaller(
                homeDirectory: layout.home,
                bundleURL: layout.bundle,
                checkpointHandler: { checkpoint in
                    if checkpoint == .stagedVersion {
                        throw FixtureError.interrupted
                    }
                }
            )
            var capturedError: BridgeInstallationError?
            do {
                try interruptedInstaller.upgrade()
            } catch let error as BridgeInstallationError {
                capturedError = error
            }

            let executableContents = try String(
                contentsOf: interruptedInstaller.paths.installedExecutable,
                encoding: .utf8
            )
            let installedVersion = try String(
                contentsOf: interruptedInstaller.paths.installedVersion,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let statusAfterInterruption = try interruptedInstaller.status()
            let repairedStatus = try BridgeInstaller(
                homeDirectory: layout.home,
                bundleURL: layout.bundle
            ).repair()

            let directoryContents = try FileManager.default.contentsOfDirectory(
                atPath: interruptedInstaller.paths.binDirectory.path
            )
            return BridgeInterruptedReplacementSnapshot(
                error: capturedError,
                executableContents: executableContents,
                installedVersion: installedVersion,
                statusAfterInterruption: statusAfterInterruption,
                repairedStatus: repairedStatus,
                temporaryFileCount: directoryContents.filter { $0.hasSuffix(".tmp") }.count
            )
        }
    }

    static func invalidExecutableHandling() throws -> BridgeInvalidExecutableSnapshot {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            try installer.install()
            try Data().write(to: installer.paths.installedExecutable)

            let damagedStatus = try installer.status()
            let repairedStatus = try installer.repair()

            try FileManager.default.removeItem(at: installer.paths.bundledExecutable)
            try FileManager.default.createDirectory(
                at: installer.paths.bundledExecutable,
                withIntermediateDirectories: false
            )
            var bundledError: BridgeInstallationError?
            do {
                try installer.repair()
            } catch let error as BridgeInstallationError {
                bundledError = error
            }

            return BridgeInvalidExecutableSnapshot(
                damagedStatus: damagedStatus,
                repairedStatus: repairedStatus,
                bundledError: bundledError
            )
        }
    }

    static func translocationRejection() throws -> BridgeTranslocationSnapshot {
        try withLayout(translocated: true) { layout in
            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            var capturedError: BridgeInstallationError?
            do {
                try installer.install()
            } catch let error as BridgeInstallationError {
                capturedError = error
            }
            return BridgeTranslocationSnapshot(
                classified: BridgeInstaller.isAppTranslocated(layout.bundle),
                error: capturedError,
                installationRootExists: FileManager.default.fileExists(
                    atPath: installer.paths.rootDirectory.path
                )
            )
        }
    }

    static func blockedDirectoryError() throws -> BridgeInstallationError? {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            try FileManager.default.createDirectory(at: layout.home, withIntermediateDirectories: true)
            let blockedRoot = layout.home.appendingPathComponent(".agent-pulse")
            try Data("not-a-directory".utf8).write(to: blockedRoot)
            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            do {
                try installer.install()
                return nil
            } catch let error as BridgeInstallationError {
                return error
            }
        }
    }

    static func permissionDeniedError() throws -> BridgeInstallationError? {
        try withLayout { layout in
            try writeBundle(layout.bundle, version: "1.0.0", executable: "bridge-v1")
            try FileManager.default.createDirectory(at: layout.home, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: layout.home.path
            )
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: layout.home.path
                )
            }

            let installer = BridgeInstaller(homeDirectory: layout.home, bundleURL: layout.bundle)
            do {
                try installer.install()
                return nil
            } catch let error as BridgeInstallationError {
                return error
            }
        }
    }

    @MainActor
    static func settingsPermissions() throws -> (directory: Int, configuration: Int) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent(".agent-pulse/config.json")
        let suite = "agent-pulse-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = AgentPulseSettings(defaults: defaults, bridgeConfigURL: config)
        return (
            directory: permissions(at: config.deletingLastPathComponent()),
            configuration: permissions(at: config)
        )
    }

    private static func writeBundle(_ bundle: URL, version: String, executable: String) throws {
        let helpers = bundle.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try Data(executable.utf8).write(to: helpers.appendingPathComponent("agent-pulse-hook"))
        try Data("\(version)\n".utf8).write(
            to: helpers.appendingPathComponent("agent-pulse-hook.version")
        )
    }

    private static func permissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attributes?[.posixPermissions] as? NSNumber
        return permissions?.intValue ?? 0
    }

    private static func withLayout<T>(
        translocated: Bool = false,
        _ body: (Layout) throws -> T
    ) throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bundle: URL
        if translocated {
            bundle = root.appendingPathComponent(
                "AppTranslocation/instance/d/Agent Pulse.app",
                isDirectory: true
            )
        } else {
            bundle = root.appendingPathComponent("Agent Pulse.app", isDirectory: true)
        }
        return try body(Layout(home: root.appendingPathComponent("home"), bundle: bundle))
    }

    private struct Layout {
        var home: URL
        var bundle: URL
    }

    private enum FixtureError: Error {
        case interrupted
    }
}
