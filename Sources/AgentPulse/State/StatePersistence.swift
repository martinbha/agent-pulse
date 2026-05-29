import Foundation

struct StatePersistence: Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        self.encoder = encoder
        self.decoder = decoder

        if let fileURL {
            self.fileURL = fileURL
        } else {
            let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = supportURL
                .appendingPathComponent("AgentPulse", isDirectory: true)
                .appendingPathComponent("state.json")
        }
    }

    func load() throws -> [AgentKind: AgentStatusSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let stored = try decoder.decode([String: AgentStatusSnapshot].self, from: data)
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            guard let agent = AgentKind(rawValue: key) else {
                return nil
            }
            return (agent, value)
        })
    }

    func save(_ snapshots: [AgentKind: AgentStatusSnapshot]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stored = Dictionary(uniqueKeysWithValues: snapshots.map { agent, snapshot in
            (agent.rawValue, snapshot)
        })

        let data = try encoder.encode(stored)
        try data.write(to: fileURL, options: .atomic)
    }
}

