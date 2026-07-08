import Testing

@testable import AgentPulseCore

@Suite struct ClaudeCredentialResolutionTests {
    @Test func fileCredentialsWinOverKeychain() {
        let resolution = ClaudeCredentialFixtures.resolve(
            fileJSON: ClaudeCredentialFixtures.sampleFileJSON,
            keychain: .success(ClaudeCredentialFixtures.keychainCredentials(accessToken: "keychain-token"))
        )

        #expect(resolution.credentials?.source == .file)
        #expect(resolution.credentials?.oauth.accessToken == "file-token")
        #expect(resolution.credentials?.oauth.refreshToken == "file-refresh")
        #expect(resolution.credentials?.oauth.subscriptionType == "claude_max")
    }

    @Test func keychainUsedWhenFileMissing() {
        let resolution = ClaudeCredentialFixtures.resolve(
            keychain: .success(ClaudeCredentialFixtures.keychainCredentials(accessToken: "keychain-token"))
        )

        #expect(resolution.credentials?.source == .keychain)
        #expect(resolution.credentials?.oauth.accessToken == "keychain-token")
    }

    @Test func environmentTokenIsTrimmedFallback() {
        let resolution = ClaudeCredentialFixtures.resolve(environmentToken: "  env-token \n")

        #expect(resolution.credentials?.source == .environment)
        #expect(resolution.credentials?.oauth.accessToken == "env-token")
        #expect(resolution.credentials?.oauth.refreshToken == nil)
    }

    @Test func desktopCredentialsDecryptAsLastResort() {
        let resolution = ClaudeCredentialFixtures.resolve(
            desktopTokenCacheJSON: ClaudeCredentialFixtures.claudeCodeDesktopCacheJSON,
            desktopPassword: "test-password"
        )

        #expect(resolution.credentials?.source == .desktop)
        #expect(resolution.credentials?.oauth.accessToken == "desktop-code-token")
        #expect(resolution.credentials?.oauth.refreshToken == "desktop-code-refresh")
    }

    @Test func desktopPrefersClaudeCodeSessionEntry() {
        // "aaa:other-session" sorts first alphabetically; the claude_code
        // session entry must still win.
        let resolution = ClaudeCredentialFixtures.resolve(
            desktopTokenCacheJSON: ClaudeCredentialFixtures.claudeCodeDesktopCacheJSON,
            desktopPassword: "test-password"
        )

        #expect(resolution.credentials?.oauth.accessToken == "desktop-code-token")
    }

    @Test func keychainDenialSurfacesAsIssue() {
        let resolution = ClaudeCredentialFixtures.resolve(keychain: .failure(.keychainAccessDenied))

        #expect(resolution.credentials == nil)
        #expect(resolution.issue == .keychainAccessDenied)
    }

    @Test func noSourcesYieldsNoCredentialsAndNoIssue() {
        let resolution = ClaudeCredentialFixtures.resolve()

        #expect(resolution.credentials == nil)
        #expect(resolution.issue == nil)
    }

    @Test func manualRefreshPrefersKeychainOverFile() {
        let resolution = ClaudeCredentialFixtures.resolve(
            fileJSON: ClaudeCredentialFixtures.sampleFileJSON,
            keychain: .success(ClaudeCredentialFixtures.keychainCredentials(accessToken: "keychain-token")),
            refreshKeychainAccess: true
        )

        #expect(resolution.credentials?.source == .keychain)
    }
}

@Suite struct ClaudeKeychainErrorMappingTests {
    @Test func missingItemMapsToNotFound() {
        let outcome = ClaudeCredentialFixtures.classifyKeychainTermination(
            "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain."
        )

        #expect(outcome == .notFound)
    }

    @Test func deniedInteractionMapsToDenied() {
        let outcome = ClaudeCredentialFixtures.classifyKeychainTermination(
            "security: SecKeychainItemCopyContent: User interaction is not allowed."
        )

        #expect(outcome == .denied)
    }

    @Test func userCancelMapsToDenied() {
        let outcome = ClaudeCredentialFixtures.classifyKeychainTermination(
            "security: The authorization was denied since the user canceled the operation."
        )

        #expect(outcome == .denied)
    }

    @Test func unknownErrorMapsToFailure() {
        let outcome = ClaudeCredentialFixtures.classifyKeychainTermination("security: unexpected explosion")

        #expect(outcome == .failure)
    }
}

@Suite struct ClaudeTokenExpiryTests {
    @Test func missingExpiryNeedsRefresh() {
        #expect(ClaudeCredentialFixtures.needsRefresh(expiresAtMsFromNow: nil))
    }

    @Test func farFutureExpiryDoesNotNeedRefresh() {
        #expect(!ClaudeCredentialFixtures.needsRefresh(expiresAtMsFromNow: 10 * 60 * 1000))
    }

    @Test func expiryInsideBufferNeedsRefresh() {
        #expect(ClaudeCredentialFixtures.needsRefresh(expiresAtMsFromNow: 2 * 60 * 1000))
    }

    @Test func pastExpiryNeedsRefresh() {
        #expect(ClaudeCredentialFixtures.needsRefresh(expiresAtMsFromNow: -1000))
    }
}

@Suite struct ClaudeCredentialPersistenceTests {
    @Test func desktopSourceIsNeverWrittenBack() {
        #expect(ClaudeCredentialFixtures.desktopSaveLeavesConfigUntouched())
    }

    @Test func fileSourcePersistsRotatedToken() {
        #expect(ClaudeCredentialFixtures.fileSaveRoundTrip() == "rotated-token")
    }
}
