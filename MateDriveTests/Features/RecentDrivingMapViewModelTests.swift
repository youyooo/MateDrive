import XCTest
@testable import MateDriveApp

final class RecentDrivingMapViewModelTests: XCTestCase {
    func testListMapToolbarModeOffersOneButtonForTheOppositeView() {
        XCTAssertEqual(ListMapViewMode.map.toggleDestination, .list)
        XCTAssertEqual(ListMapViewMode.map.toolbarSystemImage, "list.bullet")
        XCTAssertEqual(ListMapViewMode.list.toggleDestination, .map)
        XCTAssertEqual(ListMapViewMode.list.toolbarSystemImage, "map")
    }

    func testDecodesMeasured251CoordinatePayload() throws {
        let response = try Self.fixture()
        let point = try XCTUnwrap(response.data.coordinates.first)
        XCTAssertEqual(response.data.originalPoints, 5)
        XCTAssertEqual(response.data.simplifiedPoints, 5)
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
        XCTAssertEqual(viewModel.state.invalidPointCount, 2)
        XCTAssertEqual(viewModel.state.originalPointCount, 5)
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

    @MainActor
    func testRepeatedEntryRestoresRoutesBeforeFailedRefresh() async throws {
        let cache = VehiclePageStateCache<RecentDrivingMapState>()
        let key = VehiclePageCacheKey(serverURL: "https://example.invalid", carId: 6)
        let first = RecentDrivingMapViewModel(
            api: DrivingCoordinatesAPIStub(result: .success(try Self.fixture())),
            cacheKey: key,
            stateCache: cache
        )
        await first.load(carId: 6)

        let reopened = RecentDrivingMapViewModel(
            api: DrivingCoordinatesAPIStub(result: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.routes.map(\.id), [140, 139])

        await reopened.load(carId: 6)

        XCTAssertEqual(reopened.state.routes.map(\.id), [140, 139])
        XCTAssertNotNil(reopened.state.errorMessage)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertFalse(reopened.state.isRefreshing)
    }

    @MainActor
    func testConcurrentLoadsShareOneRefresh() async throws {
        let api = DrivingCoordinatesAPIStub(
            result: .success(try Self.fixture()),
            delayNanoseconds: 50_000_000
        )
        let viewModel = RecentDrivingMapViewModel(api: api)

        async let first: Void = viewModel.load(carId: 6)
        async let second: Void = viewModel.load(carId: 6)
        _ = await (first, second)

        let callCount = await api.callCount
        XCTAssertEqual(callCount, 1)
    }

    private static func fixture() throws -> DrivingCoordinatesResponse {
        let json = #"{"data":{"car_id":1,"coordinates":[{"drive_id":139,"latitude":28.207473,"longitude":112.857734,"speed":3,"elevation":0,"outside_temp":28.5,"date":"2026-07-10T23:40:59Z","type":"track"},{"drive_id":139,"latitude":28.2076,"longitude":112.858,"speed":18,"date":"2026-07-10T23:41:19Z","type":"end"},{"drive_id":140,"latitude":28.31,"longitude":112.82,"speed":0,"date":"2026-07-11T08:00:00Z","type":"start"},{"latitude":28.32,"longitude":112.83,"speed":1,"date":"2026-07-11T08:00:30Z","type":"track"},{"drive_id":140,"latitude":999,"longitude":999,"speed":200,"date":"2026-07-11T08:01:00Z","type":"track"}],"original_points":5,"simplified_points":5,"units":{"length":"km","temperature":"C"}}}"#
        return try JSONDecoder.teslamate.decode(DrivingCoordinatesResponse.self, from: Data(json.utf8))
    }
}

private actor DrivingCoordinatesAPIStub: DrivingCoordinatesAPIProviding {
    let result: APIResult<DrivingCoordinatesResponse>
    let delayNanoseconds: UInt64
    private(set) var receivedCarID: Int?
    private(set) var callCount = 0
    init(
        result: APIResult<DrivingCoordinatesResponse>,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }
    func drivingCoordinates(carId: Int) async -> APIResult<DrivingCoordinatesResponse> {
        callCount += 1
        receivedCarID = carId
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return result
    }
}
