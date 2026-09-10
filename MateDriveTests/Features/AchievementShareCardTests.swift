import SwiftUI
import XCTest
@testable import MateDriveApp

@MainActor
final class AchievementShareCardTests: XCTestCase {
    func testDefaultCardHidesDatesPlacesDetailsCoordinatesAndDriveIdentifiers() throws {
        let content = AchievementShareCardBuilder.content(
            achievement: try achievementFixture(),
            units: .metric,
            language: .chinese,
            options: AchievementShareCardOptions()
        )

        XCTAssertEqual(content.reportTitle, "成就卡片")
        XCTAssertEqual(content.achievementTitle, "城市档案员")
        XCTAssertNil(content.placeNamesText)
        XCTAssertTrue(content.detailLines.isEmpty)
        XCTAssertTrue(content.tiers.allSatisfy { $0.unlockDateText == nil })
        XCTAssertFalse(content.optionsIncludeSensitiveDetails)
        XCTAssertNotNil(content.hiddenDetailsLabel)
        let description = String(describing: content)
        XCTAssertFalse(description.contains("岳麓区"))
        XCTAssertFalse(description.contains("2026-06-25"))
        XCTAssertFalse(description.contains("12.345678"))
        XCTAssertFalse(description.contains("34.876543"))
        XCTAssertFalse(description.contains("136"))
    }

    func testSelectedSensitiveDetailsIncludeNamesAndReadableDetailsButNeverCoordinatesOrDriveIDs() throws {
        let content = AchievementShareCardBuilder.content(
            achievement: try achievementFixture(),
            units: .metric,
            language: .english,
            options: AchievementShareCardOptions(
                includesUnlockDates: true,
                includesPlaceNames: true,
                includesProgressDetails: true
            )
        )

        XCTAssertEqual(content.placeNamesText, "Yuelu District")
        XCTAssertFalse(content.detailLines.isEmpty)
        XCTAssertNotNil(content.tiers.first?.unlockDateText)
        XCTAssertTrue(content.optionsIncludeSensitiveDetails)
        XCTAssertNil(content.hiddenDetailsLabel)
        let description = String(describing: content)
        XCTAssertFalse(description.contains("12.345678"))
        XCTAssertFalse(description.contains("34.876543"))
        XCTAssertFalse(description.contains("136"))
    }

    func testMissingValuesRemainUnavailableInsteadOfBecomingZero() throws {
        let content = AchievementShareCardBuilder.content(
            achievement: try decodeAchievement(#"{"id":"equatorial_navigation","current_value":null,"unit":"km","tiers":[{"tier":1,"threshold":null,"unlocked":false,"progress":null}]}"#),
            units: .metric,
            language: .english,
            options: AchievementShareCardOptions()
        )

        XCTAssertEqual(content.currentValueText, "--")
        XCTAssertEqual(content.goalText, "--")
        XCTAssertEqual(content.progressText, "--")
        XCTAssertFalse(String(describing: content).contains("0 km"))
        XCTAssertFalse(String(describing: content).contains("0%"))
    }

    func testUnknownServerIdentifierUsesSafeLocalizedDefinition() throws {
        let content = AchievementShareCardBuilder.content(
            achievement: try decodeAchievement(#"{"id":"private_server_code","current_value":2,"tiers":[]}"#),
            units: .metric,
            language: .chinese,
            options: AchievementShareCardOptions()
        )

        XCTAssertEqual(content.achievementTitle, "新成就")
        XCTAssertFalse(String(describing: content).contains("private_server_code"))
    }

    func testAchievementCardRendersAsHighResolutionNonblankImage() throws {
        let content = AchievementShareCardBuilder.content(
            achievement: try achievementFixture(),
            units: .metric,
            language: .chinese,
            options: AchievementShareCardOptions()
        )
        let renderer = ImageRenderer(content: AchievementShareCardView(content: content))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1350)
        XCTAssertTrue(imageHasVisibleVariation(cgImage))

        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Achievement Card"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAchievementCardProgressBarsDoNotRenderWarningArtifacts() throws {
        let content = AchievementShareCardBuilder.content(
            achievement: try achievementFixture(),
            units: .metric,
            language: .chinese,
            options: AchievementShareCardOptions()
        )
        let renderer = ImageRenderer(content: AchievementShareCardView(content: content))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(redDominantPixelCount(in: cgImage), 0)
    }

    private func achievementFixture() throws -> TeslaMateAchievement {
        let point = SyntheticCoordinates.point(latitudeOffset: 0.345678, longitudeOffset: 0.876543)
        return try decodeAchievement("""
        {"id":"urban_archivist","current_value":7,"tiers":[{"tier":1,"threshold":5,"unlocked":true,"unlocked_at":"2026-06-25T10:11:18Z","unlocked_drive_id":136,"progress":1},{"tier":2,"threshold":20,"unlocked":false,"progress":0.35}],"visited_places":[{"name":"Yuelu District","latitude":\(point.latitude),"longitude":\(point.longitude),"days":16}],"missing_hours":[2,3],"aux_min":24.5,"aux_max":39,"aux_min_drive_id":52,"aux_max_drive_id":136}
        """)
    }

    private func decodeAchievement(_ json: String) throws -> TeslaMateAchievement {
        try JSONDecoder.teslamate.decode(TeslaMateAchievement.self, from: Data(json.utf8))
    }

    private func imageHasVisibleVariation(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel >= 32
        else { return false }

        let bytesPerPixel = image.bitsPerPixel / 8
        var sampledColors = Set<UInt32>()
        let xStep = max(image.width / 20, 1)
        let yStep = max(image.height / 20, 1)
        for y in stride(from: 0, to: image.height, by: yStep) {
            for x in stride(from: 0, to: image.width, by: xStep) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                sampledColors.insert(
                    UInt32(bytes[offset]) << 24
                        | UInt32(bytes[offset + 1]) << 16
                        | UInt32(bytes[offset + 2]) << 8
                        | UInt32(bytes[offset + 3])
                )
            }
        }
        return sampledColors.count >= 4
    }

    private func redDominantPixelCount(in image: CGImage) -> Int {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel >= 32
        else { return .max }

        let bytesPerPixel = image.bitsPerPixel / 8
        var count = 0
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                let red = Int(bytes[offset])
                let green = Int(bytes[offset + 1])
                let blue = Int(bytes[offset + 2])
                if red > 150, red * 4 > green * 5, red * 3 > blue * 5 {
                    count += 1
                }
            }
        }
        return count
    }
}
