import Foundation

enum PreferenceMigration {
    static func migrate(_ defaults: UserDefaults, from legacy: String, to current: String) {
        var values = defaults.persistentDomain(forName: current) ?? [:]
        guard values["hunterFileMigration"] == nil else { return }
        for (key, value) in defaults.persistentDomain(forName: legacy) ?? [:] where values[key] == nil { values[key] = value }
        values["hunterFileMigration"] = true
        defaults.setPersistentDomain(values, forName: current)
    }
}
