import Foundation

public enum DriveEnergyValueValidator {
    public static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else {
            return nil
        }
        return value
    }
}

public struct DrivesResponse: Decodable, Sendable {
    public let data: DrivesPayload?
    public let error: String?
}

public struct DrivesPayload: Decodable, Sendable {
    public let drives: [DriveData]
}

public struct DriveDetailResponse: Decodable, Sendable {
    public let data: DriveDetailPayload?
    public let error: String?
}

public struct DriveDetailPayload: Decodable, Sendable {
    public let car: DriveDetailCar?
    public let drive: DriveDetail?
    public let units: Units?

    enum CodingKeys: String, CodingKey {
        case car
        case drive
        case units
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        car = try container.decodeIfPresent(DriveDetailCar.self, forKey: .car)
        units = try container.decodeIfPresent(Units.self, forKey: .units)
        var decodedDrive = try container.decodeIfPresent(DriveDetail.self, forKey: .drive)
        decodedDrive?.sourceUnits = units
        drive = decodedDrive
    }
}

public struct DriveData: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int { driveId ?? -1 }
    public var distance: Double? { odometerDetails?.distance ?? rawDistance }
    public var startBatteryLevel: Int? { batteryDetails?.startBatteryLevel }
    public var endBatteryLevel: Int? { batteryDetails?.endBatteryLevel }
    public var efficiencyWhKm: Double? {
        guard let distance, distance > 0, let energy = DriveEnergyValueValidator.positiveFinite(energyConsumedNet) else {
            return DriveEnergyValueValidator.positiveFinite(consumptionNet)
        }
        return energy * 1000 / distance
    }
    public var usableEnergyConsumedNet: Double? { DriveEnergyValueValidator.positiveFinite(energyConsumedNet) }
    public var usableConsumptionNet: Double? { DriveEnergyValueValidator.positiveFinite(consumptionNet) }

    public let driveId: Int?
    public let carId: Int?
    public let startDate: String?
    public let endDate: String?
    public let durationMin: Int?
    public let durationStr: String?
    public let startAddress: String?
    public let endAddress: String?
    public let averageSpeed: Double?
    public let speedMax: Int?
    public let speedAvg: Double?
    public let powerMax: Int?
    public let powerMin: Int?
    public let odometerDetails: DriveOdometerDetails?
    public let batteryDetails: DriveBatteryDetails?
    public let rangeIdeal: DriveRange?
    public let rangeRated: DriveRange?
    public let outsideTempAvg: Double?
    public let insideTempAvg: Double?
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?
    private let rawDistance: Double?

    enum CodingKeys: String, CodingKey {
        case driveId
        case carId
        case startDate
        case endDate
        case distance
        case durationMin
        case durationStr
        case startAddress
        case endAddress
        case averageSpeed
        case speedMax
        case speedAvg
        case powerMax
        case powerMin
        case odometerDetails
        case batteryDetails
        case rangeIdeal
        case rangeRated
        case outsideTempAvg
        case insideTempAvg
        case energyConsumedNet
        case consumptionNet
    }

    public init(
        driveId: Int?,
        carId: Int? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        distance: Double? = nil,
        durationMin: Int? = nil,
        durationStr: String? = nil,
        startAddress: String? = nil,
        endAddress: String? = nil,
        averageSpeed: Double? = nil,
        speedMax: Int? = nil,
        speedAvg: Double? = nil,
        powerMax: Int? = nil,
        powerMin: Int? = nil,
        odometerDetails: DriveOdometerDetails? = nil,
        batteryDetails: DriveBatteryDetails? = nil,
        rangeIdeal: DriveRange? = nil,
        rangeRated: DriveRange? = nil,
        outsideTempAvg: Double? = nil,
        insideTempAvg: Double? = nil,
        energyConsumedNet: Double? = nil,
        consumptionNet: Double? = nil
    ) {
        self.driveId = driveId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.rawDistance = distance
        self.durationMin = durationMin
        self.durationStr = durationStr
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.averageSpeed = averageSpeed
        self.speedMax = speedMax
        self.speedAvg = speedAvg
        self.powerMax = powerMax
        self.powerMin = powerMin
        self.odometerDetails = odometerDetails
        self.batteryDetails = batteryDetails
        self.rangeIdeal = rangeIdeal
        self.rangeRated = rangeRated
        self.outsideTempAvg = outsideTempAvg
        self.insideTempAvg = insideTempAvg
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        driveId = try container.decodeIfPresent(Int.self, forKey: .driveId)
        carId = try container.decodeIfPresent(Int.self, forKey: .carId)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        rawDistance = try container.decodeIfPresent(Double.self, forKey: .distance)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        durationStr = try container.decodeIfPresent(String.self, forKey: .durationStr)
        startAddress = try container.decodeIfPresent(String.self, forKey: .startAddress)
        endAddress = try container.decodeIfPresent(String.self, forKey: .endAddress)
        averageSpeed = try container.decodeIfPresent(Double.self, forKey: .averageSpeed)
        speedMax = try container.decodeIfPresent(Int.self, forKey: .speedMax)
        speedAvg = try container.decodeIfPresent(Double.self, forKey: .speedAvg)
        powerMax = try container.decodeIfPresent(Int.self, forKey: .powerMax)
        powerMin = try container.decodeIfPresent(Int.self, forKey: .powerMin)
        odometerDetails = try container.decodeIfPresent(DriveOdometerDetails.self, forKey: .odometerDetails)
        batteryDetails = try container.decodeIfPresent(DriveBatteryDetails.self, forKey: .batteryDetails)
        rangeIdeal = try container.decodeIfPresent(DriveRange.self, forKey: .rangeIdeal)
        rangeRated = try container.decodeIfPresent(DriveRange.self, forKey: .rangeRated)
        outsideTempAvg = try container.decodeIfPresent(Double.self, forKey: .outsideTempAvg)
        insideTempAvg = try container.decodeIfPresent(Double.self, forKey: .insideTempAvg)
        energyConsumedNet = try container.decodeIfPresent(Double.self, forKey: .energyConsumedNet)
        consumptionNet = try container.decodeIfPresent(Double.self, forKey: .consumptionNet)
    }
}

