import XCTest
@testable import MateDriveApp

final class EnergyCycleAnalyzerTests: XCTestCase {
    func testOpenCycleLabelDescribesTheCurrentDischargeCycleRatherThanActiveCharging() {
        XCTAssertEqual(EnergyCycleState.open.title(language: .chinese), "当前周期")
        XCTAssertEqual(EnergyCycleState.open.title(language: .english), "Current cycle")
    }

    func testBuildsChargeToNextChargeCycleWithSeparateInputBatteryAndDrivingEnergy() throws {
        let charges = [
            charge(
                id: 1,
                start: "2026-07-14T08:00:00Z",
                end: "2026-07-14T09:00:00Z",
                added: 40,
                used: 44,
                startSOC: 20,
                endSOC: 80,
                endRange: 360,
                odometer: 118_000
            ),
            charge(
                id: 2,
                start: "2026-07-15T18:00:00Z",
                end: "2026-07-15T18:30:00Z",
                added: 7,
                used: 8,
                startSOC: 70,
                endSOC: 80,
                endRange: 356,
                odometer: 118_030
            )
        ]
        let drives = [drive(
            id: 10,
            start: "2026-07-14T10:00:00Z",
            end: "2026-07-14T11:00:00Z",
            energy: 6.2,
            distance: 30,
            startSOC: 80,
            endSOC: 70
        )]

        let analysis = EnergyCycleAnalyzer.analyze(
            dataSet: EnergyCycleDataSet(charges: charges, drives: drives),
            period: .month,
            now: try date("2026-07-16T12:00:00Z"),
            calendar: calendar
        )
        let cycle = try XCTUnwrap(analysis.recentCycles.first { $0.chargeId == 1 })

        XCTAssertEqual(cycle.state, .complete)
        XCTAssertEqual(cycle.chargeStartSOC, 20)
        XCTAssertEqual(cycle.chargeEndSOC, 80)
        XCTAssertEqual(cycle.dischargeEndSOC, 70)
        XCTAssertEqual(cycle.chargeSOCDelta, 60)
        XCTAssertEqual(cycle.dischargeSOCDelta, 10)
        XCTAssertEqual(cycle.chargerInputKWh, 44)
        XCTAssertEqual(cycle.batteryAddedKWh, 40)
        XCTAssertEqual(cycle.chargingLossKWh, 4)
        XCTAssertEqual(try XCTUnwrap(cycle.chargingEfficiency), 90.909, accuracy: 0.001)
        XCTAssertEqual(cycle.drivingEnergyKWh, 6.2)
        XCTAssertEqual(cycle.distanceKm, 30)
        XCTAssertTrue(cycle.drivingEnergyIsComplete)
    }

