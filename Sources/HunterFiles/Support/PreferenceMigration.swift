import Foundation

enum PreferenceMigration {
    static func migrate(_ defaults: UserDefaults, from legacy: [String], to current: String) {
        var values = defaults.persistentDomain(forName: current) ?? [:]
        guard values["hunterFilesMigration"] == nil else { return }
        for domain in legacy {
            for (key, value) in defaults.persistentDomain(forName: domain) ?? [:] where values[key] == nil { values[key] = value }
        }
        values["hunterFilesMigration"] = true
        defaults.setPersistentDomain(values, forName: current)
    }
}
