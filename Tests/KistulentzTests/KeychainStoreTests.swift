import Foundation
import Security
import XCTest
@testable import Kistulentz

/// Exercises the real macOS Keychain through `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`,
/// matching how `swift test --disable-sandbox` already runs this suite (see README.md and
/// .github/workflows/ci.yml). Every test uses a freshly generated, UUID-suffixed account name and
/// cleans up after itself, so nothing here can collide with or clobber a real stored API key —
/// production only ever reads/writes the fixed "openai-api-key" / "anthropic-api-key" accounts
/// (see AIProvider.keychainAccount in AppSettings.swift), which this file never touches.
final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore()

    override func setUpWithError() throws {
        // Some environments (a locked keychain, a headless session with no keychain at all) can't
        // reach the Keychain even outside of SwiftPM's build sandbox. Skip rather than fail the
        // whole suite if a trivial save/delete round trip doesn't work here.
        let canary = uniqueAccount()
        do {
            try store.save("canary", account: canary)
            try store.delete(account: canary)
        } catch {
            throw XCTSkip("Keychain is not reachable in this environment: \(error.localizedDescription)")
        }
    }

    // MARK: - Save / read / delete

    func testSaveThenReadRoundTripsTheValue() throws {
        let account = uniqueAccount()
        defer { try? store.delete(account: account) }

        try store.save("sk-test-abc123", account: account)

        XCTAssertEqual(store.read(account: account), "sk-test-abc123")
    }

    func testSavingAnEmptyStringRoundTrips() throws {
        let account = uniqueAccount()
        defer { try? store.delete(account: account) }

        try store.save("", account: account)

        XCTAssertEqual(store.read(account: account), "")
    }

    func testSavingTwiceOverwritesThePreviousValueWithoutThrowing() throws {
        let account = uniqueAccount()
        defer { try? store.delete(account: account) }

        try store.save("first-value", account: account)
        try store.save("second-value", account: account)

        XCTAssertEqual(store.read(account: account), "second-value")
    }

    func testDeleteRemovesTheStoredValue() throws {
        let account = uniqueAccount()
        try store.save("to-be-deleted", account: account)

        try store.delete(account: account)

        XCTAssertNil(store.read(account: account))
    }

    func testDeletingAnAccountThatWasNeverStoredDoesNotThrow() {
        XCTAssertNoThrow(try store.delete(account: uniqueAccount()))
    }

    func testReadingAnAccountThatWasNeverStoredReturnsNil() {
        XCTAssertNil(store.read(account: uniqueAccount()))
    }

    // MARK: - Legacy service fallback

    /// Kistulentz shipped under two earlier bundle identities ("com.beauhenry.kistuletz", a typo
    /// fix, and "com.draftsmith.mac", from before the app was renamed from DraftSmith). `read`
    /// falls back through both so a key stored under an old install isn't silently lost. This
    /// seeds an entry directly under the older service name — bypassing `KeychainStore.save`,
    /// which only ever writes to the *current* service — to prove that fallback actually works.
    func testReadFallsBackToAPreDraftSmithRenameServiceName() throws {
        let account = uniqueAccount()
        let legacyService = "com.draftsmith.mac"
        defer { try? store.delete(account: account) }

        try addLegacyItem(value: "legacy-key", account: account, service: legacyService)

        XCTAssertEqual(store.read(account: account), "legacy-key")
    }

    func testReadFallsBackToTheKistuletzTypoServiceName() throws {
        let account = uniqueAccount()
        let legacyService = "com.beauhenry.kistuletz"
        defer { try? store.delete(account: account) }

        try addLegacyItem(value: "legacy-key", account: account, service: legacyService)

        XCTAssertEqual(store.read(account: account), "legacy-key")
    }

    func testCurrentServiceTakesPrecedenceOverALegacyServiceForTheSameAccount() throws {
        let account = uniqueAccount()
        defer { try? store.delete(account: account) }

        try addLegacyItem(value: "legacy-key", account: account, service: "com.draftsmith.mac")
        try store.save("current-key", account: account)

        XCTAssertEqual(store.read(account: account), "current-key")
    }

    func testDeleteClearsTheValueFromEveryLegacyServiceToo() throws {
        let account = uniqueAccount()
        try addLegacyItem(value: "legacy-key", account: account, service: "com.draftsmith.mac")

        try store.delete(account: account)

        XCTAssertNil(store.read(account: account))
    }

    // MARK: - KeychainError

    func testInvalidValueErrorHasAUserFacingDescription() {
        let error = KeychainError.invalidValue

        XCTAssertEqual(error.errorDescription, "The API key could not be stored.")
    }

    func testStatusErrorAlwaysProducesANonEmptyDescription() {
        // Don't pin the exact wording of SecCopyErrorMessageString's system-provided text (it can
        // vary by OS version); just confirm every status code still surfaces *some* message to
        // show the person instead of a blank alert.
        for status: OSStatus in [errSecItemNotFound, errSecDuplicateItem, errSecAuthFailed, -99_999] {
            let description = KeychainError.status(status).errorDescription
            XCTAssertNotNil(description, "status \(status) produced no description")
            XCTAssertFalse(description?.isEmpty ?? true, "status \(status) produced an empty description")
        }
    }

    // MARK: - Helpers

    private func uniqueAccount() -> String {
        "kistulentz-tests-\(UUID().uuidString)"
    }

    /// Writes directly to the Keychain under an arbitrary service name, bypassing
    /// `KeychainStore` entirely. Used to simulate a value left behind by an older Kistulentz
    /// install, which `KeychainStore.save` (always writes to the current service) cannot do.
    private func addLegacyItem(value: String, account: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.status(status)
        }
    }
}
