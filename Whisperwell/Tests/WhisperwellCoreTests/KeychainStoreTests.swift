import XCTest
@testable import WhisperwellCore

/// Uses the real login keychain under a throwaway service name, removed afterwards.
final class KeychainStoreTests: XCTestCase {
    func testSaveReadUpdateDelete() throws {
        let store = KeychainStore(service: "Whisperwell-tests-\(UUID().uuidString)")
        addTeardownBlock { try? store.set("k", nil) }

        XCTAssertNil(try store.get("k"))
        try store.set("k", "one")
        XCTAssertEqual(try store.get("k"), "one")
        try store.set("k", "two")
        XCTAssertEqual(try store.get("k"), "two")
        try store.set("k", "")
        XCTAssertNil(try store.get("k"))
        XCTAssertNoThrow(try store.set("k", nil), "deleting a missing key is fine")
    }
}
