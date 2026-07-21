import Foundation

@testable import AgentPulseBridgeSupport

struct BridgeRequestSnapshot: Equatable {
    var method: String?
    var url: String?
    var timeout: TimeInterval
    var authorization: String?
    var contentType: String?
    var body: [String: String]
}

enum BridgeDeliveryFixtures {
    static func decodedConfiguration(from value: String) -> BridgeConfiguration? {
        try? BridgeConfigurationLoader.decode(Data(value.utf8))
    }

    static func configurationError(from value: String) -> BridgeConfigurationError? {
        do {
            _ = try BridgeConfigurationLoader.decode(Data(value.utf8))
            return nil
        } catch let error as BridgeConfigurationError {
            return error
        } catch {
            return nil
        }
    }

    static func requestSnapshot() throws -> BridgeRequestSnapshot {
        let event = BridgeEventNormalizer.normalize(
            agent: "sample",
            input: ["hook_event_name": "Stop", "session_id": "session-1"],
            currentDirectory: "/tmp/project",
            timestamp: "2026-07-21T10:30:00Z",
            hostBundleID: "com.example.host"
        )
        let request = try BridgeRequestFactory.make(
            event: event,
            configuration: BridgeConfiguration(port: 37_462, token: "secret-token")
        )
        let data = request.httpBody ?? Data()
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let body = object.reduce(into: [String: String]()) { result, entry in
            if let value = entry.value as? String {
                result[entry.key] = value
            }
        }

        return BridgeRequestSnapshot(
            method: request.httpMethod,
            url: request.url?.absoluteString,
            timeout: request.timeoutInterval,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            contentType: request.value(forHTTPHeaderField: "Content-Type"),
            body: body
        )
    }

    static func responseError(statusCode: Int?) -> BridgeRequestError? {
        let response: URLResponse
        if let statusCode {
            response = HTTPURLResponse(
                url: URL(string: "http://127.0.0.1:37462/v1/events")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        } else {
            response = URLResponse(
                url: URL(string: "http://127.0.0.1:37462/v1/events")!,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            )
        }

        do {
            try BridgeResponseValidator.validate(response)
            return nil
        } catch let error as BridgeRequestError {
            return error
        } catch {
            return nil
        }
    }
}
