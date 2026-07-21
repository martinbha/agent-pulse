import Foundation

@testable import AgentPulseCore

struct SetupLocationSnapshot {
    var systemApplications: ApplicationLocationHealth
    var userApplications: ApplicationLocationHealth
    var otherBundle: ApplicationLocationHealth
    var unbundled: ApplicationLocationHealth
    var translocated: ApplicationLocationHealth
}

struct SetupTransitionSnapshot {
    var translocatedAction: SetupRecommendedAction
    var serverFailureAction: SetupRecommendedAction
    var missingBridgeAction: SetupRecommendedAction
    var missingHostAction: SetupRecommendedAction
    var missingHooksAction: SetupRecommendedAction
    var completedAction: SetupRecommendedAction
    var outdatedBridgeAction: SetupRecommendedAction
    var duplicatedHooksAction: SetupRecommendedAction
    var invalidHooksAction: SetupRecommendedAction
    var unsafeConfigurationAction: SetupRecommendedAction
    var removedHooksAction: SetupRecommendedAction
    var signInAction: SetupRecommendedAction
    var testAction: SetupRecommendedAction
    var notificationAction: SetupRecommendedAction
    var loginAction: SetupRecommendedAction
    var completeBlockingIssue: SetupBlockingIssue?
    var lastEventName: String?
    var lastEventAge: TimeInterval?
}

struct SetupAdapterSnapshot {
    var missingBridge: BridgeHealth
    var currentBridge: BridgeHealth
    var outdatedBridge: BridgeHealth
    var unreadableBridge: BridgeHealth
    var invalidBridge: BridgeHealth
    var missingJSON: HookConfigurationHealth
    var currentJSON: HookConfigurationHealth
    var duplicateJSON: HookConfigurationHealth
    var invalidJSON: HookConfigurationHealth
    var missingTOML: HookConfigurationHealth
    var currentTOML: HookConfigurationHealth
    var duplicateTOML: HookConfigurationHealth
    var invalidTOML: HookConfigurationHealth
}

struct SetupInspectionSnapshot {
    var inspectedAtEpoch: TimeInterval
    var application: ApplicationLocationHealth
    var serverIsHealthy: Bool
    var bridge: BridgeHealth
    var firstHost: IntegrationHostHealth?
    var secondHooks: HookConfigurationHealth?
    var firstUsage: SetupUsageHealth?
    var notifications: NotificationAuthorizationHealth
    var launchAtLogin: LaunchAtLoginHealth
    var lastEvent: LastIntegrationEventHealth?
    var diagnosticsContainSecret: Bool
    var inputsUnchanged: Bool
}

enum SetupHealthFixtures {
    private static let endpoint = URL(string: "http://127.0.0.1:37462")!
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func applicationLocations() -> SetupLocationSnapshot {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        return SetupLocationSnapshot(
            systemApplications: SetupHealthClassifier.applicationLocation(
                bundleURL: URL(fileURLWithPath: "/Applications/Status App.app"),
                homeDirectory: home
            ),
            userApplications: SetupHealthClassifier.applicationLocation(
                bundleURL: URL(fileURLWithPath: "/Users/example/Applications/Status App.app"),
                homeDirectory: home
            ),
            otherBundle: SetupHealthClassifier.applicationLocation(
                bundleURL: URL(fileURLWithPath: "/Volumes/Tools/Status App.app"),
                homeDirectory: home
            ),
            unbundled: SetupHealthClassifier.applicationLocation(
                bundleURL: URL(fileURLWithPath: "/tmp/.build/debug/status-app"),
                homeDirectory: home
            ),
            translocated: SetupHealthClassifier.applicationLocation(
                bundleURL: URL(
                    fileURLWithPath: "/private/var/folders/x/AppTranslocation/id/d/Status App.app"
                ),
                homeDirectory: home
            )
        )
    }

