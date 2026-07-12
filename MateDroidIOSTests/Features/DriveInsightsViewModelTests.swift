import XCTest
@testable import MateDroidIOS

@MainActor
final class DriveInsightsViewModelTests: XCTestCase {
    func testLoadsServerRoutesMatchesOnlyVerifiableLatestDriveAndKeepsEvaluations() async throws {
        let insights = try JSONDecoder.teslamate.decode(
            TeslaMateDriveInsightsResponse.self,
            from: #"{"data":{"drive_stats":[{"start_latitude":1,"start_longitude":2,"end_latitude":3,"end_longitude":4,"start_address":"Home","end_address":"Work","drive_count":7,"avg_distance_km":16,"avg_duration_min":28,"avg_energy_kwh":-3,"consumption_wh_km":186,"last_drive_date":"2026-07-09T23:24:17.553Z"},{"start_latitude":5,"start_longitude":6,"end_latitude":7,"end_longitude":8,"start_address":"A","end_address":"B","drive_count":1,"last_drive_date":"2026-01-01T00:00:00Z"}]}}"#.data(using: .utf8)!
        ).data!
        let activities = try JSONDecoder.teslamate.decode(
            TeslaMateActivitiesResponse.self,
            from: #"{"data":[{"id":135,"type":"drive","startDate":"2026-07-09T23:24:17.553Z","stats":{"evaluations":[{"type":"golden_foot","priority":3,"titleKey":"drive_eval_golden_foot_title"}]}}]}"#.data(using: .utf8)!
        )
        let api = DriveInsightsTestAPI(
            insights: .success(insights),
            activities: .success(activities),
            drives: [.init(driveId: 135, startDate: "2026-07-09T23:24:17.553Z")]
        )
        let viewModel = DriveInsightsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.routes.map(\.insight.driveCount), [7, 1])
        XCTAssertEqual(viewModel.state.routes[0].latestDriveId, 135)
        XCTAssertNil(viewModel.state.routes[1].latestDriveId)
        XCTAssertEqual(viewModel.visibleRoutes.count, 1)
        XCTAssertEqual(viewModel.state.evaluations.first?.driveId, 135)
        XCTAssertEqual(viewModel.state.evaluations.first?.evaluation.type, "golden_foot")

        viewModel.setFilter(.all)
        XCTAssertEqual(viewModel.visibleRoutes.count, 2)
    }
}

private struct DriveInsightsTestAPI: DriveInsightsAPIProviding {
    let insights: APIResult<TeslaMateDriveInsightsData>
    let activitiesResult: APIResult<TeslaMateActivitiesResponse>
    let driveValues: [DriveData]

    init(insights: APIResult<TeslaMateDriveInsightsData>, activities: APIResult<TeslaMateActivitiesResponse>, drives: [DriveData]) {
        self.insights = insights
        activitiesResult = activities
        driveValues = drives
    }

    func driveInsights(carId _: Int) async -> APIResult<TeslaMateDriveInsightsData> { insights }
    func activities(carId _: Int, page _: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> { activitiesResult }
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> { .success(driveValues) }
}
