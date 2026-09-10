import Foundation

public struct ChargesResponse: Decodable, Sendable {
    public let data: ChargesPayload?
    public let error: String?
}

public struct ChargesPayload: Decodable, Sendable {
    public let charges: [ChargeData]
}

public struct ChargeDetailResponse: Decodable, Sendable {
    public let data: ChargeDetailPayload?
    public let error: String?
}

public struct ChargeDetailPayload: Decodable, Sendable {
    public let car: ChargeDetailCar?
    public let charge: ChargeDetail?
}

public struct ChargeData: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int { chargeId ?? -1 }

    public let chargeId: Int?
    public let carId: Int?
    public let startDate: String?
    public let endDate: String?
    public let address: String?
    public let chargeEnergyAdded: Double?
    public let chargeEnergyUsed: Double?
    public let cost: Double?
    public let durationMin: Int?
    public let durationStr: String?
    public let chargerPower: Double?
    public let chargerPhases: Int?
    public let batteryDetails: ChargeBatteryDetails?
    public let rangeIdeal: ChargeRange?
    public let rangeRated: ChargeRange?
    public let outsideTempAvg: Double?
    public let odometer: Double?
    public let latitude: Double?
    public let longitude: Double?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?

    public init(
        chargeId: Int?,
        carId: Int? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        address: String? = nil,
        chargeEnergyAdded: Double? = nil,
        chargeEnergyUsed: Double? = nil,
        cost: Double? = nil,
        durationMin: Int? = nil,
        durationStr: String? = nil,
        chargerPower: Double? = nil,
        chargerPhases: Int? = nil,
        batteryDetails: ChargeBatteryDetails? = nil,
        rangeIdeal: ChargeRange? = nil,
        rangeRated: ChargeRange? = nil,
        outsideTempAvg: Double? = nil,
        odometer: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil
    ) {
        self.chargeId = chargeId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.address = address
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargeEnergyUsed = chargeEnergyUsed
        self.cost = cost
        self.durationMin = durationMin
        self.durationStr = durationStr
        self.chargerPower = chargerPower
        self.chargerPhases = chargerPhases
        self.batteryDetails = batteryDetails
        self.rangeIdeal = rangeIdeal
        self.rangeRated = rangeRated
        self.outsideTempAvg = outsideTempAvg
        self.odometer = odometer
        self.latitude = latitude
        self.longitude = longitude
        self.startBatteryLevel = startBatteryLevel ?? batteryDetails?.startBatteryLevel
        self.endBatteryLevel = endBatteryLevel ?? batteryDetails?.endBatteryLevel
    }
}

public struct ChargeDetailCar: Decodable, Equatable, Sendable {
    public let carId: Int?
    public let carName: String?

    public init(carId: Int? = nil, carName: String? = nil) {
        self.carId = carId
        self.carName = carName
    }
}

public struct ChargeBatteryDetails: Decodable, Equatable, Sendable {
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let currentBatteryLevel: Int?

    public init(startBatteryLevel: Int? = nil, endBatteryLevel: Int? = nil, currentBatteryLevel: Int? = nil) {
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.currentBatteryLevel = currentBatteryLevel
    }
}

public struct ChargeRange: Decodable, Equatable, Sendable {
    public let startRange: Double?
    public let endRange: Double?

    public init(startRange: Double? = nil, endRange: Double? = nil) {
        self.startRange = startRange
        self.endRange = endRange
    }
}

public struct ChargeDetail: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let startDate: String?
    public let endDate: String?
    public let address: String?
    public let chargeEnergyAdded: Double?
    public let chargeEnergyUsed: Double?
    public let cost: Double?
    public let durationMin: Int?
    public let durationStr: String?
    public let batteryDetails: ChargeBatteryDetails?
    public let rangeIdeal: ChargeRange?
    public let rangeRated: ChargeRange?
    public let outsideTempAvg: Double?
    public let odometer: Double?
    public let latitude: Double?
    public let longitude: Double?
    public let chargePoints: [ChargePoint]?
    public let isCharging: Bool?

    private enum CodingKeys: String, CodingKey {
        case chargeId
        case startDate
        case endDate
        case address
        case chargeEnergyAdded
        case chargeEnergyUsed
        case cost
        case durationMin
        case durationStr
        case batteryDetails
        case rangeIdeal
        case rangeRated
        case outsideTempAvg
        case odometer
        case latitude
        case longitude
        case chargePoints
        case chargeDetails
        case isCharging
    }

    public init(
        chargeId: Int,
        startDate: String? = nil,
        endDate: String? = nil,
        address: String? = nil,
        chargeEnergyAdded: Double? = nil,
        chargeEnergyUsed: Double? = nil,
        cost: Double? = nil,
        durationMin: Int? = nil,
        durationStr: String? = nil,
        batteryDetails: ChargeBatteryDetails? = nil,
        rangeIdeal: ChargeRange? = nil,
        rangeRated: ChargeRange? = nil,
        outsideTempAvg: Double? = nil,
        odometer: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        chargePoints: [ChargePoint]? = nil,
        isCharging: Bool? = nil
    ) {
        self.chargeId = chargeId
        self.startDate = startDate
        self.endDate = endDate
        self.address = address
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargeEnergyUsed = chargeEnergyUsed
        self.cost = cost
        self.durationMin = durationMin
        self.durationStr = durationStr
        self.batteryDetails = batteryDetails
        self.rangeIdeal = rangeIdeal
        self.rangeRated = rangeRated
        self.outsideTempAvg = outsideTempAvg
        self.odometer = odometer
        self.latitude = latitude
        self.longitude = longitude
        self.chargePoints = chargePoints
        self.isCharging = isCharging
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chargeId = try container.decode(Int.self, forKey: .chargeId)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        chargeEnergyAdded = try container.decodeIfPresent(Double.self, forKey: .chargeEnergyAdded)
        chargeEnergyUsed = try container.decodeIfPresent(Double.self, forKey: .chargeEnergyUsed)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        durationStr = try container.decodeIfPresent(String.self, forKey: .durationStr)
        batteryDetails = try container.decodeIfPresent(ChargeBatteryDetails.self, forKey: .batteryDetails)
        rangeIdeal = try container.decodeIfPresent(ChargeRange.self, forKey: .rangeIdeal)
        rangeRated = try container.decodeIfPresent(ChargeRange.self, forKey: .rangeRated)
        outsideTempAvg = try container.decodeIfPresent(Double.self, forKey: .outsideTempAvg)
        odometer = try container.decodeIfPresent(Double.self, forKey: .odometer)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        chargePoints = try container.decodeIfPresent([ChargePoint].self, forKey: .chargePoints) ??
            container.decodeIfPresent([ChargePoint].self, forKey: .chargeDetails)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging)
    }

    public var startBatteryLevel: Int? { batteryDetails?.startBatteryLevel }
    public var endBatteryLevel: Int? { batteryDetails?.endBatteryLevel }
    public var currentBatteryLevel: Int? { batteryDetails?.currentBatteryLevel }
    public var currentOrEndBatteryLevel: Int? { currentBatteryLevel ?? endBatteryLevel }
}

