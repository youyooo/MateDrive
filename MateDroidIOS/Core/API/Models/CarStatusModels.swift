import Foundation

public struct CarStatusResponse: Decodable, Sendable {
    public let data: CarStatusPayload?
    public let error: String?
}

public struct CarStatusPayload: Decodable, Equatable, Sendable {
    public let status: CarStatus?
    public let units: Units?

    public init(status: CarStatus? = nil, units: Units? = nil) {
        self.status = status
        self.units = units
    }
}

public struct Units: Decodable, Equatable, Sendable {
    public let unitOfLength: String?
    public let unitOfPressure: String?
    public let unitOfTemperature: String?

    public init(unitOfLength: String? = nil, unitOfTemperature: String? = nil, unitOfPressure: String? = nil) {
        self.unitOfLength = unitOfLength
        self.unitOfPressure = unitOfPressure
        self.unitOfTemperature = unitOfTemperature
    }

    public var isMetric: Bool { unitOfLength == "km" }
    public var isImperial: Bool { unitOfLength == "mi" }
}

public struct CarStatus: Decodable, Equatable, Sendable {
    public let displayName: String?
    public let state: String?
    public let stateSince: String?
    public let odometer: Double?
    public let carStatus: CarStatusDetails?
    public let carGeodata: CarGeodata?
    public let carVersions: CarVersions?
    public let drivingDetails: DrivingDetails?
    public let climateDetails: ClimateDetails?
    public let batteryDetails: BatteryDetails?
    public let chargingDetails: ChargingDetails?
    public let tpmsDetails: TpmsDetails?

    public init(
        displayName: String? = nil,
        state: String? = nil,
        stateSince: String? = nil,
        odometer: Double? = nil,
        carStatus: CarStatusDetails? = nil,
        carGeodata: CarGeodata? = nil,
        carVersions: CarVersions? = nil,
        drivingDetails: DrivingDetails? = nil,
        climateDetails: ClimateDetails? = nil,
        batteryDetails: BatteryDetails? = nil,
        chargingDetails: ChargingDetails? = nil,
        tpmsDetails: TpmsDetails? = nil
    ) {
        self.displayName = displayName
        self.state = state
        self.stateSince = stateSince
        self.odometer = odometer
        self.carStatus = carStatus
        self.carGeodata = carGeodata
        self.carVersions = carVersions
        self.drivingDetails = drivingDetails
        self.climateDetails = climateDetails
        self.batteryDetails = batteryDetails
        self.chargingDetails = chargingDetails
        self.tpmsDetails = tpmsDetails
    }

    public var batteryLevel: Int? { batteryDetails?.batteryLevel }
    public var usableBatteryLevel: Int? { batteryDetails?.usableBatteryLevel }
    public var ratedBatteryRangeKm: Double? { batteryDetails?.ratedBatteryRange }
    public var estBatteryRangeKm: Double? { batteryDetails?.estBatteryRange }
    public var idealBatteryRangeKm: Double? { batteryDetails?.idealBatteryRange }
    public var pluggedIn: Bool? { chargingDetails?.pluggedIn }
    public var chargingState: String? { chargingDetails?.chargingState }
    public var isCharging: Bool { chargingState?.lowercased() == "charging" }
    public var chargeLimitSoc: Int? { chargingDetails?.chargeLimitSoc }
    public var chargerPower: Int? { isCharging ? chargingDetails?.chargerPower : nil }
    public var acPhases: Int? { chargingDetails?.acPhases }
    public var isDcCharging: Bool { isCharging && (chargingDetails?.isDcCharging ?? false) }
    public var isChargeComplete: Bool { chargingState?.lowercased() == "complete" }
    public var isChargeCompletePluggedIn: Bool { isChargeComplete && pluggedIn == true }
    public var insideTemp: Double? { climateDetails?.insideTemp }
    public var outsideTemp: Double? { climateDetails?.outsideTemp }
    public var geofence: String? {
        let value = carGeodata?.geofence?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }
    public var locationSummary: String? {
        if let geofence { return geofence }
        guard let latitude, let longitude else { return nil }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }
    public var latitude: Double? { hasValidCoordinates ? carGeodata?.latitude : nil }
    public var longitude: Double? { hasValidCoordinates ? carGeodata?.longitude : nil }
    public var locked: Bool? { carStatus?.locked }
    public var sentryMode: Bool? { carStatus?.sentryMode }
    public var centerDisplayState: String? { carStatus?.centerDisplayState }
    public var isSentryAlerted: Bool { centerDisplayState == "7" }
    public var version: String? { carVersions?.version }
    public var updateAvailable: Bool? { carVersions?.updateAvailable }

    private var hasValidCoordinates: Bool {
        GeoCoordinateValidator.location(latitude: carGeodata?.latitude, longitude: carGeodata?.longitude) != nil
    }
}

