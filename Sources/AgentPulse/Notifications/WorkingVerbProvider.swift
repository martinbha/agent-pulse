import Foundation

struct WorkingVerbProvider {
    private let verbs: [String]

    init(verbs: [String] = Self.loadVerbs()) {
        self.verbs = verbs.isEmpty ? ["Working"] : verbs
    }

    func randomVerb() -> String {
        verbs.randomElement() ?? "Working"
    }

    private static func loadVerbs() -> [String] {
        let urls = [
            Bundle.main.url(forResource: "working-verbs", withExtension: "txt"),
            sourceResourceURL
        ].compactMap { $0 }

        for url in urls {
            if let verbs = try? loadVerbs(from: url), !verbs.isEmpty {
                return verbs
            }
        }

        return ["Working"]
    }

    private static var sourceResourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("working-verbs.txt")
    }

    private static func loadVerbs(from url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
