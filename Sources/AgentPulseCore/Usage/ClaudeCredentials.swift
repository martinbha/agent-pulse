import Foundation

struct ClaudeOAuthCredentials: Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Double?
    var subscriptionType: String?
}

enum ClaudeCredentialSource: Sendable, Equatable {
    case file
    case keychain
    case environment
    case desktop
}

enum ClaudeCredentialLoadIssue: Error, Sendable, Equatable {
    case keychainAccessDenied
    case keychainFailure(String)

    var message: String {
        switch self {
        case .keychainAccessDenied:
            return "Claude Keychain access denied."
        case .keychainFailure(let message):
            return message
        }
    }
}

struct ClaudeCredentialResult: @unchecked Sendable {
    var oauth: ClaudeOAuthCredentials
    let source: ClaudeCredentialSource
    var fullData: [String: Any]
}

struct ClaudeCredentialResolution {
    let credentials: ClaudeCredentialResult?
    let issue: ClaudeCredentialLoadIssue?
}
