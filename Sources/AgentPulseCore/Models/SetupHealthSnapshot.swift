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
    case available(location: URL)
    case unavailable
}

enum HookConfigurationHealth: Equatable, Sendable {
    case missing
    case current
    case outdated
    case duplicated(ownedEntryCount: Int)
    case invalid(String)
}

enum HookTrustHealth: Equatable, Sendable {
    case notApplicable
    case verified(trusted: Int, managed: Int, total: Int)
    case needsReview(untrusted: Int, modified: Int, total: Int)
    case disabled(disabled: Int, total: Int)
    case missing(found: Int, expected: Int)
    case unavailable(String)
}

enum SetupUsageHealth: Equatable, Sendable {
    case loading
    case available
    case missingAuth
    case accessDenied
    case sessionExpired
    case notInstalled
    case notLoggedIn
    case error
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
    case reviewHookTrust(AgentKind)
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
    let hookTrust: HookTrustHealth
    let usage: SetupUsageHealth
    let lastEvent: LastIntegrationEventHealth
    let recommendedAction: SetupRecommendedAction

    var id: AgentKind { agent }

    init(
        agent: AgentKind,
        host: IntegrationHostHealth,
        hooks: HookConfigurationHealth,
        hookTrust: HookTrustHealth = .notApplicable,
        usage: SetupUsageHealth,
        lastEvent: LastIntegrationEventHealth,
        recommendedAction: SetupRecommendedAction
    ) {
        self.agent = agent
        self.host = host
        self.hooks = hooks
        self.hookTrust = hookTrust
        self.usage = usage
        self.lastEvent = lastEvent
        self.recommendedAction = recommendedAction
    }
}

