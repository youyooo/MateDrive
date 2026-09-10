import XCTest
@testable import MateDriveApp

final class DashboardOverviewPresentationTests: XCTestCase {
    func testOverviewPresentsLatestDriveChargeAndOdometerInRequiredOrder() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 9,
            ratedRange: 260,
            odometer: 118_859,
            exteriorColor: "PPSW",
            currencyCode: "CNY",
            totalDrives: 87,
            latestDrive: DashboardLatestDrive(
                driveId: 88,
                startedAt: nil,
                endedAt: nil,
                distanceKm: 26.5,
                durationMinutes: 40,
                energyConsumedNet: 5.4,
                consumptionNet: 204,
                startRatedRangeKm: 380,
                endRatedRangeKm: 342
            ),
            latestCharge: DashboardLatestCharge(
                chargeId: 15,
                startedAt: nil,
                endedAt: nil,
                energyAddedKWh: 32.4,
                cost: 27.83,
                durationMinutes: 56,
                address: "家",
                startBatteryLevel: 20,
                endBatteryLevel: 80,
                odometerKm: 118_800
            )
        )

        let result = DashboardOverviewPresentation(
            state: state,
            units: .metric,
            language: .chinese
        )

        XCTAssertEqual(result.items.map(\.id), ["latest-drive", "latest-charge", "odometer"])
        XCTAssertEqual(result.items.map(\.title), ["最近一次行程", "最近一次充电", "总里程"])
        XCTAssertEqual(result.items.map(\.primaryValue), ["26.5 km", "32.4 kWh", "118,859 km"])
        XCTAssertEqual(result.items[0].primaryLabel, "实际行驶")
        XCTAssertEqual(result.items[0].metrics, [
            DashboardOverviewMetric(id: "range-drop", label: "表显消耗", value: "38 km"),
            DashboardOverviewMetric(id: "remaining-range", label: "预计剩余", value: "342 km"),
            DashboardOverviewMetric(id: "duration", label: "时长", value: "40分钟")
        ])
        XCTAssertEqual(result.items[1].metrics, [
            DashboardOverviewMetric(id: "battery-change", label: "电量变化", value: "20% → 80%"),
            DashboardOverviewMetric(id: "duration", label: "时长", value: "56分钟"),
            DashboardOverviewMetric(id: "cost", label: "本次费用", value: "¥27.83")
        ])
        XCTAssertEqual(result.items[2].metrics, [
            DashboardOverviewMetric(id: "drive-count", label: "累计行程", value: "87次"),
            DashboardOverviewMetric(id: "latest-distance", label: "最近行驶", value: "26.5 km"),
            DashboardOverviewMetric(id: "rated-range", label: "额定续航", value: "260 km")
        ])
        XCTAssertEqual(result.items.map(\.route), [
            .driveDetail(carId: 9, driveId: 88, exteriorColor: "PPSW"),
            .chargeDetail(carId: 9, chargeId: 15, exteriorColor: "PPSW"),
            .mileage(carId: 9, exteriorColor: "PPSW", targetDay: nil)
        ])
    }

    func testOverviewConvertsDriveRangesAndOdometerForImperialDisplay() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 3,
            odometer: 100,
            latestDrive: DashboardLatestDrive(
                driveId: 4,
                startedAt: nil,
                endedAt: nil,
                distanceKm: 26.5,
                durationMinutes: nil,
                energyConsumedNet: nil,
                consumptionNet: nil,
                startRatedRangeKm: 380,
                endRatedRangeKm: 342
            )
        )

        let result = DashboardOverviewPresentation(
            state: state,
            units: .imperial,
            language: .english
        )

        XCTAssertEqual(result.items[0].primaryValue, "16.5 mi")
        XCTAssertEqual(result.items[0].metrics[0].value, "24 mi")
        XCTAssertEqual(result.items[0].metrics[1].value, "213 mi")
        XCTAssertEqual(result.items[2].primaryValue, "62 mi")
    }

    func testOverviewKeepsStablePlaceholdersWithoutVehicleData() {
        let result = DashboardOverviewPresentation(
            state: DashboardState(isLoading: false),
            units: .metric,
            language: .english
        )

        XCTAssertEqual(result.items.map(\.primaryValue), ["--", "--", "--"])
        XCTAssertEqual(result.items.map(\.route), [nil, nil, nil])
        XCTAssertEqual(result.items[1].metrics.last?.value, "Add cost")
    }

    func testLatestChargeCostUsesSelectedRegionalCurrency() {
        let state = DashboardState(
            isLoading: false,
            currencyCode: "HKD",
            latestCharge: DashboardLatestCharge(
                chargeId: 2,
                startedAt: nil,
                endedAt: nil,
                energyAddedKWh: 8,
                cost: 12.5,
                durationMinutes: 20,
                address: "Ignored location",
                startBatteryLevel: 60,
                endBatteryLevel: 80,
                odometerKm: nil
            )
        )

        let result = DashboardOverviewPresentation(state: state, units: .metric, language: .english)

        XCTAssertEqual(result.items[1].metrics.map(\.id), ["battery-change", "duration", "cost"])
        XCTAssertEqual(result.items[1].metrics.last?.value, "HK$12.50")
        XCTAssertFalse(result.items[1].metrics.contains { $0.value.contains("Ignored location") })
    }

    func testLatestChargeLabelsExpiredTariffAsHistoricalReference() {
        let state = DashboardState(
            isLoading: false,
            currencyCode: "CNY",
            latestCharge: DashboardLatestCharge(
                chargeId: 3,
                startedAt: nil,
                endedAt: nil,
                energyAddedKWh: 10,
                cost: 5.04,
                durationMinutes: 60,
                address: "家",
                startBatteryLevel: 70,
                endBatteryLevel: 80,
                odometerKm: nil,
                isCostEstimated: true,
                isCostHistoricalReference: true
            )
        )

        let result = DashboardOverviewPresentation(
            state: state,
            units: .metric,
            language: .chinese
        )

        XCTAssertEqual(result.items[1].metrics.last?.label, "历史参考费用")
        XCTAssertEqual(result.items[1].metrics.last?.value, "¥5.04")
    }

    func testOverviewPresentsPersonalBestAtmosphereForLatestDrive() {
        let fingerprint = DriveRouteFingerprint(points: (0..<4).map { index in
            let point = SyntheticCoordinates.point(
                latitudeOffset: Double(index) * 0.01,
                longitudeOffset: Double(index) * 0.01
            )
            return DriveRoutePoint(latitude: point.latitude, longitude: point.longitude)
        })
        let label = DriveRouteLabelRule(
            carId: 9,
            name: "上班通勤",
            typicalDistanceKm: 20,
            fingerprint: fingerprint
        )
        let intelligence = DriveIntelligenceResult(
            confirmedLabel: label,
            suggestion: nil,
            benchmark: DriveBenchmarkResult(
                currentEfficiency: 150,
                benchmarkEfficiency: 190,
                percentageDifference: -21,
                recentEfficiencies: [210, 200, 190, 180, 150],
                currentTrendIndex: 4,
                rank: 1,
                previousBestEfficiency: 180,
                sampleCount: 4,
                samplesNeeded: 0,
                accent: .personalBest,
                isThreeDriveStreak: true,
                fiveDriveImprovementPercent: nil
            )
        )
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 9,
            latestDrive: DashboardLatestDrive(
                driveId: 88,
                startedAt: nil,
                endedAt: nil,
                distanceKm: 20,
                durationMinutes: 30,
                energyConsumedNet: 3,
                consumptionNet: 150,
                intelligence: intelligence
            )
        )

        let result = DashboardOverviewPresentation(state: state, units: .metric, language: .chinese)
        let highlight = result.items[0].highlight

        XCTAssertEqual(highlight?.style, .personalBest)
        XCTAssertEqual(highlight?.title, "新的个人最佳")
        XCTAssertEqual(highlight?.detail, "较原纪录节省 30 Wh/km")
        XCTAssertEqual(highlight?.systemImage, "trophy.fill")
    }
}