    static func setupTransitions() -> SetupTransitionSnapshot {
        let application: ApplicationLocationHealth = .applications(
            URL(fileURLWithPath: "/Applications/Status App.app")
        )
        let healthyServer: LocalServerHealth = .healthy(endpoint: endpoint, version: "1.0.0")
        let currentBridge: BridgeHealth = .current(version: "1.0.0")
        let hosts = availableHosts()
        let currentHooks = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { ($0, HookConfigurationHealth.current) }
        )
        let missingHooks = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { ($0, HookConfigurationHealth.missing) }
        )
        let availableUsage = Dictionary(
            uniqueKeysWithValues: AgentKind.allCases.map { ($0, UsageAvailability.available) }
        )
        let events = recentEvents()

        func snapshot(
            application overrideApplication: ApplicationLocationHealth? = nil,
            server: LocalServerHealth? = nil,
            bridge: BridgeHealth? = nil,
            hosts overrideHosts: [AgentKind: IntegrationHostHealth]? = nil,
            hooks: [AgentKind: HookConfigurationHealth]? = nil,
            usage: [AgentKind: UsageAvailability]? = nil,
            events overrideEvents: [AgentKind: AgentStatusSnapshot]? = nil,
            notifications: NotificationAuthorizationHealth = .authorized,
            launchAtLogin: LaunchAtLoginHealth = .enabled
        ) -> SetupHealthSnapshot {
            SetupHealthClassifier.makeSnapshot(
                inspectedAt: now,
                application: overrideApplication ?? application,
                localServer: server ?? healthyServer,
                bridge: bridge ?? currentBridge,
                hosts: overrideHosts ?? hosts,
                hooks: hooks ?? currentHooks,
                usage: usage ?? availableUsage,
                events: overrideEvents ?? events,
                notifications: notifications,
                launchAtLogin: launchAtLogin
            )
        }

        var oneHostMissing = hosts
        oneHostMissing[.codex] = .unavailable
        var duplicatedHooks = currentHooks
        duplicatedHooks[.codex] = .duplicated(ownedEntryCount: 2)
        var invalidHooks = currentHooks
        invalidHooks[.codex] = .invalid("The marker block is malformed.")
        var removedHooks = currentHooks
        removedHooks[.codex] = .missing
        var missingAuth = availableUsage
        missingAuth[.claude] = .missingAuth
        var missingEvent = events
        missingEvent[.claude] = .idle(agent: .claude)

        let complete = snapshot()
        return SetupTransitionSnapshot(
            translocatedAction: snapshot(
                application: .translocated(
                    URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/id/d/Status App.app")
                )
            ).recommendedAction,
            serverFailureAction: snapshot(
                server: .unreachable(endpoint: endpoint, reason: "Connection refused.")
            ).recommendedAction,
            missingBridgeAction: snapshot(bridge: .missing).recommendedAction,
            missingHostAction: snapshot(hosts: oneHostMissing).recommendedAction,
            missingHooksAction: snapshot(hooks: missingHooks).recommendedAction,
            completedAction: complete.recommendedAction,
            outdatedBridgeAction: snapshot(
                bridge: .outdated(installedVersion: "0.9.0", bundledVersion: "1.0.0")
            ).recommendedAction,
            duplicatedHooksAction: snapshot(hooks: duplicatedHooks).recommendedAction,
            invalidHooksAction: snapshot(hooks: invalidHooks).recommendedAction,
            unsafeConfigurationAction: snapshot(
                hosts: oneHostMissing,
                hooks: invalidHooks
            ).recommendedAction,
            removedHooksAction: snapshot(hooks: removedHooks).recommendedAction,
            signInAction: snapshot(usage: missingAuth).recommendedAction,
            testAction: snapshot(events: missingEvent).recommendedAction,
            notificationAction: snapshot(notifications: .notDetermined).recommendedAction,
            loginAction: snapshot(launchAtLogin: .requiresApproval).recommendedAction,
            completeBlockingIssue: complete.blockingIssue,
            lastEventName: eventName(from: complete.integration(for: .claude)?.lastEvent),
            lastEventAge: eventAge(from: complete.integration(for: .claude)?.lastEvent)
        )
    }

    static func adapters() -> SetupAdapterSnapshot {
        let configurationURL = URL(fileURLWithPath: "/tmp/settings")
        let unchangedJSON = JSONHookConfigurationResult(
            configurationURL: configurationURL,
            resolvedTargetURL: configurationURL,
            changes: [
                JSONHookConfigurationChange(event: "Event", kind: .unchanged, ownedEntryCount: 1),
            ],
            didWrite: false,
            backupURL: nil,
            blocker: nil
        )
        let missingJSON = JSONHookConfigurationResult(
            configurationURL: configurationURL,
            resolvedTargetURL: configurationURL,
            changes: [
                JSONHookConfigurationChange(event: "Event", kind: .added, ownedEntryCount: 0),
            ],
            didWrite: false,
            backupURL: nil,
            blocker: nil
        )
        let duplicateJSON = JSONHookConfigurationResult(
            configurationURL: configurationURL,
            resolvedTargetURL: configurationURL,
            changes: [
                JSONHookConfigurationChange(event: "Event", kind: .updated, ownedEntryCount: 2),
            ],
            didWrite: false,
            backupURL: nil,
            blocker: nil
        )
        let invalidJSON = JSONHookConfigurationResult(
            configurationURL: configurationURL,
            resolvedTargetURL: configurationURL,
            changes: [],
            didWrite: false,
            backupURL: nil,
            blocker: .invalidJSON
        )

        func tomlResult(
            kind: TOMLHookConfigurationChangeKind,
            managed: Int,
            legacy: Int,
            blocker: TOMLHookConfigurationBlocker? = nil
        ) -> TOMLHookConfigurationResult {
            TOMLHookConfigurationResult(
                configurationURL: configurationURL,
                resolvedTargetURL: configurationURL,
                change: TOMLHookConfigurationChange(
                    kind: kind,
                    managedBlockCount: managed,
                    legacyBlockCount: legacy
                ),
                didWrite: false,
                backupURL: nil,
                blocker: blocker
            )
        }

        return SetupAdapterSnapshot(
            missingBridge: SetupHealthInspector.bridgeHealth(from: .missing),
            currentBridge: SetupHealthInspector.bridgeHealth(from: .current(version: "1.0.0")),
            outdatedBridge: SetupHealthInspector.bridgeHealth(
                from: .outdated(installedVersion: "0.9.0", bundledVersion: "1.0.0")
            ),
            unreadableBridge: SetupHealthInspector.bridgeHealth(
                from: .damaged(reason: "The installed bridge cannot be executed.")
            ),
            invalidBridge: SetupHealthInspector.bridgeHealth(
                from: .damaged(reason: "The installed bridge permissions are not 0755.")
            ),
            missingJSON: SetupHealthInspector.jsonHookHealth(from: missingJSON),
            currentJSON: SetupHealthInspector.jsonHookHealth(from: unchangedJSON),
            duplicateJSON: SetupHealthInspector.jsonHookHealth(from: duplicateJSON),
            invalidJSON: SetupHealthInspector.jsonHookHealth(from: invalidJSON),
            missingTOML: SetupHealthInspector.tomlHookHealth(
                from: tomlResult(kind: .added, managed: 0, legacy: 0)
            ),
            currentTOML: SetupHealthInspector.tomlHookHealth(
                from: tomlResult(kind: .unchanged, managed: 1, legacy: 0)
            ),
            duplicateTOML: SetupHealthInspector.tomlHookHealth(
                from: tomlResult(kind: .updated, managed: 1, legacy: 1)
            ),
            invalidTOML: SetupHealthInspector.tomlHookHealth(
                from: tomlResult(
                    kind: .unchanged,
                    managed: 0,
                    legacy: 0,
                    blocker: .malformedMarkers(.unterminatedRegion)
                )
            )
        )
    }

    static func asynchronousInspection() async -> SetupInspectionSnapshot {
        let application: ApplicationLocationHealth = .applications(
            URL(fileURLWithPath: "/Applications/Status App.app")
        )
        let server: LocalServerHealth = .healthy(endpoint: endpoint, version: "1.0.0")
        let usage: [AgentKind: UsageAvailability] = [
            .claude: .error("Bearer private-token"),
            .codex: .available,
        ]
        let event = AgentStatusSnapshot(
            agent: .claude,
            state: .working,
            event: "Working",
            sessionID: "private-token",
            cwd: "/private/private-token",
            project: "private-token",
            updatedAt: now.addingTimeInterval(-45),
            source: "private-token"
        )
        let events: [AgentKind: AgentStatusSnapshot] = [.claude: event]
        let originalUsage = usage
        let originalEvents = events

        let inspector = SetupHealthInspector(
            now: { now },
            applicationProvider: { application },
            localServerProvider: { server },
            bridgeProvider: { .current(version: "1.0.0") },
            hostProvider: { agent in
                .available(location: URL(fileURLWithPath: "/Applications/\(agent.rawValue).app"))
            },
            hookProvider: { _ in .current },
            notificationProvider: { .authorized },
            launchAtLoginProvider: { .enabled }
        )

        let snapshot = await inspector.inspect(usage: usage, events: events)
        let diagnostics = SetupHealthDiagnosticsRenderer.lines(for: snapshot).joined(separator: "\n")
        return SetupInspectionSnapshot(
            inspectedAtEpoch: snapshot.inspectedAt.timeIntervalSince1970,
            application: snapshot.application,
            serverIsHealthy: {
                if case .healthy = snapshot.localServer { return true }
                return false
            }(),
            bridge: snapshot.bridge,
            firstHost: snapshot.integration(for: .claude)?.host,
            secondHooks: snapshot.integration(for: .codex)?.hooks,
            firstUsage: snapshot.integration(for: .claude)?.usage,
            notifications: snapshot.notifications,
            launchAtLogin: snapshot.launchAtLogin,
            lastEvent: snapshot.integration(for: .claude)?.lastEvent,
            diagnosticsContainSecret: diagnostics.contains("private-token"),
            inputsUnchanged: usage == originalUsage && events == originalEvents
        )
    }

    private static func availableHosts() -> [AgentKind: IntegrationHostHealth] {
        Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { agent in
            (
                agent,
                .available(
                    location: URL(fileURLWithPath: "/Applications/\(agent.rawValue).app")
                )
            )
        })
    }

    private static func eventName(from health: LastIntegrationEventHealth?) -> String? {
        guard case .received(let event, _, _) = health else { return nil }
        return event
    }

    private static func eventAge(from health: LastIntegrationEventHealth?) -> TimeInterval? {
        guard case .received(_, _, let age) = health else { return nil }
        return age
    }

    private static func recentEvents() -> [AgentKind: AgentStatusSnapshot] {
        Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { agent in
            (
                agent,
                AgentStatusSnapshot(
                    agent: agent,
                    state: .done,
                    event: "Stop",
                    sessionID: "session",
                    cwd: "/tmp/project",
                    project: "project",
                    updatedAt: now.addingTimeInterval(-60),
                    source: "hook"
                )
            )
        })
    }
}
