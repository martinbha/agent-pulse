import Foundation

enum ApplicationLocationHealth: Equatable, Sendable {
    case applications(URL)
    case userApplications(URL)
    case other(URL)
    case unbundled(URL)
    case translocated(URL)

    var bundleURL: URL {
        switch self {
        case .applications(let url),
             .userApplications(let url),
             .other(let url),
             .unbundled(let url),
             .translocated(let url):
            return url
        }
    }
}

enum LocalServerHealth: Equatable, Sendable {
    case healthy(endpoint: URL, version: String)
    case unreachable(endpoint: URL, reason: String)
    case invalidResponse(endpoint: URL, reason: String)

    var endpoint: URL {
        switch self {
        case .healthy(let endpoint, _),
             .unreachable(let endpoint, _),
             .invalidResponse(let endpoint, _):
            return endpoint
        }
    }
}

enum BridgeHealth: Equatable, Sendable {
    case missing
    case current(version: String)
    case outdated(installedVersion: String?, bundledVersion: String)
    case unreadable(String)
    case invalid(String)
}

enum IntegrationHostHealth: Equatable, Sendable {
    case available(applicationURL: URL)
    case unavailable
}

enum HookConfigurationHealth: Equatable, Sendable {
    case missing
    case current
    case outdated
    case duplicated(ownedEntryCount: Int)
    case invalid(String)
}

enum LastIntegrationEventHealth: Equatable, Sendable {
    case never
    case received(event: String, timestamp: Date, age: TimeInterval)
}

enum NotificationAuthorizationHealth: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unavailable(String)
}

enum LaunchAtLoginHealth: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case unavailable(String)
}

enum SetupRecommendedAction: Equatable, Sendable {
    case moveApplication
    case restartLocalServer
    case installBridge
    case repairBridge
    case installHost(AgentKind)
    case installIntegration(AgentKind)
    case repairIntegration(AgentKind)
    case reviewIntegrationConfiguration(AgentKind)
    case signIn(AgentKind)
    case testIntegration(AgentKind)
    case requestNotificationPermission
    case openNotificationSettings
    case approveLaunchAtLogin
    case none
}

struct SetupBlockingIssue: Equatable, Sendable {
    let action: SetupRecommendedAction
    let message: String
}

struct IntegrationHealthSnapshot: Equatable, Identifiable, Sendable {
    let agent: AgentKind
    let host: IntegrationHostHealth
    let hooks: HookConfigurationHealth
    let usage: UsageAvailability
    let lastEvent: LastIntegrationEventHealth
    let recommendedAction: SetupRecommendedAction

    var id: AgentKind { agent }
}

struct SetupHealthSnapshot: Equatable, Sendable {
    let inspectedAt: Date
    let application: ApplicationLocationHealth
    let localServer: LocalServerHealth
    let bridge: BridgeHealth
    let integrations: [IntegrationHealthSnapshot]
    let notifications: NotificationAuthorizationHealth
    let launchAtLogin: LaunchAtLoginHealth
    let recommendedAction: SetupRecommendedAction
    let blockingIssue: SetupBlockingIssue?

    func integration(for agent: AgentKind) -> IntegrationHealthSnapshot? {
        integrations.first { $0.agent == agent }
    }
}

enum SetupHealthClassifier {
    static func applicationLocation(
        bundleURL: URL,
        homeDirectory: URL
    ) -> ApplicationLocationHealth {
        let bundle = bundleURL.standardizedFileURL
        if BridgeInstaller.isAppTranslocated(bundle) {
            return .translocated(bundle)
        }
        guard bundle.pathExtension.lowercased() == "app" else {
            return .unbundled(bundle)
        }

        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .standardizedFileURL.path
        let userApplications = homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL.path
        if isDescendant(bundle.path, of: systemApplications) {
            return .applications(bundle)
        }
        if isDescendant(bundle.path, of: userApplications) {
            return .userApplications(bundle)
        }
        return .other(bundle)
    }

