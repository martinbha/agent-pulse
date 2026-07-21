import Testing

@testable import AgentPulseCore

@Suite struct ServerTokenStoreTests {
    @Test func acceptsOnlyTheCurrentToken() {
        let store = ServerTokenStore(token: "initial-token")

        #expect(store.matches("initial-token"))
        #expect(!store.matches("other-token"))
        #expect(!store.matches(nil))
    }

    @Test func replacementInvalidatesThePreviousToken() {
        let store = ServerTokenStore(token: "initial-token")

        store.replace(with: "replacement-token")

        #expect(store.matches("replacement-token"))
        #expect(!store.matches("initial-token"))
    }

    @Test func rejectsDifferentLengthAndUnicodeTokens() {
        let store = ServerTokenStore(token: "token-123")

        #expect(!store.matches("token-1234"))
        #expect(!store.matches("token-12"))
        #expect(!store.matches("tøken-123"))
    }
}
