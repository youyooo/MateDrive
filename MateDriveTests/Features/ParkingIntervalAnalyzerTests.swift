import Foundation
import XCTest
@testable import MateDriveApp

final class ParkingIntervalAnalyzerTests: XCTestCase {
    func testSeparatesChargeGainFromStandbyLoss() throws {
        let park = TeslaMateActivity(
            id: 10,
            type: "park",
            startDate: "2026-07-18T18:00:00+08:00",
            endDate: "2026-07-19T07:00:00+08:00",
            durationMin: 780,
            rangeDiffKm: 132,
            soc: 50,
            socDiff: 28,
            endRangeKm: 300
        )
        let charge = TeslaMateActivity(
            id: 11,
            type: "charge",
            startDate: "2026-07-18T23:00:00+08:00",
            endDate: "2026-07-19T01:00:00+08:00",
            kwh: 18,
            soc: 49,
            socDiff: 30
        )

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [charge], sleepIntervals: [])
        ))

        XCTAssertEqual(metrics.startBatteryPercent, 50)
        XCTAssertEqual(metrics.endBatteryPercent, 78)
        XCTAssertEqual(metrics.netBatteryChangePercent, 28)
        XCTAssertEqual(metrics.chargeGainPercent, 30)
        XCTAssertEqual(metrics.standbyBatteryChangePercent, -2)
        XCTAssertEqual(metrics.quality, .complete)
    }

    func testMissingBatteryBoundaryRemainsPartialInsteadOfZero() throws {
        let park = TeslaMateActivity(
            id: 12,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00"
        )

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: [])
        ))

        XCTAssertNil(metrics.startBatteryPercent)
        XCTAssertNil(metrics.netBatteryChangePercent)
        XCTAssertNil(metrics.standbyBatteryChangePercent)
        XCTAssertEqual(metrics.quality, .partial)
    }

    func testClipsSleepAcrossMidnightAndNeverReportsNegativeAwakeDuration() throws {
        let park = TeslaMateActivity(
            id: 13,
            type: "park",
            startDate: "2026-07-18T22:00:00+08:00",
            endDate: "2026-07-19T02:00:00+08:00",
            soc: 70,
            socDiff: -1,
            endRangeKm: 400
        )
        let sleepIntervals = [
            SleepInterval(start: date("2026-07-18T21:30:00+08:00"), end: date("2026-07-18T23:00:00+08:00")),
            SleepInterval(start: date("2026-07-19T00:00:00+08:00"), end: date("2026-07-19T03:00:00+08:00"))
        ]

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: sleepIntervals)
        ))

        XCTAssertEqual(metrics.duration, 4 * 60 * 60)
        XCTAssertEqual(metrics.sleepDuration, 3 * 60 * 60)
        XCTAssertEqual(metrics.awakeDuration, 1 * 60 * 60)
        XCTAssertGreaterThanOrEqual(metrics.awakeDuration, 0)
        XCTAssertEqual(metrics.wakeCount, 1)
    }

    func testSumsMultipleChargesAndUsesAdjacentDriveBoundaries() throws {
        let previousDrive = TeslaMateActivity(id: 14, type: "drive", soc: 60, socDiff: -10, endRangeKm: 310)
        let nextDrive = TeslaMateActivity(id: 15, type: "drive", rangeDiffKm: -20, soc: 54, endRangeKm: 270)
        let park = TeslaMateActivity(
            id: 16,
            type: "park",
            startDate: "2026-07-18T18:00:00+08:00",
            endDate: "2026-07-19T06:00:00+08:00"
        )
        let charges = [
            TeslaMateActivity(id: 17, type: "charge", kwh: 5.5, socDiff: 3),
            TeslaMateActivity(id: 18, type: "charge", kwh: 4.5, socDiff: 2)
        ]

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(
                parking: park,
                charges: charges,
                sleepIntervals: [],
                previousDrive: previousDrive,
                nextDrive: nextDrive
            )
        ))

        XCTAssertEqual(metrics.startBatteryPercent, 50)
        XCTAssertEqual(metrics.endBatteryPercent, 54)
        XCTAssertEqual(metrics.netBatteryChangePercent, 4)
        XCTAssertEqual(metrics.chargeGainPercent, 5)
        XCTAssertEqual(metrics.standbyBatteryChangePercent, -1)
        XCTAssertEqual(metrics.startRatedRangeKm, 310)
        XCTAssertEqual(metrics.endRatedRangeKm, 290)
        XCTAssertEqual(metrics.ratedRangeChangeKm, -20)
        XCTAssertEqual(metrics.vehicleReportedChargeEnergyKWh, 10)
    }

    func testMissingChargeSOCLeavesStandbyUnavailable() throws {
        let park = TeslaMateActivity(
            id: 19,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00",
            soc: 60,
            socDiff: -3,
            endRangeKm: 390
        )
        let charge = TeslaMateActivity(id: 20, type: "charge", kwh: 4)

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [charge], sleepIntervals: [])
        ))

        XCTAssertNil(metrics.chargeGainPercent)
        XCTAssertNil(metrics.standbyBatteryChangePercent)
        XCTAssertEqual(metrics.quality, .partial)
        XCTAssertTrue(metrics.missingReasonCodes.contains("missing_charge_soc_change"))
    }

    func testMissingChargeEnergyRemainsNilAndPartial() throws {
        let park = TeslaMateActivity(
            id: 21,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00",
            rangeDiffKm: 25,
            soc: 60,
            socDiff: 2,
            endRangeKm: 390
        )
        let charges = [
            TeslaMateActivity(id: 22, type: "charge", kwh: 4, socDiff: 3),
            TeslaMateActivity(id: 23, type: "charge", socDiff: 1)
        ]

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: charges, sleepIntervals: [])
        ))

        XCTAssertNil(metrics.vehicleReportedChargeEnergyKWh)
        XCTAssertEqual(metrics.quality, .partial)
        XCTAssertTrue(metrics.missingReasonCodes.contains("missing_charge_energy"))
    }

    func testMissingRangeMetricsRemainPartial() throws {
        let park = TeslaMateActivity(
            id: 24,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00",
            soc: 60,
            socDiff: -1
        )

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: [])
        ))

        XCTAssertNil(metrics.startRatedRangeKm)
        XCTAssertNil(metrics.endRatedRangeKm)
        XCTAssertNil(metrics.ratedRangeChangeKm)
        XCTAssertEqual(metrics.quality, .partial)
        XCTAssertTrue(metrics.missingReasonCodes.contains("missing_start_range"))
        XCTAssertTrue(metrics.missingReasonCodes.contains("missing_end_range"))
        XCTAssertTrue(metrics.missingReasonCodes.contains("missing_range_change"))
    }

    func testParkingWithoutChargeEnergyCanRemainComplete() throws {
        let park = TeslaMateActivity(
            id: 25,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00",
            rangeDiffKm: -5,
            soc: 60,
            socDiff: -1,
            endRangeKm: 390
        )

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: [])
        ))

        XCTAssertNil(metrics.vehicleReportedChargeEnergyKWh)
        XCTAssertEqual(metrics.quality, .complete)
        XCTAssertFalse(metrics.missingReasonCodes.contains("missing_charge_energy"))
    }

    func testNonParkingInputReturnsNil() {
        let drive = TeslaMateActivity(
            id: 26,
            type: "drive",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00"
        )

        XCTAssertNil(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: drive, charges: [], sleepIntervals: [])
        ))
    }

    func testNonIncreasingDateRangeReturnsNil() {
        let park = TeslaMateActivity(
            id: 27,
            type: "park",
            startDate: "2026-07-18T12:00:00+08:00",
            endDate: "2026-07-18T10:00:00+08:00"
        )

        XCTAssertNil(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: [])
        ))
    }

    func testMalformedDateRangeReturnsNil() {
        let park = TeslaMateActivity(
            id: 28,
            type: "park",
            startDate: "not-a-date",
            endDate: "2026-07-18T12:00:00+08:00"
        )

        XCTAssertNil(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: [])
        ))
    }

    private func date(_ value: String) -> Date {
        guard let parsed = ISO8601DateFormatter().date(from: value) else {
            fatalError("Invalid test date: \(value)")
        }
        return parsed
    }
}
