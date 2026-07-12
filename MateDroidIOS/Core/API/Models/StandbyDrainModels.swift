import Foundation

public struct StandbyDrainResponse: Decodable, Equatable, Sendable {
    public let data: StandbyDrainData?
    public let units: StandbyDrainUnits?
    public let error: String?
}

public struct StandbyDrainData: Decodable, Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let radiusMeters: Double?
    public let periodDays: Int?
    public let totalParkingEvents: Int?
    public let totalParkingDays: Double?
    public let averageDrainRateKmH: Double?
    public let averageDrainPercent24H: Double?
    public let totalRangeLossKm: Double?
    public let minimumDrainRateKmH: Double?
    public let maximumDrainRateKmH: Double?

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case radiusMeters
        case periodDays
        case totalParkingEvents
        case totalParkingDays
        case averageDrainRateKmH = "avgDrainRateKmH"
        case averageDrainPercent24H = "avgDrainRatePct24H"
        case totalRangeLossKm
        case minimumDrainRateKmH = "minDrainRateKmH"
        case maximumDrainRateKmH = "maxDrainRateKmH"
    }
}

public struct StandbyDrainUnits: Decodable, Equatable, Sendable {
    public let length: String?
}

public struct TopDrainLocationsResponse: Decodable, Equatable, Sendable {
    public let locations: [TopDrainLocation]
    public let units: TeslaMateServerStatsUnits?
}

public struct TopDrainLocation: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(latitude ?? 0),\(longitude ?? 0)" }
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let totalRangeLossKm: Double?
    public let averageDrainPercent24H: Double?
    public let averageDrainRateKmH: Double?
    public let parkingCount: Int?
    public let totalDurationMin: Double?

    private enum CodingKeys: String, CodingKey {
        case address, latitude, longitude, totalRangeLossKm, parkingCount, totalDurationMin
        case averageDrainPercent24H = "avgDrainRatePct24h"
        case averageDrainRateKmH = "avgDrainRateKmH"
    }
}
