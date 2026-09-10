import XCTest
@testable import MateDriveApp

final class SmartActivityPrivacyTests: XCTestCase {
    func testClearDerivedDataPreservesLearnedAndManualValues() async throws {
        let sessions = PrivacySessionStore(values: [Self.sessionFixture])
        let labels = PrivacyLabelStore(values: [Self.labelFixture])
        let prices = PrivacyPricingStore(values: [Self.pricingFixture])
        let controller = SmartActivityPrivacyDataController(
            sessionStore: sessions,
            labelStore: labels,
            pricingObservationStore: prices
        )

        try await controller.clearDerivedData()
        let remainingSessions = try await sessions.sessions(carId: 1)
        let remainingLabel = try await labels.override(id: Self.labelFixture.id)
        let remainingPrices = try await prices.observations(carId: 1, stationKey: "station")

        XCTAssertTrue(remainingSessions.isEmpty)
        XCTAssertEqual(remainingLabel, Self.labelFixture)
        XCTAssertEqual(remainingPrices, [Self.pricingFixture])
    }

    func testClearLearnedDataRemovesDurableDecisionsAndInvalidatesDerivedSessions() async throws {
        let sessions = PrivacySessionStore(values: [Self.sessionFixture])
        let labels = PrivacyLabelStore(values: [Self.labelFixture])
        let prices = PrivacyPricingStore(values: [Self.pricingFixture])
        let controller = SmartActivityPrivacyDataController(
            sessionStore: sessions,
            labelStore: labels,
            pricingObservationStore: prices
        )

        try await controller.clearLearnedData()
        let remainingSessions = try await sessions.sessions(carId: 1)
        let remainingLabel = try await labels.override(id: Self.labelFixture.id)
        let remainingPrices = try await prices.observations(carId: 1, stationKey: "station")

        XCTAssertTrue(remainingSessions.isEmpty)
        XCTAssertNil(remainingLabel)
        XCTAssertTrue(remainingPrices.isEmpty)
    }

    private static let sessionFixture = SmartActivitySession(
        id: "privacy-session",
        carId: 1,
        startDate: Date(timeIntervalSince1970: 1_720_000_000),
        endDate: nil,
        placeKey: "station",
        latitude: nil,
        longitude: nil,
        geofenceID: nil,
        provisionalKind: .parking,
        classification: nil,
        parkingMetrics: nil,
        chargeCost: nil,
        eventReferences: [],
        isOpen: true,
        quality: .unavailable,
        derivationVersion: 1,
        sourceFingerprint: "privacy-source",
        derivationFingerprint: "privacy-derived"
    )

    private static let labelFixture = ActivityLabelOverride(
        id: "privacy-label",
        carId: 1,
        sessionId: nil,
        placeKey: "station",
        scope: .futureAtPlace,
        purpose: .replenishment,
        customName: "Preferred charger",
        icon: "bolt.fill",
        colorHex: "#34C759",
        startMinute: nil,
        endMinute: nil,
        updatedAt: Date(timeIntervalSince1970: 1_720_000_100)
    )

    private static let pricingFixture = ChargePricingObservation(
        id: "privacy-price",
        carId: 1,
        chargeId: 8,
        stationKey: "station",
        scope: .futureAtStation,
        finalAmount: 6.6,
        billedEnergyKWh: 10,
        pricePerKWh: 0.66,
        serviceFeePerKWh: nil,
        fixedFee: nil,
        currencyCode: "CNY",
        confirmedAt: Date(timeIntervalSince1970: 1_720_000_200)
    )
}

private actor PrivacySessionStore: SmartActivitySessionStoring {
    private var values: [SmartActivitySession]

    init(values: [SmartActivitySession]) { self.values = values }

    func sessions(carId: Int) async throws -> [SmartActivitySession] {
        values.filter { $0.carId == carId }
    }

    func session(carId: Int, sessionId: String) async throws -> SmartActivitySession? {
        values.first { $0.carId == carId && $0.id == sessionId }
    }

    func replace(carId: Int, sessions: [SmartActivitySession]) async throws {
        values.removeAll { $0.carId == carId }
        values.append(contentsOf: sessions)
    }

    func removeDerivedSessions() async throws { values.removeAll() }
}

private actor PrivacyLabelStore: ActivityLabelOverrideStoring {
    private var values: [ActivityLabelOverride]

    init(values: [ActivityLabelOverride]) { self.values = values }

    func overrides(carId: Int) async throws -> [ActivityLabelOverride] {
        values.filter { $0.carId == carId }
    }

    func override(id: String) async throws -> ActivityLabelOverride? {
        values.first { $0.id == id }
    }

    func save(_ value: ActivityLabelOverride) async throws { values.append(value) }
    func delete(id: String) async throws { values.removeAll { $0.id == id } }
    func removeAll() async throws { values.removeAll() }
}

private actor PrivacyPricingStore: ChargePricingObservationStoring {
    private var values: [ChargePricingObservation]

    init(values: [ChargePricingObservation]) { self.values = values }

    func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation] {
        values.filter { $0.carId == carId && $0.stationKey == stationKey }
    }

    func save(_ value: ChargePricingObservation) async throws { values.append(value) }
    func remove(id: String) async throws { values.removeAll { $0.id == id } }
    func removeAll() async throws { values.removeAll() }
}
