import XCTest
@testable import MateDroidIOS

final class EnvironmentHistoryViewModelTests: XCTestCase {
    func testEnvironmentHistoryDecodesMeasured251Payload() throws {
        let response = try Self.fixture()

        XCTAssertEqual(response.data.series.count, 1)
        XCTAssertEqual(response.data.series[0].tpmsPressureFl, 2.9)
        XCTAssertEqual(response.data.series[0].outsideTemp, 28.45)
        XCTAssertEqual(response.data.series[0].samplePolicy, "day_drive_median")
        XCTAssertNotNil(response.data.series[0].timestamp)
        XCTAssertEqual(response.data.summary?.lowestPressure?.wheel, "rear_right")
        XCTAssertEqual(response.data.temperatureEnergyBuckets.first?.medianConsumptionWhPerUnit, 187.81)
        XCTAssertEqual(response.data.leakObservations.first?.confidence, "medium")
        XCTAssertEqual(response.data.metadata?.minSamples, 3)
        XCTAssertEqual(response.units?.unitOfPressure, "bar")
    }

    func testEnvironmentChartSelectionSnapsToNearestDatedPoint() throws {
        let response = try Self.fixture()
        let point = try XCTUnwrap(response.data.series.first)
        let date = try XCTUnwrap(point.timestamp)

        XCTAssertEqual(EnvironmentChartSelection.nearest(to: date.addingTimeInterval(60), in: response.data.series), point)
        XCTAssertNil(EnvironmentChartSelection.nearest(to: date, in: []))
    }

    @MainActor
    func testViewModelUsesRangeSpecificGrainAndOmitsUndatedPoints() async throws {
        let api = EnvironmentHistoryAPIStub(result: .success(try Self.fixture(includesUndatedPoint: true)))
        let viewModel = EnvironmentHistoryViewModel(api: api)

        await viewModel.load(carId: 7)
        await viewModel.select(.sevenDays, carId: 7)

        XCTAssertEqual(viewModel.datedPoints.count, 1)
        XCTAssertEqual(viewModel.state.range, .sevenDays)
        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertNil(viewModel.state.errorMessage)
        let calls = await api.calls
        XCTAssertEqual(calls, [
            EnvironmentHistoryAPICall(carId: 7, range: "30d", grain: "day"),
            EnvironmentHistoryAPICall(carId: 7, range: "7d", grain: "hour")
        ])
    }

    @MainActor
    func testViewModelKeepsLastResponseVisibleWhenRefreshFails() async throws {
        let api = EnvironmentHistoryAPIStub(result: .success(try Self.fixture()))
        let viewModel = EnvironmentHistoryViewModel(api: api)
        await viewModel.load(carId: 1)
        await api.setResult(.failure(.network("offline")))

        await viewModel.load(carId: 1)

        XCTAssertNotNil(viewModel.state.response)
        XCTAssertNotNil(viewModel.state.errorMessage)
        XCTAssertFalse(viewModel.state.isLoading)
    }

    @MainActor
    func testFailedRangeChangeKeepsPreviousRangeAndDataMeaning() async throws {
        let api = EnvironmentHistoryAPIStub(result: .success(try Self.fixture()))
        let viewModel = EnvironmentHistoryViewModel(api: api)
        await viewModel.load(carId: 1)
        await api.setResult(.failure(.network("offline")))

        await viewModel.select(.sevenDays, carId: 1)

        XCTAssertEqual(viewModel.state.range, .thirtyDays)
        XCTAssertNotNil(viewModel.state.response)
        XCTAssertNotNil(viewModel.state.errorMessage)
    }

    private static func fixture(includesUndatedPoint: Bool = false) throws -> EnvironmentHistoryResponse {
        let undated = includesUndatedPoint ? #",{"tpms_pressure_fl":0,"sample_count":0}"# : ""
        let json = #"{"data":{"series":[{"date_from":1782316800000,"date_to":1782403200000,"date":"2026-06-25T00:00:00","tpms_pressure_fl":2.9,"tpms_pressure_fr":2.8,"tpms_pressure_rl":2.8,"tpms_pressure_rr":2.7,"tire_pressure_gap":0.1,"outside_temp":28.45,"inside_temp":21.06,"consumption_wh_per_unit":116.06,"sample_count":5,"sample_policy":"day_drive_median"}"# + undated + #"],"summary":{"point_count":1,"sample_count":5,"lowest_pressure":{"type":"lowest_pressure","value":2.7,"unit":"bar","wheel":"rear_right","date_from":1782316800000},"average_pressure_gap":0.1,"average_outside_temp":28.45},"temperature_energy_buckets":[{"temperature_from":24,"temperature_to":26,"median_consumption_wh_per_unit":187.81,"average_consumption_wh_per_unit":170.2,"drive_count":3,"distance":27.44}],"leak_observations":[{"wheel":"rear_right","earlier_median":2.9,"later_median":2.7,"delta":-0.2,"earlier_sample_count":6,"later_sample_count":3,"confidence":"medium"}],"metadata":{"requested_grain":"day","resolved_grain":"day","sample_policy":"day_drive_median","start_date":"2026-06-12T00:00:00Z","end_date":"2026-07-11T00:00:00Z","timezone":"Asia/Shanghai","min_samples":3}},"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#
        return try JSONDecoder.teslamate.decode(EnvironmentHistoryResponse.self, from: Data(json.utf8))
    }
}

private struct EnvironmentHistoryAPICall: Equatable, Sendable {
    let carId: Int
    let range: String
    let grain: String
}

private actor EnvironmentHistoryAPIStub: EnvironmentHistoryAPIProviding {
    private var result: APIResult<EnvironmentHistoryResponse>
    private(set) var calls: [EnvironmentHistoryAPICall] = []

    init(result: APIResult<EnvironmentHistoryResponse>) { self.result = result }

    func setResult(_ result: APIResult<EnvironmentHistoryResponse>) { self.result = result }

    func environmentHistory(carId: Int, range: String, grain: String) async -> APIResult<EnvironmentHistoryResponse> {
        calls.append(EnvironmentHistoryAPICall(carId: carId, range: range, grain: grain))
        return result
    }
}
