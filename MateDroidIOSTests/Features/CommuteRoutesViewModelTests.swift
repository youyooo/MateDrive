import XCTest
@testable import MateDroidIOS

final class CommuteRoutesViewModelTests: XCTestCase {
    func testDecodesMeasured251CommuteRoutePayload() throws {
        let response = try Self.fixture()
        let route = try XCTUnwrap(response.routes.first { $0.id == 1 })

        XCTAssertEqual(response.summary?.totalCommuteDrives, 28)
        XCTAssertEqual(route.tripCount, 11)
        XCTAssertEqual(try XCTUnwrap(route.averageDurationMinutes), 7.2727, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averageRegenCaptureRate), 0.9416, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averagePercentSpeed40To80), 0.3431, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averagePercentSpeed0To20), 0.4672, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averagePercentSpeed20To40), 0.1711, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averagePercentSpeed80To120), 0.0185, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averagePercentSpeed120Plus), 0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(route.averageHardBrakingPer100Km), 1.828, accuracy: 0.001)
        XCTAssertEqual(response.units?.unitOfLength, "km")
    }

    @MainActor
    func testViewModelSortsRoutesByObservedTripCount() async throws {
        let api = CommuteRoutesAPIStub(result: .success(try Self.fixture()))
        let viewModel = CommuteRoutesViewModel(api: api)

        await viewModel.load(carId: 9)

        XCTAssertEqual(viewModel.state.routes.map(\.id), [1, 2])
        XCTAssertEqual(viewModel.state.summary?.totalCommuteRoutes, 2)
        XCTAssertNil(viewModel.state.errorMessage)
        let receivedCarID = await api.receivedCarID
        XCTAssertEqual(receivedCarID, 9)
    }

    @MainActor
    func testFailureDoesNotReplaceMissingRoutesWithZeros() async {
        let viewModel = CommuteRoutesViewModel(api: CommuteRoutesAPIStub(result: .failure(.network("offline"))))

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.routes.isEmpty)
        XCTAssertNil(viewModel.state.summary)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    private static func fixture() throws -> CommuteRoutesResponse {
        let json = #"{"routes":[{"id":2,"startLatitude":28.31,"startLongitude":112.82,"endLatitude":28.20,"endLongitude":112.85,"tripCount":7,"avgDurationMin":20,"totalDistanceKm":142.1},{"id":1,"startLatitude":28.20,"startLongitude":112.85,"endLatitude":28.31,"endLongitude":112.82,"startAddress":"","endAddress":"","tripCount":11,"smartCommuteCount":1,"avgDurationMin":7.2727,"minDurationMin":1,"maxDurationMin":42,"totalDistanceKm":109.4,"avgRegenCaptureRate":0.9416,"totalHardBrakingCount":2,"avgHardBrakingPer100km":1.828,"totalElevationGain":719,"totalElevationLoss":782,"avgPctSpeed0_20":0.4672,"avgPctSpeed20_40":0.1711,"avgPctSpeed40_80":0.3431,"avgPctSpeed80_120":0.0185,"avgPctSpeed120Plus":0}],"summary":{"totalCommuteRoutes":2,"totalCommuteDrives":28,"totalSmartCommutes":2},"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#
        return try JSONDecoder.teslamate.decode(CommuteRoutesResponse.self, from: Data(json.utf8))
    }
}

private actor CommuteRoutesAPIStub: CommuteRoutesAPIProviding {
    let result: APIResult<CommuteRoutesResponse>
    private(set) var receivedCarID: Int?
    init(result: APIResult<CommuteRoutesResponse>) { self.result = result }
    func commuteRoutes(carId: Int) async -> APIResult<CommuteRoutesResponse> {
        receivedCarID = carId
        return result
    }
}
