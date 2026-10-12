import XCTest
@testable import HunterFiles

final class PreferenceMigrationTests: XCTestCase {
    func testRenamePreservesOldValuesWithoutReplacingNewOnes() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let old = UUID().uuidString, new = UUID().uuidString, qa = UUID().uuidString
        defer { for name in [old, new, qa] { defaults.removePersistentDomain(forName: name) } }
        defaults.setPersistentDomain(["libraryPath": "/old/library.openeagle", "semanticEnabled": true], forName: old)
        defaults.setPersistentDomain(["semanticEnabled": false], forName: new)
        PreferenceMigration.migrate(defaults, from: [old], to: new)
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["libraryPath"] as? String, "/old/library.openeagle")
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["semanticEnabled"] as? Bool, false)
        XCTAssertNil(defaults.persistentDomain(forName: qa))
        defaults.setPersistentDomain(["libraryPath": "/changed"], forName: old)
        PreferenceMigration.migrate(defaults, from: [old], to: new)
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["libraryPath"] as? String, "/old/library.openeagle")
    }
    func testNearestBrandWinsAndOriginalBrandFillsMissingPreferences() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let original = UUID().uuidString, previous = UUID().uuidString, current = UUID().uuidString
        defer { for name in [original, previous, current] { defaults.removePersistentDomain(forName: name) } }
        defaults.setPersistentDomain(["libraryPath": "/original", "appearance": "dark", "hoverPreview": true], forName: original)
        defaults.setPersistentDomain(["libraryPath": "/previous", "localModelPath": "/model", "hunterFileMigration": true], forName: previous)
        defaults.setPersistentDomain(["appearance": "light"], forName: current)
        PreferenceMigration.migrate(defaults, from: [previous, original], to: current)
        let values = defaults.persistentDomain(forName: current)!
        XCTAssertEqual(values["libraryPath"] as? String, "/previous")
        XCTAssertEqual(values["localModelPath"] as? String, "/model")
        XCTAssertEqual(values["appearance"] as? String, "light")
        XCTAssertEqual(values["hoverPreview"] as? Bool, true)
        XCTAssertEqual(values["hunterFilesMigration"] as? Bool, true)
    }
}