public struct DriveOdometerDetails: Decodable, Equatable, Sendable {
    public let odometerStart: Double?
    public let odometerEnd: Double?
    public let distance: Double?

    enum CodingKeys: String, CodingKey {
        case odometerStart
        case odometerEnd
        case distance = "odometerDistance"
    }

    public init(odometerStart: Double? = nil, odometerEnd: Double? = nil, distance: Double? = nil) {
        self.odometerStart = odometerStart
        self.odometerEnd = odometerEnd
        self.distance = distance
    }
}

public struct DriveBatteryDetails: Decodable, Equatable, Sendable {
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let isRangeIdeal: Bool?

    public init(startBatteryLevel: Int? = nil, endBatteryLevel: Int? = nil, isRangeIdeal: Bool? = nil) {
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.isRangeIdeal = isRangeIdeal
    }
}

public struct DriveRange: Decodable, Equatable, Sendable {
    public let startRange: Double?
    public let endRange: Double?
    public let rangeDiff: Double?

    public init(startRange: Double? = nil, endRange: Double? = nil, rangeDiff: Double? = nil) {
        self.startRange = startRange
        self.endRange = endRange
        self.rangeDiff = rangeDiff
    }
}

public struct DriveDetailCar: Decodable, Equatable, Sendable {
    public let carId: Int?
    public let carName: String?

    public init(carId: Int? = nil, carName: String? = nil) {
        self.carId = carId
        self.carName = carName
    }
}

public struct DriveDetail: Decodable, Equatable, Identifiable, Sendable {
    public var id: Int { driveId }
    public var distance: Double? { odometerDetails?.distance ?? rawDistance }
    public var startBatteryLevel: Int? { batteryDetails?.startBatteryLevel }
    public var endBatteryLevel: Int? { batteryDetails?.endBatteryLevel }
    public var usableEnergyConsumedNet: Double? { DriveEnergyValueValidator.positiveFinite(energyConsumedNet) }
    public var usableConsumptionNet: Double? { DriveEnergyValueValidator.positiveFinite(consumptionNet) }

