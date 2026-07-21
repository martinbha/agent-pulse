import Foundation

public enum BridgeRequestError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidResponse
    case rejected(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The local event endpoint could not be constructed."
        case .invalidResponse:
            return "The local event endpoint returned an invalid response."
        case .rejected(let statusCode):
            return "The local event endpoint returned HTTP \(statusCode)."
        }
    }
}

public enum BridgeRequestFactory {
    public static func make(
        event: BridgeEvent,
        configuration: BridgeConfiguration
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(configuration.port)
        components.path = "/v1/events"

        guard let url = components.url else {
            throw BridgeRequestError.invalidEndpoint
        }

        var request = URLRequest(url: url, timeoutInterval: 1)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(event)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        return request
    }
}

public enum BridgeResponseValidator {
    public static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BridgeRequestError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BridgeRequestError.rejected(httpResponse.statusCode)
        }
    }
}
