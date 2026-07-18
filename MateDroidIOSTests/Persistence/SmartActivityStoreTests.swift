import XCTest
@testable import MateDroidIOS

final class SmartActivityStoreTests: XCTestCase {
    func testSessionRoundTripPreservesUnavailableValuesAndReturnsNewestFirst() async throws {
        let stores = try await SmartActivityTestStores.make()
        let older = SmartActivitySession.fixture(
            id: "older",
            startDate: Date(timeIntervalSince1970: 1_720_000_000),
            classification: nil
        )
        let newer = SmartActivitySession.fixture(
            id: "newer",
            startDate: Date(timeIntervalSince1970: 1_720_003_600),
            classification: .fixture
        )

        try await stores.sessions.replace(carId: 1, sessions: [older, newer])

        let sessions = try await stores.sessions.sessions(carId: 1)
        let loadedOlder = try await stores.sessions.session(carId: 1, sessionId: older.id)
        XCTAssertEqual(sessions, [newer, older])
        XCTAssertEqual(loadedOlder, older)
        let indexedValues = try await stores.database.rows(
            "SELECT end_date, confidence FROM vehicle_activity_sessions WHERE session_id = ?;",
            bindings: [.text(older.id)]
        )
        XCTAssertEqual(indexedValues, [[.null, .null]])
    }

    func testReplacingDerivedSessionsDoesNotDeleteUserOverridesOrPricingObservations() async throws {
        let stores = try await SmartActivityTestStores.make()
        let session = SmartActivitySession.fixture(classification: .fixture)
        let label = ActivityLabelOverride.fixture(purpose: .custom)
        let observation = ChargePricingObservation.fixture()
        try await stores.labels.save(label)
        try await stores.pricing.save(observation)
        try await stores.sessions.replace(carId: 1, sessions: [session])

        try await stores.sessions.replace(carId: 1, sessions: [])

        let sessions = try await stores.sessions.sessions(carId: 1)
        let loadedLabel = try await stores.labels.override(id: label.id)
        let observations = try await stores.pricing.observations(
            carId: 1,
            stationKey: observation.stationKey
        )
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(loadedLabel, label)
        XCTAssertEqual(observations, [observation])
        XCTAssertNotEqual(label.purpose, session.classification?.purpose)
    }

    func testEmptyReplacementOnlyRemovesRequestedCarsDerivedSessions() async throws {
        let stores = try await SmartActivityTestStores.make()
        let firstCar = SmartActivitySession.fixture(id: "car-1", carId: 1)
        let secondCar = SmartActivitySession.fixture(id: "car-2", carId: 2)
        try await stores.sessions.replace(carId: 1, sessions: [firstCar])
        try await stores.sessions.replace(carId: 2, sessions: [secondCar])

        try await stores.sessions.replace(carId: 1, sessions: [])

        let firstCarSessions = try await stores.sessions.sessions(carId: 1)
        let secondCarSessions = try await stores.sessions.sessions(carId: 2)
        XCTAssertTrue(firstCarSessions.isEmpty)
        XCTAssertEqual(secondCarSessions, [secondCar])
    }

    func testFailedReplacementRollsBackDeletionAndPartialInserts() async throws {
        let stores = try await SmartActivityTestStores.make()
        let existing = SmartActivitySession.fixture(id: "existing")
        try await stores.sessions.replace(carId: 1, sessions: [existing])
        let firstDuplicate = SmartActivitySession.fixture(
            id: "duplicate",
            startDate: Date(timeIntervalSince1970: 1_720_003_600)
        )
        let secondDuplicate = SmartActivitySession.fixture(
            id: "duplicate",
            startDate: Date(timeIntervalSince1970: 1_720_007_200)
        )

        do {
            try await stores.sessions.replace(
                carId: 1,
                sessions: [firstDuplicate, secondDuplicate]
            )
            XCTFail("Expected duplicate session IDs to fail")
        } catch {
            let sessions = try await stores.sessions.sessions(carId: 1)
            XCTAssertEqual(sessions, [existing])
        }
    }

