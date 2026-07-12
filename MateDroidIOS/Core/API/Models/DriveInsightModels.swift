import Foundation

public struct TeslaMateDriveInsightsResponse: Decodable, Equatable, Sendable {
    public let data: TeslaMateDriveInsightsData?
}

public struct TeslaMateDriveInsightsData: Decodable, Equatable, Sendable {
    public let car: TeslaMateDriveInsightsCar?
    public let driveStats: [TeslaMateRouteInsight]
    public let units: TeslaMateServerStatsUnits?

    private enum CodingKeys: String, CodingKey { case car, driveStats, units }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        car = try container.decodeIfPresent(TeslaMateDriveInsightsCar.self, forKey: .car)
        driveStats = try container.decodeIfPresent([TeslaMateRouteInsight].self, forKey: .driveStats) ?? []
        units = try container.decodeIfPresent(TeslaMateServerStatsUnits.self, forKey: .units)
    }
}

public struct TeslaMateDriveInsightsCar: Decodable, Equatable, Sendable {
    public let carId: Int?
    public let carName: String?
}

public struct TeslaMateRouteInsight: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { "\(startLatitude ?? 0)-\(startLongitude ?? 0)-\(endLatitude ?? 0)-\(endLongitude ?? 0)" }
    public let startLatitude: Double?
    public let startLongitude: Double?
    public let endLatitude: Double?
    public let endLongitude: Double?
    public let startAddress: String?
    public let endAddress: String?
    public let driveCount: Int?
    public let totalDistanceKm: Double?
    public let avgDistanceKm: Double?
    public let totalDurationMin: Double?
    public let avgDurationMin: Double?
    public let avgSpeedKmh: Double?
    public let totalEnergyKwh: Double?
    public let avgEnergyKwh: Double?
    public let avgPowerKw: Double?
    public let consumptionWhKm: Double?
    public let lastDriveDate: String?
    public let mostCommonHour: Int?
}