    func testTodaySummaryComparesAgainstYesterdayAndReportsCoverage() throws {
        let charges = [
            charge(id: 1, start: "2026-07-15T08:00:00Z", end: "2026-07-15T09:00:00Z", added: 20, used: 22, startSOC: 40, endSOC: 70),
            charge(id: 2, start: "2026-07-16T08:00:00Z", end: "2026-07-16T09:00:00Z", added: 10, used: 11, startSOC: 70, endSOC: 80),
            charge(id: 3, start: "2026-07-16T10:00:00Z", end: "2026-07-16T10:30:00Z", added: 5, used: nil, startSOC: 80, endSOC: 85)
        ]
        let drives = [
            drive(id: 10, start: "2026-07-15T12:00:00Z", end: "2026-07-15T12:30:00Z", energy: 4, distance: 20, startSOC: 70, endSOC: 62),
            drive(id: 11, start: "2026-07-16T12:00:00Z", end: "2026-07-16T12:30:00Z", energy: 2, distance: 10, startSOC: 85, endSOC: 80),
            drive(id: 12, start: "2026-07-16T13:00:00Z", end: "2026-07-16T13:10:00Z", energy: nil, distance: nil, startSOC: 80, endSOC: 79)
        ]

        let analysis = EnergyCycleAnalyzer.analyze(
            dataSet: EnergyCycleDataSet(charges: charges, drives: drives),
            period: .today,
            now: try date("2026-07-16T14:00:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(analysis.current.chargeCount, 2)
        XCTAssertEqual(analysis.current.chargerInputKWh, 11)
        XCTAssertEqual(analysis.current.chargerInputRecordCount, 1)
        XCTAssertFalse(analysis.current.chargerInputIsComplete)
        XCTAssertEqual(analysis.current.batteryAddedKWh, 15)
        XCTAssertEqual(analysis.current.drivingEnergyKWh, 2)
        XCTAssertEqual(analysis.current.drivingEnergyRecordCount, 1)
        XCTAssertEqual(analysis.current.driveCount, 2)
        XCTAssertEqual(analysis.current.chargeSOCAdded, 15)
        XCTAssertEqual(analysis.current.driveSOCUsed, 6)
        XCTAssertEqual(analysis.previous.chargerInputKWh, 22)
        XCTAssertEqual(analysis.previous.batteryAddedKWh, 20)
        XCTAssertEqual(analysis.previous.drivingEnergyKWh, 4)
    }

    func testConsecutiveTopUpIsNotPresentedAsACompletedDischargeCycle() throws {
        let charges = [
            charge(id: 1, start: "2026-07-15T08:00:00Z", end: "2026-07-15T08:30:00Z", added: 5, used: 6, startSOC: 70, endSOC: 75),
            charge(id: 2, start: "2026-07-15T09:00:00Z", end: "2026-07-15T09:30:00Z", added: 5, used: 6, startSOC: 75, endSOC: 80)
        ]

        let analysis = EnergyCycleAnalyzer.analyze(
            dataSet: EnergyCycleDataSet(charges: charges, drives: []),
            period: .week,
            now: try date("2026-07-16T12:00:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(analysis.recentCycles.first { $0.chargeId == 1 }?.state, .consecutiveCharge)
        XCTAssertEqual(analysis.recentCycles.first { $0.chargeId == 2 }?.state, .open)
    }

    func testOpenCycleUsesLatestDriveEndSOCWhenDatabaseRowsAreNewestFirst() throws {
        let charges = [
            charge(
                id: 1,
                start: "2026-07-16T08:00:00Z",
                end: "2026-07-16T08:30:00Z",
                added: 8,
                used: 9,
                startSOC: 70,
                endSOC: 80
            )
        ]
        let drives = [
            drive(
                id: 11,
                start: "2026-07-16T10:00:00Z",
                end: "2026-07-16T10:30:00Z",
                energy: 2.1,
                distance: 12,
                startSOC: 76,
                endSOC: 70
            ),
            drive(
                id: 10,
                start: "2026-07-16T09:00:00Z",
                end: "2026-07-16T09:30:00Z",
                energy: 1.4,
                distance: 8,
                startSOC: 80,
                endSOC: 76
            )
        ]

        let analysis = EnergyCycleAnalyzer.analyze(
            dataSet: EnergyCycleDataSet(charges: charges, drives: drives),
            period: .today,
            now: try date("2026-07-16T12:00:00Z"),
            calendar: calendar
        )
        let cycle = try XCTUnwrap(analysis.recentCycles.first)

        XCTAssertEqual(cycle.state, .open)
        XCTAssertEqual(cycle.dischargeEndSOC, 70)
        XCTAssertEqual(cycle.dischargeSOCDelta, 10)
    }

    func testRangeTrendNormalizesEndRangeToOneHundredPercentSOC() throws {
        let charges = [
            charge(id: 1, start: "2026-06-01T08:00:00Z", end: "2026-06-01T09:00:00Z", added: 20, used: 22, startSOC: 40, endSOC: 80, endRange: 400, odometer: 100_000),
            charge(id: 2, start: "2026-07-01T08:00:00Z", end: "2026-07-01T09:00:00Z", added: 20, used: 22, startSOC: 40, endSOC: 80, endRange: 392, odometer: 110_000)
        ]

        let analysis = EnergyCycleAnalyzer.analyze(
            dataSet: EnergyCycleDataSet(charges: charges, drives: []),
            period: .month,
            now: try date("2026-07-16T12:00:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(analysis.rangeTrend.map(\.rangeAt100Km), [500, 490])
        XCTAssertEqual(analysis.rangeTrend.map(\.odometerKm), [100_000, 110_000])
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func charge(
        id: Int,
        start: String,
        end: String,
        added: Double?,
        used: Double?,
        startSOC: Int?,
        endSOC: Int?,
        endRange: Double? = nil,
        odometer: Double? = nil
    ) -> ChargeSummaryRecord {
        ChargeSummaryRecord(
            chargeId: id,
            carId: 1,
            startDate: start,
            endDate: end,
            chargeEnergyAdded: added,
            cost: nil,
            address: "Home",
            chargeEnergyUsed: used,
            startBatteryLevel: startSOC,
            endBatteryLevel: endSOC,
            endRatedRangeKm: endRange,
            odometerKm: odometer
        )
    }

    private func drive(
        id: Int,
        start: String,
        end: String,
        energy: Double?,
        distance: Double?,
        startSOC: Int?,
        endSOC: Int?
    ) -> DriveSummaryRecord {
        DriveSummaryRecord(
            driveId: id,
            carId: 1,
            startDate: start,
            endDate: end,
            distance: distance,
            durationMin: 30,
            energyConsumedNet: energy,
            startBatteryLevel: startSOC,
            endBatteryLevel: endSOC
        )
    }
}
