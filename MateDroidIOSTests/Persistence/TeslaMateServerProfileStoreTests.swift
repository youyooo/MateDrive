import XCTest
@testable import MateDroidIOS

final class TeslaMateServerProfileStoreTests: XCTestCase {
    func testStoreRoundTripsAndReplacesAProfileAtomically() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = TeslaMateServerProfileStore(database: database)
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)
        let first = profile(serverKey: "server", date: firstDate, state: .available)
        let second = profile(serverKey: "server", date: secondDate, state: .degraded)

        try await store.save(first)
        let storedFirst = try await store.profile(serverKey: "server", carId: 1)
        XCTAssertEqual(storedFirst, first)

        try await store.save(second)
        let storedSecond = try await store.profile(serverKey: "server", carId: 1)
        XCTAssertEqual(storedSecond, second)
    }

    func testDeleteRemovesOnlyMatchingServer() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let store = TeslaMateServerProfileStore(database: database)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = profile(serverKey: "server-one", date: date, state: .available)
        let second = profile(serverKey: "server-two", date: date, state: .available)
        try await store.save(first)
        try await store.save(second)

        try await store.delete(serverKey: "server-one")

        let deleted = try await store.profile(serverKey: "server-one", carId: 1)
        let retained = try await store.profile(serverKey: "server-two", carId: 1)
        XCTAssertNil(deleted)
        XCTAssertEqual(retained, second)
    }

    func testDatabaseTransactionRollsBackEarlierCommandsWhenLaterCommandFails() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await database.execute("CREATE TABLE transaction_test (value TEXT NOT NULL);")

        do {
            try await database.performTransaction([
                SQLiteCommand("INSERT INTO transaction_test (value) VALUES (?);", bindings: [.text("first")]),
                SQLiteCommand("INSERT INTO missing_table (value) VALUES (?);", bindings: [.text("fail")])
            ])
            XCTFail("Expected transaction failure")
        } catch {
            XCTAssertTrue(error is SQLiteError)
        }

        let values = try await database.textValues("SELECT value FROM transaction_test;")
        XCTAssertEqual(values, [])
    }

    private func profile(
        serverKey: String,
        date: Date,
        state: TeslaMateCapabilityState
    ) -> TeslaMateServerProfile {
        TeslaMateServerProfile(
            serverKey: serverKey,
            carId: 1,
            version: TeslaMateVersionInfo(
                apiVersion: "unknown",
                mtAPIVersion: "2.4.1",
                buildInfo: "TeslaMate API"
            ),
            capabilities: [
                .serverStats: TeslaMateCapabilityStatus(
                    state: state,
                    reason: state == .degraded ? .paginationMetadataInvalid : nil,
                    source: .endpointProbe,
                    checkedAt: date,
                    lastSuccessfulAt: date
                )
            ],
            connectionIssue: .authentication(statusCode: 401),
            checkedAt: date,
            lastSuccessfulCheckAt: date
        )
    }
}
