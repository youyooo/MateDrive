import Foundation

public struct EnvironmentHistoryResponse: Decodable, Equatable, Sendable {
    public let data: EnvironmentHistoryData
    public let units: TeslaMateServerStatsUnits?
}

public struct EnvironmentHistoryData: Decodable, Equatable, Sendable {
    public let series: [EnvironmentHistoryPoint]
    public let summary: EnvironmentHistorySummary?
    public let temperatureEnergyBuckets: [TemperatureEnergyBucket]
    public let leakObservations: [TireLeakObservation]
    public let metadata: EnvironmentHistoryMetadata?

    public init(
        series: [EnvironmentHistoryPoint] = [],
        summary: EnvironmentHistorySummary? = nil,
        temperatureEnergyBuckets: [TemperatureEnergyBucket] = [],
        leakObservations: [TireLeakObservation] = [],
        metadata: EnvironmentHistoryMetadata? = nil
    ) {
        self.series = series
        self.summary = summary
        self.temperatureEnergyBuckets = temperatureEnergyBuckets
        self.leakObservations = leakObservations
        self.metadata = metadata
    }
}

public struct EnvironmentHistoryPoint: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(dateFrom ?? 0)-\(driveId ?? 0)-\(date ?? "")" }
    public let dateFrom: Int64?
    public let dateTo: Int64?
    public let date: String?
    public let driveId: Int?
    public let tpmsPressureFl: Double?
    public let tpmsPressureFr: Double?
    public let tpmsPressureRl: Double?
    public let tpmsPressureRr: Double?
    public let tirePressureGap: Double?
    public let outsideTemp: Double?
    public let insideTemp: Double?
    public let consumptionWhPerUnit: Double?
    public let sampleCount: Int?
    public let samplePolicy: String?

    public var timestamp: Date? {
        if let dateFrom { return Date(timeIntervalSince1970: TimeInterval(dateFrom) / 1_000) }
        return date.flatMap(DomainDateParser.date(from:))
    }
}

public struct EnvironmentHistorySummary: Decodable, Equatable, Sendable {
    public let pointCount: Int?
    public let sampleCount: Int?
    public let maxPressureGap: EnvironmentHistoryExtreme?
    public let lowestPressure: EnvironmentHistoryExtreme?
    public let highestPressure: EnvironmentHistoryExtreme?
    public let averagePressureGap: Double?
    public let averageOutsideTemp: Double?
}

public struct EnvironmentHistoryExtreme: Decodable, Equatable, Sendable {
    public let type: String?
    public let value: Double?
    public let unit: String?
    public let wheel: String?
    public let dateFrom: Int64?
    public let date: String?
    public let driveId: Int?
}

public struct TemperatureEnergyBucket: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(temperatureFrom ?? 0)-\(temperatureTo ?? 0)" }
    public let temperatureFrom: Double?
    public let temperatureTo: Double?
    public let medianConsumptionWhPerUnit: Double?
    public let averageConsumptionWhPerUnit: Double?
    public let driveCount: Int?
    public let distance: Double?
}

public struct TireLeakObservation: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(wheel ?? "unknown")-\(earlierMedian ?? 0)-\(laterMedian ?? 0)" }
    public let wheel: String?
    public let earlierMedian: Double?
    public let laterMedian: Double?
    public let delta: Double?
    public let earlierSampleCount: Int?
    public let laterSampleCount: Int?
    public let confidence: String?
}

public struct EnvironmentHistoryMetadata: Decodable, Equatable, Sendable {
    public let requestedGrain: String?
    public let resolvedGrain: String?
    public let samplePolicy: String?
    public let startDate: String?
    public let endDate: String?
    public let timezone: String?
    public let minSamples: Int?
}
