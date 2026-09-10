import ActivityKit
import Foundation

public struct ChargeLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let batteryLevel: Int?
        public let chargeLimitSoc: Int?
        public let chargerPowerKW: Int?
        public let energyAddedKWh: Double?
        public let timeToFullMinutes: Int?
        public let isDC: Bool
        public let isCharging: Bool
        public let displayLanguage: WidgetDisplayLanguage
        public let quality: WidgetChargeDataQuality
        public let updatedAt: Date

        public init(
            batteryLevel: Int? = nil,
            chargeLimitSoc: Int? = nil,
            chargerPowerKW: Int? = nil,
            energyAddedKWh: Double? = nil,
            timeToFullMinutes: Int? = nil,
            isDC: Bool = false,
            isCharging: Bool = true,
            displayLanguage: WidgetDisplayLanguage = .system,
            quality: WidgetChargeDataQuality = .complete,
            updatedAt: Date = Date()
        ) {
            self.batteryLevel = batteryLevel
            self.chargeLimitSoc = chargeLimitSoc
            self.chargerPowerKW = chargerPowerKW
            self.energyAddedKWh = energyAddedKWh
            self.timeToFullMinutes = timeToFullMinutes
            self.isDC = isDC
            self.isCharging = isCharging
            self.displayLanguage = displayLanguage
            self.quality = quality
            self.updatedAt = updatedAt
        }

        private enum CodingKeys: String, CodingKey {
            case batteryLevel
            case chargeLimitSoc
            case chargerPowerKW
            case energyAddedKWh
            case timeToFullMinutes
            case isDC
            case isCharging
            case displayLanguage
            case quality
            case updatedAt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
            chargeLimitSoc = try container.decodeIfPresent(Int.self, forKey: .chargeLimitSoc)
            chargerPowerKW = try container.decodeIfPresent(Int.self, forKey: .chargerPowerKW)
            energyAddedKWh = try container.decodeIfPresent(Double.self, forKey: .energyAddedKWh)
            timeToFullMinutes = try container.decodeIfPresent(Int.self, forKey: .timeToFullMinutes)
            isDC = try container.decode(Bool.self, forKey: .isDC)
            isCharging = try container.decode(Bool.self, forKey: .isCharging)
            displayLanguage = try container.decodeIfPresent(
                WidgetDisplayLanguage.self,
                forKey: .displayLanguage
            ) ?? .system
            quality = try container.decodeIfPresent(
                WidgetChargeDataQuality.self,
                forKey: .quality
            ) ?? .complete
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(batteryLevel, forKey: .batteryLevel)
            try container.encodeIfPresent(chargeLimitSoc, forKey: .chargeLimitSoc)
            try container.encodeIfPresent(chargerPowerKW, forKey: .chargerPowerKW)
            try container.encodeIfPresent(energyAddedKWh, forKey: .energyAddedKWh)
            try container.encodeIfPresent(timeToFullMinutes, forKey: .timeToFullMinutes)
            try container.encode(isDC, forKey: .isDC)
            try container.encode(isCharging, forKey: .isCharging)
            try container.encode(displayLanguage, forKey: .displayLanguage)
            try container.encode(quality, forKey: .quality)
            try container.encode(updatedAt, forKey: .updatedAt)
        }
    }

    public let carID: Int?
    public let carName: String
    public let vehicleIdentifier: String?

    public init(carID: Int? = nil, carName: String, vehicleIdentifier: String? = nil) {
        self.carID = carID
        self.carName = carName
        self.vehicleIdentifier = vehicleIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case carID
        case carName
        case vehicleIdentifier
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        carID = try container.decodeIfPresent(Int.self, forKey: .carID)
        carName = try container.decode(String.self, forKey: .carName)
        vehicleIdentifier = try container.decodeIfPresent(String.self, forKey: .vehicleIdentifier)
    }

    public func encode(to encoder: any Encoder) throws {
        if let vehicleIdentifier,
           !WidgetVehicleIdentity.isCanonicalIdentifier(vehicleIdentifier) {
            throw EncodingError.invalidValue(
                "<redacted>",
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "vehicleIdentifier must be a canonical lowercase 64-character hexadecimal identity"
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(carName, forKey: .carName)
        try container.encodeIfPresent(vehicleIdentifier, forKey: .vehicleIdentifier)
    }
}
