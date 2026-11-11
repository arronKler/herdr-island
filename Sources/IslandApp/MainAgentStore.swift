import Foundation
import IslandCore

/// Persists which agent the composer treats as the main recipient. Only the
/// identity is stored; status, title, and project are re-resolved from the
/// live sample on every presentation.
struct MainAgentStore {
    private let defaults: UserDefaults
    private let key = "herdrIsland.mainAgent"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MainAgentIdentity? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MainAgentIdentity.self, from: data)
    }

    func save(_ identity: MainAgentIdentity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        defaults.set(data, forKey: key)
    }
}
