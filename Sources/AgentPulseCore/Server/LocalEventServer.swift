import Foundation
import Network

final class LocalEventServer: @unchecked Sendable {
    private let port: UInt16
    private let tokenStore: ServerTokenStore
    private let eventHandler: (AgentEvent) async -> Void
    private let stateProvider: () async -> ServerStateResponse
    private let clearHandler: () async -> Void
    private let statusHandler: (String) -> Void
    private let queue = DispatchQueue(label: "AgentPulse.LocalEventServer")

    private var listener: NWListener?

    init(
        port: UInt16,
        token: String,
        eventHandler: @escaping (AgentEvent) async -> Void,
        stateProvider: @escaping () async -> ServerStateResponse,
        clearHandler: @escaping () async -> Void,
        statusHandler: @escaping (String) -> Void
    ) {
        self.port = port
        self.tokenStore = ServerTokenStore(token: token)
        self.eventHandler = eventHandler
        self.stateProvider = stateProvider
        self.clearHandler = clearHandler
        self.statusHandler = statusHandler
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func updateToken(_ token: String) {
        tokenStore.replace(with: token)
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            statusHandler("Listening on 127.0.0.1:\(port)")
        case .failed(let error):
            statusHandler("Server failed: \(error.localizedDescription)")
        case .cancelled:
            statusHandler("Server stopped")
        case .waiting(let error):
            statusHandler("Server waiting: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(from: connection, buffer: Data())
    }

    private func receive(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = HTTPRequest.parse(nextBuffer) {
                Task {
                    let response = await self.route(request)
                    self.send(response, on: connection)
                }
                return
            }

            if error != nil || isComplete {
                send(.error("Invalid request", statusCode: 400, reason: "Bad Request"), on: connection)
                return
            }

            receive(from: connection, buffer: nextBuffer)
        }
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        guard request.path == "/v1/health" || tokenStore.matches(request.bearerToken) else {
            return .error("Unauthorized", statusCode: 401, reason: "Unauthorized")
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            return .json(
                HealthResponse(
                    ok: true,
                    app: "Agent Pulse",
                    version: AgentPulseVersion.current
                )
            )

        case ("GET", "/v1/state"):
            return .json(await stateProvider())

        case ("POST", "/v1/events"):
            do {
                let event = try AgentPulseJSON.decoder.decode(AgentEvent.self, from: request.body)
                await eventHandler(event)
                return .json(OKResponse(ok: true))
            } catch {
                return .error("Invalid event payload: \(error.localizedDescription)", statusCode: 400, reason: "Bad Request")
            }

        case ("POST", "/v1/state/clear"):
            await clearHandler()
            return .json(OKResponse(ok: true))

        default:
            return .error("Not found", statusCode: 404, reason: "Not Found")
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
