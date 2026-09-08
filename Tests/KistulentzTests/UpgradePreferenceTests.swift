import Foundation
import XCTest
@testable import Kistulentz

final class UpgradePreferenceTests: XCTestCase {
    @MainActor
    func testLegacyBundlePreferencesAndLibraryLocationsMigrateWithoutReplacingNewValues() throws {
        let oldSuite = "KistulentzUpgradeTests.old.\(UUID().uuidString)"
        let newSuite = "KistulentzUpgradeTests.new.\(UUID().uuidString)"
        let oldDefaults = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        let newDefaults = try XCTUnwrap(UserDefaults(suiteName: newSuite))
        defer {
            oldDefaults.removePersistentDomain(forName: oldSuite)
            newDefaults.removePersistentDomain(forName: newSuite)
        }

        oldDefaults.set("anthropic", forKey: "selectedAIProvider")
        oldDefaults.set(11, forKey: "targetReadingGrade")
        oldDefaults.set("Georgia", forKey: "editorFontName")
        oldDefaults.set(20.0, forKey: "editorFontSize")
        oldDefaults.set("/Legacy/References", forKey: "referenceLibraryFolder")
        oldDefaults.set("/Legacy/Research", forKey: "Kistulentz.researchLibraryLocation")
        oldDefaults.set(
            Data("legacy-dismissals".utf8),
            forKey: "com.beauhenry.kistuletz.dismissedSuggestions.v1"
        )
        newDefaults.set(7, forKey: "targetReadingGrade")

        AppSettings.migrateLegacyDefaults(into: newDefaults, from: oldDefaults)

        XCTAssertEqual(newDefaults.string(forKey: "selectedAIProvider"), "anthropic")
        XCTAssertEqual(newDefaults.integer(forKey: "targetReadingGrade"), 7)
        XCTAssertEqual(newDefaults.string(forKey: "editorFontName"), "Georgia")
        XCTAssertEqual(newDefaults.double(forKey: "editorFontSize"), 20)
        XCTAssertEqual(newDefaults.string(forKey: "referenceLibraryFolder"), "/Legacy/References")
        XCTAssertEqual(
            newDefaults.string(forKey: "Kistulentz.researchLibraryLocation"),
            "/Legacy/Research"
        )
        XCTAssertEqual(
            newDefaults.data(forKey: "com.beauhenry.kistulentz.dismissedSuggestions.v1"),
            Data("legacy-dismissals".utf8)
        )
    }

    @MainActor
    func testWhatsNewAppearsOnlyForAnUpgradedOnboardedUserUntilAcknowledged() throws {
        let suite = "KistulentzWhatsNewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set("0.16.0", forKey: "lastSeenAppVersion")

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.shouldPresentWhatsNew(for: "0.16.1"))

        settings.acknowledgeWhatsNew(for: "0.16.1")

        XCTAssertFalse(settings.shouldPresentWhatsNew(for: "0.16.1"))
        XCTAssertEqual(AppSettings(defaults: defaults).lastSeenAppVersion, "0.16.1")
    }

    @MainActor
    func testFreshInstallDoesNotPutWhatsNewBeforeOnboarding() throws {
        let suite = "KistulentzWhatsNewFreshTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.shouldPresentWhatsNew(for: "0.16.1"))
    }
}
