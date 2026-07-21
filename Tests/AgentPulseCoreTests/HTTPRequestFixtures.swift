import Foundation

@testable import AgentPulseCore

enum HTTPRequestFixtures {
    static let maximumSize = 1_024

    static func parse(_ request: String) -> HTTPRequestParseResult {
        HTTPRequest.parse(Data(request.utf8), maximumSize: maximumSize)
    }

    static func oversizedBufferResult() -> HTTPRequestParseResult {
        HTTPRequest.parse(
            Data(repeating: 65, count: maximumSize + 1),
            maximumSize: maximumSize
        )
    }

    static func bodyString(_ request: HTTPRequest) -> String? {
        String(data: request.body, encoding: .utf8)
    }
}
