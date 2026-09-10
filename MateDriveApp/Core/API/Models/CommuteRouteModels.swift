import Foundation

public struct CommuteRoutesResponse: Decodable, Equatable, Sendable {
    public let routes: [CommuteRoute]
    public let summary: CommuteRoutesSummary?
    public let units: TeslaMateServerStatsUnits?
}

public struct CommuteRoutesSummary: Decodable, Equatable, Sendable {
    public let totalCommuteRoutes: Int?
    public let totalCommuteDrives: Int?
    public let totalSmartCommutes: Int?
    public let safetyDistanceCount: Int?
    public let lowTempRegenCount: Int?
    public let goldenFootCount: Int?
    public let rushHourComfortCount: Int?
    public let elevationInsightCount: Int?
    public let shortTripHVACCount: Int?
}

public struct CommuteRoute: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let startLatitude: Double?
    public let startLongitude: Double?
    public let endLatitude: Double?
    public let endLongitude: Double?
    public let startAddress: String?
    public let endAddress: String?
    public let tripCount: Int?
    public let smartCommuteCount: Int?
    public let averageDurationMinutes: Double?
    public let minimumDurationMinutes: Double?
    public let maximumDurationMinutes: Double?
    public let totalDistanceKm: Double?
    public let averageRegenCaptureRate: Double?
    public let totalHardBrakingCount: Int?
    public let averageHardBrakingPer100Km: Double?
    public let totalElevationGain: Double?
    public let totalElevationLoss: Double?
    public let averagePercentSpeed0To20: Double?
    public let averagePercentSpeed20To40: Double?
    public let averagePercentSpeed40To80: Double?
    public let averagePercentSpeed80To120: Double?
    public let averagePercentSpeed120Plus: Double?

    private enum CodingKeys: String, CodingKey {
        case id, startLatitude, startLongitude, endLatitude, endLongitude
        case startAddress, endAddress, tripCount, smartCommuteCount, totalDistanceKm
        case totalHardBrakingCount, totalElevationGain, totalElevationLoss
        case averageDurationMinutes = "avgDurationMin"
        case minimumDurationMinutes = "minDurationMin"
        case maximumDurationMinutes = "maxDurationMin"
        case averageRegenCaptureRate = "avgRegenCaptureRate"
        case averageHardBrakingPer100Km = "avgHardBrakingPer100km"
        case averagePercentSpeed0To20 = "avgpctspeed020"
        case averagePercentSpeed20To40 = "avgpctspeed2040"
        case averagePercentSpeed40To80 = "avgpctspeed4080"
        case averagePercentSpeed80To120 = "avgpctspeed80120"
        case averagePercentSpeed120Plus = "avgPctSpeed120Plus"
    }
}
