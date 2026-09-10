import XCTest
@testable import MateDriveApp

final class LaunchExperienceViewTests: XCTestCase {
    func testLaunchExperienceRemainsVisibleForThreeSeconds() {
        XCTAssertEqual(LaunchExperienceTiming.minimumDisplayDuration, .seconds(3))
    }

    func testReducedMotionDisablesNonessentialAppAnimations() {
        XCTAssertTrue(MateDriveMotion.animationsEnabled(reduceMotion: false))
        XCTAssertFalse(MateDriveMotion.animationsEnabled(reduceMotion: true))
    }

    func testSnapshotUsesCachedVehicleAndChargingData() {
        let data = WidgetDisplayData(
            carName: "Model 3 Performance",
            batteryLevel: 80,
            ratedRange: 100,
            isCharging: true,
            outsideTemperature: 20,
            displayUnitSystem: .imperial
        )
        let trend = WidgetChargingTrendData(
            sessionCount: 4,
            energyKWh: 25.7,
            energyKnownCount: 4,
            currencyCode: "USD",
            energyBuckets: [25.7]
        )
        let snapshot = WidgetVehicleSnapshot(
            id: "vehicle",
            data: data,
            chargingTrend: trend
        )

        let content = LaunchExperienceSnapshot(snapshot: snapshot)

        XCTAssertEqual(content.carName, "Model 3 Performance")
        XCTAssertEqual(content.batteryText, "80%")
        XCTAssertEqual(content.batteryProgress, 0.8, accuracy: 0.001)
        XCTAssertEqual(content.rangeText, "62 mi")
        XCTAssertEqual(content.energyText, "25.7 kWh")
        XCTAssertEqual(content.outsideTemperatureText, "68°F")
        XCTAssertTrue(content.isCharging)
    }

    func testSnapshotRejectsInvalidValuesAndKeepsFallbacksExplicit() {
        let data = WidgetDisplayData(
            carName: "   ",
            batteryLevel: 120,
            ratedRange: -.infinity,
            outsideTemperature: .nan
        )

        let content = LaunchExperienceSnapshot(
            snapshot: WidgetVehicleSnapshot(id: "vehicle", data: data)
        )

        XCTAssertNil(content.carName)
        XCTAssertEqual(content.batteryText, "--")
        XCTAssertEqual(content.batteryProgress, 0)
        XCTAssertEqual(content.rangeText, "--")
        XCTAssertEqual(content.energyText, "--")
        XCTAssertEqual(content.outsideTemperatureText, "--")
        XCTAssertFalse(content.isCharging)
    }
}
