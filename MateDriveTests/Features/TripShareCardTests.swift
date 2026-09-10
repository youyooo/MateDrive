import SwiftUI
import XCTest
@testable import MateDriveApp

@MainActor
final class TripShareCardTests: XCTestCase {
    func testDefaultReportHidesDatesLocationsRouteCostsAndCustomName() throws {
        let trip = try fixtureTrip()
        let content = TripShareCardBuilder.content(
            trip: trip,
            routeSegments: routeSegments(),
            countryCount: 2,
            units: .metric,
            currencySymbol: "¥",
            language: .chinese,
            options: TripShareCardOptions()
        )

        XCTAssertEqual(content.title, "路程报告")
        XCTAssertEqual(content.headline, "330 km")
        XCTAssertNil(content.exactDateRangeText)
        XCTAssertNil(content.locationText)
        XCTAssertTrue(content.routeSegments.isEmpty)
        XCTAssertFalse(content.metrics.contains(where: { $0.id == "chargeCost" }))
        XCTAssertTrue(content.optionsIncludeSensitiveDetails == false)
        XCTAssertNotNil(content.hiddenDetailsLabel)
        let description = String(describing: content)
        XCTAssertFalse(description.contains("Secret Alps Trip"))
        XCTAssertFalse(description.contains("Paris"))
        XCTAssertFalse(description.contains("Geneva"))
        XCTAssertFalse(description.contains("2026-01-01"))
        XCTAssertFalse(description.contains("¥18.50"))
    }

    func testOptionalSensitiveDetailsAreIncludedOnlyWhenSelected() throws {
        let content = TripShareCardBuilder.content(
            trip: try fixtureTrip(),
            routeSegments: routeSegments(),
            countryCount: 2,
            units: .metric,
            currencySymbol: "¥",
            language: .english,
            options: TripShareCardOptions(
                includesExactDateRange: true,
                includesLocations: true,
                includesRouteShape: true,
                includesCosts: true
            )
        )

        XCTAssertNotNil(content.exactDateRangeText)
        XCTAssertEqual(content.locationText, "Paris → Geneva")
        XCTAssertEqual(content.routeSegments.count, 2)
        XCTAssertTrue(content.routeSegments.flatMap(\.points).allSatisfy {
            (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y)
        })
        XCTAssertEqual(content.metrics.first(where: { $0.id == "chargeCost" })?.value, "≥¥18.50")
        XCTAssertTrue(content.optionsIncludeSensitiveDetails)
        XCTAssertNil(content.hiddenDetailsLabel)
    }

    func testReportPreservesMissingAndPartialEnergyInsteadOfDisplayingZero() throws {
        let trip = try XCTUnwrap(JourneySummaryBuilder.makeSummary(
            drives: [
                TripDrive(id: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T09:00:00Z", distance: 40, durationMin: 60, energyConsumed: 7),
                TripDrive(id: 2, startDate: "2026-01-01T09:10:00Z", endDate: "2026-01-01T10:00:00Z", distance: 30, durationMin: 50, energyConsumed: nil)
            ],
            charges: [
                TripCharge(id: 3, startDate: "2026-01-01T10:05:00Z", endDate: "2026-01-01T10:35:00Z", energyAdded: nil)
            ]
        ))
        let content = TripShareCardBuilder.content(
            trip: trip,
            routeSegments: [],
            countryCount: 0,
            units: .metric,
            currencySymbol: "€",
            language: .english,
            options: TripShareCardOptions()
        )

        XCTAssertEqual(content.metrics.first(where: { $0.id == "drivingEnergy" })?.value, "≥7.0 kWh")
        XCTAssertEqual(content.metrics.first(where: { $0.id == "chargedEnergy" })?.value, "--")
        XCTAssertFalse(String(describing: content).contains("0.0 kWh"))
    }

    func testTripReportRendersAsHighResolutionNonblankImage() throws {
        let content = TripShareCardBuilder.content(
            trip: try fixtureTrip(),
            routeSegments: routeSegments(),
            countryCount: 2,
            units: .metric,
            currencySymbol: "¥",
            language: .chinese,
            options: TripShareCardOptions(includesRouteShape: true)
        )
        let renderer = ImageRenderer(content: TripShareCardView(content: content))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1350)
        XCTAssertTrue(imageHasVisibleVariation(cgImage))

        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Trip Report"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func fixtureTrip() throws -> DetectedTrip {
        try XCTUnwrap(JourneySummaryBuilder.makeSummary(
            drives: [
                TripDrive(id: 1, startDate: "2026-01-01T08:00:00Z", endDate: "2026-01-01T10:00:00Z", distance: 180, durationMin: 120, energyConsumed: 32, speedMax: 125, startAddress: "Paris, France", endAddress: "Lyon, France"),
                TripDrive(id: 2, startDate: "2026-01-01T10:40:00Z", endDate: "2026-01-01T12:10:00Z", distance: 150, durationMin: 90, energyConsumed: nil, speedMax: 118, startAddress: "Lyon, France", endAddress: "Geneva, Switzerland")
            ],
            charges: [
                TripCharge(id: 3, startDate: "2026-01-01T10:05:00Z", endDate: "2026-01-01T10:35:00Z", energyAdded: 45, cost: 18.5, address: "Lyon, France"),
                TripCharge(id: 4, startDate: "2026-01-01T12:15:00Z", endDate: "2026-01-01T12:45:00Z", energyAdded: nil, cost: nil, address: "Geneva, Switzerland")
            ],
            name: "Secret Alps Trip"
        ))
    }

    private func routeSegments() -> [SavedTripRouteSegment] {
        let first = SyntheticCoordinates.point()
        let second = SyntheticCoordinates.point(latitudeOffset: 0.01, longitudeOffset: 0.015)
        let third = SyntheticCoordinates.point(latitudeOffset: 0.018, longitudeOffset: 0.03)
        return [
            SavedTripRouteSegment(driveId: 1, points: [
                GeocodeLocation(latitude: first.latitude, longitude: first.longitude),
                GeocodeLocation(latitude: second.latitude, longitude: second.longitude)
            ]),
            SavedTripRouteSegment(driveId: 2, points: [
                GeocodeLocation(latitude: second.latitude, longitude: second.longitude),
                GeocodeLocation(latitude: third.latitude, longitude: third.longitude)
            ])
        ]
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
