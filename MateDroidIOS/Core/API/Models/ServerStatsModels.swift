import Foundation

public struct TeslaMateServerStatsResponse: Decodable, Equatable, Sendable {
    public let summary: TeslaMateServerStatsSummary?
    public let data: [TeslaMateServerStatsPeriod]
    public let pagination: TeslaMatePagination?
    public let units: TeslaMateServerStatsUnits?

    public init(
        summary: TeslaMateServerStatsSummary?,
        data: [TeslaMateServerStatsPeriod] = [],
        pagination: TeslaMatePagination? = nil,
        units: TeslaMateServerStatsUnits? = nil
    ) {
        self.summary = summary
        self.data = data
        self.pagination = pagination
        self.units = units
    }

    private enum CodingKeys: String, CodingKey {
        case summary, data, pagination, units
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decodeIfPresent(TeslaMateServerStatsSummary.self, forKey: .summary)
        data = try container.decodeIfPresent([TeslaMateServerStatsPeriod].self, forKey: .data) ?? []
        pagination = try container.decodeIfPresent(TeslaMatePagination.self, forKey: .pagination)
        units = try container.decodeIfPresent(TeslaMateServerStatsUnits.self, forKey: .units)
    }
}

public struct TeslaMateServerStatsSummary: Decodable, Equatable, Sendable {
    public let totalDistanceKm: Double?
    public let totalChargingCost: Double?
    public let avgConsumptionNet: Double?
    public let avgConsumptionGross: Double?
    public let avgSpeedKmh: Double?
    public let avgTempC: Double?
    public let totalElevationChangeM: Double?
    public let avgCostPerKwh: Double?
    public let zeroCostChargeCount: Int?
    public let avgRegenCaptureRate: Double?
    public let avgRegenKwhPer100km: Double?
    public let totalHardBrakingCount: Int?
    public let avgHardBrakingPer100km: Double?
    public let avgMaxDriveSoc: Double?
    public let regenLimitedDriveCount: Int?
    public let avgTirePressureGap: Double?
    public let totalElevationGain: Double?
    public let totalElevationLoss: Double?
    public let avgPctSpeed0_20: Double?
    public let avgPctSpeed20_40: Double?
    public let avgPctSpeed40_80: Double?
    public let avgPctSpeed80_120: Double?
    public let avgPctSpeed120Plus: Double?
    public let newPlaceDriveCount: Int?
    public let commuteRouteCount: Int?
    public let smartCommuteCount: Int?
    public let evaluations: TeslaMateServerStatsEvaluations?
    public let totalStandbyRangeLossKm: Double?
    public let avgDrainRateKmH: Double?
    public let avgDrainRatePct24h: Double?
    public let parkingEventCount: Int?
}

public struct TeslaMateServerStatsEvaluations: Decodable, Equatable, Sendable {
    public let safetyDistanceCount: Int?
    public let lowTempRegenCount: Int?
    public let goldenFootCount: Int?
    public let rushHourComfortCount: Int?
    public let elevationInsightCount: Int?
    public let shortTripHVACCount: Int?
}

public struct TeslaMateServerStatsPeriod: Decodable, Equatable, Sendable {
    public let date: String?
    public let display: String?
    public let drivingDurationMin: Int?
    public let distanceKm: Double?
    public let tripCount: Int?
    public let totalEnergyKwh: Double?
    public let chargingCost: Double?
    public let chargeCount: Int?
    public let consumptionNet: Double?
    public let consumptionGross: Double?
}

public struct TeslaMatePagination: Decodable, Equatable, Sendable {
    public let totalRecords: Int?
    public let totalPages: Int?
    public let page: Int?
    public let limit: Int?
}

public struct TeslaMateServerStatsUnits: Decodable, Equatable, Sendable {
    public let unitOfLength: String?
    public let unitOfPressure: String?
    public let unitOfTemperature: String?
}
