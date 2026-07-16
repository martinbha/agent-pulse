import Foundation

@testable import AgentPulseCore

enum AgentEventFixtures {
    static func decodedEvent(fromJSON json: String) -> AgentEvent? {
        try? AgentPulseJSON.decoder.decode(AgentEvent.self, from: Data(json.utf8))
    }
}
