import Foundation

final class ServerTokenStore: @unchecked Sendable {
    private let lock = NSLock()
    private var token: String

    init(token: String) {
        self.token = token
    }

    func replace(with token: String) {
        lock.lock()
        defer { lock.unlock() }
        self.token = token
    }

    func matches(_ candidate: String?) -> Bool {
        guard let candidate else {
            return false
        }

        lock.lock()
        defer { lock.unlock() }

        let candidateBytes = Array(candidate.utf8)
        let tokenBytes = Array(token.utf8)
        var difference = candidateBytes.count ^ tokenBytes.count

        for index in 0..<max(candidateBytes.count, tokenBytes.count) {
            let candidateByte = index < candidateBytes.count ? candidateBytes[index] : 0
            let tokenByte = index < tokenBytes.count ? tokenBytes[index] : 0
            difference |= Int(candidateByte ^ tokenByte)
        }

        return difference == 0
    }
}
