import XCTest
@testable import MateDroidIOS

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

    private func decodePayload(_ json: String) throws -> AchievementsPayload {
        try XCTUnwrap(JSONDecoder.teslamate.decode(AchievementsResponse.self, from: Data(json.utf8)).data)
    }
}

private struct AchievementTestAPI: AchievementsAPIProviding {
    let result: APIResult<AchievementsPayload>
    func achievements(carId _: Int) async -> APIResult<AchievementsPayload> { result }
}