    static func makeSnapshot(
        inspectedAt: Date,
        application: ApplicationLocationHealth,
        localServer: LocalServerHealth,
        bridge: BridgeHealth,
        hosts: [AgentKind: IntegrationHostHealth],
        hooks: [AgentKind: HookConfigurationHealth],
        usage: [AgentKind: UsageAvailability],
        events: [AgentKind: AgentStatusSnapshot],
        notifications: NotificationAuthorizationHealth,
        launchAtLogin: LaunchAtLoginHealth
    ) -> SetupHealthSnapshot {
        let integrations = AgentKind.allCases.map { agent in
            let host = hosts[agent] ?? .unavailable
            let hook = hooks[agent] ?? .missing
            let availability = usage[agent] ?? .loading
            let lastEvent = lastEventHealth(from: events[agent], inspectedAt: inspectedAt)
            return IntegrationHealthSnapshot(
                agent: agent,
                host: host,
                hooks: hook,
                usage: availability,
                lastEvent: lastEvent,
                recommendedAction: integrationAction(
                    agent: agent,
                    host: host,
                    hooks: hook,
                    usage: availability,
                    lastEvent: lastEvent
                )
            )
        }

        let decision = setupDecision(
            application: application,
            localServer: localServer,
            bridge: bridge,
            integrations: integrations,
            notifications: notifications,
            launchAtLogin: launchAtLogin
        )
        return SetupHealthSnapshot(
            inspectedAt: inspectedAt,
            application: application,
            localServer: localServer,
            bridge: bridge,
            integrations: integrations,
            notifications: notifications,
            launchAtLogin: launchAtLogin,
            recommendedAction: decision.action,
            blockingIssue: decision.blockingIssue
        )
    }

    private static func setupDecision(
        application: ApplicationLocationHealth,
        localServer: LocalServerHealth,
        bridge: BridgeHealth,
        integrations: [IntegrationHealthSnapshot],
        notifications: NotificationAuthorizationHealth,
        launchAtLogin: LaunchAtLoginHealth
    ) -> (action: SetupRecommendedAction, blockingIssue: SetupBlockingIssue?) {
        if case .translocated = application {
            return blocked(
                action: .moveApplication,
                message: "Move the application to /Applications or ~/Applications before changing integrations."
            )
        }

        switch localServer {
        case .healthy:
            break
        case .unreachable(_, let reason), .invalidResponse(_, let reason):
            return blocked(
                action: .restartLocalServer,
                message: "The local event server is unavailable. Restart the application. \(reason)"
            )
        }

        switch bridge {
        case .current:
            break
        case .missing:
            return blocked(
                action: .installBridge,
                message: "Install the local bridge before configuring integrations."
            )
        case .outdated:
            return blocked(
                action: .repairBridge,
                message: "Upgrade the installed bridge to match this application version."
            )
        case .unreadable(let reason), .invalid(let reason):
            return blocked(
                action: .repairBridge,
                message: "Repair the installed bridge. \(reason)"
            )
        }

        if let missingHost = integrations.first(where: { $0.host == .unavailable }) {
            return (.installHost(missingHost.agent), nil)
        }

        for integration in integrations {
            switch integration.hooks {
            case .invalid(let reason):
                return blocked(
                    action: .reviewIntegrationConfiguration(integration.agent),
                    message: "Review the integration configuration before continuing. \(reason)"
                )
            case .missing:
                return blocked(
                    action: .installIntegration(integration.agent),
                    message: "Install the missing integration configuration."
                )
            case .outdated, .duplicated:
                return blocked(
                    action: .repairIntegration(integration.agent),
                    message: "Repair the integration configuration."
                )
            case .current:
                break
            }
        }

        if let action = integrations.map(\.recommendedAction).first(where: { $0 != .none }) {
            return (action, nil)
        }

        switch notifications {
        case .notDetermined:
            return (.requestNotificationPermission, nil)
        case .denied:
            return (.openNotificationSettings, nil)
        case .authorized, .provisional, .ephemeral, .unavailable:
            break
        }

        if launchAtLogin == .requiresApproval {
            return (.approveLaunchAtLogin, nil)
        }
        return (.none, nil)
    }

    private static func integrationAction(
        agent: AgentKind,
        host: IntegrationHostHealth,
        hooks: HookConfigurationHealth,
        usage: UsageAvailability,
        lastEvent: LastIntegrationEventHealth
    ) -> SetupRecommendedAction {
        if host == .unavailable {
            return .installHost(agent)
        }
        switch hooks {
        case .missing:
            return .installIntegration(agent)
        case .outdated, .duplicated:
            return .repairIntegration(agent)
        case .invalid:
            return .reviewIntegrationConfiguration(agent)
        case .current:
            break
        }
        switch usage {
        case .missingAuth, .accessDenied, .sessionExpired, .notLoggedIn:
            return .signIn(agent)
        case .notInstalled:
            return .installHost(agent)
        case .loading, .available, .error:
            break
        }
        if lastEvent == .never {
            return .testIntegration(agent)
        }
        return .none
    }

