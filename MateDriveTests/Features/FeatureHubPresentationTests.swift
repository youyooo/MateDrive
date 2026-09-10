import XCTest
@testable import MateDriveApp

final class FeatureHubPresentationTests: XCTestCase {
    func testPresentationUsesSelectedVehicleAndCurrentExteriorColor() {
        let state = DashboardState(
            isLoading: false,
            cars: [
                DashboardCarOption(id: 3, name: "Road Trip"),
                DashboardCarOption(id: 7, name: "Model 3")
            ],
            selectedCarId: 7,
            carName: "Model 3 Performance",
            exteriorColor: "PPSW"
        )

        let presentation = FeatureHubPresentation(state: state)

        XCTAssertEqual(presentation.headerMode, .vehiclePicker)
        XCTAssertTrue(presentation.isAvailable)
        XCTAssertTrue(
            presentation.sections
                .flatMap(\.items)
                .map(\.route)
                .contains(.charges(carId: 7, exteriorColor: "PPSW"))
        )
    }

    func testSingleVehicleDoesNotCreateARepeatedVehicleHeading() {
        let presentation = FeatureHubPresentation(state: DashboardState(
            isLoading: false,
            cars: [DashboardCarOption(id: 7, name: "Model 3")],
            selectedCarId: 7,
            carName: "Model 3 Performance"
        ))

        XCTAssertEqual(presentation.headerMode, .none)
    }

    func testPresentationDoesNotCreateRoutesWithoutSelectedVehicle() {
        let state = DashboardState(
            isLoading: false,
            cars: [DashboardCarOption(id: 3, name: "Road Trip")],
            selectedCarId: nil,
            carName: "Tesla"
        )

        let presentation = FeatureHubPresentation(state: state)

        XCTAssertFalse(presentation.isAvailable)
        XCTAssertEqual(presentation.headerMode, .none)
        XCTAssertTrue(presentation.sections.isEmpty)
    }

    func testPresentationKeepsCatalogAvailableWhileCacheRefreshes() {
        let state = DashboardState(
            isLoading: true,
            cars: [DashboardCarOption(id: 7, name: "Model 3")],
            selectedCarId: 7,
            carName: "Model 3"
        )

        let presentation = FeatureHubPresentation(state: state)

        XCTAssertTrue(presentation.isAvailable)
        XCTAssertEqual(presentation.sections.flatMap(\.items).count, 17)
    }
}
