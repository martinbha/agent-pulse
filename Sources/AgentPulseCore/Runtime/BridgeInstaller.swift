import Darwin
import Foundation

enum BridgeInstallationStatus: Equatable {
    case missing
    case current(version: String)
    case outdated(installedVersion: String?, bundledVersion: String)
    case damaged(reason: String)
}

enum BridgeInstallationCheckpoint: Equatable {
    case stagedExecutable
    case stagedVersion
}

enum BridgeInstallationError: LocalizedError, Equatable {
    case appTranslocated(String)
    case bundledExecutableMissing(String)
    case bundledVersionInvalid(String)
    case directoryCreationFailed(String)
    case copyFailed(String)
    case permissionUpdateFailed(String)
    case replacementFailed(String)
    case removalFailed(String)

    var errorDescription: String? {
        switch self {
        case .appTranslocated:
            return "Move Agent Pulse to /Applications or ~/Applications before installing integrations."
        case .bundledExecutableMissing(let path):
            return "The bundled bridge is missing at \(path). Reinstall Agent Pulse."
        case .bundledVersionInvalid(let path):
            return "The bundled bridge version is missing or invalid at \(path). Reinstall Agent Pulse."
        case .directoryCreationFailed(let path):
            return "Could not create the bridge directory at \(path)."
        case .copyFailed(let path):
            return "Could not stage the bridge for installation at \(path)."
        case .permissionUpdateFailed(let path):
            return "Could not secure bridge permissions at \(path)."
        case .replacementFailed(let path):
            return "Could not atomically replace the bridge at \(path)."
        case .removalFailed(let path):
            return "Could not remove the installed bridge at \(path)."
        }
    }
}

struct BridgeInstallationPaths {
    let rootDirectory: URL
    let binDirectory: URL
    let installedExecutable: URL
    let installedVersion: URL
    let configuration: URL
    let bundledExecutable: URL
    let bundledVersion: URL

    init(homeDirectory: URL, bundleURL: URL) {
        rootDirectory = homeDirectory.appendingPathComponent(".agent-pulse", isDirectory: true)
        binDirectory = rootDirectory.appendingPathComponent("bin", isDirectory: true)
        installedExecutable = binDirectory.appendingPathComponent("agent-pulse-hook")
        installedVersion = binDirectory.appendingPathComponent("agent-pulse-hook.version")
        configuration = rootDirectory.appendingPathComponent("config.json")

        let helpers = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
        bundledExecutable = helpers.appendingPathComponent("agent-pulse-hook")
        bundledVersion = helpers.appendingPathComponent("agent-pulse-hook.version")
    }
}

struct BridgeInstaller {
    typealias CheckpointHandler = (BridgeInstallationCheckpoint) throws -> Void