    private static func lastEventHealth(
        from snapshot: AgentStatusSnapshot?,
        inspectedAt: Date
    ) -> LastIntegrationEventHealth {
        guard let snapshot, snapshot.updatedAt != .distantPast else {
            return .never
        }
        return .received(
            event: snapshot.event,
            timestamp: snapshot.updatedAt,
            age: max(0, inspectedAt.timeIntervalSince(snapshot.updatedAt))
        )
    }

    private static func blocked(
        action: SetupRecommendedAction,
        message: String
    ) -> (action: SetupRecommendedAction, blockingIssue: SetupBlockingIssue?) {
        (action, SetupBlockingIssue(action: action, message: message))
    }

    private static func isDescendant(_ path: String, of directory: String) -> Bool {
        path == directory || path.hasPrefix(directory + "/")
    }
}

enum SetupHealthDiagnosticsRenderer {
    static func lines(for snapshot: SetupHealthSnapshot) -> [String] {
        var lines = [
            "Application: \(applicationSummary(snapshot.application))",
            "Local server: \(serverSummary(snapshot.localServer))",
            "Bridge: \(bridgeSummary(snapshot.bridge))",
        ]
        for integration in snapshot.integrations {
            lines.append(
                "\(integration.agent.displayName): host \(hostSummary(integration.host)); "
                    + "hooks \(hookSummary(integration.hooks)); "
                    + "usage \(usageSummary(integration.usage)); "
                    + "last event \(eventSummary(integration.lastEvent))"
            )
        }
        lines += [
            "Notifications: \(String(describing: snapshot.notifications))",
            "Launch at Login: \(String(describing: snapshot.launchAtLogin))",
        ]
        if let issue = snapshot.blockingIssue {
            lines.append("Action required: \(issue.message)")
        }
        return lines
    }

    private static func applicationSummary(_ health: ApplicationLocationHealth) -> String {
        switch health {
        case .applications(let url): return "installed at \(url.path)"
        case .userApplications(let url): return "installed at \(url.path)"
        case .other(let url): return "running from \(url.path)"
        case .unbundled(let url): return "development executable at \(url.path)"
        case .translocated(let url): return "translocated at \(url.path)"
        }
    }

    private static func serverSummary(_ health: LocalServerHealth) -> String {
        switch health {
        case .healthy(let endpoint, let version):
            return "healthy at \(endpoint.absoluteString) (version \(version))"
        case .unreachable(let endpoint, let reason):
            return "unreachable at \(endpoint.absoluteString): \(reason)"
        case .invalidResponse(let endpoint, let reason):
            return "invalid response from \(endpoint.absoluteString): \(reason)"
        }
    }

    private static func bridgeSummary(_ health: BridgeHealth) -> String {
        switch health {
        case .missing: return "missing"
        case .current(let version): return "current (version \(version))"
        case .outdated(let installed, let bundled):
            return "outdated (installed \(installed ?? "unknown"), bundled \(bundled))"
        case .unreadable(let reason): return "unreadable: \(reason)"
        case .invalid(let reason): return "invalid: \(reason)"
        }
    }

    private static func hostSummary(_ health: IntegrationHostHealth) -> String {
        switch health {
        case .available(let url): return "available at \(url.path)"
        case .unavailable: return "unavailable"
        }
    }

    private static func hookSummary(_ health: HookConfigurationHealth) -> String {
        switch health {
        case .missing: return "missing"
        case .current: return "current"
        case .outdated: return "outdated"
        case .duplicated(let count): return "duplicated (\(count) owned entries)"
        case .invalid(let reason): return "invalid: \(reason)"
        }
    }

    private static func usageSummary(_ availability: UsageAvailability) -> String {
        switch availability {
        case .loading: return "loading"
        case .available: return "available"
        case .missingAuth: return "missing authentication"
        case .accessDenied: return "access denied"
        case .sessionExpired: return "session expired"
        case .notInstalled: return "host not installed"
        case .notLoggedIn: return "not logged in"
        case .error(let message): return "error: \(message)"
        }
    }

    private static func eventSummary(_ health: LastIntegrationEventHealth) -> String {
        switch health {
        case .never: return "never"
        case .received(let event, let timestamp, let age):
            return "\(event) at \(timestamp) (\(Int(age)) seconds ago)"
        }
    }
}
