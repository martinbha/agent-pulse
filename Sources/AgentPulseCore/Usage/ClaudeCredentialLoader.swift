import CommonCrypto
import Foundation

/// Resolves Claude OAuth credentials from existing local auth state, in order:
/// the CLI credentials file, the CLI Keychain item, the environment token, and
/// finally Claude Desktop's encrypted token cache.
///
/// Claude Desktop state is strictly read-only: refreshed tokens are persisted
/// back to the file and Keychain sources only, never to Desktop's config.json
/// (a bad write or a race with the running Desktop app could corrupt its auth
/// state). Callers holding a Desktop-sourced refresh keep it in memory.
struct ClaudeCredentialLoader {
    private let homeDirectory: URL
    private let environment: [String: String]
    private let keychainService: String
    private let desktopConfigURL: URL
    private let desktopSafeStorageService: String
    private let desktopSafeStorageAccount: String
    private let keychainLoadOverride: Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue>?
    private let keychainSaveOverride: (@Sendable (ClaudeCredentialResult) -> Void)?
    private let desktopSafeStoragePasswordOverride: Result<String?, ClaudeCredentialLoadIssue>?
    private static let refreshBufferMs: Double = 5 * 60 * 1000
    private static let desktopLegacyTokenCacheKey = "oauth:tokenCache"
    private static let desktopTokenCacheKeys = ["oauth:tokenCacheV2", desktopLegacyTokenCacheKey]

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        keychainService: String = "Claude Code-credentials",
        desktopConfigURL: URL? = nil,
        desktopSafeStorageService: String = "Claude Safe Storage",
        desktopSafeStorageAccount: String = "Claude Key",
        keychainLoadOverride: Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue>? = nil,
        keychainSaveOverride: (@Sendable (ClaudeCredentialResult) -> Void)? = nil,
        desktopSafeStoragePasswordOverride: Result<String?, ClaudeCredentialLoadIssue>? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.keychainService = keychainService
        self.desktopConfigURL = desktopConfigURL
            ?? homeDirectory.appendingPathComponent("Library/Application Support/Claude/config.json")
        self.desktopSafeStorageService = desktopSafeStorageService
        self.desktopSafeStorageAccount = desktopSafeStorageAccount
        self.keychainLoadOverride = keychainLoadOverride
        self.keychainSaveOverride = keychainSaveOverride
        self.desktopSafeStoragePasswordOverride = desktopSafeStoragePasswordOverride
    }

    func loadCredentials() -> ClaudeCredentialResult? {
        resolveCredentials().credentials
    }

    func resolveCredentials(refreshKeychainAccess: Bool = false) -> ClaudeCredentialResolution {
        if refreshKeychainAccess {
            return resolveCredentialsWithFreshKeychainAccess()
        }

        if let credentials = loadFromFile() {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        let keychainResult = loadFromKeychain()
        if case .success(let credentials) = keychainResult, let credentials {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        if let credentials = loadFromEnvironment() {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        let desktopResult = loadFromClaudeDesktop()
        if case .success(let credentials) = desktopResult, let credentials {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        switch keychainResult {
        case .success:
            switch desktopResult {
            case .success:
                return ClaudeCredentialResolution(credentials: nil, issue: nil)
            case .failure(let issue):
                return ClaudeCredentialResolution(credentials: nil, issue: issue)
            }
        case .failure(let issue):
            return ClaudeCredentialResolution(credentials: nil, issue: issue)
        }
    }

    /// Manual refreshes re-attempt the Keychain-backed sources first so a
    /// previously denied prompt gets a second chance.
    private func resolveCredentialsWithFreshKeychainAccess() -> ClaudeCredentialResolution {
        let keychainResult = loadFromKeychain()
        if case .success(let credentials) = keychainResult, let credentials {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        let desktopResult = loadFromClaudeDesktop()
        if case .success(let credentials) = desktopResult, let credentials {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        if case .failure(let issue) = keychainResult {
            return ClaudeCredentialResolution(credentials: nil, issue: issue)
        }
        if case .failure(let issue) = desktopResult {
            return ClaudeCredentialResolution(credentials: nil, issue: issue)
        }

        if let credentials = loadFromFile() {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        if let credentials = loadFromEnvironment() {
            return ClaudeCredentialResolution(credentials: credentials, issue: nil)
        }

        return ClaudeCredentialResolution(credentials: nil, issue: nil)
    }

    func needsRefresh(_ oauth: ClaudeOAuthCredentials) -> Bool {
        guard let expiresAt = oauth.expiresAt else {
            return true
        }
        let nowMs = Date().timeIntervalSince1970 * 1000
        return nowMs + Self.refreshBufferMs >= expiresAt
    }

    func saveCredentials(_ result: ClaudeCredentialResult) {
        switch result.source {
        case .file:
            saveToFile(result)
        case .keychain:
            saveToKeychain(result)
        case .environment, .desktop:
            // Environment tokens have no store; Desktop state is read-only.
            return
        }
    }

    private func credentialsFileURL() -> URL {
        homeDirectory.appendingPathComponent(".claude/.credentials.json")
    }

    private func loadFromFile() -> ClaudeCredentialResult? {
        let url = credentialsFileURL()
        guard
            FileManager.default.fileExists(atPath: url.path),
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return nil
        }
        return makeCredentialResult(from: root, source: .file)
    }

    private func loadFromKeychain() -> Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue> {
        if let keychainLoadOverride {
            return keychainLoadOverride
        }

        do {
            let output = try ProcessRunner.runSync(
                executable: "/usr/bin/security",
                arguments: ["find-generic-password", "-s", keychainService, "-w"],
                input: nil,
                timeout: nil,
                currentDirectory: nil
            )

            guard
                let data = output.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data),
                let root = object as? [String: Any]
            else {
                return .success(nil)
            }

            return .success(makeCredentialResult(from: root, source: .keychain))
        } catch let error as ProcessRunnerError {
            return mapKeychainError(error)
        } catch {
            return .failure(.keychainFailure("Claude Keychain lookup failed: \(error.localizedDescription)"))
        }
    }

    private func loadFromEnvironment() -> ClaudeCredentialResult? {
        guard let rawToken = environment["CLAUDE_CODE_OAUTH_TOKEN"] else {
            return nil
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return nil
        }

        return ClaudeCredentialResult(
            oauth: ClaudeOAuthCredentials(accessToken: token, refreshToken: nil, expiresAt: nil, subscriptionType: nil),
            source: .environment,
            fullData: [:]
        )
    }

    private func loadFromClaudeDesktop() -> Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue> {
        guard
            FileManager.default.fileExists(atPath: desktopConfigURL.path),
            let data = try? Data(contentsOf: desktopConfigURL),
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else {
            return .success(nil)
        }

        let encryptedTokenCaches = Self.desktopTokenCacheKeys.compactMap { key -> (String, String)? in
            guard let encryptedTokenCache = trimmed(root[key] as? String) else {
                return nil
            }
            return (key, encryptedTokenCache)
        }
        guard !encryptedTokenCaches.isEmpty else {
            return .success(nil)
        }

        let passwordResult = loadDesktopSafeStoragePassword()
        guard case .success(let password) = passwordResult else {
            if case .failure(let issue) = passwordResult {
                return .failure(issue)
            }
            return .success(nil)
        }
        guard let password, !password.isEmpty else {
            return .success(nil)
        }

        var lastIssue: ClaudeCredentialLoadIssue?
        var foundReadableCache = false
        for (cacheKey, encryptedTokenCache) in encryptedTokenCaches {
            guard let plaintext = decryptClaudeDesktopValue(encryptedTokenCache, password: password) else {
                lastIssue = .keychainFailure("Claude Desktop credentials could not be decrypted.")
                continue
            }
            guard
                let tokenData = plaintext.data(using: .utf8),
                let tokenObject = try? JSONSerialization.jsonObject(with: tokenData),
                let tokenCache = tokenObject as? [String: Any]
            else {
                lastIssue = .keychainFailure("Claude Desktop token cache was not valid JSON.")
                continue
            }

            foundReadableCache = true
            if let credentials = makeDesktopCredentialResult(from: tokenCache, root: root, cacheKey: cacheKey) {
                return .success(credentials)
            }
        }

        if foundReadableCache {
            return .success(nil)
        }
        if let lastIssue {
            return .failure(lastIssue)
        }
        return .success(nil)
    }

    private func loadDesktopSafeStoragePassword() -> Result<String?, ClaudeCredentialLoadIssue> {
        if let desktopSafeStoragePasswordOverride {
            return desktopSafeStoragePasswordOverride
        }

        do {
            let output = try ProcessRunner.runSync(
                executable: "/usr/bin/security",
                arguments: [
                    "find-generic-password",
                    "-s", desktopSafeStorageService,
                    "-a", desktopSafeStorageAccount,
                    "-w",
                ],
                input: nil,
                timeout: nil,
                currentDirectory: nil
            )
            let password = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return password.isEmpty ? .success(nil) : .success(password)
        } catch let error as ProcessRunnerError {
            switch mapKeychainError(error) {
            case .success:
                return .success(nil)
            case .failure(let issue):
                return .failure(issue)
            }
        } catch {
            return .failure(.keychainFailure("Claude Desktop Keychain lookup failed: \(error.localizedDescription)"))
        }
    }

    private func makeCredentialResult(from root: [String: Any], source: ClaudeCredentialSource) -> ClaudeCredentialResult? {
        guard
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let rawToken = oauth["accessToken"] as? String
        else {
            return nil
        }

        let accessToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            return nil
        }

        return ClaudeCredentialResult(
            oauth: ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: trimmed(oauth["refreshToken"] as? String),
                expiresAt: parseExpiresAt(oauth["expiresAt"]),
                subscriptionType: trimmed(oauth["subscriptionType"] as? String)
            ),
            source: source,
            fullData: root
        )
    }

    private func makeDesktopCredentialResult(
        from tokenCache: [String: Any],
        root: [String: Any],
        cacheKey: String
    ) -> ClaudeCredentialResult? {
        let preferredEntries = tokenCache
            .compactMap { key, value -> (String, [String: Any])? in
                guard let entry = value as? [String: Any] else { return nil }
                return (key, entry)
            }
            .sorted { lhs, rhs in
                let lhsIsCode = lhs.0.contains("user:sessions:claude_code")
                let rhsIsCode = rhs.0.contains("user:sessions:claude_code")
                if lhsIsCode != rhsIsCode {
                    return lhsIsCode
                }
                return lhs.0 < rhs.0
            }

        for (key, entry) in preferredEntries {
            guard let token = trimmed(entry["token"] as? String) ?? trimmed(entry["accessToken"] as? String) else {
                continue
            }

            var fullData = root
            fullData["desktopTokenCache"] = tokenCache
            fullData["desktopTokenCacheEntryKey"] = key
            fullData["desktopTokenCacheKey"] = cacheKey
            return ClaudeCredentialResult(
                oauth: ClaudeOAuthCredentials(
                    accessToken: token,
                    refreshToken: trimmed(entry["refreshToken"] as? String) ?? trimmed(entry["refresh_token"] as? String),
                    expiresAt: parseExpiresAt(entry["expiresAt"] ?? entry["expires_at"]),
                    subscriptionType: trimmed(entry["subscriptionType"] as? String) ?? trimmed(entry["subscription_type"] as? String)
                ),
                source: .desktop,
                fullData: fullData
            )
        }

        return nil
    }

    private func saveToFile(_ result: ClaudeCredentialResult) {
        let url = credentialsFileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let root = updatedFullData(for: result) else {
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func saveToKeychain(_ result: ClaudeCredentialResult) {
        if let keychainSaveOverride {
            keychainSaveOverride(result)
            return
        }

        guard
            let root = updatedFullData(for: result),
            let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        _ = try? ProcessRunner.runSync(
            executable: "/usr/bin/security",
            arguments: ["delete-generic-password", "-s", keychainService],
            input: nil,
            timeout: 10,
            currentDirectory: nil
        )

        _ = try? ProcessRunner.runSync(
            executable: "/usr/bin/security",
            arguments: ["add-generic-password", "-s", keychainService, "-w", json],
            input: nil,
            timeout: 10,
            currentDirectory: nil
        )
    }

    private func updatedFullData(for result: ClaudeCredentialResult) -> [String: Any]? {
        var root = result.fullData
        var oauth: [String: Any] = [
            "accessToken": result.oauth.accessToken,
        ]
        if let refreshToken = result.oauth.refreshToken {
            oauth["refreshToken"] = refreshToken
        }
        if let expiresAt = result.oauth.expiresAt {
            oauth["expiresAt"] = expiresAt
        }
        if let subscriptionType = result.oauth.subscriptionType {
            oauth["subscriptionType"] = subscriptionType
        }
        root["claudeAiOauth"] = oauth
        return root
    }

    private func parseExpiresAt(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func decryptClaudeDesktopValue(_ encryptedValue: String, password: String) -> String? {
        guard var data = Data(base64Encoded: encryptedValue) else {
            return nil
        }
        if data.starts(with: Data("v10".utf8)) {
            data.removeFirst(3)
        }
        return cryptClaudeDesktopValue(data, password: password, operation: CCOperation(kCCDecrypt))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Only used to build test fixtures; production code never encrypts or
    /// writes Claude Desktop state.
    func encryptClaudeDesktopValue(_ value: String, password: String) -> String? {
        guard let data = value.data(using: .utf8) else {
            return nil
        }
        guard let encrypted = cryptClaudeDesktopValue(data, password: password, operation: CCOperation(kCCEncrypt)) else {
            return nil
        }
        return (Data("v10".utf8) + encrypted).base64EncodedString()
    }

    private func cryptClaudeDesktopValue(_ data: Data, password: String, operation: CCOperation) -> Data? {
        guard let key = claudeDesktopSafeStorageKey(password: password) else {
            return nil
        }

        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = key.withUnsafeBytes { keyBytes in
            data.withUnsafeBytes { dataBytes in
                iv.withUnsafeBytes { ivBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            return nil
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private func claudeDesktopSafeStorageKey(password: String) -> Data? {
        let passwordBytes = Array(password.utf8)
        let saltBytes = Array("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyLength = key.count

        let status = key.withUnsafeMutableBytes { keyBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passwordBytes,
                passwordBytes.count,
                saltBytes,
                saltBytes.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                1003,
                keyBytes.bindMemory(to: UInt8.self).baseAddress,
                keyLength
            )
        }

        return status == kCCSuccess ? key : nil
    }

    func mapKeychainError(_ error: ProcessRunnerError) -> Result<ClaudeCredentialResult?, ClaudeCredentialLoadIssue> {
        guard case .terminated(_, let output) = error else {
            return .failure(.keychainFailure(error.localizedDescription))
        }

        let normalized = output.lowercased()
        if normalized.contains("could not be found in the keychain") || normalized.contains("item could not be found") {
            return .success(nil)
        }

        if normalized.contains("user interaction is not allowed")
            || normalized.contains("authorization was denied")
            || normalized.contains("user canceled")
            || normalized.contains("user cancelled") {
            return .failure(.keychainAccessDenied)
        }

        let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return .failure(.keychainFailure("Claude Keychain lookup failed."))
        }
        return .failure(.keychainFailure("Claude Keychain lookup failed: \(message)"))
    }
}
