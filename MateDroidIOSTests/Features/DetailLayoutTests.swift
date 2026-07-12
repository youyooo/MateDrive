import SwiftUI
import UIKit
import XCTest
@testable import MateDroidIOS

@MainActor
final class DetailLayoutTests: XCTestCase {
    func testCostReviewRendersReferenceLayoutWithoutExceedingPhoneWidth() throws {
        let payload = #"{"contractVersion":1,"data":{"range":{"startDate":"2026-06-12T00:00:00+08:00","endDate":"2026-07-12T00:00:00+08:00","period":"day"},"summary":{"recordedSpend":27.83,"estimatedUseCost":510.61,"chargingCost":27.83,"parkingCost":null,"estimatedDrivingEnergyCost":347.49,"estimatedStandbyEnergyCost":163.12,"totalDistanceKm":1085.08,"driveCount":72,"chargeCount":15,"missingChargeCostCount":14,"missingParkingCostCount":30},"dataQuality":{"hasAnyActivity":true,"hasStatsSummary":true,"chargingCost":{"eventCount":15,"costRecordedCount":1,"missingCostCount":14,"zeroCostCount":0,"costCoverage":0.0667},"parkingCost":{"eventCount":30,"costRecordedCount":0,"missingCostCount":30,"zeroCostCount":0,"costCoverage":0},"energyEstimate":{"isAvailable":true,"pricePerKwh":1.287,"consumptionWhPerKm":248.8}},"buckets":[{"id":"day:1","dateFrom":1782316800000,"estimatedUseCost":39.4,"recordedSpend":27.83},{"id":"day:2","dateFrom":1782489600000,"estimatedUseCost":52.84,"recordedSpend":null},{"id":"day:3","dateFrom":1782662400000,"estimatedUseCost":31.2,"recordedSpend":null}],"chargingModes":[{"mode":"AC","chargeCount":12,"energyKwh":280.2}],"placeRankings":{"charging":[{"kind":"charging","placeId":1,"displayName":"家","chargeCount":9,"totalCost":27.83,"costRecordedCount":1,"missingCostCount":8},{"kind":"charging","placeId":2,"displayName":"公司","chargeCount":4,"totalCost":null,"costRecordedCount":0,"missingCostCount":4}],"parking":[],"standby":[],"parkingZeroCostConfirmed":false},"comparison":{"previousRange":{"startDate":"2026-05-13T00:00:00+08:00","endDate":"2026-06-12T00:00:00+08:00","period":"day"},"estimatedUseCost":{"isEligible":false,"currentValue":510.61,"previousValue":480.2,"reasonCodes":["current_missing_parking_cost"]},"recordedSpend":{"isEligible":false,"currentValue":27.83,"previousValue":18.2,"reasonCodes":["current_missing_charging_cost"]}},"records":{"topCharges":[{"id":14,"type":"charge","title":"家","startDate":"2026-06-25T12:00:00Z","energyKwh":21.62,"cost":27.83}],"missingChargeCosts":[{"id":15,"type":"charge","title":"公司","startDate":"2026-07-02T12:00:00Z","energyKwh":18.2}],"missingParkingCosts":[{"id":99,"type":"park","title":"商场","startDate":"2026-07-02T13:00:00Z","durationMin":120}]}} ,"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#
        let response = try JSONDecoder.teslamate.decode(CostReviewResponse.self, from: Data(payload.utf8))
        var state = CostReviewState()
        state.isLoading = false
        state.response = response
        let viewModel = CostReviewViewModel(api: VisualCostReviewAPI(response: response), initialState: state)
        let content = CostReviewView(carId: 1, exteriorColor: nil, currencySymbol: "¥", viewModel: viewModel, navigate: { _ in })
        .frame(width: 390, height: 1_900, alignment: .top)
        .background(Color(uiColor: .systemBackground))
        .environment(\.appLanguage, .chinese)
        let image = renderHierarchy(content, size: CGSize(width: 390, height: 1_900))

        XCTAssertEqual(image.size.width, 390)
        XCTAssertEqual(image.size.height, 1_900)
        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Cost Review Chinese"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDriveTimeSeriesChartDoesNotExpandBeyondPhoneWidthWithManySamples() {
        let positions = (0..<240).map { index in
            DrivePosition(date: "2026-07-01T08:\(String(format: "%02d", index / 60)):\(String(format: "%02d", index % 60))Z", speed: index % 100)
        }
        let view = DriveTimeSeriesChart(
            title: "Speed",
            kind: .speed,
            positions: positions,
            units: .metric
        )

        let size = fittingSize(for: view, width: 320)

        XCTAssertLessThanOrEqual(size.width, 320)
    }

