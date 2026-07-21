import AppKit
import Foundation
import ServiceManagement
import UserNotifications

struct SetupHealthInspector {
    typealias ApplicationProvider = () -> ApplicationLocationHealth
    typealias LocalServerProvider = () async -> LocalServerHealth
    typealias BridgeProvider = () -> BridgeHealth
    typealias HostProvider = (AgentKind) async -> IntegrationHostHealth
    typealias HookProvider = (AgentKind) -> HookConfigurationHealth
    typealias NotificationProvider = () async -> NotificationAuthorizationHealth
    typealias LaunchAtLoginProvider = () async -> LaunchAtLoginHealth

    private let now: () -> Date
    private let applicationProvider: ApplicationProvider
    private let localServerProvider: LocalServerProvider
    private let bridgeProvider: BridgeProvider
    private let hostProvider: HostProvider
    private let hookProvider: HookProvider
    private let notificationProvider: NotificationProvider
    private let launchAtLoginProvider: LaunchAtLoginProvider

    init(
        now: @escaping () -> Date = Date.init,
        applicationProvider: @escaping ApplicationProvider,
        localServerProvider: @escaping LocalServerProvider,
        bridgeProvider: @escaping BridgeProvider,
        hostProvider: @escaping HostProvider,
        hookProvider: @escaping HookProvider,
        notificationProvider: @escaping NotificationProvider,
        launchAtLoginProvider: @escaping LaunchAtLoginProvider
    ) {
        self.now = now
        self.applicationProvider = applicationProvider
        self.localServerProvider = localServerProvider
        self.bridgeProvider = bridgeProvider
        self.hostProvider = hostProvider
        self.hookProvider = hookProvider
        self.notificationProvider = notificationProvider
        self.launchAtLoginProvider = launchAtLoginProvider
    }

    func inspect(
        usage: [AgentKind: UsageAvailability],
        events: [AgentKind: AgentStatusSnapshot]
    ) async -> SetupHealthSnapshot {
        async let localServer = localServerProvider()
        async let notifications = notificationProvider()
        async let launchAtLogin = launchAtLoginProvider()

        var hosts: [AgentKind: IntegrationHostHealth] = [:]
        var hooks: [AgentKind: HookConfigurationHealth] = [:]
        for agent in AgentKind.allCases {
            hosts[agent] = await hostProvider(agent)
            hooks[agent] = hookProvider(agent)
        }

        return await SetupHealthClassifier.makeSnapshot(
            inspectedAt: now(),
            application: applicationProvider(),
            localServer: localServer,
            bridge: bridgeProvider(),
            hosts: hosts,
            hooks: hooks,
            usage: usage,
            events: events,
            notifications: notifications,
            launchAtLogin: launchAtLogin
        )
    }