    public let driveId: Int
    public let startDate: String?
    public let endDate: String?
    public let startAddress: String?
    public let endAddress: String?
    public let odometerDetails: DriveOdometerDetails?
    public let durationMin: Int?
    public let durationStr: String?
    public let speedMax: Int?
    public let speedAvg: Double?
    public let powerMax: Int?
    public let powerMin: Int?
    public let batteryDetails: DriveBatteryDetails?
    public let rangeIdeal: DriveRange?
    public let rangeRated: DriveRange?
    public let outsideTempAvg: Double?
    public let insideTempAvg: Double?
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?
    public let positions: [DrivePosition]?
    public internal(set) var sourceUnits: Units?
    private let rawDistance: Double?

    enum CodingKeys: String, CodingKey {
        case driveId
        case startDate
        case endDate
        case startAddress
        case endAddress
        case odometerDetails
        case durationMin
        case durationStr
        case speedMax
        case speedAvg
        case powerMax
        case powerMin
        case batteryDetails
        case rangeIdeal
        case rangeRated
        case outsideTempAvg
        case insideTempAvg
        case energyConsumedNet
        case consumptionNet
        case driveDetails
        case positions
        case distance
    }

    public init(
        driveId: Int,
        startDate: String? = nil,
        endDate: String? = nil,
        startAddress: String? = nil,
        endAddress: String? = nil,
        odometerDetails: DriveOdometerDetails? = nil,
        distance: Double? = nil,
        durationMin: Int? = nil,
        durationStr: String? = nil,
        speedMax: Int? = nil,
        speedAvg: Double? = nil,
        powerMax: Int? = nil,
        powerMin: Int? = nil,
        batteryDetails: DriveBatteryDetails? = nil,
        rangeIdeal: DriveRange? = nil,
        rangeRated: DriveRange? = nil,
        outsideTempAvg: Double? = nil,
        insideTempAvg: Double? = nil,
        energyConsumedNet: Double? = nil,
        consumptionNet: Double? = nil,
        positions: [DrivePosition]? = nil,
        sourceUnits: Units? = nil
    ) {
        self.driveId = driveId
        self.startDate = startDate
        self.endDate = endDate
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.odometerDetails = odometerDetails
        self.rawDistance = distance
        self.durationMin = durationMin
        self.durationStr = durationStr
        self.speedMax = speedMax
        self.speedAvg = speedAvg
        self.powerMax = powerMax
        self.powerMin = powerMin
        self.batteryDetails = batteryDetails
        self.rangeIdeal = rangeIdeal
        self.rangeRated = rangeRated
        self.outsideTempAvg = outsideTempAvg
        self.insideTempAvg = insideTempAvg
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
        self.positions = positions
        self.sourceUnits = sourceUnits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        driveId = try container.decode(Int.self, forKey: .driveId)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(String.self, forKey: .endDate)
        startAddress = try container.decodeIfPresent(String.self, forKey: .startAddress)
        endAddress = try container.decodeIfPresent(String.self, forKey: .endAddress)
        odometerDetails = try container.decodeIfPresent(DriveOdometerDetails.self, forKey: .odometerDetails)
        rawDistance = try container.decodeIfPresent(Double.self, forKey: .distance)
        durationMin = try container.decodeIfPresent(Int.self, forKey: .durationMin)
        durationStr = try container.decodeIfPresent(String.self, forKey: .durationStr)
        speedMax = try container.decodeIfPresent(Int.self, forKey: .speedMax)
        speedAvg = try container.decodeIfPresent(Double.self, forKey: .speedAvg)
        powerMax = try container.decodeIfPresent(Int.self, forKey: .powerMax)
        powerMin = try container.decodeIfPresent(Int.self, forKey: .powerMin)
        batteryDetails = try container.decodeIfPresent(DriveBatteryDetails.self, forKey: .batteryDetails)
        rangeIdeal = try container.decodeIfPresent(DriveRange.self, forKey: .rangeIdeal)
        rangeRated = try container.decodeIfPresent(DriveRange.self, forKey: .rangeRated)
        outsideTempAvg = try container.decodeIfPresent(Double.self, forKey: .outsideTempAvg)
        insideTempAvg = try container.decodeIfPresent(Double.self, forKey: .insideTempAvg)
        energyConsumedNet = try container.decodeIfPresent(Double.self, forKey: .energyConsumedNet)
        consumptionNet = try container.decodeIfPresent(Double.self, forKey: .consumptionNet)
        positions = try container.decodeIfPresent([DrivePosition].self, forKey: .driveDetails)
            ?? container.decodeIfPresent([DrivePosition].self, forKey: .positions)
        sourceUnits = nil
    }
}