public struct CarStatusDetails: Decodable, Equatable, Sendable {
    public let healthy: Bool?
    public let locked: Bool?
    public let sentryMode: Bool?
    public let windowsOpen: Bool?
    public let doorsOpen: Bool?
    public let trunkOpen: Bool?
    public let frunkOpen: Bool?
    public let isUserPresent: Bool?
    public let centerDisplayState: String?

    private enum CodingKeys: String, CodingKey {
        case healthy
        case locked
        case sentryMode
        case windowsOpen
        case doorsOpen
        case trunkOpen
        case frunkOpen
        case isUserPresent
        case centerDisplayState
    }

    public init(
        healthy: Bool? = nil,
        locked: Bool? = nil,
        sentryMode: Bool? = nil,
        windowsOpen: Bool? = nil,
        doorsOpen: Bool? = nil,
        trunkOpen: Bool? = nil,
        frunkOpen: Bool? = nil,
        isUserPresent: Bool? = nil,
        centerDisplayState: String? = nil
    ) {
        self.healthy = healthy
        self.locked = locked
        self.sentryMode = sentryMode
        self.windowsOpen = windowsOpen
        self.doorsOpen = doorsOpen
        self.trunkOpen = trunkOpen
        self.frunkOpen = frunkOpen
        self.isUserPresent = isUserPresent
        self.centerDisplayState = centerDisplayState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        healthy = try container.decodeIfPresent(Bool.self, forKey: .healthy)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked)
        sentryMode = try container.decodeIfPresent(Bool.self, forKey: .sentryMode)
        windowsOpen = try container.decodeIfPresent(Bool.self, forKey: .windowsOpen)
        doorsOpen = try container.decodeIfPresent(Bool.self, forKey: .doorsOpen)
        trunkOpen = try container.decodeIfPresent(Bool.self, forKey: .trunkOpen)
        frunkOpen = try container.decodeIfPresent(Bool.self, forKey: .frunkOpen)
        isUserPresent = try container.decodeIfPresent(Bool.self, forKey: .isUserPresent)
        centerDisplayState = try Self.decodeFlexibleString(container, forKey: .centerDisplayState)
    }

    private static func decodeFlexibleString(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

public struct CarGeodata: Decodable, Equatable, Sendable {
    public let geofence: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(geofence: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.geofence = geofence
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct CarVersions: Decodable, Equatable, Sendable {
    public let version: String?
    public let updateAvailable: Bool?
    public let updateVersion: String?

    public init(version: String? = nil, updateAvailable: Bool? = nil, updateVersion: String? = nil) {
        self.version = version
        self.updateAvailable = updateAvailable
        self.updateVersion = updateVersion
    }
}

public struct DrivingDetails: Decodable, Equatable, Sendable {
    public let shiftState: String?
    public let power: Int?
    public let speed: Int?
    public let heading: Int?
    public let elevation: Int?

    public init(shiftState: String? = nil, power: Int? = nil, speed: Int? = nil, heading: Int? = nil, elevation: Int? = nil) {
        self.shiftState = shiftState
        self.power = power
        self.speed = speed
        self.heading = heading
        self.elevation = elevation
    }
}

public struct ClimateDetails: Decodable, Equatable, Sendable {
    public let isClimateOn: Bool?
    public let insideTemp: Double?
    public let outsideTemp: Double?
    public let isPreconditioning: Bool?

    public init(isClimateOn: Bool? = nil, insideTemp: Double? = nil, outsideTemp: Double? = nil, isPreconditioning: Bool? = nil) {
        self.isClimateOn = isClimateOn
        self.insideTemp = insideTemp
        self.outsideTemp = outsideTemp
        self.isPreconditioning = isPreconditioning
    }
}

public struct BatteryDetails: Decodable, Equatable, Sendable {
    public let batteryLevel: Int?
    public let usableBatteryLevel: Int?
    public let estBatteryRange: Double?
    public let ratedBatteryRange: Double?
    public let idealBatteryRange: Double?

    public init(
        batteryLevel: Int? = nil,
        usableBatteryLevel: Int? = nil,
        estBatteryRange: Double? = nil,
        ratedBatteryRange: Double? = nil,
        idealBatteryRange: Double? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.usableBatteryLevel = usableBatteryLevel
        self.estBatteryRange = estBatteryRange
        self.ratedBatteryRange = ratedBatteryRange
        self.idealBatteryRange = idealBatteryRange
    }
}

public struct ChargingDetails: Decodable, Equatable, Sendable {
    public let pluggedIn: Bool?
    public let chargingState: String?
    public let chargeEnergyAdded: Double?
    public let chargeLimitSoc: Int?
    public let chargePortDoorOpen: Bool?
    public let chargerActualCurrent: Int?
    public let chargerPhases: Int?
    public let chargerPower: Int?
    public let chargerVoltage: Int?
    public let chargeCurrentRequest: Int?
    public let chargeCurrentRequestMax: Int?
    public let timeToFullCharge: Double?

    public init(
        pluggedIn: Bool? = nil,
        chargingState: String? = nil,
        chargeEnergyAdded: Double? = nil,
        chargeLimitSoc: Int? = nil,
        chargePortDoorOpen: Bool? = nil,
        chargerActualCurrent: Int? = nil,
        chargerPhases: Int? = nil,
        chargerPower: Int? = nil,
        chargerVoltage: Int? = nil,
        chargeCurrentRequest: Int? = nil,
        chargeCurrentRequestMax: Int? = nil,
        timeToFullCharge: Double? = nil
    ) {
        self.pluggedIn = pluggedIn
        self.chargingState = chargingState
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargeLimitSoc = chargeLimitSoc
        self.chargePortDoorOpen = chargePortDoorOpen
        self.chargerActualCurrent = chargerActualCurrent
        self.chargerPhases = chargerPhases
        self.chargerPower = chargerPower
        self.chargerVoltage = chargerVoltage
        self.chargeCurrentRequest = chargeCurrentRequest
        self.chargeCurrentRequestMax = chargeCurrentRequestMax
        self.timeToFullCharge = timeToFullCharge
    }

    public var isDcCharging: Bool { chargerPhases == 0 }

    public var acPhases: Int? {
        switch chargerPhases {
        case 1:
            return 1
        case 2, 3:
            return 3
        default:
            return nil
        }
    }
}

public struct TpmsDetails: Decodable, Equatable, Sendable {
    public let pressureFl: Double?
    public let pressureFr: Double?
    public let pressureRl: Double?
    public let pressureRr: Double?
    public let warningFl: Bool?
    public let warningFr: Bool?
    public let warningRl: Bool?
    public let warningRr: Bool?

    private enum CodingKeys: String, CodingKey {
        case pressureFl
        case pressureFr
        case pressureRl
        case pressureRr
        case warningFl
        case warningFr
        case warningRl
        case warningRr
        case tpmsPressureFl
        case tpmsPressureFr
        case tpmsPressureRl
        case tpmsPressureRr
        case tpmsSoftWarningFl
        case tpmsSoftWarningFr
        case tpmsSoftWarningRl
        case tpmsSoftWarningRr
    }

    public init(
        pressureFl: Double? = nil,
        pressureFr: Double? = nil,
        pressureRl: Double? = nil,
        pressureRr: Double? = nil,
        warningFl: Bool? = nil,
        warningFr: Bool? = nil,
        warningRl: Bool? = nil,
        warningRr: Bool? = nil
    ) {
        self.pressureFl = pressureFl
        self.pressureFr = pressureFr
        self.pressureRl = pressureRl
        self.pressureRr = pressureRr
        self.warningFl = warningFl
        self.warningFr = warningFr
        self.warningRl = warningRl
        self.warningRr = warningRr
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pressureFl = try container.decodeIfPresent(Double.self, forKey: .pressureFl)
            ?? container.decodeIfPresent(Double.self, forKey: .tpmsPressureFl)
        pressureFr = try container.decodeIfPresent(Double.self, forKey: .pressureFr)
            ?? container.decodeIfPresent(Double.self, forKey: .tpmsPressureFr)
        pressureRl = try container.decodeIfPresent(Double.self, forKey: .pressureRl)
            ?? container.decodeIfPresent(Double.self, forKey: .tpmsPressureRl)
        pressureRr = try container.decodeIfPresent(Double.self, forKey: .pressureRr)
            ?? container.decodeIfPresent(Double.self, forKey: .tpmsPressureRr)
        warningFl = try container.decodeIfPresent(Bool.self, forKey: .warningFl)
            ?? container.decodeIfPresent(Bool.self, forKey: .tpmsSoftWarningFl)
        warningFr = try container.decodeIfPresent(Bool.self, forKey: .warningFr)
            ?? container.decodeIfPresent(Bool.self, forKey: .tpmsSoftWarningFr)
        warningRl = try container.decodeIfPresent(Bool.self, forKey: .warningRl)
            ?? container.decodeIfPresent(Bool.self, forKey: .tpmsSoftWarningRl)
        warningRr = try container.decodeIfPresent(Bool.self, forKey: .warningRr)
            ?? container.decodeIfPresent(Bool.self, forKey: .tpmsSoftWarningRr)
    }

    public var hasAnyData: Bool {
        [pressureFl, pressureFr, pressureRl, pressureRr].contains { $0 != nil } ||
            [warningFl, warningFr, warningRl, warningRr].contains { $0 != nil }
    }

    public var hasWarning: Bool {
        [warningFl, warningFr, warningRl, warningRr].contains(true)
    }
}
