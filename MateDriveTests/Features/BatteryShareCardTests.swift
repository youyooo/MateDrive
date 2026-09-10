import SwiftUI
import XCTest
@testable import MateDriveApp

@MainActor
final class BatteryShareCardTests: XCTestCase {
    func testDefaultReportHidesExactDatesAndOdometerAndDoesNotClaimLateHistoryAsLifetimeHealth() {
        let content = BatteryShareCardBuilder.content(
            stats: lateHistoryStats(),
            summary: historySummary(),
            units: .metric,
            language: .chinese,
            options: BatteryShareCardOptions()
        )

        XCTAssertEqual(content.title, "电池报告")
        XCTAssertEqual(content.headline, "需要校准")
        XCTAssertEqual(content.headlineLabel, "寿命健康度不可用")
        XCTAssertNil(content.exactRecordingPeriodText)
        XCTAssertFalse(content.metrics.contains(where: { $0.id == "recordingStartOdometer" }))
        XCTAssertEqual(content.metrics.first(where: { $0.id == "recordedCapacityRetention" })?.value, "99.3%")
        XCTAssertEqual(content.hiddenDetailsLabel, "精确记录日期和起始里程已隐藏")
        XCTAssertTrue(content.warningText.contains("不代表整车寿命健康度"))
        XCTAssertFalse(String(describing: content).contains("110,000"))
        XCTAssertFalse(String(describing: content).contains("2026"))
    }

    func testCalibratedReportShowsAbsoluteHealthAndOptionalSensitiveDetails() {
        let content = BatteryShareCardBuilder.content(
            stats: calibratedStats(),
            summary: historySummary(),
            units: .metric,
            language: .english,
            options: BatteryShareCardOptions(
                includesExactRecordingPeriod: true,
                includesRecordingStartOdometer: true
            )
        )

        XCTAssertEqual(content.headline, "88.0%")
        XCTAssertEqual(content.headlineLabel, "Estimated battery health")
        XCTAssertNotNil(content.exactRecordingPeriodText)
        XCTAssertEqual(content.metrics.first(where: { $0.id == "recordingStartOdometer" })?.value, "110,000 km")
        XCTAssertNil(content.hiddenDetailsLabel)
        XCTAssertTrue(content.optionsIncludeSensitiveDetails)
        XCTAssertTrue(content.warningText.contains("not a physical battery diagnosis"))
    }

    func testReportPreservesMissingValuesInsteadOfDisplayingZero() {
        let stats = BatteryViewModel.computeStats(
            health: BatteryHealth(),
            status: nil,
            batteryRecordingStartOdometerKm: 110_000
        )
        let content = BatteryShareCardBuilder.content(
            stats: stats,
            summary: nil,
            units: .metric,
            language: .english,
            options: BatteryShareCardOptions()
        )

        XCTAssertEqual(content.headline, "Needs calibration")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "capacityNow" })?.value, "--")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "rangeAt100" })?.value, "--")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "dataQuality" })?.value, "--")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "recordingSpan" })?.value, "--")
        XCTAssertFalse(String(describing: content).contains("0.0 kWh"))
        XCTAssertFalse(String(describing: content).contains("0 days"))
    }

    func testUnknownRecordingStartReportHidesTeslaMatePercentageAsLifetimeHealth() {
        let stats = BatteryViewModel.computeStats(
            health: BatteryHealth(
                maxRange: 476,
                currentRange: 471,
                maxCapacity: 69.5,
                currentCapacity: 69,
                ratedEfficiency: 146,
                batteryHealthPercentage: 99.3
            ),
            status: nil
        )
        let content = BatteryShareCardBuilder.content(
            stats: stats,
            summary: historySummary(),
            units: .metric,
            language: .chinese,
            options: BatteryShareCardOptions()
        )

        XCTAssertEqual(stats.confidence, .recordingStartUnknown)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertEqual(content.headline, "需要校准")
        XCTAssertEqual(content.headlineLabel, "寿命健康度不可用")
        XCTAssertNil(content.healthFraction)
        XCTAssertEqual(content.confidenceText, "记录起点未知")
        XCTAssertFalse(content.headline.contains("99.3"))
        XCTAssertEqual(
            content.metrics.first(where: { $0.id == "recordedCapacityRetention" })?.value,
            "99.3%"
        )
    }

    func testBatteryReportRendersAsHighResolutionNonblankImage() throws {
        let content = BatteryShareCardBuilder.content(
            stats: calibratedStats(),
            summary: historySummary(),
            units: .metric,
            language: .chinese,
            options: BatteryShareCardOptions()
        )
        let renderer = ImageRenderer(content: BatteryShareCardView(content: content))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1350)
        XCTAssertTrue(imageHasVisibleVariation(cgImage))

        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Battery Report"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func lateHistoryStats() -> BatteryStats {
        BatteryViewModel.computeStats(
            health: BatteryHealth(
                maxRange: 476,
                currentRange: 471,
                maxCapacity: 69.5,
                currentCapacity: 69,
                ratedEfficiency: 146,
                batteryHealthPercentage: 99.3
            ),
            status: nil,
            batteryRecordingStartOdometerKm: 110_000
        )
    }

    private func calibratedStats() -> BatteryStats {
        BatteryViewModel.computeStats(
            health: BatteryHealth(
                maxRange: 476,
                currentRange: 440,
                maxCapacity: 69.5,
                currentCapacity: 68.2,
                ratedEfficiency: 155,
                batteryHealthPercentage: 99.3
            ),
            status: nil,
            batteryReferenceRangeKm: 500,
            batteryRecordingStartOdometerKm: 110_000
        )
    }

    private func historySummary() -> BatteryHistorySummary {
        BatteryHistorySummary(
            startDate: "2026-01-01T00:00:00Z",
            endDate: "2026-07-01T00:00:00Z",
            startOdometerKm: 110_000,
            endOdometerKm: 118_000,
            capacityStartKWh: 69.5,
            capacityCurrentKWh: 69,
            capacityChangeKWh: -0.5,
            rangeStartKm: 476,
            rangeCurrentKm: 471,
            rangeChangeKm: -5,
            efficiencyWhKm: 146,
            qualifyingChargeCount: 7,
            capacityUsesMedian: true,
            rangeSmoothingSampleCount: 3,
            quality: BatteryHistoryQuality(
                score: 82,
                capacitySampleCount: 12,
                rangeSampleCount: 30,
                qualifyingChargeCount: 7,
                requiredChargeCount: 5,
                recordedDays: 181,
                recordedDistanceKm: 8_000
            )
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
