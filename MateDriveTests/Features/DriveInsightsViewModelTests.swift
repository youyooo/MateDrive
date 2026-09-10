import XCTest
@testable import MateDriveApp

@MainActor
final class DriveInsightsViewModelTests: XCTestCase {
    func testDrivingScoreUsesOnlyRecordedMetricsAndNormalizesRegenPercentages() async throws {
        let activities = try JSONDecoder.teslamate.decode(
            TeslaMateActivitiesResponse.self,
            from: #"{"data":[{"id":1,"type":"drive","distance_km":40,"stats":{"hard_braking_per_100km":0,"regen_utilization":0.8,"tire_pressure_gap_bar":0.1}},{"id":2,"type":"drive","distance_km":50,"stats":{"hard_braking_per_100km":2,"regen_utilization":60,"is_regen_limited":true,"avg_outside_temp":3,"tire_pressure_gap_bar":0.3}},{"id":3,"type":"drive","distance_km":20,"stats":{}}]}"#.data(using: .utf8)!
        )
        let api = DriveInsightsTestAPI(
            insights: .success(try emptyInsights()),
            activities: .success(activities),
            drives: []
        )
        let viewModel = DriveInsightsViewModel(api: api)

        await viewModel.load(carId: 1)

        let score = try XCTUnwrap(viewModel.state.drivingScore)
        XCTAssertEqual(score.overall, 79)
        XCTAssertEqual(score.confidence, 51)
        XCTAssertEqual(score.totalDriveCount, 3)
        XCTAssertEqual(score.components.map(\.kind), [.safety, .regeneration])
        XCTAssertEqual(score.components[0].score, 85)
        XCTAssertEqual(score.components[0].observedDriveCount, 2)
        XCTAssertEqual(score.components[1].score, 70)
        XCTAssertEqual(score.components[1].observedDriveCount, 2)
        XCTAssertTrue(score.recommendations.contains(.smootherBraking))
        XCTAssertTrue(score.recommendations.contains(.increaseRegeneration))
        XCTAssertTrue(score.recommendations.contains(.preconditionBattery))
        XCTAssertTrue(score.recommendations.contains(.checkTirePressure))
        XCTAssertTrue(score.recommendations.contains(.improveCoverage))
    }

    func testDrivingScoreIsUnavailableWhenEveryMetricIsMissing() async throws {
        let activities = try JSONDecoder.teslamate.decode(
            TeslaMateActivitiesResponse.self,
            from: #"{"data":[{"id":1,"type":"drive","stats":{}},{"id":2,"type":"park","stats":{}}]}"#.data(using: .utf8)!
        )
        let api = DriveInsightsTestAPI(
            insights: .success(try emptyInsights()),
            activities: .success(activities),
            drives: []
        )
        let viewModel = DriveInsightsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertNil(viewModel.state.drivingScore)
    }

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

    func testUsesLocalDriveHistoryForLatestRouteMatch() async throws {
        let insights = try JSONDecoder.teslamate.decode(
            TeslaMateDriveInsightsResponse.self,
            from: #"{"data":{"drive_stats":[{"start_address":"Home","end_address":"Work","drive_count":4,"last_drive_date":"2026-07-09T23:24:17.553Z"}]}}"#.data(using: .utf8)!
        ).data!
        let api = DriveInsightsTestAPI(
            insights: .success(insights),
            activities: .success(try JSONDecoder.teslamate.decode(
                TeslaMateActivitiesResponse.self,
                from: #"{"data":[]}"#.data(using: .utf8)!
            )),
            drives: [.init(driveId: 999, startDate: "2026-07-09T23:24:17.553Z")]
        )
        let viewModel = DriveInsightsViewModel(
            api: api,
            historyProvider: DriveInsightsHistoryProvider(
                drives: [.init(driveId: 135, startDate: "2026-07-09T23:24:17.553Z")]
            )
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.routes.first?.latestDriveId, 135)
    }

    func testRepeatedEntryRestoresInsightsBeforeFailedRefresh() async throws {
        let insights = try JSONDecoder.teslamate.decode(
            TeslaMateDriveInsightsResponse.self,
            from: #"{"data":{"drive_stats":[{"start_address":"Home","end_address":"Work","drive_count":4}]}}"#.data(using: .utf8)!
        ).data!
        let activities = try JSONDecoder.teslamate.decode(
            TeslaMateActivitiesResponse.self,
            from: #"{"data":[]}"#.data(using: .utf8)!
        )
        let cache = VehiclePageStateCache<DriveInsightsState>()
        let key = VehiclePageCacheKey(serverURL: "https://example.invalid", carId: 1)
        let first = DriveInsightsViewModel(
            api: DriveInsightsTestAPI(
                insights: .success(insights),
                activities: .success(activities),
                drives: []
            ),
            cacheKey: key,
            stateCache: cache
        )
        await first.load(carId: 1)

        let reopened = DriveInsightsViewModel(
            api: DriveInsightsTestAPI(
                insights: .failure(.network("offline")),
                activities: .failure(.network("offline")),
                drives: []
            ),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.routes.count, 1)

        await reopened.load(carId: 1)

        XCTAssertEqual(reopened.state.routes.count, 1)
        XCTAssertNotNil(reopened.state.errorMessage)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertFalse(reopened.state.isRefreshing)
    }

    private func emptyInsights() throws -> TeslaMateDriveInsightsData {
        try XCTUnwrap(JSONDecoder.teslamate.decode(
            TeslaMateDriveInsightsResponse.self,
            from: #"{"data":{"drive_stats":[]}}"#.data(using: .utf8)!
        ).data)
    }
}

private struct DriveInsightsHistoryProvider: MileageDataProviding {
    let drives: [DriveData]

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> { .success(drives) }
    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> { .success([]) }
    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> { .success(.metric) }
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
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        (page ?? 1) == 1 ? .success(driveValues) : .success([])
    }
}
