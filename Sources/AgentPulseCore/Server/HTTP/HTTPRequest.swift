import Foundation

enum HTTPRequestParseResult {
    case incomplete
    case request(HTTPRequest)
    case malformed
    case tooLarge
}

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

    static func parse(_ data: Data, maximumSize: Int) -> HTTPRequestParseResult {
        guard data.count <= maximumSize else {
            return .tooLarge
        }

        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return .incomplete
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .malformed
        }

        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else {
            return .malformed
        }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else {
            return .malformed
        }

        var headers: [String: String] = [:]
        for line in lines {
            guard let delimiter = line.firstIndex(of: ":") else {
                return .malformed
            }

            let name = line[..<delimiter].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: delimiter)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                return .malformed
            }
            if name == "content-length", headers[name] != nil {
                return .malformed
            }
            headers[name] = value
        }

        let expectedBodyLength: Int
        if let contentLength = headers["content-length"] {
            guard !contentLength.isEmpty,
                  contentLength.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let parsedLength = Int(contentLength) else {
                return .malformed
            }
            expectedBodyLength = parsedLength
        } else {
            expectedBodyLength = 0
        }

        let bodyStart = headerRange.upperBound
        guard expectedBodyLength <= maximumSize - bodyStart else {
            return .tooLarge
        }

        guard data.count >= bodyStart + expectedBodyLength else {
            return .incomplete
        }

        return .request(
            HTTPRequest(
                method: String(requestLine[0]),
                path: String(requestLine[1]),
                headers: headers,
                body: Data(data[bodyStart..<(bodyStart + expectedBodyLength)])
            )
        )
    }
}
