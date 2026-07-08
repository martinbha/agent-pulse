import Foundation

@MainActor
final class AgentPulseRuntime: ObservableObject {
    let store: AgentStatusStore
    let usageStore: UsageStore
    let settings: AgentPulseSettings

    @Published private(set) var serverStatus = "Starting local server..."

    private let notificationService: AgentNotificationService
    private var server: LocalEventServer?
    private var timer: Timer?

    var endpoint: String {
        "http://127.0.0.1:\(settings.port)"
    }

    var maskedToken: String {
        guard settings.token.count > 12 else {
            return settings.token
        }

        return "\(settings.token.prefix(6))...\(settings.token.suffix(6))"
    }

    convenience init() {
        self.init(
            store: AgentStatusStore(),
            usageStore: UsageStore(),
            settings: AgentPulseSettings()
        )
    }

    init(
        store: AgentStatusStore,
        usageStore: UsageStore,
        settings: AgentPulseSettings
    ) {
        self.store = store
        self.usageStore = usageStore
        self.settings = settings
        self.notificationService = AgentNotificationService()

        startServer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak store] _ in
            Task { @MainActor in
                store?.tick()
            }
        }
    }

    func refreshUsage() {
        Task { await usageStore.refresh(trigger: .manual) }
    }

    deinit {
        server?.stop()
        timer?.invalidate()
    }

    func clearCompleted() {
        store.clearCompleted()
    }

    func sendTestEvent(agent: AgentKind) {
        sendTestEvent(agent: agent, state: .working, event: "ManualStart")
    }

    func stopTestEvent(agent: AgentKind) {
        sendTestEvent(agent: agent, state: .done, event: "ManualStop")
    }

    private func sendTestEvent(agent: AgentKind, state: AgentState, event: String) {
        ingest(
            AgentEvent(
                agent: agent,
                state: state,
                event: event,
                sessionID: nil,
                cwd: FileManager.default.currentDirectoryPath,
                project: "agent-pulse",
                timestamp: Date(),
                source: "manual-test"
            )
        )
    }

    func copyEndpoint() {
        Pasteboard.copy(endpoint)
    }

    func copyToken() {
        Pasteboard.copy(settings.token)
    }

    func copyStateJSON() {
        let response = ServerStateResponse(store: store)
        if let data = try? AgentPulseJSON.encoder.encode(response),
           let value = String(data: data, encoding: .utf8) {
            Pasteboard.copy(value)
        }
    }

    func regenerateToken() {
        server?.stop()
        server = nil
        settings.regenerateToken()
        serverStatus = "Restarting local server..."
        startServer()
    }

    private func startServer() {
        let statusHandler: (String) -> Void = { [weak self] status in
            Task { @MainActor in
                self?.serverStatus = status
            }
        }

        let server = LocalEventServer(
            port: settings.port,
            token: settings.token,
            eventHandler: { [weak self] event in
                await MainActor.run {
                    self?.ingest(event)
                }
            },
            stateProvider: { [weak store] in
                await MainActor.run {
                    ServerStateResponse(store: store)
                }
            },
            clearHandler: { [weak store] in
                await MainActor.run {
                    store?.clearCompleted()
                }
            },
            statusHandler: statusHandler
        )

        do {
            try server.start()
            self.server = server
        } catch {
            serverStatus = "Server failed: \(error.localizedDescription)"
        }
    }

    private func ingest(_ event: AgentEvent) {
        let previousSnapshot = store.snapshots[event.agent] ?? .idle(agent: event.agent)
        let previousState = store.effectiveState(for: previousSnapshot)

        store.ingest(event)

        guard let newSnapshot = store.snapshots[event.agent] else {
            return
        }

        notificationService.handleTransition(
            agent: event.agent,
            previousState: previousState,
            newSnapshot: newSnapshot,
            newState: store.effectiveState(for: newSnapshot)
        )
    }
}
