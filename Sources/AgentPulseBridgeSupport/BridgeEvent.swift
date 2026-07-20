import Foundation

struct BridgeEvent: Codable, Equatable, Sendable {
    var agent: String
    var state: String
    var event: String
    var sessionID: String?
    var cwd: String
    var project: String?
    var timestamp: String
    var source: String
    var hostBundleID: String?

    enum CodingKeys: String, CodingKey {
        case agent
        case state
        case event
        case sessionID = "session_id"
        case cwd
        case project
        case timestamp
        case source
        case hostBundleID = "host_bundle_id"
    }
}
