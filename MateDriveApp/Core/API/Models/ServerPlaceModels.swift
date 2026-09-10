import Foundation

public struct ServerPlacesResponse: Decodable, Equatable, Sendable {
    public let data: [ServerPlace]
    public let pagination: TeslaMatePagination?
    public let units: TeslaMateServerStatsUnits?
}

public struct ServerPlace: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let displayName: String?
    public let latitude: Double?
    public let longitude: Double?
    public let radiusMeters: Double?
    public let primaryKind: String?
    public let role: String?
    public let roleConfidence: String?
    public let roleGroup: String?
    public let visitCount: Int?
    public let activeDays: Int?
    public let driveStartCount: Int?
    public let driveEndCount: Int?
    public let chargeCount: Int?
    public let parkCount: Int?
    public let firstSeen: String?
    public let lastSeen: String?
    public let totalDriveDistanceKm: Double?
    public let totalDriveDurationMin: Double?
    public let totalChargeKwh: Double?
    public let totalChargeCost: Double?
    public let missingChargeCostCount: Int?
    public let totalParkingDurationMin: Double?
    public let longestParkingDurationMin: Double?
    public let parkingRangeLossKm: Double?
    public let hasDriving: Bool?
    public let hasCharging: Bool?
    public let hasParking: Bool?
}