    static func live(
        endpoint: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default,
        notificationCenter: UNUserNotificationCenter = .current(),
        now: @escaping () -> Date = Date.init
    ) -> SetupHealthInspector {
        let bridgeInstaller = BridgeInstaller(
            homeDirectory: homeDirectory,
            bundleURL: bundleURL,
            fileManager: fileManager
        )
        let jsonManager = JSONHookConfigurationManager(
            configurationURL: homeDirectory.appendingPathComponent(".claude/settings.json"),
            bridgeExecutableURL: bridgeInstaller.paths.installedExecutable,
            agentArgument: AgentKind.claude.rawValue,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        let tomlManager = TOMLHookConfigurationManager(
            configurationURL: homeDirectory.appendingPathComponent(".codex/config.toml"),
            bridgeExecutableURL: bridgeInstaller.paths.installedExecutable,
            agentArgument: AgentKind.codex.rawValue,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        let application = SetupHealthClassifier.applicationLocation(
            bundleURL: bundleURL,
            homeDirectory: homeDirectory
        )

        return SetupHealthInspector(
            now: now,
            applicationProvider: { application },
            localServerProvider: { await localServerHealth(endpoint: endpoint) },
            bridgeProvider: {
                do {
                    return bridgeHealth(from: try bridgeInstaller.status())
                } catch let error as BridgeInstallationError {
                    return bridgeHealth(from: error)
                } catch {
                    return .invalid(error.localizedDescription)
                }
            },
            hostProvider: { agent in
                await hostHealth(for: agent)
            },
            hookProvider: { agent in
                switch agent {
                case .claude:
                    return jsonHookHealth(from: jsonManager.preview(.install))
                case .codex:
                    return tomlHookHealth(from: tomlManager.preview(.install))
                }
            },
            notificationProvider: {
                await notificationHealth(center: notificationCenter)
            },
            launchAtLoginProvider: {
                await launchAtLoginHealth(application: application)
            }
        )
    }

    static func bridgeHealth(from status: BridgeInstallationStatus) -> BridgeHealth {
        switch status {
        case .missing:
            return .missing
        case .current(let version):
            return .current(version: version)
        case .outdated(let installedVersion, let bundledVersion):
            return .outdated(
                installedVersion: installedVersion,
                bundledVersion: bundledVersion
            )
        case .damaged(let reason):
            let normalized = reason.lowercased()
            if normalized.contains("cannot be executed") || normalized.contains("not readable") {
                return .unreadable(reason)
            }
            return .invalid(reason)
        }
    }

    static func bridgeHealth(from error: BridgeInstallationError) -> BridgeHealth {
        switch error {
        case .bundledExecutableMissing,
             .bundledExecutableInvalid,
             .bundledVersionInvalid:
            return .invalid(error.localizedDescription)
        case .appTranslocated:
            return .invalid(error.localizedDescription)
        case .directoryCreationFailed,
             .copyFailed,
             .permissionUpdateFailed,
             .replacementFailed,
             .removalFailed:
            return .invalid(error.localizedDescription)
        }
    }

    static func jsonHookHealth(
        from result: JSONHookConfigurationResult
    ) -> HookConfigurationHealth {
        if let blocker = result.blocker {
            return .invalid(jsonBlockerMessage(blocker))
        }

        let duplicatedEntryCount = result.changes
            .filter { $0.ownedEntryCount > 1 }
            .reduce(0) { $0 + $1.ownedEntryCount }
        if duplicatedEntryCount > 0 {
            return .duplicated(ownedEntryCount: duplicatedEntryCount)
        }
        guard result.requiresWrite else {
            return .current
        }
        if !result.changes.isEmpty,
           result.changes.allSatisfy({ $0.kind == .added && $0.ownedEntryCount == 0 }) {
            return .missing
        }
        return .outdated
    }

    static func tomlHookHealth(
        from result: TOMLHookConfigurationResult
    ) -> HookConfigurationHealth {
        if let blocker = result.blocker {
            return .invalid(tomlBlockerMessage(blocker))
        }

        let totalOwnedBlocks = result.change.managedBlockCount + result.change.legacyBlockCount
        if totalOwnedBlocks > 1 {
            return .duplicated(ownedEntryCount: totalOwnedBlocks)
        }
        switch result.change.kind {
        case .unchanged:
            return .current
        case .added:
            return .missing
        case .updated, .removed:
            return .outdated
        }
    }

    private static func localServerHealth(endpoint: URL) async -> LocalServerHealth {
        let healthURL = endpoint.appendingPathComponent("v1/health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return .invalidResponse(
                    endpoint: endpoint,
                    reason: "The health endpoint did not return a successful status."
                )
            }
            let health = try AgentPulseJSON.decoder.decode(HealthResponse.self, from: data)
            guard health.ok, !health.version.isEmpty else {
                return .invalidResponse(
                    endpoint: endpoint,
                    reason: "The health endpoint returned an incomplete response."
                )
            }
            return .healthy(endpoint: endpoint, version: health.version)
        } catch {
            return .unreachable(endpoint: endpoint, reason: error.localizedDescription)
        }
    }

    @MainActor
    private static func hostHealth(for agent: AgentKind) -> IntegrationHostHealth {
        for bundleID in AgentAppLauncher.bundleIDCandidates(for: agent) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return .available(applicationURL: url)
            }
        }
        return .unavailable
    }

    private static func notificationHealth(
        center: UNUserNotificationCenter
    ) async -> NotificationAuthorizationHealth {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unavailable("Unknown notification authorization state.")
        }
    }

    @MainActor
    private static func launchAtLoginHealth(
        application: ApplicationLocationHealth
    ) -> LaunchAtLoginHealth {
        if case .unbundled = application {
            return .unavailable("Launch at Login requires an application bundle.")
        }
        switch SMAppService.mainApp.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .unavailable("Unknown Launch at Login state.")
        }
    }

    private static func jsonBlockerMessage(_ blocker: JSONHookConfigurationBlocker) -> String {
        switch blocker {
        case .readFailed: return "The configuration file could not be read."
        case .invalidJSON: return "The configuration file is not valid JSON."
        case .rootIsNotObject: return "The configuration root must be an object."
        case .unsupportedHookStructure(let path):
            return "The hook structure at \(path) cannot be changed safely."
        case .targetIsNotWritable: return "The configuration file is read-only."
        case .directoryCreationFailed: return "The configuration directory cannot be created."
        case .backupFailed: return "The configuration file cannot be backed up."
        case .serializationFailed: return "The updated configuration cannot be serialized."
        case .permissionReadFailed: return "The configuration permissions cannot be read."
        case .permissionUpdateFailed: return "The configuration permissions cannot be preserved."
        case .replacementFailed: return "The configuration file cannot be replaced atomically."
        }
    }

    private static func tomlBlockerMessage(_ blocker: TOMLHookConfigurationBlocker) -> String {
        switch blocker {
        case .readFailed: return "The configuration file could not be read."
        case .malformedMarkers(let error):
            switch error {
            case .unexpectedEnd: return "The managed block has an end marker without a begin marker."
            case .nestedBegin: return "The managed block contains a nested begin marker."
            case .duplicateRegion: return "The configuration contains duplicate managed blocks."
            case .unterminatedRegion: return "The managed block has no end marker."
            }
        case .targetIsNotWritable: return "The configuration file is read-only."
        case .directoryCreationFailed: return "The configuration directory cannot be created."
        case .backupFailed: return "The configuration file cannot be backed up."
        case .permissionReadFailed: return "The configuration permissions cannot be read."
        case .permissionUpdateFailed: return "The configuration permissions cannot be preserved."
        case .replacementFailed: return "The configuration file cannot be replaced atomically."
        }
    }
}
