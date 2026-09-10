import XCTest
@testable import MateDriveApp

final class WidgetCurrentChargePresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_320_000)

    func testChargingPresentationUsesRealMetrics() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                batteryLevel: 64,
                chargeLimitSoc: 80,
                chargerPowerKW: 72,
                energyAddedKWh: 18.4,
                timeToFullMinutes: 65,
                isDC: true,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .charging)
        XCTAssertEqual(value.batteryText, "64%")
        XCTAssertEqual(value.limitText, "Limit 80%")
        XCTAssertEqual(value.powerText, "72 kW")
        XCTAssertEqual(value.energyText, "18.4 kWh")
        XCTAssertEqual(value.remainingText, "1h 05m remaining")
        XCTAssertEqual(value.progress, WidgetChargeProgress(current: 64, total: 80))
        XCTAssertEqual(value.chargeTypeText, "DC")
    }

    func testOfflineBeatsFreshnessAndPreservesLastValues() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                quality: .offline,
                batteryLevel: 64,
                chargeLimitSoc: 80,
                chargerPowerKW: 72,
                isDC: false,
                updatedAt: now.addingTimeInterval(-5 * 60)
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .offline)
        XCTAssertEqual(value.statusText, "Offline")
        XCTAssertEqual(value.batteryText, "64%")
        XCTAssertEqual(value.powerText, "72 kW")
        XCTAssertEqual(value.updatedText, "Updated 5m")
        XCTAssertEqual(value.progress, WidgetChargeProgress(current: 64, total: 80))
        XCTAssertEqual(value.chargeTypeText, "AC")
    }

    func testThirtyMinuteBoundaryBecomesStaleOnlyAfterThreshold() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                quality: .complete,
                batteryLevel: 64,
                updatedAt: now
            )
        )

        let atBoundary = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now.addingTimeInterval(1_800)
        )
        let afterBoundary = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now.addingTimeInterval(1_801)
        )

        XCTAssertEqual(atBoundary.state, .charging)
        XCTAssertEqual(afterBoundary.state, .stale)
        XCTAssertEqual(afterBoundary.statusText, "Data may be out of date")
    }

    func testSnapshotWithoutCurrentChargeShowsEnglishRecovery() {
        let snapshot = WidgetVehicleSnapshot.fixture(currentCharge: nil)
        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: "Model Y",
            now: now
        )

        XCTAssertEqual(value.state, .unavailable)
        XCTAssertEqual(value.carName, "Model 3")
        XCTAssertEqual(value.batteryText, "--")
        XCTAssertEqual(value.statusText, "Open MateDrive to sync")
        XCTAssertNil(value.powerText)
    }

    func testCompletelyMissingSnapshotIsUnavailable() {
        let value = WidgetCurrentChargePresentation.make(
            snapshot: nil,
            configuredVehicleName: "Model Y",
            now: now
        )

        XCTAssertEqual(value.state, .unavailable)
        XCTAssertEqual(value.carName, "Model Y")
        XCTAssertEqual(value.batteryText, "--")
    }

    func testIdlePresentationContainsNoPreviousChargeMetrics() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .idle,
                quality: .complete,
                batteryLevel: 55,
                chargeLimitSoc: 80,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .idle)
        XCTAssertEqual(value.statusText, "Not charging")
        XCTAssertEqual(value.batteryText, "55%")
        XCTAssertNil(value.limitText)
        XCTAssertNil(value.powerText)
        XCTAssertNil(value.energyText)
        XCTAssertNil(value.remainingText)
        XCTAssertNil(value.progress)
        XCTAssertNil(value.chargeTypeText)
    }

    func testOfflineIdlePresentationStillContainsNoPreviousChargeMetrics() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .idle,
                quality: .offline,
                batteryLevel: 55,
                chargeLimitSoc: 80,
                chargerPowerKW: 72,
                energyAddedKWh: 18.4,
                timeToFullMinutes: 65,
                isDC: true,
                updatedAt: now.addingTimeInterval(-5 * 60)
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .offline)
        XCTAssertEqual(value.statusText, "Offline")
        XCTAssertEqual(value.batteryText, "55%")
        XCTAssertNil(value.limitText)
        XCTAssertNil(value.powerText)
        XCTAssertNil(value.energyText)
        XCTAssertNil(value.remainingText)
        XCTAssertNil(value.progress)
        XCTAssertNil(value.chargeTypeText)
    }

    func testStaleIdlePresentationContainsNoProgressOrChargeType() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .idle,
                quality: .complete,
                batteryLevel: 55,
                chargeLimitSoc: 80,
                chargerPowerKW: 72,
                energyAddedKWh: 18.4,
                timeToFullMinutes: 65,
                isDC: true,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now.addingTimeInterval(1_801)
        )

        XCTAssertEqual(value.state, .stale)
        XCTAssertNil(value.limitText)
        XCTAssertNil(value.powerText)
        XCTAssertNil(value.energyText)
        XCTAssertNil(value.remainingText)
        XCTAssertNil(value.progress)
        XCTAssertNil(value.chargeTypeText)
    }

    func testPartialChargeHasAnExplicitTrustLabel() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                quality: .partial,
                batteryLevel: 64,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .charging)
        XCTAssertEqual(value.statusText, "Charging")
        XCTAssertEqual(value.trustText, "Partial data")
    }

    func testChargingStatusAndDurationFollowTheAppLanguage() {
        let cases: [(WidgetDisplayLanguage, Int, String, String)] = [
            (.english, 65, "Charging", "1h 05m remaining"),
            (.english, 5, "Charging", "5m remaining"),
            (.english, 0, "Charging", "0m remaining"),
            (.chinese, 65, "正在充电", "剩余 1小时05分钟"),
            (.chinese, 5, "正在充电", "剩余 5分钟"),
            (.chinese, 0, "正在充电", "剩余 0分钟"),
            (.traditionalChinese, 65, "正在充電", "剩餘 1小時05分鐘"),
            (.traditionalChinese, 5, "正在充電", "剩餘 5分鐘"),
            (.traditionalChinese, 0, "正在充電", "剩餘 0分鐘")
        ]

        for (language, minutes, status, remaining) in cases {
            let snapshot = WidgetVehicleSnapshot.fixture(
                data: .fixture(carName: "Model 3", displayLanguage: language),
                currentCharge: .fixture(
                    phase: .charging,
                    timeToFullMinutes: minutes,
                    updatedAt: now
                )
            )
            let value = WidgetCurrentChargePresentation.make(
                snapshot: snapshot,
                configuredVehicleName: nil,
                now: now
            )

            XCTAssertEqual(value.statusText, status, "language: \(language), minutes: \(minutes)")
            XCTAssertEqual(value.remainingText, remaining, "language: \(language), minutes: \(minutes)")
        }
    }
}
