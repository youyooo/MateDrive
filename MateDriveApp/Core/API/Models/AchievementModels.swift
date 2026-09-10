import Foundation

public struct AchievementsResponse: Decodable, Equatable, Sendable {
    public let data: AchievementsPayload?
    public let error: String?
}

public struct AchievementsPayload: Decodable, Equatable, Sendable {
    public let achievements: [TeslaMateAchievement]
    public let summary: AchievementSummary?
    public let units: Units?
}

public struct AchievementSummary: Decodable, Equatable, Sendable {
    public let total: Int?
    public let unlocked: Int?
}

public struct TeslaMateAchievement: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let currentValue: Double?
    public let unit: String?
    public let tiers: [AchievementTier]
    public let missingHours: [Int]?
    public let visitedPlaces: [AchievementPlace]?
    public let auxiliaryMinimum: Double?
    public let auxiliaryMaximum: Double?
    public let auxiliaryMinimumDriveId: Int?
    public let auxiliaryMaximumDriveId: Int?

    private enum CodingKeys: String, CodingKey {
        case id, currentValue, unit, tiers, missingHours, visitedPlaces
        case auxiliaryMinimum = "auxMin"
        case auxiliaryMaximum = "auxMax"
        case auxiliaryMinimumDriveId = "auxMinDriveId"
        case auxiliaryMaximumDriveId = "auxMaxDriveId"
    }
}

public struct AchievementTier: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int { tier }
    public let tier: Int
    public let threshold: Double?
    public let unlocked: Bool
    public let unlockedAt: String?
    public let unlockedDriveId: Int?
    public let progress: Double?
}

public struct AchievementPlace: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(name)-\(latitude ?? 0)-\(longitude ?? 0)" }
    public let name: String
    public let latitude: Double?
    public let longitude: Double?
    public let days: Double?
}
