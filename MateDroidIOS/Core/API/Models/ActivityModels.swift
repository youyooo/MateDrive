import Foundation

public struct TeslaMateActivitiesResponse: Decodable, Equatable, Sendable {
    public let data: [TeslaMateActivity]
    public let pagination: TeslaMatePagination?
    public let units: TeslaMateServerStatsUnits?

    private enum CodingKeys: String, CodingKey { case data, pagination, units }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decodeIfPresent([TeslaMateActivity].self, forKey: .data) ?? []
        pagination = try container.decodeIfPresent(TeslaMatePagination.self, forKey: .pagination)
        units = try container.decodeIfPresent(TeslaMateServerStatsUnits.self, forKey: .units)
    }
}

public enum TeslaMateActivityKind: String, CaseIterable, Codable, Hashable, Sendable {
    case drive
    case charge
    case park
    case unknown
}

public struct TeslaMateActivity: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: Int
    public let type: String
    public let startDate: String?
    public let endDate: String?
    public let durationMin: Double?
    public let startAddress: String?
    public let endAddress: String?
    public let startLatitude: Double?
    public let startLongitude: Double?
    public let endLatitude: Double?
    public let endLongitude: Double?
    public let kwh: Double?
    public let kwhUsed: Double?
    public let cost: Double?
    public let rangeDiffKm: Double?
    public let soc: Int?
    public let socDiff: Int?
    public let odometerKm: Double?
    public let distanceKm: Double?
    public let endRangeKm: Double?
    public let stats: TeslaMateActivityStats?

    public var kind: TeslaMateActivityKind {
        TeslaMateActivityKind(rawValue: type.lowercased()) ?? .unknown
    }

    public var stableID: String { "\(kind.rawValue)-\(id)" }

    public init(
        id: Int,
        type: String,
        startDate: String? = nil,
        endDate: String? = nil,
        durationMin: Double? = nil,
        startAddress: String? = nil,
        endAddress: String? = nil,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        kwh: Double? = nil,
        kwhUsed: Double? = nil,
        cost: Double? = nil,
        rangeDiffKm: Double? = nil,
        soc: Int? = nil,
        socDiff: Int? = nil,
        odometerKm: Double? = nil,
        distanceKm: Double? = nil,
        endRangeKm: Double? = nil,
        stats: TeslaMateActivityStats? = nil
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.durationMin = durationMin
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.kwh = kwh
        self.kwhUsed = kwhUsed
        self.cost = cost
        self.rangeDiffKm = rangeDiffKm
        self.soc = soc
        self.socDiff = socDiff
        self.odometerKm = odometerKm
        self.distanceKm = distanceKm
        self.endRangeKm = endRangeKm
        self.stats = stats
    }
}

public extension TeslaMateActivity {
    func withCost(_ cost: Double?) -> TeslaMateActivity {
        TeslaMateActivity(
            id: id, type: type, startDate: startDate, endDate: endDate, durationMin: durationMin,
            startAddress: startAddress, endAddress: endAddress, startLatitude: startLatitude,
            startLongitude: startLongitude, endLatitude: endLatitude, endLongitude: endLongitude,
            kwh: kwh, kwhUsed: kwhUsed, cost: cost, rangeDiffKm: rangeDiffKm, soc: soc,
            socDiff: socDiff, odometerKm: odometerKm, distanceKm: distanceKm,
            endRangeKm: endRangeKm, stats: stats
        )
    }
}

public struct TeslaMateActivityStats: Codable, Equatable, Hashable, Sendable {
    public let regenUtilization: Double?
    public let hardBrakingCount: Int?
    public let hardBrakingPer100km: Double?
    public let totalElevationGain: Double?
    public let totalElevationLoss: Double?
    public let tirePressureGapBar: Double?
    public let isRegenLimited: Bool?
    public let avgOutsideTemp: Double?
    public let maxDriveSoc: Double?
    public let isNewPlace: Bool?
    public let isSmartCommute: Bool?
    public let commuteRouteId: Int?
    public let evaluations: [TeslaMateDriveEvaluation]?
}

public struct TeslaMateDriveEvaluation: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { "\(type)-\(priority ?? 0)-\(titleKey ?? "")" }
    public let type: String
    public let priority: Int?
    public let titleKey: String?
    public let messageKey: String?
}
