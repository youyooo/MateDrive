import XCTest
@testable import MateDroidIOS

final class TopDrainLocationsViewModelTests: XCTestCase {
    func testTopDrainLocationsDecodeMeasured251Payload() throws {
        let response = try Self.fixture()
        let location = try XCTUnwrap(response.locations.first)

        XCTAssertEqual(location.totalRangeLossKm, 38.17)
        XCTAssertEqual(location.averageDrainPercent24H, 6.87)
        XCTAssertEqual(location.averageDrainRateKmH, 1.49)
        XCTAssertEqual(location.parkingCount, 12)
        XCTAssertEqual(location.totalDurationMin, 7_236.6)
        XCTAssertEqual(response.units?.unitOfLength, "km")
    }

    @MainActor
    func testViewModelFiltersInvalidCoordinatesAndSortsByRangeLoss() async throws {
        let api = TopDrainLocationsAPIStub(result: .success(try Self.fixture(includesInvalid: true)))
        let viewModel = TopDrainLocationsViewModel(api: api)

        await viewModel.load(carId: 7)

        XCTAssertEqual(viewModel.state.locations.compactMap(\.totalRangeLossKm), [276.75, 38.17])
        XCTAssertNil(viewModel.state.errorMessage)
        XCTAssertFalse(viewModel.state.isLoading)
        let receivedCarID = await api.receivedCarID
        XCTAssertEqual(receivedCarID, 7)
    }

    @MainActor
    func testFailureDoesNotInventHotspotRows() async {
        let api = TopDrainLocationsAPIStub(result: .failure(.network("offline")))
        let viewModel = TopDrainLocationsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.locations.isEmpty)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    private static func fixture(includesInvalid: Bool = false) throws -> TopDrainLocationsResponse {
        let invalid = includesInvalid ? #",{"latitude":999,"longitude":999,"totalRangeLossKm":999}"# : ""
        let second = includesInvalid ? #",{"address":"","latitude":28.2076,"longitude":112.8577,"totalRangeLossKm":276.75,"avgDrainRatePct24h":-7.48,"avgDrainRateKmH":1.44,"parkingCount":24,"totalDurationMin":11503}"# : ""
        let json = #"{"locations":[{"address":"","latitude":28.3116,"longitude":112.822,"totalRangeLossKm":38.17,"avgDrainRatePct24h":6.87,"avgDrainRateKmH":1.49,"parkingCount":12,"totalDurationMin":7236.6}"# + second + invalid + #"],"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#
        return try JSONDecoder.teslamate.decode(TopDrainLocationsResponse.self, from: Data(json.utf8))
    }
}

private actor TopDrainLocationsAPIStub: TopDrainLocationsAPIProviding {
    let result: APIResult<TopDrainLocationsResponse>
    private(set) var receivedCarID: Int?
    init(result: APIResult<TopDrainLocationsResponse>) { self.result = result }
    func topDrainLocations(carId: Int) async -> APIResult<TopDrainLocationsResponse> {
        receivedCarID = carId
        return result
    }
}
