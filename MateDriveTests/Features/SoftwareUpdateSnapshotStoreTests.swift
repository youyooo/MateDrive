import XCTest
@testable import MateDriveApp

final class SoftwareUpdateSnapshotStoreTests: XCTestCase {
    func testReleaseMemoryPreservesProtectedDiskFallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoftwareUpdateSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storageURL = directory.appendingPathComponent("software-updates.json")
        let store = SoftwareUpdateSnapshotStore(storageURL: storageURL)
        let snapshot = SoftwareUpdateSnapshot(
            updates: [UpdateData(version: "2026.26.5", startDate: "2026-07-27")],
            savedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        await store.save(snapshot, serverURL: "https://example.invalid", carId: 7)

        await store.releaseMemory()

        let restored = await store.load(serverURL: "https://example.invalid", carId: 7)
        XCTAssertEqual(restored, snapshot)
    }
}
