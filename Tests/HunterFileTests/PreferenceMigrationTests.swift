import XCTest
@testable import HunterFile

final class PreferenceMigrationTests: XCTestCase {
    func testRenamePreservesOldValuesWithoutReplacingNewOnes() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let old = UUID().uuidString, new = UUID().uuidString, qa = UUID().uuidString
        defer { for name in [old, new, qa] { defaults.removePersistentDomain(forName: name) } }
        defaults.setPersistentDomain(["libraryPath": "/old/library.openeagle", "semanticEnabled": true], forName: old)
        defaults.setPersistentDomain(["semanticEnabled": false], forName: new)
        PreferenceMigration.migrate(defaults, from: old, to: new)
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["libraryPath"] as? String, "/old/library.openeagle")
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["semanticEnabled"] as? Bool, false)
        XCTAssertNil(defaults.persistentDomain(forName: qa))
        defaults.setPersistentDomain(["libraryPath": "/changed"], forName: old)
        PreferenceMigration.migrate(defaults, from: old, to: new)
        XCTAssertEqual(defaults.persistentDomain(forName: new)?["libraryPath"] as? String, "/old/library.openeagle")
    }
}
