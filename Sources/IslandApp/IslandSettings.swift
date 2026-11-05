import Foundation
import IslandCore

enum IslandSettings {
    private enum Key {
        static let autoExpandOnBlocked = "autoExpandOnBlocked"
        static let autoExpandOnCompletion = "autoExpandOnCompletion"
        static let completionHold = "completionHold"
    }

    static func load(defaults: UserDefaults = .standard) -> IslandRules {
        var rules = IslandRules.default
        if defaults.object(forKey: Key.completionHold) != nil {
            let hold = defaults.double(forKey: Key.completionHold)
            if hold > 0 { rules.completionHold = hold }
        }
        return rules
    }

    static func loadToggles(defaults: UserDefaults = .standard) -> (blocked: Bool, completion: Bool) {
        let blocked = defaults.object(forKey: Key.autoExpandOnBlocked) == nil
            ? true
            : defaults.bool(forKey: Key.autoExpandOnBlocked)
        let completion = defaults.object(forKey: Key.autoExpandOnCompletion) == nil
            ? true
            : defaults.bool(forKey: Key.autoExpandOnCompletion)
        return (blocked, completion)
    }

    static func save(
        blocked: Bool,
        completion: Bool,
        hold: TimeInterval,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(blocked, forKey: Key.autoExpandOnBlocked)
        defaults.set(completion, forKey: Key.autoExpandOnCompletion)
        defaults.set(hold, forKey: Key.completionHold)
    }

    static func rules(defaults: UserDefaults = .standard) -> IslandRules {
        var rules = load(defaults: defaults)
        let toggles = loadToggles(defaults: defaults)
        rules.autoExpandOnBlocked = toggles.blocked
        rules.autoExpandOnCompletion = toggles.completion
        return rules
    }
}
