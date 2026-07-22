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
    var currentCanTest: Bool
    var missingCanTest: Bool
}

struct SetupIntegrationStatesSnapshot {
    var connected: SetupIntegrationState
    var waitingForEvent: SetupIntegrationState
    var bridgeUnavailable: SetupIntegrationState
    var hostUnavailable: SetupIntegrationState
    var missing: SetupIntegrationState
    var outdated: SetupIntegrationState
    var invalid: SetupIntegrationState
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

struct SetupSelfTestSnapshot {
    var executed: [SetupOperation]
    var inspectionCount: Int
    var noticeKind: SetupOperationNotice.Kind?
    var noticeMessage: String?
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
        let missing = integration(host: available, hooks: .missing)
        let current = integration(host: available, hooks: .current)
        return SetupIntegrationOperationsSnapshot(
            missing: SetupIntegrationOperations.available(for: missing),
            current: SetupIntegrationOperations.available(for: current),
            outdated: SetupIntegrationOperations.available(
                for: integration(host: available, hooks: .outdated)
            ),
            invalid: SetupIntegrationOperations.available(
                for: integration(host: available, hooks: .invalid("Malformed"))
            ),
            unavailable: SetupIntegrationOperations.available(
                for: integration(host: .unavailable, hooks: .missing)
            ),
            currentCanTest: SetupIntegrationOperations.canTest(current),
            missingCanTest: SetupIntegrationOperations.canTest(missing)
        )
    }

    static func integrationStates() -> SetupIntegrationStatesSnapshot {
        let available: IntegrationHostHealth = .available(
            location: URL(fileURLWithPath: "/usr/local/bin/tool")
        )
        let current = integration(
            host: available,
            hooks: .current,
            lastEvent: .received(
                event: "Stop",
                timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                age: 10
            )
        )
        let waiting = integration(host: available, hooks: .current)
        return SetupIntegrationStatesSnapshot(
            connected: SetupIntegrationStateResolver.state(
                for: current,
                bridge: .current(version: "1.0.0")
            ),
            waitingForEvent: SetupIntegrationStateResolver.state(
                for: waiting,
                bridge: .current(version: "1.0.0")
            ),
            bridgeUnavailable: SetupIntegrationStateResolver.state(
                for: current,
                bridge: .missing
            ),
            hostUnavailable: SetupIntegrationStateResolver.state(
                for: integration(host: .unavailable, hooks: .current),
                bridge: .current(version: "1.0.0")
            ),
            missing: SetupIntegrationStateResolver.state(
                for: integration(host: available, hooks: .missing),
                bridge: .missing
            ),
            outdated: SetupIntegrationStateResolver.state(
                for: integration(host: available, hooks: .outdated),
                bridge: .missing
            ),
            invalid: SetupIntegrationStateResolver.state(
                for: integration(host: available, hooks: .invalid("Malformed")),
                bridge: .missing
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
    static func successfulSelfTest() async -> SetupSelfTestSnapshot {
        var inspectionCount = 0
        var executed: [SetupOperation] = []
        let workflow = SetupWorkflow(
            defaults: makeDefaults(),
            inspectionProvider: {
                inspectionCount += 1
                return makeSnapshot()
            },
            operationExecutor: { operation in
                executed.append(operation)
                return SetupOperationReport(message: "Delivery verified")
            }
        )

        await workflow.perform(.test(.codex))
        return SetupSelfTestSnapshot(
            executed: executed,
            inspectionCount: inspectionCount,
            noticeKind: workflow.testNotices[.codex]?.kind,
            noticeMessage: workflow.testNotices[.codex]?.message
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
        hooks: HookConfigurationHealth,
        lastEvent: LastIntegrationEventHealth = .never
    ) -> IntegrationHealthSnapshot {
        IntegrationHealthSnapshot(
            agent: .claude,
            host: host,
            hooks: hooks,
            usage: .available,
            lastEvent: lastEvent,
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