    func testMalformedSessionPayloadIsSkipped() async throws {
        let stores = try await SmartActivityTestStores.make()
        let valid = SmartActivitySession.fixture()
        try await stores.sessions.replace(carId: 1, sessions: [valid])
        try await stores.database.run(
            """
            INSERT INTO vehicle_activity_sessions
            (session_id, car_id, start_date, end_date, place_key, purpose, confidence,
             quality, derivation_version, source_fingerprint, derivation_fingerprint,
             payload_json, updated_at)
            VALUES (?, ?, ?, NULL, ?, ?, NULL, ?, ?, ?, ?, ?, ?);
            """,
            bindings: [
                .text("malformed"), .int(1), .text("2026-07-19T00:00:00Z"),
                .text("broken"), .text("parking"), .text("unavailable"), .int(1),
                .text("source"), .text("derived"), .text("not-json"),
                .text("2026-07-19T00:00:00Z")
            ]
        )

        let sessions = try await stores.sessions.sessions(carId: 1)
        XCTAssertEqual(sessions, [valid])
    }

    func testLabelOverridesRoundTripInDeterministicOrderAndCanBeDeleted() async throws {
        let stores = try await SmartActivityTestStores.make()
        let older = ActivityLabelOverride.fixture(
            id: "older-label",
            customName: nil,
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let newer = ActivityLabelOverride.fixture(
            id: "newer-label",
            updatedAt: Date(timeIntervalSince1970: 1_720_003_600)
        )
        try await stores.labels.save(older)
        try await stores.labels.save(newer)

        let initialOverrides = try await stores.labels.overrides(carId: 1)
        let loadedOlder = try await stores.labels.override(id: older.id)
        XCTAssertEqual(initialOverrides, [newer, older])
        XCTAssertEqual(loadedOlder, older)
        try await stores.labels.delete(id: newer.id)
        let afterDelete = try await stores.labels.overrides(carId: 1)
        XCTAssertEqual(afterDelete, [older])
        try await stores.labels.removeAll()
        let afterRemoveAll = try await stores.labels.overrides(carId: 1)
        XCTAssertTrue(afterRemoveAll.isEmpty)
    }

    func testPricingObservationsRoundTripNilValuesNewestFirstAndCanBeRemoved() async throws {
        let stores = try await SmartActivityTestStores.make()
        let older = ChargePricingObservation.fixture(
            id: "older-price",
            billedEnergyKWh: nil,
            pricePerKWh: nil,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            confirmedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let newer = ChargePricingObservation.fixture(
            id: "newer-price",
            confirmedAt: Date(timeIntervalSince1970: 1_720_003_600)
        )
        try await stores.pricing.save(older)
        try await stores.pricing.save(newer)

        let observations = try await stores.pricing.observations(carId: 1, stationKey: "station:home")
        XCTAssertEqual(observations, [newer, older])
        try await stores.pricing.removeAll()
        let afterRemoveAll = try await stores.pricing.observations(carId: 1, stationKey: "station:home")
        XCTAssertTrue(afterRemoveAll.isEmpty)
    }

    func testDatabaseRestoreIncludesSessionsOverridesAndPricingObservations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SmartActivityStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try SQLiteDatabase.open(path: directory.appendingPathComponent("source.sqlite").path)
        try await Migrations.applyAll(to: source)
        let sourceStores = SmartActivityTestStores(database: source)
        let session = SmartActivitySession.fixture()
        let label = ActivityLabelOverride.fixture()
        let observation = ChargePricingObservation.fixture()
        try await sourceStores.sessions.replace(carId: 1, sessions: [session])
        try await sourceStores.labels.save(label)
        try await sourceStores.pricing.save(observation)
        let snapshotURL = directory.appendingPathComponent("snapshot.sqlite")
        _ = try await source.backup(to: snapshotURL)
        let restored = try SQLiteDatabase.open(path: directory.appendingPathComponent("restored.sqlite").path)

        try await restored.restore(from: snapshotURL)

        let restoredStores = SmartActivityTestStores(database: restored)
        let sessions = try await restoredStores.sessions.sessions(carId: 1)
        let labels = try await restoredStores.labels.overrides(carId: 1)
        let observations = try await restoredStores.pricing.observations(
            carId: 1,
            stationKey: observation.stationKey
        )
        XCTAssertEqual(sessions, [session])
        XCTAssertEqual(labels, [label])
        XCTAssertEqual(observations, [observation])
    }
}

private struct SmartActivityTestStores {
    let database: SQLiteDatabase
    let sessions: SmartActivityStore
    let labels: ActivityLabelOverrideStore
    let pricing: ChargePricingObservationStore

