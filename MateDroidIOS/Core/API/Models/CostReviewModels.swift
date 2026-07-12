import Foundation

public struct CostReviewResponse: Decodable, Equatable, Sendable {
    public let contractVersion: Int?
    public let data: CostReviewData
    public let units: TeslaMateServerStatsUnits?
}

public struct CostReviewData: Decodable, Equatable, Sendable {
    public let range: CostReviewDateRange
    public let summary: CostReviewSummary
    public let dataQuality: CostReviewDataQuality
    public let buckets: [CostReviewBucket]
    public let chargingModes: [CostReviewChargingMode]
    public let placeRankings: CostReviewPlaceRankings
    public let comparison: CostReviewComparison?
    public let records: CostReviewRecords
}

public struct CostReviewDateRange: Decodable, Equatable, Sendable {
    public let startDate: String?
    public let endDate: String?
    public let period: String?
}

public struct CostReviewSummary: Decodable, Equatable, Sendable {
    public let recordedSpend: Double?
    public let estimatedUseCost: Double?
    public let chargingCost: Double?
    public let parkingCost: Double?
    public let estimatedDrivingEnergyCost: Double?
    public let estimatedStandbyEnergyCost: Double?
    public let totalDistanceKm: Double?
    public let driveCount: Int?
    public let totalEnergyKwh: Double?
    public let chargeCount: Int?
    public let chargingDayCount: Int?
    public let averagePricePerKwh: Double?
    public let freeChargeCount: Int?
    public let freeEnergyKwh: Double?
    public let costRecordedChargeCount: Int?
    public let missingChargeCostCount: Int?
    public let standbyRangeLossKm: Double?
    public let standbyEventCount: Int?
    public let parkingEventCount: Int?
    public let parkingCostRecordedCount: Int?
    public let missingParkingCostCount: Int?
    public let zeroParkingCostCount: Int?
    public let energyCostEstimatePricePerKwh: Double?
    public let energyCostEstimatePriceSource: String?
    public let energyCostEstimateConsumptionWhPerKm: Double?
}

public struct CostReviewCostQuality: Decodable, Equatable, Sendable {
    public let eventCount: Int?
    public let costRecordedCount: Int?
    public let missingCostCount: Int?
    public let zeroCostCount: Int?
    public let costCoverage: Double?
}

public struct CostReviewEnergyEstimateQuality: Decodable, Equatable, Sendable {
    public let isAvailable: Bool?
    public let pricePerKwh: Double?
    public let consumptionWhPerKm: Double?
}

public struct CostReviewDataQuality: Decodable, Equatable, Sendable {
    public let hasAnyActivity: Bool?
    public let hasStatsSummary: Bool?
    public let chargingCost: CostReviewCostQuality
    public let parkingCost: CostReviewCostQuality
    public let energyEstimate: CostReviewEnergyEstimateQuality
}

public struct CostReviewBucket: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let dateFrom: Int64?
    public let dateTo: Int64?
    public let granularity: String?
    public let estimatedUseCost: Double?
    public let recordedSpend: Double?
    public let chargingSpend: Double?
    public let estimatedDrivingEnergyCost: Double?
    public let estimatedStandbyEnergyCost: Double?
    public let parkingCost: Double?
    public let chargingEnergyKwh: Double?
    public let chargeCount: Int?
    public let driveCount: Int?
    public let dataQuality: CostReviewDataQuality?

    public var date: Date? {
        dateFrom.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
    }
}

public struct CostReviewChargingMode: Decodable, Equatable, Identifiable, Sendable {
    public let mode: String
    public let chargeCount: Int?
    public let energyKwh: Double?
    public var id: String { mode }
}

public struct CostReviewPlaceRanking: Decodable, Equatable, Identifiable, Sendable {
    public let kind: String?
    public let placeId: Int?
    public let displayName: String?
    public let latitude: Double?
    public let longitude: Double?
    public let chargeCount: Int?
    public let parkCount: Int?
    public let totalEnergyKwh: Double?
    public let totalCost: Double?
    public let costRecordedCount: Int?
    public let missingCostCount: Int?
    public let zeroCostCount: Int?
    public let averagePricePerKwh: Double?
    public let totalDurationMin: Double?
    public let totalRangeLossKm: Double?
    public let estimatedCost: Double?
    public let latestAt: String?

    public var id: String {
        "\(kind ?? "place"):\(placeId.map(String.init) ?? displayName ?? "unknown")"
    }
}

public struct CostReviewPlaceRankings: Decodable, Equatable, Sendable {
    public let charging: [CostReviewPlaceRanking]
    public let parking: [CostReviewPlaceRanking]
    public let standby: [CostReviewPlaceRanking]
    public let parkingZeroCostConfirmed: Bool?
}

public struct CostReviewMetricComparison: Decodable, Equatable, Sendable {
    public let isEligible: Bool?
    public let currentValue: Double?
    public let previousValue: Double?
    public let delta: Double?
    public let percentageChange: Double?
    public let reasonCodes: [String]
}

public struct CostReviewComparison: Decodable, Equatable, Sendable {
    public let previousRange: CostReviewDateRange?
    public let previousSummary: CostReviewSummary?
    public let previousDataQuality: CostReviewDataQuality?
    public let estimatedUseCost: CostReviewMetricComparison?
    public let recordedSpend: CostReviewMetricComparison?
    public let chargingSpend: CostReviewMetricComparison?
    public let costPerDistance: CostReviewMetricComparison?
}

public struct CostReviewRecord: Decodable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let type: String?
    public let title: String?
    public let startDate: String?
    public let endDate: String?
    public let address: String?
    public let placeId: Int?
    public let energyKwh: Double?
    public let cost: Double?
    public let durationMin: Double?
    public let unitPricePerKwh: Double?
    public let rangeLossKm: Double?
}

public struct CostReviewRecords: Decodable, Equatable, Sendable {
    public let topCharges: [CostReviewRecord]
    public let missingChargeCosts: [CostReviewRecord]
    public let missingParkingCosts: [CostReviewRecord]
}
