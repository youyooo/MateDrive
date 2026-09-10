import XCTest
@testable import MateDriveApp

final class DrivingRecordsViewModelTests: XCTestCase {
    func testDecodesMeasured251ExtremeStatistics() throws {
        let response = try Self.fixture()
        let speed = try XCTUnwrap(response.extremes.first { $0.type == "highest_speed" })
        let daily = try XCTUnwrap(response.extremes.first { $0.type == "daily_most_drives" })
        XCTAssertEqual(speed.value, 146)
        XCTAssertEqual(speed.unit, "km/h")
        XCTAssertEqual(speed.driveId, 82)
        XCTAssertEqual(speed.date, "2026-07-05")
        XCTAssertNil(daily.driveId)
        XCTAssertEqual(response.units?.unitOfTemperature, "C")
    }

    @MainActor
    func testViewModelPreservesServerOrderAndMissingValues() async throws {
        let api = DrivingRecordsAPIStub(result: .success(try Self.fixture()))
        let viewModel = DrivingRecordsViewModel(api: api)
        await viewModel.load(carId: 4)
        XCTAssertEqual(viewModel.state.records.map(\.type), ["highest_speed", "daily_most_drives", "most_efficient"])
        XCTAssertNil(viewModel.state.records.last?.value)
        XCTAssertNil(viewModel.state.errorMessage)
        let receivedCarID = await api.receivedCarID
        XCTAssertEqual(receivedCarID, 4)
    }

    @MainActor
    func testFailureDoesNotInventZeroRecords() async {
        let viewModel = DrivingRecordsViewModel(api: DrivingRecordsAPIStub(result: .failure(.network("offline"))))
        await viewModel.load(carId: 1)
        XCTAssertTrue(viewModel.state.records.isEmpty)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    @MainActor
    func testRepeatedEntryRestoresRecordsBeforeFailedRefresh() async throws {
        let cache = VehiclePageStateCache<DrivingRecordsState>()
        let key = VehiclePageCacheKey(serverURL: "https://example.invalid", carId: 4)
        let first = DrivingRecordsViewModel(
            api: DrivingRecordsAPIStub(result: .success(try Self.fixture())),
            cacheKey: key,
            stateCache: cache
        )
        await first.load(carId: 4)

        let reopened = DrivingRecordsViewModel(
            api: DrivingRecordsAPIStub(result: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.records.map(\.type), ["highest_speed", "daily_most_drives", "most_efficient"])

        await reopened.load(carId: 4)

        XCTAssertEqual(reopened.state.records.count, 3)
        XCTAssertNotNil(reopened.state.errorMessage)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertFalse(reopened.state.isRefreshing)
    }

    private static func fixture() throws -> StatsExtremesResponse {
        let json = #"{"extremes":[{"type":"highest_speed","value":146,"unit":"km/h","date":"2026-07-05","drive_id":82},{"type":"daily_most_drives","value":8,"unit":"drives","date":"2026-06-29"},{"type":"most_efficient","unit":"%","date":"2026-06-25","drive_id":7}],"units":{"unit_of_length":"km","unit_of_pressure":"","unit_of_temperature":"C"}}"#
        return try JSONDecoder.teslamate.decode(StatsExtremesResponse.self, from: Data(json.utf8))
    }
}

private actor DrivingRecordsAPIStub: DrivingRecordsAPIProviding {
    let result: APIResult<StatsExtremesResponse>
    private(set) var receivedCarID: Int?
    init(result: APIResult<StatsExtremesResponse>) { self.result = result }
    func statsExtremes(carId: Int) async -> APIResult<StatsExtremesResponse> {
        receivedCarID = carId
        return result
    }
}
