import Foundation
import Network

final class LocalEventServer: @unchecked Sendable {
    static let maximumRequestSize = 1_048_576
    static let requestTimeout: TimeInterval = 5

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
        let timeout = scheduleIdleTimeout(for: connection)
        connection.start(queue: queue)
        receive(from: connection, buffer: Data(), timeout: timeout)
    }

    private func scheduleIdleTimeout(for connection: NWConnection) -> DispatchWorkItem {
        let timeout = DispatchWorkItem {
            connection.cancel()
        }
        queue.asyncAfter(deadline: .now() + Self.requestTimeout, execute: timeout)
        return timeout
    }

    private func receive(
        from connection: NWConnection,
        buffer: Data,
        timeout: DispatchWorkItem
    ) {
        let remainingCapacity = max(0, Self.maximumRequestSize - buffer.count)
        let receiveLength = min(65_536, remainingCapacity + 1)

        connection.receive(minimumIncompleteLength: 1, maximumLength: receiveLength) { [weak self] data, _, isComplete, error in
            guard let self else {
                timeout.cancel()
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            switch HTTPRequest.parse(nextBuffer, maximumSize: Self.maximumRequestSize) {
            case .request(let request):
                timeout.cancel()
                Task {
                    let response = await self.route(request)
                    self.send(response, on: connection)
                }
                return
            case .malformed:
                timeout.cancel()
                send(.error("Invalid request", statusCode: 400, reason: "Bad Request"), on: connection)
                return
            case .tooLarge:
                timeout.cancel()
                send(.error("Request too large", statusCode: 413, reason: "Payload Too Large"), on: connection)
                return
            case .incomplete:
                break
            }

            if error != nil || isComplete {
                timeout.cancel()
                send(.error("Invalid request", statusCode: 400, reason: "Bad Request"), on: connection)
                return
            }

            let nextTimeout: DispatchWorkItem
            if let data, !data.isEmpty {
                timeout.cancel()
                nextTimeout = scheduleIdleTimeout(for: connection)
            } else {
                nextTimeout = timeout
            }

            receive(from: connection, buffer: nextBuffer, timeout: nextTimeout)
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
