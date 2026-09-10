import Foundation

public struct BatteryResponse: Decodable, Sendable {
    public let data: BatteryPayload?
    public let error: String?
}

public struct BatteryPayload: Decodable, Sendable {
    public let battery: BatteryData?
}

public struct BatteryData: Decodable, Equatable, Sendable {
    public let carId: Int?
    public let usableBatteryLevel: Int?
    public let batteryLevel: Int?
    public let ratedBatteryRangeKm: Double?
    public let idealBatteryRangeKm: Double?
    public let estBatteryRangeKm: Double?
    public let efficiency: Double?
}

public struct BatteryHealthResponse: Decodable, Sendable {
    public let data: BatteryHealthPayload?
    public let error: String?
}

public struct BatteryHealthPayload: Decodable, Sendable {
    public let batteryHealth: BatteryHealth?

    private enum CodingKeys: String, CodingKey {
        case batteryHealth
        case batteryData
    }

    public init(batteryHealth: BatteryHealth? = nil) {
        self.batteryHealth = batteryHealth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        batteryHealth = try container.decodeIfPresent(BatteryHealth.self, forKey: .batteryHealth)
            ?? container.decodeIfPresent(BatteryHealth.self, forKey: .batteryData)
    }
}

public struct BatteryHealth: Decodable, Equatable, Sendable {
    public let maxRange: Double?
    public let currentRange: Double?
    public let maxCapacity: Double?
    public let currentCapacity: Double?
    public let ratedEfficiency: Double?
    public let batteryHealthPercentage: Double?

    private enum CodingKeys: String, CodingKey {
        case maxRange
        case currentRange
        case currentMaxRange
        case maxCapacity
        case currentCapacity
        case ratedEfficiency
        case batteryHealthPercentage
        case batteryHealth
    }

    public init(maxRange: Double? = nil, currentRange: Double? = nil, maxCapacity: Double? = nil, currentCapacity: Double? = nil, ratedEfficiency: Double? = nil, batteryHealthPercentage: Double? = nil) {
        self.maxRange = maxRange
        self.currentRange = currentRange
        self.maxCapacity = maxCapacity
        self.currentCapacity = currentCapacity
        self.ratedEfficiency = ratedEfficiency
        self.batteryHealthPercentage = Self.normalizedHealthPercentage(batteryHealthPercentage)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxRange = try container.decodeIfPresent(Double.self, forKey: .maxRange)
        currentRange = try container.decodeIfPresent(Double.self, forKey: .currentRange)
            ?? container.decodeIfPresent(Double.self, forKey: .currentMaxRange)
        maxCapacity = try container.decodeIfPresent(Double.self, forKey: .maxCapacity)
        currentCapacity = try container.decodeIfPresent(Double.self, forKey: .currentCapacity)
        ratedEfficiency = Self.normalizedEfficiency(
            try container.decodeIfPresent(Double.self, forKey: .ratedEfficiency)
        )
        let rawBatteryHealthPercentage = try container.decodeIfPresent(Double.self, forKey: .batteryHealthPercentage)
            ?? container.decodeIfPresent(Double.self, forKey: .batteryHealth)
        batteryHealthPercentage = Self.normalizedHealthPercentage(rawBatteryHealthPercentage)
    }

    private static func normalizedEfficiency(_ value: Double?) -> Double? {
        guard let value else {
            return nil
        }
        if value <= 2 {
            return value * 1000
        }
        if value < 50 {
            return value * 10
        }
        return value
    }

    private static func normalizedHealthPercentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        let percent = value <= 1 ? value * 100 : value
        return min(percent, 100)
    }
}

public struct BatteryHistoryResponse: Decodable, Equatable, Sendable {
    public let data: BatteryHistoryData?
}

public struct BatteryHistoryData: Decodable, Equatable, Sendable {
    public let car: BatteryHistoryCar?
    public let charts: BatteryHistoryCharts?
    public let efficiency: BatteryHistoryEfficiency?
    public let units: BatteryHistoryUnits?
}

public struct BatteryHistoryCar: Decodable, Equatable, Sendable {
    public let carId: Int?
    public let carName: String?
}

public struct BatteryHistoryCharts: Decodable, Equatable, Sendable {
    public let capacity: [BatteryCapacityPoint]
    public let capacityMedian: [BatteryCapacityPoint]
    public let range: [BatteryRangePoint]

    private enum CodingKeys: String, CodingKey { case capacity, capacityMedian, range }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capacity = try container.decodeIfPresent([BatteryCapacityPoint].self, forKey: .capacity) ?? []
        capacityMedian = try container.decodeIfPresent([BatteryCapacityPoint].self, forKey: .capacityMedian) ?? []
        range = try container.decodeIfPresent([BatteryRangePoint].self, forKey: .range) ?? []
    }
}

public struct BatteryCapacityPoint: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(date ?? "")-\(odometer ?? 0)" }
    public let bucket: String?
    public let date: String?
    public let odometer: Double?
    public let capacity: Double?
}

public struct BatteryRangePoint: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(date ?? "")-\(odometer ?? 0)" }
    public let date: String?
    public let odometer: Double?
    public let range: Double?
}

public struct BatteryHistoryEfficiency: Decodable, Equatable, Sendable {
    public let value: Double?
    public let source: String?
    public let ready: Bool?
    public let qualifyingChargeCount: Int?
    public let requiredChargeCount: Int?
    public let minDurationMin: Int?
    public let maxEndBatteryLevel: Int?

    public var whPerKm: Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value < 50 ? value * 10 : value
    }
}

public struct BatteryHistoryUnits: Decodable, Equatable, Sendable {
    public let unitOfLength: String?
    public let unitOfTemperature: String?
    public let unitOfEnergy: String?
}

public struct UpdatesResponse: Decodable, Sendable {
    public let data: UpdatesPayload?
    public let error: String?
}

public struct UpdatesPayload: Decodable, Sendable {
    public let updates: [UpdateData]?
}

public struct UpdateData: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { updateId ?? 0 }

    public let updateId: Int?
    public let version: String?
    public let startDate: String?
    public let endDate: String?

    public init(updateId: Int? = nil, version: String? = nil, startDate: String? = nil, endDate: String? = nil) {
        self.updateId = updateId
        self.version = version
        self.startDate = startDate
        self.endDate = endDate
    }
}
