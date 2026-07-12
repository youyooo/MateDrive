import XCTest
@testable import MateDroidIOS

final class TripRuleTests: XCTestCase {
    func testAggregatorMatchesAndroidTripTotals() throws {
        let drives = [
            drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120, energy: 32, speed: 125, start: "A", end: "B", startBattery: 90, endBattery: 35),
            drive(2, "2026-01-01T10:40:00Z", "2026-01-01T12:10:00Z", distance: 150, duration: 90, energy: nil, speed: 118, start: "B", end: "C", startBattery: 80, endBattery: 28)
        ]
        let charges = [
            charge(1, "2026-01-01T10:05:00Z", "2026-01-01T10:35:00Z", energy: 45, cost: 18.5),
            charge(2, "2026-01-01T12:15:00Z", "2026-01-01T12:45:00Z", energy: 20, cost: nil)
        ]

        let trip = try XCTUnwrap(TripAggregator.buildTrip(drives: drives, charges: charges, name: "Road Trip"))

        XCTAssertEqual(trip.totalDistance, 330)
        XCTAssertEqual(trip.totalDrivingDurationMin, 210)
        XCTAssertEqual(trip.totalDurationMin, 250)
        XCTAssertEqual(trip.totalEnergyConsumed, 32)
        XCTAssertEqual(trip.totalEnergyCharged, 65)
        XCTAssertEqual(trip.totalChargeCost, 18.5)
        XCTAssertEqual(trip.pricedChargeCount, 1)
        XCTAssertEqual(trip.missingChargeCostCount, 1)
        XCTAssertFalse(trip.chargeCostIsComplete)
        XCTAssertEqual(try XCTUnwrap(trip.averageEfficiency), 96.96969696969697, accuracy: 0.0001)
        XCTAssertEqual(trip.maxSpeed, 125)
        XCTAssertEqual(trip.startAddress, "A")
        XCTAssertEqual(trip.endAddress, "C")
        XCTAssertEqual(trip.startBatteryLevel, 90)
        XCTAssertEqual(trip.endBatteryLevel, 28)
        XCTAssertEqual(trip.name, "Road Trip")
    }

    func testAggregatorTreatsZeroCostAsPricedAndReportsCompleteCoverage() throws {
        let trip = try XCTUnwrap(TripAggregator.buildTrip(
            drives: [drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120)],
            charges: [
                charge(1, "2026-01-01T10:05:00Z", "2026-01-01T10:35:00Z", energy: 45, cost: 0),
                charge(2, "2026-01-01T10:40:00Z", "2026-01-01T11:10:00Z", energy: 20, cost: 12.5)
            ]
        ))

        XCTAssertEqual(trip.totalChargeCost, 12.5)
        XCTAssertEqual(trip.pricedChargeCount, 2)
        XCTAssertEqual(trip.missingChargeCostCount, 0)
        XCTAssertTrue(trip.chargeCostIsComplete)
    }

    func testAggregatorWithNoChargesHasCompleteEmptyCoverageAndNoCost() throws {
        let trip = try XCTUnwrap(TripAggregator.buildTrip(
            drives: [drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120)],
            charges: []
        ))

        XCTAssertNil(trip.totalChargeCost)
        XCTAssertEqual(trip.pricedChargeCount, 0)
        XCTAssertEqual(trip.missingChargeCostCount, 0)
        XCTAssertTrue(trip.chargeCostIsComplete)
    }

    func testDetectorFiltersMicroDrivesAndRequiresAndroidTripThresholds() {
        let drives = [
            drive(99, "2026-01-01T07:55:00Z", "2026-01-01T07:58:00Z", distance: 0.5, duration: 3),
            drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120),
            drive(2, "2026-01-01T10:40:00Z", "2026-01-01T12:10:00Z", distance: 150, duration: 90)
        ]
        let charges = [
            charge(1, "2026-01-01T10:05:00Z", "2026-01-01T10:35:00Z", energy: 45)
        ]

        let trips = TripDetector.detectTrips(drives: drives, dcCharges: charges)

        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.drives.map(\.id), [1, 2])
        XCTAssertEqual(trips.first?.totalDistance, 330)
    }

    func testDetectorBreaksTripWhenAndroidGapThresholdIsExceeded() {
        let drives = [
            drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120),
            drive(2, "2026-01-01T13:36:00Z", "2026-01-01T15:00:00Z", distance: 150, duration: 84)
        ]
        let charges = [
            charge(1, "2026-01-01T10:05:00Z", "2026-01-01T10:35:00Z", energy: 45)
        ]

        XCTAssertTrue(TripDetector.detectTrips(drives: drives, dcCharges: charges).isEmpty)
    }

    func testTripFallbackDisplayNameUsesSelectedLanguage() throws {
        let trip = try XCTUnwrap(TripAggregator.buildTrip(
            drives: [
                drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120)
            ],
            charges: [],
            name: nil
        ))

        XCTAssertEqual(trip.displayName(language: .english), "Start -> End")
        XCTAssertEqual(trip.displayName(language: .chinese), "开始 -> 结束")
    }

    func testTripTimelineGeneratedLabelsUseSelectedLanguage() throws {
        let trip = try XCTUnwrap(TripAggregator.buildTrip(
            drives: [
                drive(1, "2026-01-01T08:00:00Z", "2026-01-01T10:00:00Z", distance: 180, duration: 120),
                drive(2, "2026-01-01T10:40:00Z", "2026-01-01T12:10:00Z", distance: 150, duration: 90)
            ],
            charges: [
                charge(1, "2026-01-01T10:05:00Z", "2026-01-01T10:35:00Z", energy: 45)
            ],
            name: nil
        ))

        let segments = TripTimelineBuilder.build(trip: trip, dcChargeIds: [1], showShort: true)

        XCTAssertEqual(segments.map { $0.displayLabel(language: .english) }, ["Drive 1", "Parked", "Charge 1", "Parked", "Drive 2"])
        XCTAssertEqual(segments.map { $0.displayLabel(language: .chinese) }, ["行程 1", "停放", "充电 1", "停放", "行程 2"])
        XCTAssertEqual(segments.map { $0.displayLabel(language: .german) }, ["Fahrt 1", "Geparkt", "Ladung 1", "Geparkt", "Fahrt 2"])
        XCTAssertEqual(segments.map { $0.displayLabel(language: .spanish) }, ["Trayecto 1", "Aparcado", "Carga 1", "Aparcado", "Trayecto 2"])
        XCTAssertEqual(segments.map { $0.displayLabel(language: .italian) }, ["Tragitto 1", "Parcheggiata", "Ricarica 1", "Parcheggiata", "Tragitto 2"])
        XCTAssertEqual(segments.map { $0.displayLabel(language: .catalan) }, ["Trajecte 1", "Aparcat", "Càrrega 1", "Aparcat", "Trajecte 2"])
        XCTAssertEqual(segments[0].destination(carId: 7, exteriorColor: "Red"), .driveDetail(carId: 7, driveId: 1, exteriorColor: "Red"))
        XCTAssertNil(segments[1].destination(carId: 7, exteriorColor: "Red"))
        XCTAssertEqual(segments[2].destination(carId: 7, exteriorColor: "Red"), .chargeDetail(carId: 7, chargeId: 1, exteriorColor: "Red"))
    }

    private func drive(
        _ id: Int,
        _ startDate: String,
        _ endDate: String,
        distance: Double,
        duration: Int,
        energy: Double? = nil,
        speed: Double = 0,
        start: String? = nil,
        end: String? = nil,
        startBattery: Int? = nil,
        endBattery: Int? = nil
    ) -> TripDrive {
        TripDrive(
            id: id,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            durationMin: duration,
            energyConsumed: energy,
            speedMax: speed,
            startAddress: start,
            endAddress: end,
            startBatteryLevel: startBattery,
            endBatteryLevel: endBattery
        )
    }

    private func charge(
        _ id: Int,
        _ startDate: String,
        _ endDate: String,
        energy: Double,
        cost: Double? = nil
    ) -> TripCharge {
        TripCharge(id: id, startDate: startDate, endDate: endDate, energyAdded: energy, cost: cost)
    }
}
