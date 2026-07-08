import Foundation

@testable import AgentPulseCore

// Foundation-touching fixtures for the credential loader tests; assertion
// files import Testing only (see TestFixtures.swift for why).
enum ClaudeCredentialFixtures {
    static let sampleFileJSON = """
    {
      "claudeAiOauth": {
        "accessToken": "file-token",
        "refreshToken": "file-refresh",
        "expiresAt": 9999999999999,
        "subscriptionType": "claude_max"
      }
    }
    """

    static let claudeCodeDesktopCacheJSON = """
    {
      "user:sessions:claude_code:abc": {
        "token": "desktop-code-token",
        "refreshToken": "desktop-code-refresh",
        "expiresAt": 9999999999999
      },
      "aaa:other-session": {
        "token": "desktop-other-token"
      }
    }
    """

    enum KeychainMappingOutcome: Equatable {
        case notFound
        case denied
        case failure
    }

    static func keychainCredentials(accessToken: String) -> ClaudeCredentialResult {
        ClaudeCredentialResult(
            oauth: ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: "keychain-refresh",
                expiresAt: 9_999_999_999_999,
                subscriptionType: nil
            ),
            source: .keychain,
            fullData: ["claudeAiOauth": ["accessToken": accessToken]]
        )
    }

    static func resolve(
        fileJSON: String? = nil,
        environmentToken: String? = nil,
        keychain: Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue> = .success(nil),
        desktopTokenCacheJSON: String? = nil,
        desktopPassword: String? = nil,
        refreshKeychainAccess: Bool = false
    ) -> ClaudeCredentialResolution {
        let loader = makeLoader(
            fileJSON: fileJSON,
            environmentToken: environmentToken,
            keychain: keychain,
            desktopTokenCacheJSON: desktopTokenCacheJSON,
            desktopPassword: desktopPassword
        )
        return loader.resolveCredentials(refreshKeychainAccess: refreshKeychainAccess)
    }

    static func classifyKeychainTermination(_ output: String) -> KeychainMappingOutcome {
        let loader = makeLoader()
        switch loader.mapKeychainError(.terminated(44, output)) {
        case .success:
            return .notFound
        case .failure(.keychainAccessDenied):
            return .denied
        case .failure:
            return .failure
        }
    }

    static func needsRefresh(expiresAtMsFromNow: Double?) -> Bool {
        let loader = makeLoader()
        let expiresAt = expiresAtMsFromNow.map { Date().timeIntervalSince1970 * 1000 + $0 }
        let oauth = ClaudeOAuthCredentials(
            accessToken: "token",
            refreshToken: nil,
            expiresAt: expiresAt,
            subscriptionType: nil
        )
        return loader.needsRefresh(oauth)
    }

    /// Resolves Desktop-sourced credentials, mutates the token, saves, and
    /// reports whether Desktop's config file bytes stayed identical.
    static func desktopSaveLeavesConfigUntouched() -> Bool {
        let home = makeTempHome()
        let configURL = home.appendingPathComponent("desktop-config.json")
        let loader = ClaudeCredentialLoader(
            homeDirectory: home,
            environment: [:],
            desktopConfigURL: configURL,
            keychainLoadOverride: .success(nil),
            desktopSafeStoragePasswordOverride: .success("test-password")
        )

        writeDesktopConfig(to: configURL, tokenCacheJSON: claudeCodeDesktopCacheJSON, password: "test-password", loader: loader)
        guard let before = try? Data(contentsOf: configURL) else {
            return false
        }

        guard var credentials = loader.resolveCredentials().credentials, credentials.source == .desktop else {
            return false
        }
        credentials.oauth.accessToken = "rotated-token"
        loader.saveCredentials(credentials)

        guard let after = try? Data(contentsOf: configURL) else {
            return false
        }
        return before == after
    }

    /// Resolves file-sourced credentials, rotates the token, saves, and
    /// returns the access token from a fresh resolution.
    static func fileSaveRoundTrip() -> String? {
        let home = makeTempHome()
        let loader = ClaudeCredentialLoader(
            homeDirectory: home,
            environment: [:],
            keychainLoadOverride: .success(nil),
            desktopSafeStoragePasswordOverride: .success(nil)
        )
        writeCredentialsFile(home: home, json: sampleFileJSON)

        guard var credentials = loader.resolveCredentials().credentials, credentials.source == .file else {
            return nil
        }
        credentials.oauth.accessToken = "rotated-token"
        loader.saveCredentials(credentials)

        return loader.resolveCredentials().credentials?.oauth.accessToken
    }

    // MARK: - Private helpers

    private static func makeLoader(
        fileJSON: String? = nil,
        environmentToken: String? = nil,
        keychain: Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue> = .success(nil),
        desktopTokenCacheJSON: String? = nil,
        desktopPassword: String? = nil
    ) -> ClaudeCredentialLoader {
        let home = makeTempHome()
        let configURL = home.appendingPathComponent("desktop-config.json")

        var environment: [String: String] = [:]
        if let environmentToken {
            environment["CLAUDE_CODE_OAUTH_TOKEN"] = environmentToken
        }

        let loader = ClaudeCredentialLoader(
            homeDirectory: home,
            environment: environment,
            desktopConfigURL: configURL,
            keychainLoadOverride: keychain,
            desktopSafeStoragePasswordOverride: .success(desktopPassword)
        )

        if let fileJSON {
            writeCredentialsFile(home: home, json: fileJSON)
        }
        if let desktopTokenCacheJSON, let desktopPassword {
            writeDesktopConfig(to: configURL, tokenCacheJSON: desktopTokenCacheJSON, password: desktopPassword, loader: loader)
        }

        return loader
    }

    private static func makeTempHome() -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-pulse-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private static func writeCredentialsFile(home: URL, json: String) {
        let url = home.appendingPathComponent(".claude/.credentials.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(json.utf8).write(to: url)
    }

    private static func writeDesktopConfig(to url: URL, tokenCacheJSON: String, password: String, loader: ClaudeCredentialLoader) {
        guard let encrypted = loader.encryptClaudeDesktopValue(tokenCacheJSON, password: password) else {
            return
        }
        let root: [String: Any] = ["oauth:tokenCacheV2": encrypted]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else {
            return
        }
        try? data.write(to: url)
    }
}