    init(database: SQLiteDatabase) {
        self.database = database
        sessions = SmartActivityStore(database: database)
        labels = ActivityLabelOverrideStore(database: database)
        pricing = ChargePricingObservationStore(database: database)
    }

    static func make() async throws -> SmartActivityTestStores {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        return SmartActivityTestStores(database: database)
    }
}

private extension ActivityClassificationResult {
    static let fixture = ActivityClassificationResult(
        purpose: .commute,
        confidence: 0.75,
        source: .heuristic,
        reasons: [.repeatedRoute],
        classifierVersion: 2
    )
}

private extension SmartActivitySession {
    static func fixture(
        id: String = "session-1",
        carId: Int = 1,
        startDate: Date = Date(timeIntervalSince1970: 1_720_000_000),
        classification: ActivityClassificationResult? = nil
    ) -> SmartActivitySession {
        SmartActivitySession(
            id: id,
            carId: carId,
            startDate: startDate,
            endDate: nil,
            placeKey: "place:home",
            latitude: nil,
            longitude: nil,
            geofenceID: nil,
            provisionalKind: .parking,
            classification: classification,
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: [],
            isOpen: true,
            quality: .unavailable,
            derivationVersion: 3,
            sourceFingerprint: "source-1",
            derivationFingerprint: "derived-1"
        )
    }
}

private extension ActivityLabelOverride {
    static func fixture(
        id: String = "label-1",
        purpose: SmartActivityPurpose = .homeCharging,
        customName: String? = "Home",
        startMinute: Int? = 480,
        endMinute: Int? = 600,
        updatedAt: Date = Date(timeIntervalSince1970: 1_720_000_000)
    ) -> ActivityLabelOverride {
        ActivityLabelOverride(
            id: id,
            carId: 1,
            sessionId: "session-1",
            placeKey: "place:home",
            scope: .futureAtPlace,
            purpose: purpose,
            customName: customName,
            icon: "house",
            colorHex: "#336699",
            startMinute: startMinute,
            endMinute: endMinute,
            updatedAt: updatedAt
        )
    }
}

private extension ChargePricingObservation {
    static func fixture(
        id: String = "price-1",
        billedEnergyKWh: Double? = 20,
        pricePerKWh: Double? = 0.8,
        serviceFeePerKWh: Double? = 0.2,
        fixedFee: Double? = 1,
        confirmedAt: Date = Date(timeIntervalSince1970: 1_720_000_000)
    ) -> ChargePricingObservation {
        ChargePricingObservation(
            id: id,
            carId: 1,
            chargeId: 42,
            stationKey: "station:home",
            scope: .futureAtStation,
            finalAmount: 21,
            billedEnergyKWh: billedEnergyKWh,
            pricePerKWh: pricePerKWh,
            serviceFeePerKWh: serviceFeePerKWh,
            fixedFee: fixedFee,
            currencyCode: "CNY",
            confirmedAt: confirmedAt
        )
    }
}