    func testDriveTirePressureChartConvertsUnitsAndFitsSmallPhoneWidth() {
        let positions = [
            DrivePosition(date: "2026-07-01T08:00:00Z", tpmsPressureFl: 3.0, tpmsPressureFr: 3.1, tpmsPressureRl: 2.9, tpmsPressureRr: 2.8),
            DrivePosition(date: "2026-07-01T08:10:00Z", tpmsPressureFl: 2.9, tpmsPressureFr: 3.0, tpmsPressureRl: 2.8, tpmsPressureRr: 2.7)
        ]

        let metric = DriveChartSampleBuilder.samples(kind: .tirePressure, positions: positions, units: .metric)
        let imperial = DriveChartSampleBuilder.samples(kind: .tirePressure, positions: positions, units: .imperial)
        let psiSource = DriveChartSampleBuilder.samples(
            kind: .tirePressure,
            positions: [DrivePosition(date: "2026-07-01T08:00:00Z", tpmsPressureFl: 43.5114)],
            units: .metric,
            sourcePressureUnit: "psi"
        )
        let view = DriveTimeSeriesChart(title: "胎压", kind: .tirePressure, positions: positions, units: .metric)
            .environment(\.appLanguage, .chinese)
        let size = fittingSize(for: view, width: 320)

        XCTAssertEqual(metric.count, 8)
        XCTAssertEqual(Set(metric.map(\.series)), ["frontLeft", "frontRight", "rearLeft", "rearRight"])
        XCTAssertEqual(metric.first?.value, 3.0)
        XCTAssertEqual(imperial.first?.value ?? 0, 43.5114, accuracy: 0.001)
        XCTAssertEqual(psiSource.first?.value ?? 0, 3.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(size.width, 320)
    }

    func testDriveTimeSeriesChartRendersVisualAttachment() throws {
        var positions: [DrivePosition] = []
        for index in 0..<24 {
            let date = String(format: "2026-07-01T18:%02d:00Z", index)
            let position = DrivePosition(
                date: date,
                speed: 35 + ((index * 17) % 60),
                power: index % 5 == 0 ? -12 : 10 + ((index * 13) % 55),
                batteryLevel: 75 - index / 4,
                elevation: 45 + Int(sin(Double(index) / 4) * 8),
                climateInfo: DriveClimateInfo(insideTemp: 22, outsideTemp: 18.5)
            )
            positions.append(position)
        }
        let content = DriveTimeSeriesChart(title: "速度", kind: .speed, positions: positions, units: .metric)
            .padding(16)
            .frame(width: 390, height: 260)
            .background(Color(uiColor: .systemBackground))
            .environment(\.appLanguage, .chinese)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image: UIImage = renderer.uiImage else {
            return XCTFail("Expected chart renderer to produce a UIImage.")
        }

        XCTAssertEqual(image.size.width, 390)
        XCTAssertEqual(image.size.height, 260)
        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Drive Time Series Chart"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
    }

    func testDriveAnalysisPanelRendersAllReferenceChartsInDarkMode() throws {
        var positions: [DrivePosition] = []
        for index in 0..<32 {
            let wave = sin(Double(index) / 6)
            let temperatureWave = sin(Double(index) / 8)
            positions.append(DrivePosition(
                date: String(format: "2026-07-01T18:%02d:00Z", index),
                speed: 30 + ((index * 19) % 70),
                power: index % 6 == 0 ? -15 : 8 + ((index * 17) % 65),
                batteryLevel: 78 - index / 4,
                elevation: 48 + Int(sin(Double(index) / 5) * 10),
                tpmsPressureFl: 2.84 + wave * 0.02,
                tpmsPressureFr: 2.86 + wave * 0.02,
                tpmsPressureRl: 2.89 + wave * 0.02,
                tpmsPressureRr: 2.85 + wave * 0.02,
                climateInfo: DriveClimateInfo(insideTemp: 22, outsideTemp: 18.5 + temperatureWave),
                batteryInfo: DriveBatteryInfo(batteryHeater: index < 4)
            ))
        }
        let detail = DriveDetail(
            driveId: 1,
            positions: positions,
            sourceUnits: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
        )
        let content = DrivePositionCharts(detail: detail, units: .metric)
            .padding(16)
            .frame(width: 390, height: 1_900, alignment: .top)
            .background(Color(uiColor: .systemBackground))
            .environment(\.appLanguage, .chinese)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.uiImage else {
            return XCTFail("Expected the analysis panel to render.")
        }

        XCTAssertEqual(image.size.width, 390)
        XCTAssertEqual(image.size.height, 1_900)
        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Drive Analysis Panel Dark"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
    }

    func testChargePointChartDoesNotExpandBeyondPhoneWidthWithManySamples() {
        let points = (0..<240).map { index in
            ChargePoint(
                date: nil,
                batteryLevel: index % 100,
                chargeEnergyAdded: nil,
                chargerDetails: ChargerDetails(chargerPower: 90)
            )
        }

        let size = fittingSize(for: ChargePointChart(points: points), width: 320)

        XCTAssertLessThanOrEqual(size.width, 320)
    }

    func testChargeComparisonCurveDoesNotExpandBeyondPhoneWidthWithManySamples() {
        let points = (0..<240).map { index in
            SessionCurvePoint(soc: Double(index) / 2.4, power: Double(20 + (index % 120)))
        }

        let size = fittingSize(for: ChargeComparisonCurveChart(points: points, isBase: true), width: 320)

        XCTAssertLessThanOrEqual(size.width, 320)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testDriveStatsGridWithReconstructedEnergySourceFitsSmallPhoneWidth() {
        let detail = DriveDetail(
            driveId: 1,
            distance: 10,
            durationMin: 20,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", speed: 30, power: 18, batteryLevel: 70, elevation: 40),
                DrivePosition(date: "2026-07-01T08:00:20Z", speed: 45, power: 22, batteryLevel: 69, elevation: 42)
            ]
        )
        let stats = DriveStatsCalculator.calculateStats(detail)
        let view = DriveStatsGrid(stats: stats, units: .metric)
            .environment(\.appLanguage, .chinese)

        let size = fittingSize(for: view, width: 320)

        XCTAssertEqual(stats.energySource, DriveEnergySource.powerSamples)
        XCTAssertLessThanOrEqual(size.width, 320)
    }

    func testDashboardTyrePressureDoesNotExpandBeyondSmallPhoneWidth() {
        let tpms = TpmsDetails(
            pressureFl: 3.0,
            pressureFr: 3.075,
            pressureRl: nil,
            pressureRr: 2.95,
            warningFl: false,
            warningFr: true,
            warningRl: nil,
            warningRr: false
        )
        let view = DashboardTyrePressureView(
            tpms: tpms,
            units: .metric,
            palette: CarColorPalettes.forExteriorColor(nil, darkTheme: false)
        )
        .environment(\.appLanguage, .chinese)

        let size = fittingSize(for: view, width: 320)

        XCTAssertLessThanOrEqual(size.width, 320)
    }

    private func fittingSize<Content: View>(for view: Content, width: CGFloat) -> CGSize {
        let controller = UIHostingController(rootView: view)
        controller.view.bounds = CGRect(x: 0, y: 0, width: width, height: 1_000)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller.sizeThatFits(in: CGSize(width: width, height: 1_000))
    }

    private func renderHierarchy<Content: View>(_ view: Content, size: CGSize) -> UIImage {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }
}

private struct VisualCostReviewAPI: CostReviewAPIProviding {
    let response: CostReviewResponse
    func costReview(carId _: Int, startDate _: Date, endDate _: Date) async -> APIResult<CostReviewResponse> {
        .success(response)
    }
}
