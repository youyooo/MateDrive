import Foundation

public enum ActivityLabelScope: String, Codable, Sendable {
    case sessionOnly, futureAtPlace
}

public struct ActivityLabelOverride: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let sessionId: String?
    public let placeKey: String?
    public let scope: ActivityLabelScope
    public let purpose: SmartActivityPurpose
    public let customName: String?
    public let icon: String
    public let colorHex: String
    public let startMinute: Int?
    public let endMinute: Int?
    public let updatedAt: Date

    public init(
        id: String,
        carId: Int,
        sessionId: String?,
        placeKey: String?,
        scope: ActivityLabelScope,
        purpose: SmartActivityPurpose,
        customName: String?,
        icon: String,
        colorHex: String,
        startMinute: Int?,
        endMinute: Int?,
        updatedAt: Date
    ) {
        self.id = id
        self.carId = carId
        self.sessionId = sessionId
        self.placeKey = placeKey
        self.scope = scope
        self.purpose = purpose
        self.customName = customName
        self.icon = icon
        self.colorHex = colorHex
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.updatedAt = updatedAt
    }
}

public enum ChargePricingObservationScope: String, Codable, Sendable {
    case sessionOnly, futureAtStation
}

public struct ChargePricingObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let chargeId: Int
    public let stationKey: String
    public let scope: ChargePricingObservationScope
    public let finalAmount: Double
    public let billedEnergyKWh: Double?
    public let pricePerKWh: Double?
    public let serviceFeePerKWh: Double?
    public let fixedFee: Double?
    public let currencyCode: String
    public let confirmedAt: Date

    public init(
        id: String,
        carId: Int,
        chargeId: Int,
        stationKey: String,
        scope: ChargePricingObservationScope,
        finalAmount: Double,
        billedEnergyKWh: Double?,
        pricePerKWh: Double?,
        serviceFeePerKWh: Double?,
        fixedFee: Double?,
        currencyCode: String,
        confirmedAt: Date
    ) {
        self.id = id
        self.carId = carId
        self.chargeId = chargeId
        self.stationKey = stationKey
        self.scope = scope
        self.finalAmount = finalAmount
        self.billedEnergyKWh = billedEnergyKWh
        self.pricePerKWh = pricePerKWh
        self.serviceFeePerKWh = serviceFeePerKWh
        self.fixedFee = fixedFee
        self.currencyCode = currencyCode
        self.confirmedAt = confirmedAt
    }
}

enum SmartActivityPersistenceCoding {
    static func encode<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from value: String) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(value.utf8))
    }

    static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