    let paths: BridgeInstallationPaths
    private let fileManager: FileManager
    private let checkpointHandler: CheckpointHandler?

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        checkpointHandler: CheckpointHandler? = nil
    ) {
        paths = BridgeInstallationPaths(homeDirectory: homeDirectory, bundleURL: bundleURL)
        self.fileManager = fileManager
        self.checkpointHandler = checkpointHandler
    }

    static func isAppTranslocated(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.pathComponents.contains("AppTranslocation")
    }

    func status() throws -> BridgeInstallationStatus {
        let bundledVersion = try readBundledVersion()
        guard fileManager.fileExists(atPath: paths.installedExecutable.path) else {
            return .missing
        }

        guard executablePermissions(at: paths.installedExecutable) == 0o755 else {
            return .damaged(reason: "The installed bridge permissions are not 0755.")
        }
        guard directoryPermissions(at: paths.rootDirectory) == 0o700,
              directoryPermissions(at: paths.binDirectory) == 0o700 else {
            return .damaged(reason: "The bridge directories are not owner-only.")
        }
        if fileManager.fileExists(atPath: paths.configuration.path),
           executablePermissions(at: paths.configuration) != 0o600 {
            return .damaged(reason: "The bridge configuration permissions are not 0600.")
        }

        let installedVersion = readVersion(at: paths.installedVersion)
        guard installedVersion == bundledVersion else {
            return .outdated(
                installedVersion: installedVersion,
                bundledVersion: bundledVersion
            )
        }
        return .current(version: bundledVersion)
    }

    @discardableResult
    func install() throws -> BridgeInstallationStatus {
        try reconcile()
    }

    @discardableResult
    func repair() throws -> BridgeInstallationStatus {
        try reconcile()
    }

    @discardableResult
    func upgrade() throws -> BridgeInstallationStatus {
        try reconcile()
    }

    func remove() throws {
        try rejectTranslocatedApp()

        for url in [paths.installedExecutable, paths.installedVersion] {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw BridgeInstallationError.removalFailed(url.path)
            }
        }

        guard fileManager.fileExists(atPath: paths.binDirectory.path) else { return }
        do {
            if try fileManager.contentsOfDirectory(atPath: paths.binDirectory.path).isEmpty {
                try fileManager.removeItem(at: paths.binDirectory)
            }
        } catch {
            throw BridgeInstallationError.removalFailed(paths.binDirectory.path)
        }
    }

    private func reconcile() throws -> BridgeInstallationStatus {
        try rejectTranslocatedApp()
        let bundledVersion = try readBundledVersion()
        guard fileManager.isReadableFile(atPath: paths.bundledExecutable.path) else {
            throw BridgeInstallationError.bundledExecutableMissing(paths.bundledExecutable.path)
        }

        if try status() == .current(version: bundledVersion) {
            return .current(version: bundledVersion)
        }

        try prepareDirectories()
        try atomicCopy(
            from: paths.bundledExecutable,
            to: paths.installedExecutable,
            permissions: 0o755,
            checkpoint: .stagedExecutable
        )
        try atomicCopy(
            from: paths.bundledVersion,
            to: paths.installedVersion,
            permissions: 0o644,
            checkpoint: .stagedVersion
        )
        try secureConfigurationIfPresent()

        return .current(version: bundledVersion)
    }

    private func rejectTranslocatedApp() throws {
        guard !Self.isAppTranslocated(paths.bundledExecutable) else {
            throw BridgeInstallationError.appTranslocated(paths.bundledExecutable.path)
        }
    }

    private func readBundledVersion() throws -> String {
        guard let version = readVersion(at: paths.bundledVersion) else {
            throw BridgeInstallationError.bundledVersionInvalid(paths.bundledVersion.path)
        }
        return version
    }

    private func readVersion(at url: URL) -> String? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func prepareDirectories() throws {
        do {
            try fileManager.createDirectory(
                at: paths.binDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw BridgeInstallationError.directoryCreationFailed(paths.binDirectory.path)
        }

        for directory in [paths.rootDirectory, paths.binDirectory] {
            do {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: directory.path
                )
            } catch {
                throw BridgeInstallationError.permissionUpdateFailed(directory.path)
            }
        }
    }

    private func secureConfigurationIfPresent() throws {
        guard fileManager.fileExists(atPath: paths.configuration.path) else { return }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.configuration.path
            )
        } catch {
            throw BridgeInstallationError.permissionUpdateFailed(paths.configuration.path)
        }
    }

    private func atomicCopy(
        from source: URL,
        to destination: URL,
        permissions: Int,
        checkpoint: BridgeInstallationCheckpoint
    ) throws {
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }

        do {
            try fileManager.copyItem(at: source, to: temporary)
        } catch {
            throw BridgeInstallationError.copyFailed(destination.path)
        }

        do {
            try fileManager.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: temporary.path
            )
        } catch {
            throw BridgeInstallationError.permissionUpdateFailed(destination.path)
        }

        do {
            try checkpointHandler?(checkpoint)
        } catch {
            throw BridgeInstallationError.replacementFailed(destination.path)
        }

        let result = temporary.path.withCString { temporaryPath in
            destination.path.withCString { destinationPath in
                Darwin.rename(temporaryPath, destinationPath)
            }
        }
        guard result == 0 else {
            throw BridgeInstallationError.replacementFailed(destination.path)
        }
    }

    private func executablePermissions(at url: URL) -> Int? {
        guard let permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions]
            as? NSNumber else {
            return nil
        }
        return permissions.intValue & 0o777
    }

    private func directoryPermissions(at url: URL) -> Int? {
        executablePermissions(at: url)
    }
}
