import XCTest
@testable import MateDroidIOS

final class RecentDrivingMapViewModelTests: XCTestCase {
    func testDecodesMeasured251CoordinatePayload() throws {
        let response = try Self.fixture()
        let point = try XCTUnwrap(response.data.coordinates.first)
        XCTAssertEqual(response.data.originalPoints, 4)
        XCTAssertEqual(response.data.simplifiedPoints, 4)
        XCTAssertEqual(point.driveId, 139)
        XCTAssertEqual(point.outsideTemp, 28.5)
        XCTAssertEqual(point.type, "track")
        XCTAssertEqual(response.data.units?.length, "km")
    }

    @MainActor
    func testGroupsSortsAndFiltersCoordinatesWithoutInventingSamples() async throws {
        let api = DrivingCoordinatesAPIStub(result: .success(try Self.fixture()))
        let viewModel = RecentDrivingMapViewModel(api: api)
        await viewModel.load(carId: 6)

        XCTAssertEqual(viewModel.state.routes.map(\.id), [140, 139])
        XCTAssertEqual(viewModel.state.routes.last?.points.count, 2)
        XCTAssertEqual(viewModel.state.routes.last?.maximumSpeed, 18)
        XCTAssertEqual(viewModel.state.invalidPointCount, 1)
        XCTAssertEqual(viewModel.state.originalPointCount, 4)
        let receivedCarID = await api.receivedCarID
        XCTAssertEqual(receivedCarID, 6)
    }

    @MainActor
    func testFailureLeavesRouteCollectionEmpty() async {
        let viewModel = RecentDrivingMapViewModel(api: DrivingCoordinatesAPIStub(result: .failure(.network("offline"))))
        await viewModel.load(carId: 1)
        XCTAssertTrue(viewModel.state.routes.isEmpty)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    private static func fixture() throws -> DrivingCoordinatesResponse {
        let json = #"{"data":{"car_id":1,"coordinates":[{"drive_id":139,"latitude":28.207473,"longitude":112.857734,"speed":3,"elevation":0,"outside_temp":28.5,"date":"2026-07-10T23:40:59Z","type":"track"},{"drive_id":139,"latitude":28.2076,"longitude":112.858,"speed":18,"date":"2026-07-10T23:41:19Z","type":"end"},{"drive_id":140,"latitude":28.31,"longitude":112.82,"speed":0,"date":"2026-07-11T08:00:00Z","type":"start"},{"drive_id":140,"latitude":999,"longitude":999,"speed":200,"date":"2026-07-11T08:01:00Z","type":"track"}],"original_points":4,"simplified_points":4,"units":{"length":"km","temperature":"C"}}}"#
        return try JSONDecoder.teslamate.decode(DrivingCoordinatesResponse.self, from: Data(json.utf8))
    }
}

private actor DrivingCoordinatesAPIStub: DrivingCoordinatesAPIProviding {
    let result: APIResult<DrivingCoordinatesResponse>
    private(set) var receivedCarID: Int?
    init(result: APIResult<DrivingCoordinatesResponse>) { self.result = result }
    func drivingCoordinates(carId: Int) async -> APIResult<DrivingCoordinatesResponse> {
        receivedCarID = carId
        return result
    }
}