struct SetupHealthSnapshot: Equatable, Sendable {
    let inspectedAt: Date
    let application: ApplicationLocationHealth
    let localServer: LocalServerHealth
    let bridge: BridgeHealth
    let integrations: [IntegrationHealthSnapshot]
    let notifications: NotificationAuthorizationHealth
    let notificationHelpers: [AgentKind: NotificationAuthorizationHealth]
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
        hookTrust: [AgentKind: HookTrustHealth] = [:],
        usage: [AgentKind: UsageAvailability],
        events: [AgentKind: AgentStatusSnapshot],
        notifications: NotificationAuthorizationHealth,
        notificationHelpers: [AgentKind: NotificationAuthorizationHealth] = [:],
        launchAtLogin: LaunchAtLoginHealth
    ) -> SetupHealthSnapshot {
        let integrations = AgentKind.allCases.map { agent in
            let host = hosts[agent] ?? .unavailable
            let hook = hooks[agent] ?? .missing
            let availability = setupUsageHealth(from: usage[agent] ?? .loading)
            let lastEvent = lastEventHealth(from: events[agent], inspectedAt: inspectedAt)
            return IntegrationHealthSnapshot(
                agent: agent,
                host: host,
                hooks: hook,
                hookTrust: hookTrust[agent] ?? .notApplicable,
                usage: availability,
                lastEvent: lastEvent,
                recommendedAction: integrationAction(
                    agent: agent,
                    host: host,
                    hooks: hook,
                    hookTrust: hookTrust[agent] ?? .notApplicable,
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
            notificationHelpers: notificationHelpers,
            launchAtLogin: launchAtLogin
        )
        return SetupHealthSnapshot(
            inspectedAt: inspectedAt,
            application: application,
            localServer: localServer,
            bridge: bridge,
            integrations: integrations,
            notifications: notifications,
            notificationHelpers: notificationHelpers,
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
        notificationHelpers: [AgentKind: NotificationAuthorizationHealth],
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

        for integration in integrations {
            if case .invalid(let reason) = integration.hooks {
                return blocked(
                    action: .reviewIntegrationConfiguration(integration.agent),
                    message: "Review the integration configuration before continuing. \(reason)"
                )
            }
        }

        if let missingHost = integrations.first(where: { $0.host == .unavailable }) {
            return (.installHost(missingHost.agent), nil)
        }

        for integration in integrations {
            switch integration.hooks {
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
            case .current, .invalid:
                break
            }
        }

        if let trustReview = integrations.first(where: { integration in
            switch integration.hookTrust {
            case .needsReview, .disabled, .missing, .unavailable:
                return true
            case .notApplicable, .verified:
                return false
            }
        }) {
            return (.reviewHookTrust(trustReview.agent), nil)
        }

        if let action = integrations.map(\.recommendedAction).first(where: { $0 != .none }) {
            return (action, nil)
        }

        let actionableNotificationStates = notificationHelpers.values.contains {
            if case .unavailable = $0 { return false }
            return true
        } ? Array(notificationHelpers.values) : [notifications]

        if actionableNotificationStates.contains(.notDetermined) {
            return (.requestNotificationPermission, nil)
        }
        if actionableNotificationStates.contains(.denied) {
            return (.openNotificationSettings, nil)
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
        hookTrust: HookTrustHealth,
        usage: SetupUsageHealth,
        lastEvent: LastIntegrationEventHealth
    ) -> SetupRecommendedAction {
        if case .invalid = hooks {
            return .reviewIntegrationConfiguration(agent)
        }
        if host == .unavailable {
            return .installHost(agent)
        }
        switch hooks {
        case .missing:
            return .installIntegration(agent)
        case .outdated, .duplicated:
            return .repairIntegration(agent)
        case .current, .invalid:
            break
        }
        switch hookTrust {
        case .needsReview, .disabled, .missing, .unavailable:
            return .reviewHookTrust(agent)
        case .notApplicable, .verified:
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

    private static func setupUsageHealth(from availability: UsageAvailability) -> SetupUsageHealth {
        switch availability {
        case .loading: return .loading
        case .available: return .available
        case .missingAuth: return .missingAuth
        case .accessDenied: return .accessDenied
        case .sessionExpired: return .sessionExpired
        case .notInstalled: return .notInstalled
        case .notLoggedIn: return .notLoggedIn
        case .error: return .error
        }
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
                    + "hook trust \(hookTrustSummary(integration.hookTrust)); "
                    + "usage \(usageSummary(integration.usage)); "
                    + "last event \(eventSummary(integration.lastEvent))"
            )
        }
        for agent in AgentKind.allCases {
            if let health = snapshot.notificationHelpers[agent] {
                lines.append(
                    "\(agent.displayName) notification sender: \(notificationSummary(health))"
                )
            }
        }
        lines += [
            "Main app notifications: \(notificationSummary(snapshot.notifications))",
            "Launch at Login: \(launchAtLoginSummary(snapshot.launchAtLogin))",
        ]
        if let issue = snapshot.blockingIssue {
            lines.append("Action required: \(issue.message)")
        } else if snapshot.recommendedAction != .none {
            lines.append("Recommended action: \(actionSummary(snapshot.recommendedAction))")
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

    private static func hookTrustSummary(_ health: HookTrustHealth) -> String {
        switch health {
        case .notApplicable:
            return "not applicable"
        case .verified(let trusted, let managed, let total):
            return "verified (\(trusted) trusted, \(managed) managed, \(total) total)"
        case .needsReview(let untrusted, let modified, let total):
            return "needs review (\(untrusted) untrusted, \(modified) modified, \(total) total)"
        case .disabled(let disabled, let total):
            return "disabled (\(disabled) of \(total))"
        case .missing(let found, let expected):
            return "incomplete (\(found) of \(expected))"
        case .unavailable(let reason):
            return "unavailable: \(reason)"
        }
    }

    private static func usageSummary(_ availability: SetupUsageHealth) -> String {
        switch availability {
        case .loading: return "loading"
        case .available: return "available"
        case .missingAuth: return "missing authentication"
        case .accessDenied: return "access denied"
        case .sessionExpired: return "session expired"
        case .notInstalled: return "host not installed"
        case .notLoggedIn: return "not logged in"
        case .error: return "error"
        }
    }

    private static func eventSummary(_ health: LastIntegrationEventHealth) -> String {
        switch health {
        case .never: return "never"
        case .received(let event, let timestamp, let age):
            return "\(event) at \(timestamp) (\(Int(age)) seconds ago)"
        }
    }

    private static func notificationSummary(_ health: NotificationAuthorizationHealth) -> String {
        switch health {
        case .notDetermined: return "not requested"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        case .unavailable(let reason): return "unavailable: \(reason)"
        }
    }

    private static func launchAtLoginSummary(_ health: LaunchAtLoginHealth) -> String {
        switch health {
        case .notRegistered: return "not registered"
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval"
        case .notFound: return "not found"
        case .unavailable(let reason): return "unavailable: \(reason)"
        }
    }

    private static func actionSummary(_ action: SetupRecommendedAction) -> String {
        switch action {
        case .moveApplication: return "move the application"
        case .restartLocalServer: return "restart the local server"
        case .installBridge: return "install the bridge"
        case .repairBridge: return "repair the bridge"
        case .installHost(let agent): return "install \(agent.displayName)"
        case .installIntegration(let agent): return "set up \(agent.displayName)"
        case .repairIntegration(let agent): return "repair \(agent.displayName) integration"
        case .reviewIntegrationConfiguration(let agent):
            return "review \(agent.displayName) configuration"
        case .reviewHookTrust(let agent): return "review \(agent.displayName) hook approval"
        case .signIn(let agent): return "sign in to \(agent.displayName)"
        case .testIntegration(let agent): return "test \(agent.displayName) integration"
        case .requestNotificationPermission: return "request notification permission"
        case .openNotificationSettings: return "open notification settings"
        case .approveLaunchAtLogin: return "approve Launch at Login"
        case .none: return "none"
        }
    }
}
