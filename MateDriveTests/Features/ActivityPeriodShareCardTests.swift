import SwiftUI
import XCTest
@testable import MateDriveApp

@MainActor
final class ActivityPeriodShareCardTests: XCTestCase {
    func testDefaultRecapHidesExactDatesAndCostsAndMarksPartialHistory() {
        let content = ActivityPeriodShareCardBuilder.content(
            summary: summaryFixture(),
            dateFilter: .thirtyDays,
            activityFilter: .all,
            dateRange: ActivityPeriodDateRange(
                start: Date(timeIntervalSince1970: 1_782_864_000),
                end: Date(timeIntervalSince1970: 1_783_468_800)
            ),
            historyIsComplete: false,
            locationFilterIsActive: true,
            currencyCode: "CNY",
            units: .metric,
            language: .chinese,
            options: ActivityPeriodShareCardOptions()
        )

        XCTAssertEqual(content.title, "活动回顾")
        XCTAssertEqual(content.periodLabel, "最近 30 天")
        XCTAssertNil(content.exactDateRangeText)
        XCTAssertTrue(content.costMetrics.isEmpty)
        XCTAssertEqual(content.historyLabel, "历史记录不完整")
        XCTAssertEqual(content.recordCountText, "≥6")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "distance" })?.value, "≥30.0 km")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "chargedEnergy" })?.value, "≥20.0 kWh")
        XCTAssertEqual(content.hiddenDetailsLabel, "精确日期和费用已隐藏")
        XCTAssertTrue(content.scopeLabels.contains("已应用地点筛选"))
        XCTAssertFalse(String(describing: content).contains("¥12.50"))
        XCTAssertFalse(String(describing: content).contains("2026"))
    }

    func testSelectedSensitiveDetailsIncludeExactDateRangeAndCoverageAwareCosts() {
        let options = ActivityPeriodShareCardOptions(includesExactDateRange: true, includesCosts: true)
        let content = ActivityPeriodShareCardBuilder.content(
            summary: summaryFixture(),
            dateFilter: .thirtyDays,
            activityFilter: .all,
            dateRange: ActivityPeriodDateRange(
                start: Date(timeIntervalSince1970: 1_782_864_000),
                end: Date(timeIntervalSince1970: 1_783_468_800)
            ),
            historyIsComplete: true,
            locationFilterIsActive: false,
            currencyCode: "CNY",
            units: .metric,
            language: .english,
            options: options
        )

        XCTAssertTrue(options.includesSensitiveDetails)
        XCTAssertNotNil(content.exactDateRangeText)
        XCTAssertEqual(content.costMetrics.first(where: { $0.id == "chargeCost" })?.value, "≥¥12.50")
        XCTAssertEqual(content.costMetrics.first(where: { $0.id == "parkingCost" })?.value, "≥¥10.00")
        XCTAssertTrue(content.coverageNotes.contains("Price coverage: 1/2"))
        XCTAssertTrue(content.coverageNotes.contains("1 parking record unmatched"))
        XCTAssertNil(content.hiddenDetailsLabel)
    }

    func testParkingCostDistinguishesNoParkingFromEntirelyUnmatchedParking() {
        let unmatched = ActivityPeriodShareCardBuilder.content(
            summary: ActivityPeriodSummary(
                activityCount: 1,
                driveCount: 0,
                chargeCount: 0,
                parkingCount: 1,
                distanceKm: nil,
                distanceRecordCount: 0,
                distanceIsComplete: true,
                chargedEnergyKWh: nil,
                chargedEnergyRecordCount: 0,
                chargedEnergyIsComplete: true,
                drivingEnergyKWh: nil,
                drivingEnergyRecordCount: 0,
                drivingEnergyIsComplete: true,
                knownChargeCost: nil,
                pricedChargeCount: 0,
                missingChargeCostCount: 0,
                chargeCostIsComplete: true,
                parkingCost: ParkingCostSummary(sessionCost: 0, recurringMonthlyCost: 0, matchedParkingCount: 0, unmatchedParkingCount: 1)
            ),
            dateFilter: .all,
            activityFilter: .park,
            dateRange: nil,
            historyIsComplete: true,
            locationFilterIsActive: false,
            currencyCode: "CNY",
            units: .metric,
            language: .english,
            options: ActivityPeriodShareCardOptions(includesCosts: true)
        )
        let noParking = ActivityPeriodShareCardBuilder.content(
            summary: emptySummary(),
            dateFilter: .all,
            activityFilter: .all,
            dateRange: nil,
            historyIsComplete: true,
            locationFilterIsActive: false,
            currencyCode: "CNY",
            units: .metric,
            language: .english,
            options: ActivityPeriodShareCardOptions(includesCosts: true)
        )

        XCTAssertEqual(unmatched.costMetrics.first(where: { $0.id == "parkingCost" })?.value, "--")
        XCTAssertEqual(noParking.costMetrics.first(where: { $0.id == "parkingCost" })?.value, "¥0.00")

        let partialEmpty = ActivityPeriodShareCardBuilder.content(
            summary: emptySummary(),
            dateFilter: .all,
            activityFilter: .all,
            dateRange: nil,
            historyIsComplete: false,
            locationFilterIsActive: false,
            currencyCode: "CNY",
            units: .metric,
            language: .english,
            options: ActivityPeriodShareCardOptions(includesCosts: true)
        )
        XCTAssertEqual(partialEmpty.costMetrics.first(where: { $0.id == "chargeCost" })?.value, "--")
        XCTAssertEqual(partialEmpty.costMetrics.first(where: { $0.id == "parkingCost" })?.value, "--")
    }

    func testPeriodRecapRendersAsHighResolutionNonblankImage() throws {
        let content = ActivityPeriodShareCardBuilder.content(
            summary: summaryFixture(),
            dateFilter: .thirtyDays,
            activityFilter: .all,
            dateRange: nil,
            historyIsComplete: true,
            locationFilterIsActive: false,
            currencyCode: "CNY",
            units: .metric,
            language: .chinese,
            options: ActivityPeriodShareCardOptions(includesCosts: true)
        )
        let renderer = ImageRenderer(content: ActivityPeriodShareCardView(content: content))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1350)
        XCTAssertTrue(imageHasVisibleVariation(cgImage))

        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Activity Period Recap"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func summaryFixture() -> ActivityPeriodSummary {
        ActivityPeriodSummary(
            activityCount: 6,
            driveCount: 2,
            chargeCount: 2,
            parkingCount: 2,
            distanceKm: 30,
            distanceRecordCount: 1,
            distanceIsComplete: false,
            chargedEnergyKWh: 20,
            chargedEnergyRecordCount: 1,
            chargedEnergyIsComplete: false,
            drivingEnergyKWh: 5,
            drivingEnergyRecordCount: 1,
            drivingEnergyIsComplete: false,
            knownChargeCost: 12.5,
            pricedChargeCount: 1,
            missingChargeCostCount: 1,
            chargeCostIsComplete: false,
            parkingCost: ParkingCostSummary(sessionCost: 10, recurringMonthlyCost: 0, matchedParkingCount: 1, unmatchedParkingCount: 1)
        )
    }

    private func emptySummary() -> ActivityPeriodSummary {
        ActivityPeriodSummary(
            activityCount: 0,
            driveCount: 0,
            chargeCount: 0,
            parkingCount: 0,
            distanceKm: nil,
            distanceRecordCount: 0,
            distanceIsComplete: true,
            chargedEnergyKWh: nil,
            chargedEnergyRecordCount: 0,
            chargedEnergyIsComplete: true,
            drivingEnergyKWh: nil,
            drivingEnergyRecordCount: 0,
            drivingEnergyIsComplete: true,
            knownChargeCost: nil,
            pricedChargeCount: 0,
            missingChargeCostCount: 0,
            chargeCostIsComplete: true,
            parkingCost: ParkingCostSummary(sessionCost: 0, recurringMonthlyCost: 0, matchedParkingCount: 0, unmatchedParkingCount: 0)
        )
    }

    private func imageHasVisibleVariation(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel >= 32
        else { return false }

        let bytesPerPixel = image.bitsPerPixel / 8
        var sampledColors = Set<UInt32>()
        let xStep = max(image.width / 20, 1)
        let yStep = max(image.height / 20, 1)
        for y in stride(from: 0, to: image.height, by: yStep) {
            for x in stride(from: 0, to: image.width, by: xStep) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                sampledColors.insert(
                    UInt32(bytes[offset]) << 24
                        | UInt32(bytes[offset + 1]) << 16
                        | UInt32(bytes[offset + 2]) << 8
                        | UInt32(bytes[offset + 3])
                )
            }
        }
        return sampledColors.count >= 4
    }
}