public struct DrivePosition: Decodable, Equatable, Sendable {
    public let date: String?
    public let latitude: Double?
    public let longitude: Double?
    public let speed: Int?
    public let power: Int?
    public let batteryLevel: Int?
    public let elevation: Int?
    public let tpmsPressureFl: Double?
    public let tpmsPressureFr: Double?
    public let tpmsPressureRl: Double?
    public let tpmsPressureRr: Double?
    public let tirePressureGap: Double?
    public let climateInfo: DriveClimateInfo?
    public let batteryInfo: DriveBatteryInfo?

    public var insideTemp: Double? { climateInfo?.insideTemp }
    public var outsideTemp: Double? { climateInfo?.outsideTemp }
    public var isClimateOn: Bool { climateInfo?.isClimateOn == true }
    public var isBatteryHeaterOn: Bool { batteryInfo?.batteryHeater == true || batteryInfo?.batteryHeaterOn == true }

    public init(
        date: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        speed: Int? = nil,
        power: Int? = nil,
        batteryLevel: Int? = nil,
        elevation: Int? = nil,
        tpmsPressureFl: Double? = nil,
        tpmsPressureFr: Double? = nil,
        tpmsPressureRl: Double? = nil,
        tpmsPressureRr: Double? = nil,
        tirePressureGap: Double? = nil,
        climateInfo: DriveClimateInfo? = nil,
        batteryInfo: DriveBatteryInfo? = nil
    ) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.power = power
        self.batteryLevel = batteryLevel
        self.elevation = elevation
        self.tpmsPressureFl = tpmsPressureFl
        self.tpmsPressureFr = tpmsPressureFr
        self.tpmsPressureRl = tpmsPressureRl
        self.tpmsPressureRr = tpmsPressureRr
        self.tirePressureGap = tirePressureGap
        self.climateInfo = climateInfo
        self.batteryInfo = batteryInfo
    }
}

public struct DriveBatteryInfo: Decodable, Equatable, Sendable {
    public let batteryHeater: Bool?
    public let batteryHeaterOn: Bool?
    public let batteryHeaterNoPower: Bool?

    public init(batteryHeater: Bool? = nil, batteryHeaterOn: Bool? = nil, batteryHeaterNoPower: Bool? = nil) {
        self.batteryHeater = batteryHeater
        self.batteryHeaterOn = batteryHeaterOn
        self.batteryHeaterNoPower = batteryHeaterNoPower
    }
}

public struct DriveClimateInfo: Decodable, Equatable, Sendable {
    public let insideTemp: Double?
    public let outsideTemp: Double?
    public let isClimateOn: Bool?
    public let fanStatus: Int?
    public let driverTempSetting: Double?
    public let passengerTempSetting: Double?

    public init(insideTemp: Double? = nil, outsideTemp: Double? = nil, isClimateOn: Bool? = nil, fanStatus: Int? = nil, driverTempSetting: Double? = nil, passengerTempSetting: Double? = nil) {
        self.insideTemp = insideTemp
        self.outsideTemp = outsideTemp
        self.isClimateOn = isClimateOn
        self.fanStatus = fanStatus
        self.driverTempSetting = driverTempSetting
        self.passengerTempSetting = passengerTempSetting
    }
}
