import XCTest
@testable import MateDroidIOS

final class KeychainStoreTests: XCTestCase {
    func testSetGetAndRemoveSecret() async throws {
        let store = KeychainStore(service: "com.matedrive.ios.tests.\(UUID().uuidString)")

        try await store.set("secret-value", for: "apiToken")
        let saved = try await store.get("apiToken")
        XCTAssertEqual(saved, "secret-value")

        try await store.remove("apiToken")
        let removed = try await store.get("apiToken")
        XCTAssertNil(removed)
    }
}
