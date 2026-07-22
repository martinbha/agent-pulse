import Foundation

enum SetupOperation: Equatable {
    case installBridge
    case repairBridge
    case setUp(AgentKind)
    case repair(AgentKind)
    case remove(AgentKind)

    var agent: AgentKind? {
        switch self {
        case .setUp(let agent), .repair(let agent), .remove(let agent):
            return agent
        case .installBridge, .repairBridge:
            return nil
        }
    }

    var title: String {
        switch self {
        case .installBridge: return "Install Bridge"
        case .repairBridge: return "Repair Bridge"
        case .setUp: return "Set Up"
        case .repair: return "Repair"
        case .remove: return "Remove"
        }
    }
}

struct SetupOperationReport: Equatable {
    let message: String
}

struct SetupOperationFailure: LocalizedError, Equatable {
    let message: String
    let recovery: String

    var errorDescription: String? { message }
    var recoverySuggestion: String? { recovery }
}

struct SetupOperationNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let message: String
    let recovery: String?
}

enum SetupPresentationPolicy {
    static func shouldPresent(
        hasSeenWelcome: Bool,
        snapshot: SetupHealthSnapshot
    ) -> Bool {
        guard hasSeenWelcome else {
            return true
        }

        switch snapshot.recommendedAction {
        case .moveApplication,
             .restartLocalServer,
             .repairBridge,
             .repairIntegration,
             .reviewIntegrationConfiguration:
            return true
        case .installBridge:
            return snapshot.integrations.contains { integration in
                switch integration.hooks {
                case .current, .outdated, .duplicated, .invalid:
                    return true
                case .missing:
                    return false
                }
            }
        case .installHost,
             .installIntegration,
             .signIn,
             .testIntegration,
             .requestNotificationPermission,
             .openNotificationSettings,
             .approveLaunchAtLogin,
             .none:
            return false
        }
    }
}

enum SetupIntegrationOperations {
    static func available(for integration: IntegrationHealthSnapshot) -> [SetupOperation] {
        switch integration.hooks {
        case .missing:
            guard case .available = integration.host else {
                return []
            }
            return [.setUp(integration.agent)]
        case .current:
            return [.remove(integration.agent)]
        case .outdated, .duplicated:
            return [.repair(integration.agent), .remove(integration.agent)]
        case .invalid:
            return []
        }
    }
}

@MainActor
final class SetupWorkflow: ObservableObject {
    typealias InspectionProvider = () async -> SetupHealthSnapshot
    typealias OperationExecutor = (SetupOperation) async throws -> SetupOperationReport

    @Published private(set) var snapshot: SetupHealthSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeOperation: SetupOperation?
    @Published private(set) var notice: SetupOperationNotice?

    private let defaults: UserDefaults
    private let inspectionProvider: InspectionProvider
    private let operationExecutor: OperationExecutor

    private static let welcomeSeenKey = "setup.welcomeSeen"

    init(
        defaults: UserDefaults = .standard,
        inspectionProvider: @escaping InspectionProvider,
        operationExecutor: @escaping OperationExecutor
    ) {
        self.defaults = defaults
        self.inspectionProvider = inspectionProvider
        self.operationExecutor = operationExecutor
    }

    static func live(runtime: AgentPulseRuntime) -> SetupWorkflow {
        guard let endpoint = URL(string: runtime.endpoint) else {
            preconditionFailure("The local endpoint must be a valid URL")
        }

        let inspector = SetupHealthInspector.live(endpoint: endpoint)
        let executor = SetupMutationExecutor.live()
        return SetupWorkflow(
            inspectionProvider: { [unowned runtime] in
                let usage = Dictionary(
                    uniqueKeysWithValues: AgentKind.allCases.map { agent in
                        (agent, runtime.usageStore.status(for: agent).availability)
                    }
                )
                return await inspector.inspect(
                    usage: usage,
                    events: runtime.store.snapshots
                )
            },
            operationExecutor: executor.execute
        )
    }

    var hasSeenWelcome: Bool {
        defaults.bool(forKey: Self.welcomeSeenKey)
    }

    func prepareForLaunch() async -> Bool {
        await refresh()
        guard let snapshot else {
            return !hasSeenWelcome
        }
        return SetupPresentationPolicy.shouldPresent(
            hasSeenWelcome: hasSeenWelcome,
            snapshot: snapshot
        )
    }

