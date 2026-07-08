import Foundation

struct HTTPResponse {
    var statusCode: Int
    var reason: String
    var body: Data
    var contentType: String

    static func json<T: Encodable>(_ value: T, statusCode: Int = 200, reason: String = "OK") -> HTTPResponse {
        let body = (try? AgentPulseJSON.encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(statusCode: statusCode, reason: reason, body: body, contentType: "application/json")
    }

    static func error(_ message: String, statusCode: Int, reason: String) -> HTTPResponse {
        HTTPResponse.json(ErrorResponse(ok: false, error: message), statusCode: statusCode, reason: reason)
    }

    var data: Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(statusCode) \(reason)\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n".utf8))
        response.append(Data("\r\n".utf8))
        response.append(body)
        return response
    }
}

