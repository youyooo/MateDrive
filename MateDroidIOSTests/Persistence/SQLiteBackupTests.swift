import XCTest
@testable import MateDroidIOS

final class SQLiteBackupTests: XCTestCase {
    func testOnlineBackupCreatesAnIndependentConsistentSnapshot() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let liveURL = directory.appendingPathComponent("live.sqlite")
        let snapshotURL = directory.appendingPathComponent("snapshot.sqlite")
        let database = try SQLiteDatabase.open(path: liveURL.path)
        try await database.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY, value TEXT NOT NULL);")
        try await database.run("INSERT INTO sample VALUES (1, 'before');")
        try await database.setUserVersion(7)

        let metadata = try await database.backup(to: snapshotURL)
        try await database.run("INSERT INTO sample VALUES (2, 'after');")

        let snapshot = try SQLiteDatabase.open(path: snapshotURL.path)
        let snapshotIDs = try await snapshot.intValues("SELECT id FROM sample ORDER BY id;")
        let snapshotIsValid = try await snapshot.integrityCheck()
        XCTAssertEqual(snapshotIDs, [1])
        XCTAssertEqual(metadata.schemaVersion, 7)
        XCTAssertGreaterThan(metadata.byteCount, 0)
        XCTAssertTrue(snapshotIsValid)
    }

    func testRestoreUsesSnapshotAsSourceWithoutReplacingConnection() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let liveURL = directory.appendingPathComponent("live.sqlite")
        let sourceURL = directory.appendingPathComponent("source.sqlite")
        let database = try SQLiteDatabase.open(path: liveURL.path)
        try await database.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY);")
        try await database.run("INSERT INTO sample VALUES (1);")

        let source = try SQLiteDatabase.open(path: sourceURL.path)
        try await source.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY);")
        try await source.run("INSERT INTO sample VALUES (9);")
        try await source.setUserVersion(11)

        try await database.restore(from: sourceURL)

        let restoredIDs = try await database.intValues("SELECT id FROM sample;")
        let restoredVersion = try await database.userVersion()
        XCTAssertEqual(restoredIDs, [9])
        XCTAssertEqual(restoredVersion, 11)
        try await database.run("INSERT INTO sample VALUES (10);")
        let updatedIDs = try await database.intValues("SELECT id FROM sample ORDER BY id;")
        XCTAssertEqual(updatedIDs, [9, 10])
    }

    func testRestoreRejectsCorruptSnapshotBeforeChangingLiveData() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let liveURL = directory.appendingPathComponent("live.sqlite")
        let corruptURL = directory.appendingPathComponent("corrupt.sqlite")
        let database = try SQLiteDatabase.open(path: liveURL.path)
        try await database.execute("CREATE TABLE sample (id INTEGER PRIMARY KEY);")
        try await database.run("INSERT INTO sample VALUES (1);")
        try Data("not a sqlite database".utf8).write(to: corruptURL)

        do {
            try await database.restore(from: corruptURL)
            XCTFail("Expected corrupt snapshot to be rejected")
        } catch {
            let liveIDs = try await database.intValues("SELECT id FROM sample;")
            XCTAssertEqual(liveIDs, [1])
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SQLiteBackupTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
