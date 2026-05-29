import Foundation

struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    var bearerToken: String? {
        guard let authorization = headers["authorization"] else {
            return nil
        }

        let prefix = "Bearer "
        guard authorization.hasPrefix(prefix) else {
            return nil
        }

        return String(authorization.dropFirst(prefix.count))
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return nil
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            return nil
        }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let delimiter = line.firstIndex(of: ":") else {
                continue
            }

            let name = line[..<delimiter].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: delimiter)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let expectedBodyLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + expectedBodyLength else {
            return nil
        }

        return HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(data[bodyStart..<(bodyStart + expectedBodyLength)])
        )
    }
}

