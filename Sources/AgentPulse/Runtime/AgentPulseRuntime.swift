import Foundation

@MainActor
final class AgentPulseRuntime: ObservableObject {
    let store: AgentStatusStore
    let settings: AgentPulseSettings

    @Published private(set) var serverStatus = "Starting local server..."

    private var server: LocalEventServer?
    private var timer: Timer?

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
