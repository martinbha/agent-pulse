import Testing

@testable import AgentPulseCore

@Suite struct HTTPRequestTests {
    @Test func parsesCompleteRequestAndNormalizesHeaders() {
        let result = HTTPRequestFixtures.parse(
            "POST /v1/events HTTP/1.1\r\nContent-Length: 4\r\nAUTHORIZATION: Bearer token\r\n\r\ntest"
        )

        guard case .request(let request) = result else {
            Issue.record("Expected a complete request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/v1/events")
        #expect(HTTPRequestFixtures.bodyString(request) == "test")
        #expect(request.bearerToken == "token")
    }

    @Test func waitsForCompleteHeadersAndBody() {
        guard case .incomplete = HTTPRequestFixtures.parse("GET /v1/state HTTP/1.1\r\nHost: localhost") else {
            Issue.record("Expected incomplete headers")
            return
        }

        guard case .incomplete = HTTPRequestFixtures.parse(
            "POST /v1/events HTTP/1.1\r\nContent-Length: 4\r\n\r\nte"
        ) else {
            Issue.record("Expected an incomplete body")
            return
        }
    }

    @Test func treatsMissingContentLengthAsAnEmptyBody() {
        guard case .request(let request) = HTTPRequestFixtures.parse("GET /v1/health HTTP/1.1\r\n\r\n") else {
            Issue.record("Expected a complete bodyless request")
            return
        }

        #expect(request.body.isEmpty)
    }

    @Test func rejectsInvalidContentLengths() {
        for value in ["-1", "+1", "1.5", "nope", ""] {
            guard case .malformed = HTTPRequestFixtures.parse(
                "POST /v1/events HTTP/1.1\r\nContent-Length: \(value)\r\n\r\n"
            ) else {
                Issue.record("Expected malformed Content-Length: \(value)")
                continue
            }
        }
    }

    @Test func rejectsDuplicateContentLengthAndMalformedHeaders() {
        guard case .malformed = HTTPRequestFixtures.parse(
            "POST /v1/events HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 1\r\n\r\n"
        ) else {
            Issue.record("Expected duplicate Content-Length headers to be rejected")
            return
        }

        guard case .malformed = HTTPRequestFixtures.parse("GET /v1/state HTTP/1.1\r\nInvalid Header\r\n\r\n") else {
            Issue.record("Expected malformed headers to be rejected")
            return
        }
    }

    @Test func rejectsOversizedBufferedAndDeclaredRequests() {
        guard case .tooLarge = HTTPRequestFixtures.oversizedBufferResult() else {
            Issue.record("Expected the buffered-size limit to be enforced")
            return
        }

        guard case .tooLarge = HTTPRequestFixtures.parse(
            "POST /v1/events HTTP/1.1\r\nContent-Length: \(HTTPRequestFixtures.maximumSize)\r\n\r\n"
        ) else {
            Issue.record("Expected the declared-size limit to be enforced")
            return
        }
    }
}
