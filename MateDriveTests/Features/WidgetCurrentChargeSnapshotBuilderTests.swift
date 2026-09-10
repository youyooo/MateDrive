import XCTest
@testable import MateDriveApp

@MainActor
final class WidgetCurrentChargeSnapshotBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_320_000)

    func testActiveChargeBuildsCompleteSnapshot() throws {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.chargingFixture),
            currentChargeResult: .success(.active(.activeFixture)),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.phase, .charging)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertEqual(result?.batteryLevel, 70)
        XCTAssertEqual(result?.chargeLimitSoc, 80)
        XCTAssertEqual(result?.chargerPowerKW, 80)
        XCTAssertEqual(result?.energyAddedKWh, 28)
        XCTAssertEqual(result?.timeToFullMinutes, 90)
        XCTAssertEqual(result?.isDC, true)
        XCTAssertEqual(result?.updatedAt, now)
    }

    func testChargingStatusWithoutActiveRecordBuildsStartingSnapshot() {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.chargingFixture),
            currentChargeResult: .success(.noActiveCharge),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.phase, .starting)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertEqual(result?.batteryLevel, 70)
        XCTAssertEqual(result?.chargeLimitSoc, 80)
        XCTAssertEqual(result?.chargerPowerKW, 80)
        XCTAssertNil(result?.energyAddedKWh)
        XCTAssertEqual(result?.timeToFullMinutes, 90)
        XCTAssertEqual(result?.isDC, true)
    }

    func testDetailFailureBuildsPartialSnapshotFromAuthoritativeStatus() {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.chargingFixture),
            currentChargeResult: .failure(.network("offline")),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.phase, .charging)
        XCTAssertEqual(result?.quality, .partial)
        XCTAssertEqual(result?.batteryLevel, 70)
        XCTAssertEqual(result?.energyAddedKWh, 27)
    }

    func testAuthoritativeIdleClearsEveryChargeMetric() {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.idleFixture),
            currentChargeResult: nil,
            previous: .fixture(
                phase: .charging,
                batteryLevel: 70,
                chargerPowerKW: 80,
                energyAddedKWh: 28,
                timeToFullMinutes: 90,
                isDC: true
            ),
            now: now
        )

        XCTAssertEqual(result?.phase, .idle)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertEqual(result?.batteryLevel, 55)
        XCTAssertEqual(result?.chargeLimitSoc, 80)
        XCTAssertNil(result?.chargerPowerKW)
        XCTAssertNil(result?.energyAddedKWh)
        XCTAssertNil(result?.timeToFullMinutes)
        XCTAssertNil(result?.isDC)
    }

    func testStatusFailurePreservesPreviousTimestampAndMarksOffline() {
        let previous = WidgetCurrentChargeData.fixture(
            phase: .charging,
            batteryLevel: 65,
            updatedAt: now.addingTimeInterval(-600)
        )

        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .failure(.network("offline")),
            currentChargeResult: nil,
            previous: previous,
            now: now
        )

        XCTAssertEqual(result?.quality, .offline)
        XCTAssertEqual(result?.batteryLevel, 65)
        XCTAssertEqual(result?.updatedAt, previous.updatedAt)
    }

    func testStatusFailureWithoutPreviousSnapshotReturnsNil() {
        XCTAssertNil(WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .failure(.network("offline")),
            currentChargeResult: nil,
            previous: nil,
            now: now
        ))
    }

    func testActiveDetailFillsOnlyStatusGapsFromItsLatestPoint() {
        let status = CarStatusPayload(status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: true, chargingState: "Charging")
        ))
        let detail = ChargeDetail(
            chargeId: 9008,
            chargeEnergyAdded: 12.5,
            batteryDetails: ChargeBatteryDetails(currentBatteryLevel: 69),
            chargePoints: [
                ChargePoint(
                    date: "2026-08-01T12:00:00Z",
                    batteryLevel: 68,
                    chargeEnergyAdded: 12,
                    chargerDetails: ChargerDetails(chargerPower: 65, chargerPhases: 0)
                )
            ],
            isCharging: true
        )

        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(status),
            currentChargeResult: .success(.active(detail)),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.batteryLevel, 69)
        XCTAssertNil(result?.chargeLimitSoc)
        XCTAssertEqual(result?.chargerPowerKW, 65)
        XCTAssertEqual(result?.energyAddedKWh, 12.5)
        XCTAssertNil(result?.timeToFullMinutes)
        XCTAssertEqual(result?.isDC, true)
    }

    func testMissingCurrentMetricsDoNotReusePreviousSessionOrManufactureZeros() {
        let status = CarStatusPayload(status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: true, chargingState: "Charging")
        ))
        let detail = ChargeDetail(chargeId: 9009, chargePoints: [], isCharging: true)
        let previous = WidgetCurrentChargeData.fixture(
            phase: .charging,
            batteryLevel: 66,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 24,
            timeToFullMinutes: 60,
            isDC: true
        )

        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(status),
            currentChargeResult: .success(.active(detail)),
            previous: previous,
            now: now
        )

        XCTAssertEqual(result?.phase, .charging)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertNil(result?.batteryLevel)
        XCTAssertNil(result?.chargeLimitSoc)
        XCTAssertNil(result?.chargerPowerKW)
        XCTAssertNil(result?.energyAddedKWh)
        XCTAssertNil(result?.timeToFullMinutes)
        XCTAssertNil(result?.isDC)
        XCTAssertEqual(result?.updatedAt, now)
    }

    func testSuccessfulPayloadWithoutStatusMarksPreviousOfflineOrReturnsNil() {
        let previous = WidgetCurrentChargeData.fixture(
            phase: .charging,
            batteryLevel: 65,
            updatedAt: now.addingTimeInterval(-600)
        )

        let preserved = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(CarStatusPayload(status: nil)),
            currentChargeResult: nil,
            previous: previous,
            now: now
        )
        let missing = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(CarStatusPayload(status: nil)),
            currentChargeResult: nil,
            previous: nil,
            now: now
        )

        XCTAssertEqual(preserved?.quality, .offline)
        XCTAssertEqual(preserved?.batteryLevel, 65)
        XCTAssertEqual(preserved?.updatedAt, now.addingTimeInterval(-600))
        XCTAssertNil(missing)
    }

    func testMixedChargePointDatesUseLatestParseablePoint() {
        let status = CarStatusPayload(status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: true, chargingState: "Charging")
        ))
        let detail = ChargeDetail(
            chargeId: 9010,
            chargePoints: [
                ChargePoint(
                    date: "not-a-date",
                    batteryLevel: 20,
                    chargeEnergyAdded: 2,
                    chargerDetails: ChargerDetails(chargerPower: 20, chargerPhases: 3)
                ),
                ChargePoint(
                    date: "2026-08-01T10:00:00Z",
                    batteryLevel: 45,
                    chargeEnergyAdded: 4,
                    chargerDetails: ChargerDetails(chargerPower: 45, chargerPhases: 3)
                ),
                ChargePoint(
                    date: "2026-08-01T11:00:00Z",
                    batteryLevel: 57,
                    chargeEnergyAdded: 7,
                    chargerDetails: ChargerDetails(chargerPower: 57, chargerPhases: 0)
                )
            ],
            isCharging: true
        )

        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(status),
            currentChargeResult: .success(.active(detail)),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.batteryLevel, 57)
        XCTAssertEqual(result?.chargerPowerKW, 57)
        XCTAssertEqual(result?.energyAddedKWh, 7)
        XCTAssertEqual(result?.isDC, true)
    }

    func testFractionalHoursRoundToNearestMinute() {
        let status = CarStatusPayload(status: CarStatus(
            chargingDetails: ChargingDetails(
                pluggedIn: true,
                chargingState: "Charging",
                timeToFullCharge: 1.51
            )
        ))

        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(status),
            currentChargeResult: .success(.noActiveCharge),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.timeToFullMinutes, 91)
    }
}

private extension CarStatusPayload {
    static let chargingFixture = CarStatusPayload(status: CarStatus(
        displayName: "Model 3",
        batteryDetails: BatteryDetails(batteryLevel: 70),
        chargingDetails: ChargingDetails(
            pluggedIn: true,
            chargingState: "Charging",
            chargeEnergyAdded: 27,
            chargeLimitSoc: 80,
            chargerPhases: 0,
            chargerPower: 80,
            timeToFullCharge: 1.5
        )
    ))

    static let idleFixture = CarStatusPayload(status: CarStatus(
        displayName: "Model 3",
        batteryDetails: BatteryDetails(batteryLevel: 55),
        chargingDetails: ChargingDetails(
            pluggedIn: false,
            chargingState: "Disconnected",
            chargeLimitSoc: 80
        )
    ))
}

private extension ChargeDetail {
    static let activeFixture = ChargeDetail(
        chargeId: 9007,
        chargeEnergyAdded: 28,
        batteryDetails: ChargeBatteryDetails(
            startBatteryLevel: 40,
            currentBatteryLevel: 69
        ),
        chargePoints: [],
        isCharging: true
    )
}