public struct ChargePoint: Decodable, Equatable, Sendable {
    public let date: String?
    public let batteryLevel: Int?
    public let chargeEnergyAdded: Double?
    public let chargerDetails: ChargerDetails?
    public let outsideTemp: Double?
    public let batteryInfo: ChargeBatteryInfo?
    public let connectorType: String?

    public init(
        date: String? = nil,
        batteryLevel: Int? = nil,
        chargeEnergyAdded: Double? = nil,
        chargerDetails: ChargerDetails? = nil,
        outsideTemp: Double? = nil,
        batteryInfo: ChargeBatteryInfo? = nil,
        connectorType: String? = nil
    ) {
        self.date = date
        self.batteryLevel = batteryLevel
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargerDetails = chargerDetails
        self.outsideTemp = outsideTemp
        self.batteryInfo = batteryInfo
        self.connectorType = connectorType
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case batteryLevel
        case chargeEnergyAdded
        case chargerDetails
        case outsideTemp
        case batteryInfo
        case connectorType = "connChargeCable"
        case fastChargerInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
        chargeEnergyAdded = try container.decodeIfPresent(Double.self, forKey: .chargeEnergyAdded)
        outsideTemp = try container.decodeIfPresent(Double.self, forKey: .outsideTemp)
        batteryInfo = try container.decodeIfPresent(ChargeBatteryInfo.self, forKey: .batteryInfo)
        connectorType = try container.decodeIfPresent(String.self, forKey: .connectorType)

        let base = try container.decodeIfPresent(ChargerDetails.self, forKey: .chargerDetails)
        let fast = try container.decodeIfPresent(FastChargerInfo.self, forKey: .fastChargerInfo)
        chargerDetails = ChargerDetails(
            chargerPower: base?.chargerPower,
            chargerVoltage: base?.chargerVoltage,
            chargerActualCurrent: base?.chargerActualCurrent,
            chargerPhases: base?.chargerPhases,
            fastChargerPresent: fast?.fastChargerPresent ?? base?.fastChargerPresent,
            fastChargerBrand: fast?.fastChargerBrand ?? base?.fastChargerBrand,
            fastChargerType: fast?.fastChargerType ?? base?.fastChargerType
        )
    }

    public var chargerPower: Int? { chargerDetails?.chargerPower }
    public var chargerVoltage: Int? { chargerDetails?.chargerVoltage }
    public var chargerCurrent: Int? { chargerDetails?.chargerActualCurrent }
}

private struct FastChargerInfo: Decodable {
    let fastChargerPresent: Bool?
    let fastChargerBrand: String?
    let fastChargerType: String?
}

public struct ChargerDetails: Decodable, Equatable, Sendable {
    public let chargerPower: Int?
    public let chargerVoltage: Int?
    public let chargerActualCurrent: Int?
    public let chargerPhases: Int?
    public let fastChargerPresent: Bool?
    public let fastChargerBrand: String?
    public let fastChargerType: String?

    public init(
        chargerPower: Int? = nil,
        chargerVoltage: Int? = nil,
        chargerActualCurrent: Int? = nil,
        chargerPhases: Int? = nil,
        fastChargerPresent: Bool? = nil,
        fastChargerBrand: String? = nil,
        fastChargerType: String? = nil
    ) {
        self.chargerPower = chargerPower
        self.chargerVoltage = chargerVoltage
        self.chargerActualCurrent = chargerActualCurrent
        self.chargerPhases = chargerPhases
        self.fastChargerPresent = fastChargerPresent
        self.fastChargerBrand = fastChargerBrand
        self.fastChargerType = fastChargerType
    }
}

public struct ChargeBatteryInfo: Decodable, Equatable, Sendable {
    public let idealBatteryRangeKm: Double?
    public let ratedBatteryRangeKm: Double?
    public let usableBatteryLevel: Int?

    public init(idealBatteryRangeKm: Double? = nil, ratedBatteryRangeKm: Double? = nil, usableBatteryLevel: Int? = nil) {
        self.idealBatteryRangeKm = idealBatteryRangeKm
        self.ratedBatteryRangeKm = ratedBatteryRangeKm
        self.usableBatteryLevel = usableBatteryLevel
    }
}

public enum CurrentChargeOutcome: Equatable, Sendable {
    case active(ChargeDetail)
    case noActiveCharge
}
