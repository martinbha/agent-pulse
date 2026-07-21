import Testing

@testable import AgentPulseBridgeSupport

@Suite struct BridgeDeliveryTests {
    @Test func decodesValidConfiguration() throws {
        let configuration = try #require(
            BridgeDeliveryFixtures.decodedConfiguration(
                from: #"{"port":37462,"token":"secret-token"}"#
            )
        )
        #expect(configuration.port == 37_462)
        #expect(configuration.token == "secret-token")
    }

    @Test func rejectsMalformedOrIncompleteConfiguration() {
        #expect(BridgeDeliveryFixtures.configurationError(from: "not json") != nil)
        #expect(BridgeDeliveryFixtures.configurationError(from: #"{"port":37462}"#) != nil)
        #expect(
            BridgeDeliveryFixtures.configurationError(
                from: #"{"port":37462,"token":"  "}"#
            ) == .invalid("token must not be empty")
        )
    }

    @Test func buildsAuthenticatedLoopbackRequest() throws {
        let request = try BridgeDeliveryFixtures.requestSnapshot()

        #expect(request.method == "POST")
        #expect(request.url == "http://127.0.0.1:37462/v1/events")
        #expect(request.timeout == 1)
        #expect(request.authorization == "Bearer secret-token")
        #expect(request.contentType == "application/json")
        #expect(request.body["agent"] == "sample")
        #expect(request.body["state"] == "done")
        #expect(request.body["session_id"] == "session-1")
        #expect(request.body["host_bundle_id"] == "com.example.host")
    }

    @Test func validatesHTTPResponseStatus() {
        #expect(BridgeDeliveryFixtures.responseError(statusCode: 200) == nil)
        #expect(BridgeDeliveryFixtures.responseError(statusCode: 204) == nil)
        #expect(BridgeDeliveryFixtures.responseError(statusCode: 401) == .rejected(401))
        #expect(BridgeDeliveryFixtures.responseError(statusCode: 500) == .rejected(500))
        #expect(BridgeDeliveryFixtures.responseError(statusCode: nil) == .invalidResponse)
    }
}