    func markWelcomeSeen() {
        defaults.set(true, forKey: Self.welcomeSeenKey)
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let snapshot = await inspectionProvider()
        self.snapshot = snapshot
        isRefreshing = false
    }

    func perform(_ operation: SetupOperation) async {
        guard activeOperation == nil else {
            return
        }

        if let snapshot, case .translocated = snapshot.application {
            notice = SetupOperationNotice(
                kind: .failure,
                message: "Setup changes are unavailable while the app is translocated.",
                recovery: "Move Agent Pulse to /Applications or ~/Applications, reopen it, and try again."
            )
            return
        }

        activeOperation = operation
        notice = nil
        do {
            let report = try await operationExecutor(operation)
            notice = SetupOperationNotice(
                kind: .success,
                message: report.message,
                recovery: nil
            )
        } catch let failure as SetupOperationFailure {
            notice = SetupOperationNotice(
                kind: .failure,
                message: failure.message,
                recovery: failure.recovery
            )
        } catch {
            notice = SetupOperationNotice(
                kind: .failure,
                message: error.localizedDescription,
                recovery: "Retry the operation. If it fails again, reopen Setup and review the reported status."
            )
        }
        activeOperation = nil
        await refresh()
    }

    func dismissNotice() {
        notice = nil
    }
}

struct SetupMutationExecutor {
    let execute: SetupWorkflow.OperationExecutor

