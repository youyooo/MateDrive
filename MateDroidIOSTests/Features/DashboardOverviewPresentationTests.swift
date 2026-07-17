import XCTest
@testable import MateDroidIOS

final class DashboardOverviewPresentationTests: XCTestCase {
    func testOverviewUsesOnlyExistingDashboardState() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 9,
            odometer: 118_859,
            exteriorColor: "PPSW",
            totalCharges: 15,
            totalDrives: 88
        )

        let result = DashboardOverviewPresentation(
            state: state,
            units: .metric,
            language: .chinese
        )

        XCTAssertEqual(result.items.map(\.title), ["里程表", "行程", "充电"])
        XCTAssertEqual(result.items.map(\.value), ["118,859 km", "88", "15"])
        XCTAssertEqual(result.items.map(\.route), [
            .mileage(carId: 9, exteriorColor: "PPSW", targetDay: nil),
            .activities(carId: 9, exteriorColor: "PPSW"),
            .charges(carId: 9, exteriorColor: "PPSW")
        ])
    }

    func testOverviewConvertsOdometerForImperialDisplay() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 3,
            odometer: 100,
            totalCharges: 2,
            totalDrives: 4
        )

        let result = DashboardOverviewPresentation(
            state: state,
            units: .imperial,
            language: .english
        )

        XCTAssertEqual(result.items.map(\.title), ["Odometer", "Drives", "Charges"])
        XCTAssertEqual(result.items.map(\.value), ["62 mi", "4", "2"])
    }

    func testOverviewKeepsStablePlaceholdersWithoutVehicleData() {
        let result = DashboardOverviewPresentation(
            state: DashboardState(isLoading: false),
            units: .metric,
            language: .english
        )

        XCTAssertEqual(result.items.map(\.value), ["--", "--", "--"])
        XCTAssertEqual(result.items.map(\.route), [nil, nil, nil])
    }
}
