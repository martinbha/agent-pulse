import Foundation

@testable import AgentPulseCore

struct SetupPresentationPolicySnapshot {
    var fresh: Bool
    var partial: Bool
    var complete: Bool
    var outdated: Bool
    var invalid: Bool
    var translocated: Bool
    var optionalMissingBridge: Bool
    var configuredMissingBridge: Bool
}

struct SetupIntegrationOperationsSnapshot {
    var missing: [SetupOperation]
    var current: [SetupOperation]
    var outdated: [SetupOperation]
    var invalid: [SetupOperation]
    var unavailable: [SetupOperation]
}

struct SetupMutationSnapshot {
    var executed: [SetupOperation]
    var inspectionCount: Int
    var noticeKind: SetupOperationNotice.Kind?
    var noticeMessage: String?
    var noticeRecovery: String?
    var isOperationComplete: Bool
    var hasSeenWelcome: Bool
}

struct SetupFailureSnapshot {
    var message: String
    var recovery: String
}

enum SetupWorkflowFixtures {
    @MainActor
    static func presentationStates() -> SetupPresentationPolicySnapshot {
        let complete = makeSnapshot()
        let partial = makeSnapshot(hooks: [.claude: .missing, .codex: .current])
        let outdated = makeSnapshot(
            bridge: .outdated(installedVersion: "0.9.0", bundledVersion: "1.0.0")
        )
        let invalid = makeSnapshot(hooks: [.claude: .invalid("Invalid JSON"), .codex: .current])
        let translocated = makeSnapshot(
            application: .translocated(
                URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/id/d/Agent Pulse.app")
            )
        )
        let optionalMissingBridge = makeSnapshot(
            bridge: .missing,
            hooks: [.claude: .missing, .codex: .missing]
        )
        let configuredMissingBridge = makeSnapshot(
            bridge: .missing,
            hooks: [.claude: .current, .codex: .missing]
        )

        return SetupPresentationPolicySnapshot(
            fresh: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: false,
                snapshot: complete
            ),
            partial: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: partial
            ),
            complete: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: complete
            ),
            outdated: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: outdated
            ),
            invalid: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: invalid
            ),
            translocated: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: translocated
            ),
            optionalMissingBridge: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: optionalMissingBridge
            ),
            configuredMissingBridge: SetupPresentationPolicy.shouldPresent(
                hasSeenWelcome: true,
                snapshot: configuredMissingBridge
            )
        )
    }

    static func integrationOperations() -> SetupIntegrationOperationsSnapshot {
        let available: IntegrationHostHealth = .available(
            location: URL(fileURLWithPath: "/usr/local/bin/tool")
        )
        return SetupIntegrationOperationsSnapshot(
            missing: SetupIntegrationOperations.available(
                for: integration(host: available, hooks: .missing)
            ),
            current: SetupIntegrationOperations.available(
                for: integration(host: available, hooks: .current)
            ),
            outdated: SetupIntegrationOperations.available(
                for: integration(host: available, hooks: .outdated)
            ),
            invalid: SetupIntegrationOperations.available(
                for: integration(host: available, hooks: .invalid("Malformed"))
            ),
            unavailable: SetupIntegrationOperations.available(
                for: integration(host: .unavailable, hooks: .missing)
            )
        )
    }

    @MainActor
    static func successfulMutation() async -> SetupMutationSnapshot {
        let defaults = makeDefaults()
        var inspectionCount = 0
        var executed: [SetupOperation] = []
        let workflow = SetupWorkflow(
            defaults: defaults,
            inspectionProvider: {
                inspectionCount += 1
                return makeSnapshot()
            },
            operationExecutor: { operation in
                executed.append(operation)
                return SetupOperationReport(message: "Finished")
            }
        )

        _ = await workflow.prepareForLaunch()
        workflow.markWelcomeSeen()
        await workflow.perform(.setUp(.claude))

        return SetupMutationSnapshot(
            executed: executed,
            inspectionCount: inspectionCount,
            noticeKind: workflow.notice?.kind,
            noticeMessage: workflow.notice?.message,
            noticeRecovery: workflow.notice?.recovery,
            isOperationComplete: workflow.activeOperation == nil,
            hasSeenWelcome: workflow.hasSeenWelcome
        )
    }

    @MainActor
    static func failedMutation() async -> SetupMutationSnapshot {
        let expected = SetupOperationFailure(
            message: "The configuration is read-only.",
            recovery: "Restore write access, then retry."
        )
        var inspectionCount = 0
        let workflow = SetupWorkflow(
            defaults: makeDefaults(),
            inspectionProvider: {
                inspectionCount += 1
                return makeSnapshot()
            },
            operationExecutor: { _ in throw expected }
        )

        await workflow.perform(.repair(.codex))
        return SetupMutationSnapshot(
            executed: [],
            inspectionCount: inspectionCount,
            noticeKind: workflow.notice?.kind,
            noticeMessage: workflow.notice?.message,
            noticeRecovery: workflow.notice?.recovery,
            isOperationComplete: workflow.activeOperation == nil,
            hasSeenWelcome: workflow.hasSeenWelcome
        )
    }

    @MainActor
    static func translocatedMutation() async -> SetupMutationSnapshot {
        var executed: [SetupOperation] = []
        var inspectionCount = 0
        let snapshot = makeSnapshot(
            application: .translocated(
                URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/id/d/Agent Pulse.app")
            )
        )
        let workflow = SetupWorkflow(
            defaults: makeDefaults(),
            inspectionProvider: {
                inspectionCount += 1
                return snapshot
            },
            operationExecutor: { operation in
                executed.append(operation)
                return SetupOperationReport(message: "Unexpected")
            }
        )

        await workflow.refresh()
        await workflow.perform(.remove(.claude))
        return SetupMutationSnapshot(
            executed: executed,
            inspectionCount: inspectionCount,
            noticeKind: workflow.notice?.kind,
            noticeMessage: workflow.notice?.message,
            noticeRecovery: workflow.notice?.recovery,
            isOperationComplete: workflow.activeOperation == nil,
            hasSeenWelcome: workflow.hasSeenWelcome
        )
    }

    @MainActor
    static func missingBundledBridgeFailure() async throws -> SetupFailureSnapshot {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("agent-pulse-setup-executor-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home", isDirectory: true)
        let bundle = root.appendingPathComponent("Agent Pulse.app", isDirectory: true)
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let executor = SetupMutationExecutor.live(
            homeDirectory: home,
            bundleURL: bundle,
            fileManager: fileManager
        )
        do {
            _ = try await executor.execute(.installBridge)
            return SetupFailureSnapshot(message: "", recovery: "")
        } catch let failure as SetupOperationFailure {
            return SetupFailureSnapshot(
                message: failure.message,
                recovery: failure.recovery
            )
        }
    }

    @MainActor
    private static func makeSnapshot(
        application: ApplicationLocationHealth = .applications(
            URL(fileURLWithPath: "/Applications/Agent Pulse.app")
        ),
        bridge: BridgeHealth = .current(version: "1.0.0"),
        hooks: [AgentKind: HookConfigurationHealth] = [
            .claude: .current,
            .codex: .current,
        ]
    ) -> SetupHealthSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let endpoint = URL(string: "http://127.0.0.1:37462")!
        let hosts = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { agent in
                (agent, IntegrationHostHealth.available(location: URL(fileURLWithPath: "/usr/bin/\(agent.rawValue)")))
            }
        )
        let usage = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { ($0, UsageAvailability.available) }
        )
        let events = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { agent in
                (
                    agent,
                    AgentStatusSnapshot(
                        agent: agent,
                        state: .done,
                        event: "Stop",
                        sessionID: nil,
                        cwd: nil,
                        project: nil,
                        updatedAt: now.addingTimeInterval(-10),
                        source: "hook"
                    )
                )
            }
        )
        return SetupHealthClassifier.makeSnapshot(
            inspectedAt: now,
            application: application,
            localServer: .healthy(endpoint: endpoint, version: "1.0.0"),
            bridge: bridge,
            hosts: hosts,
            hooks: hooks,
            usage: usage,
            events: events,
            notifications: .authorized,
            launchAtLogin: .enabled
        )
    }

    private static func integration(
        host: IntegrationHostHealth,
        hooks: HookConfigurationHealth
    ) -> IntegrationHealthSnapshot {
        IntegrationHealthSnapshot(
            agent: .claude,
            host: host,
            hooks: hooks,
            usage: .available,
            lastEvent: .never,
            recommendedAction: .none
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suite = "agent-pulse-setup-workflow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
