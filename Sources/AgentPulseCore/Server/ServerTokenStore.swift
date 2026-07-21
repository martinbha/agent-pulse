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
        return candidate == token
    }
}
