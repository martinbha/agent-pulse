import Foundation

@MainActor
final class AgentPulseRuntime: ObservableObject {
    let store: AgentStatusStore
    let settings: AgentPulseSettings

    @Published private(set) var serverStatus = "Starting local server..."

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

    init() {
        self.store = AgentStatusStore()
        self.settings = AgentPulseSettings()

        startServer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak store] _ in
            Task { @MainActor in
                store?.tick()
            }
        }
    }

    init(store: AgentStatusStore, settings: AgentPulseSettings) {
        self.store = store
        self.settings = settings

        startServer()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak store] _ in
            Task { @MainActor in
                store?.tick()
            }
        }
    }

    deinit {
        server?.stop()
        timer?.invalidate()
    }

    func clearCompleted() {
        store.clearCompleted()
    }

    func sendTestEvent(agent: AgentKind) {
        store.ingest(
            AgentEvent(
                agent: agent,
                state: .working,
                event: "ManualTest",
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
            eventHandler: { [weak store] event in
                await MainActor.run {
                    store?.ingest(event)
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
}
