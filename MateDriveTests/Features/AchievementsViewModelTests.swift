import XCTest
@testable import MateDriveApp

@MainActor
final class AchievementsViewModelTests: XCTestCase {
    func testAchievementsDecodeAndSortUnlockedBeforeHighestProgress() async throws {
        let payload = try decodePayload(#"{"data":{"achievements":[{"id":"urban_archivist","current_value":7,"tiers":[{"tier":1,"threshold":20,"unlocked":false,"progress":0.35}],"visited_places":[{"name":"岳麓区","latitude":28.18,"longitude":112.84,"days":16}]},{"id":"equatorial_navigation","current_value":118704.1,"unit":"km","tiers":[{"tier":1,"threshold":40075,"unlocked":true,"unlocked_at":"2026-06-25T10:11:18Z","unlocked_drive_id":1,"progress":1}]},{"id":"thermal_shock","current_value":14.5,"unit":"°C","tiers":[{"tier":1,"threshold":50,"unlocked":false,"progress":0.29}],"aux_min":24.5,"aux_max":39,"aux_min_drive_id":52,"aux_max_drive_id":136}],"summary":{"total":3,"unlocked":1},"units":{"unit_of_length":"km","unit_of_temperature":"C"}}}"#)
        let viewModel = AchievementsViewModel(api: AchievementTestAPI(result: .success(payload)))

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.achievements.map(\.id), ["equatorial_navigation", "urban_archivist", "thermal_shock"])
        XCTAssertEqual(viewModel.state.summary?.unlocked, 1)
        XCTAssertEqual(viewModel.state.achievements[0].tiers[0].unlockedDriveId, 1)
        XCTAssertEqual(viewModel.state.achievements[1].visitedPlaces?.first?.name, "岳麓区")
        XCTAssertEqual(viewModel.state.achievements[2].auxiliaryMinimum, 24.5)
        XCTAssertEqual(viewModel.state.units?.unitOfLength, "km")
    }

    func testUnknownAchievementUsesLocalizedSafeFallback() {
        let definition = AchievementDefinition.definition(for: "server_internal_code")

        XCTAssertEqual(definition.chineseTitle, "新成就")
        XCTAssertFalse(definition.chineseTitle.contains("server_internal_code"))
        XCTAssertEqual(AchievementDefinition.definition(for: "24h_mosaic").chineseTitle, "全天足迹")
    }

    func testAchievementsRepeatedEntryRestoresRowsAndFailedRefreshPreservesThem() async throws {
        let payload = try decodePayload(#"{"data":{"achievements":[{"id":"equatorial_navigation","current_value":42000,"unit":"km","tiers":[{"tier":1,"threshold":40075,"unlocked":true,"progress":1}]}],"summary":{"total":1,"unlocked":1}}}"#)
        let cache = VehiclePageStateCache<AchievementsState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = AchievementsViewModel(
            api: AchievementTestAPI(result: .success(payload)),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)

        let reopened = AchievementsViewModel(
            api: AchievementTestAPI(result: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.achievements.map(\.id), ["equatorial_navigation"])

        await reopened.load(carId: 1)

        XCTAssertEqual(reopened.state.achievements.map(\.id), ["equatorial_navigation"])
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testAchievementsOverlappingLoadsStartOneRequest() async {
        let api = SlowAchievementTestAPI()
        let viewModel = AchievementsViewModel(api: api)

        async let first: Void = viewModel.load(carId: 1)
        async let second: Void = viewModel.load(carId: 1)
        _ = await (first, second)

        let requestCount = await api.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testAchievementsCacheSuccessfulEmptyResult() async throws {
        let payload = try decodePayload(
            #"{"data":{"achievements":[],"summary":{"total":0,"unlocked":0}}}"#
        )
        let cache = VehiclePageStateCache<AchievementsState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = AchievementsViewModel(
            api: AchievementTestAPI(result: .success(payload)),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)

        let reopened = AchievementsViewModel(
            api: AchievementTestAPI(result: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertTrue(reopened.state.achievements.isEmpty)
    }

    private func decodePayload(_ json: String) throws -> AchievementsPayload {
        try XCTUnwrap(JSONDecoder.teslamate.decode(AchievementsResponse.self, from: Data(json.utf8)).data)
    }
}

private struct AchievementTestAPI: AchievementsAPIProviding {
    let result: APIResult<AchievementsPayload>
    func achievements(carId _: Int) async -> APIResult<AchievementsPayload> { result }
}

private actor SlowAchievementTestAPI: AchievementsAPIProviding {
    private var requests = 0

    var requestCount: Int {
        requests
    }

    func achievements(carId _: Int) async -> APIResult<AchievementsPayload> {
        requests += 1
        try? await Task.sleep(for: .milliseconds(100))
        let data = Data(#"{"data":{"achievements":[],"summary":{"total":0,"unlocked":0}}}"#.utf8)
        guard let payload = try? JSONDecoder.teslamate.decode(
            AchievementsResponse.self,
            from: data
        ).data else {
            return .failure(.invalidResponse("fixture"))
        }
        return .success(payload)
    }
}
