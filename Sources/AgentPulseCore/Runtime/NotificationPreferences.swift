import Foundation

@MainActor
final class NotificationPreferences: ObservableObject {
    @Published private(set) var playsSounds: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.playsSounds = defaults.object(forKey: Keys.playsSounds) as? Bool ?? false
    }

    @discardableResult
    func setPlaysSounds(_ enabled: Bool) -> Bool {
        guard playsSounds != enabled else {
            return false
        }

        playsSounds = enabled
        defaults.set(enabled, forKey: Keys.playsSounds)
        return true
    }

    private enum Keys {
        static let playsSounds = "notifications.playSounds"
    }
}