    static func live(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> SetupMutationExecutor {
        let bridge = BridgeInstaller(
            homeDirectory: homeDirectory,
            bundleURL: bundleURL,
            fileManager: fileManager
        )
        let json = JSONHookConfigurationManager(
            configurationURL: homeDirectory.appendingPathComponent(".claude/settings.json"),
            bridgeExecutableURL: bridge.paths.installedExecutable,
            agentArgument: AgentKind.claude.rawValue,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )
        let toml = TOMLHookConfigurationManager(
            configurationURL: homeDirectory.appendingPathComponent(".codex/config.toml"),
            bridgeExecutableURL: bridge.paths.installedExecutable,
            agentArgument: AgentKind.codex.rawValue,
            homeDirectory: homeDirectory,
            fileManager: fileManager
        )

        return SetupMutationExecutor { operation in
            switch operation {
            case .installBridge:
                try installBridge(using: bridge)
                return SetupOperationReport(message: "The local bridge is installed and ready.")
            case .repairBridge:
                try repairBridge(using: bridge)
                return SetupOperationReport(message: "The local bridge was repaired successfully.")
            case .setUp(let agent):
                try installBridge(using: bridge)
                try applyIntegration(
                    agent: agent,
                    operation: .install,
                    json: json,
                    toml: toml
                )
                return SetupOperationReport(
                    message: "\(agent.displayName) was set up successfully."
                )
            case .repair(let agent):
                try repairBridge(using: bridge)
                try applyIntegration(
                    agent: agent,
                    operation: .install,
                    json: json,
                    toml: toml
                )
                return SetupOperationReport(
                    message: "\(agent.displayName) was repaired successfully."
                )
            case .remove(let agent):
                try applyIntegration(
                    agent: agent,
                    operation: .remove,
                    json: json,
                    toml: toml
                )
                return SetupOperationReport(
                    message: "The Agent Pulse hooks were removed from \(agent.displayName)."
                )
            }
        }
    }

    private enum IntegrationMutation {
        case install
        case remove
    }

    private static func installBridge(using bridge: BridgeInstaller) throws {
        do {
            _ = try bridge.install()
        } catch let error as BridgeInstallationError {
            throw bridgeFailure(error)
        }
    }

    private static func repairBridge(using bridge: BridgeInstaller) throws {
        do {
            _ = try bridge.repair()
        } catch let error as BridgeInstallationError {
            throw bridgeFailure(error)
        }
    }

    private static func bridgeFailure(
        _ error: BridgeInstallationError
    ) -> SetupOperationFailure {
        let message = error.errorDescription ?? "The local bridge could not be changed."
        let recovery: String
        switch error {
        case .appTranslocated:
            recovery = "Move Agent Pulse to /Applications or ~/Applications, reopen it, and retry."
        case .bundledExecutableMissing,
             .bundledExecutableInvalid,
             .bundledVersionInvalid:
            recovery = "Reinstall or rebuild the complete Agent Pulse app bundle, then reopen Setup."
        case .directoryCreationFailed:
            recovery = "Confirm your home folder is writable and that ~/.agent-pulse is owned by your account, then retry."
        case .copyFailed:
            recovery = "Confirm ~/.agent-pulse is writable and has available disk space, then retry."
        case .permissionUpdateFailed:
            recovery = "Restore ownership of ~/.agent-pulse to your account, then retry."
        case .replacementFailed:
            recovery = "Close other processes using the bridge, confirm ~/.agent-pulse is writable, and retry."
        case .removalFailed:
            recovery = "Close other processes using the bridge, confirm ~/.agent-pulse is writable, and retry removal."
        }
        return SetupOperationFailure(message: message, recovery: recovery)
    }

    private static func applyIntegration(
        agent: AgentKind,
        operation: IntegrationMutation,
        json: JSONHookConfigurationManager,
        toml: TOMLHookConfigurationManager
    ) throws {
        switch agent {
        case .claude:
            let result = json.apply(operation == .install ? .install : .remove)
            if let blocker = result.blocker {
                throw jsonFailure(
                    blocker,
                    configurationURL: result.resolvedTargetURL
                )
            }
        case .codex:
            let result = toml.apply(operation == .install ? .install : .remove)
            if let blocker = result.blocker {
                throw tomlFailure(
                    blocker,
                    configurationURL: result.resolvedTargetURL
                )
            }
        }
    }

    private static func jsonFailure(
        _ blocker: JSONHookConfigurationBlocker,
        configurationURL: URL
    ) -> SetupOperationFailure {
        let path = configurationURL.path
        switch blocker {
        case .readFailed:
            return failure("The Claude Code configuration could not be read.", path, "Confirm the file is readable")
        case .invalidJSON:
            return failure("The Claude Code configuration is not valid JSON.", path, "Correct the JSON syntax")
        case .rootIsNotObject:
            return failure("The Claude Code configuration must contain a JSON object.", path, "Replace the top-level value with an object")
        case .unsupportedHookStructure(let hookPath):
            return failure("The hook structure at \(hookPath) cannot be changed safely.", path, "Review that hook value")
        case .targetIsNotWritable:
            return failure("The Claude Code configuration is read-only.", path, "Restore write access")
        case .directoryCreationFailed:
            return failure("The Claude Code configuration directory could not be created.", path, "Confirm the parent directory is writable")
        case .backupFailed:
            return failure("The Claude Code configuration could not be backed up.", path, "Confirm the directory has enough space and is writable")
        case .serializationFailed:
            return failure("The updated Claude Code configuration could not be encoded.", path, "Retry after reopening Setup")
        case .permissionReadFailed:
            return failure("The Claude Code configuration permissions could not be read.", path, "Confirm the file is accessible")
        case .permissionUpdateFailed:
            return failure("The Claude Code configuration permissions could not be preserved.", path, "Restore owner read and write access")
        case .replacementFailed:
            return failure("The Claude Code configuration could not be replaced safely.", path, "Confirm the file and directory are writable")
        }
    }

    private static func tomlFailure(
        _ blocker: TOMLHookConfigurationBlocker,
        configurationURL: URL
    ) -> SetupOperationFailure {
        let path = configurationURL.path
        switch blocker {
        case .readFailed:
            return failure("The Codex configuration could not be read.", path, "Confirm the file is readable")
        case .malformedMarkers:
            return failure("The Agent Pulse markers in the Codex configuration are malformed.", path, "Review the BEGIN and END marker pair")
        case .targetIsNotWritable:
            return failure("The Codex configuration is read-only.", path, "Restore write access")
        case .directoryCreationFailed:
            return failure("The Codex configuration directory could not be created.", path, "Confirm the parent directory is writable")
        case .backupFailed:
            return failure("The Codex configuration could not be backed up.", path, "Confirm the directory has enough space and is writable")
        case .permissionReadFailed:
            return failure("The Codex configuration permissions could not be read.", path, "Confirm the file is accessible")
        case .permissionUpdateFailed:
            return failure("The Codex configuration permissions could not be preserved.", path, "Restore owner read and write access")
        case .replacementFailed:
            return failure("The Codex configuration could not be replaced safely.", path, "Confirm the file and directory are writable")
        }
    }

    private static func failure(
        _ message: String,
        _ path: String,
        _ nextStep: String
    ) -> SetupOperationFailure {
        SetupOperationFailure(
            message: message,
            recovery: "\(nextStep) at \(path), then retry. No unrelated settings were changed."
        )
    }
}
