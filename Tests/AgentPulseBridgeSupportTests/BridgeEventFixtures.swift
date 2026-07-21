import Foundation

@testable import AgentPulseBridgeSupport

enum BridgeEventFixtures {
    static func decodedInput(from value: String?) -> [String: Any] {
        BridgeEventNormalizer.decodeInput(value.map { Data($0.utf8) } ?? Data())
    }

    static func encodedObject(for event: BridgeEvent) throws -> [String: Any] {
        let data = try JSONEncoder().encode(event)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
