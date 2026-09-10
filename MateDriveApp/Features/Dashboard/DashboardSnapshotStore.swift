import CryptoKit
import Foundation

public protocol DashboardSnapshotStoring: Sendable {
    func save(_ snapshot: DashboardSnapshot, serverURL: String) async
    func load(serverURL: String, carId: Int, now: Date) async -> DashboardSnapshot?
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public let savedAt: Date
    public let cars: [DashboardSnapshotCar]
    public let selectedCarId: Int
    public let carName: String
    public let vehicleModelName: String?
    public let batteryLevel: Int?
    public let isCharging: Bool
    public let isLocked: Bool?
    public let sentryModeActive: Bool
    public let outsideTemperature: Double?
    public let insideTemperature: Double?
    public let ratedRange: Double?
    public let odometer: Double?
    public let locationText: String?
    public let latitude: Double?
    public let longitude: Double?
    public let softwareVersion: String?
    public let tpms: DashboardSnapshotTPMS?
    public let exteriorColor: String?
    public let wheelType: String?
    public let trimBadging: String?
    public let units: DashboardSnapshotUnits?
    public let currencyCode: String
    public let totalCharges: Int?
    public let totalDrives: Int?
    public let totalUpdates: Int?
    public let vehicleState: String?
    public let vehicleStateSince: Date?
    public let latestDrive: DashboardLatestDrive?
    public let latestCharge: DashboardLatestCharge?

    public init?(state: DashboardState, savedAt: Date = Date()) {
        guard let selectedCarId = state.selectedCarId else { return nil }
        self.savedAt = savedAt
        self.cars = state.cars.map { DashboardSnapshotCar(id: $0.id, name: $0.name) }
        self.selectedCarId = selectedCarId
        self.carName = state.carName
        self.vehicleModelName = state.vehicleModelName
        self.batteryLevel = state.batteryLevel
        self.isCharging = state.isCharging
        self.isLocked = state.isLocked
        self.sentryModeActive = state.sentryModeActive
        self.outsideTemperature = state.outsideTemperature
        self.insideTemperature = state.insideTemperature
        self.ratedRange = state.ratedRange
        self.odometer = state.odometer
        self.locationText = state.locationText
        self.latitude = state.latitude
        self.longitude = state.longitude
        self.softwareVersion = state.softwareVersion
        self.tpms = state.tpmsDetails.map(DashboardSnapshotTPMS.init)
        self.exteriorColor = state.exteriorColor
        self.wheelType = state.wheelType
        self.trimBadging = state.trimBadging
        self.units = state.units.map(DashboardSnapshotUnits.init)
        self.currencyCode = state.currencyCode
        self.totalCharges = state.totalCharges
        self.totalDrives = state.totalDrives
        self.totalUpdates = state.totalUpdates
        self.vehicleState = state.vehicleState
        self.vehicleStateSince = state.vehicleStateSince
        self.latestDrive = state.latestDrive
        self.latestCharge = state.latestCharge
    }

    public func state(errorMessage: String, now: Date = Date()) -> DashboardState {
        DashboardState(
            isLoading: false,
            cars: cars.map { DashboardCarOption(id: $0.id, name: $0.name) },
            selectedCarId: selectedCarId,
            carName: carName,
            vehicleModelName: vehicleModelName,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            isLocked: isLocked,
            sentryModeActive: sentryModeActive,
            outsideTemperature: outsideTemperature,
            insideTemperature: insideTemperature,
            ratedRange: ratedRange,
            odometer: odometer,
            locationText: locationText,
            latitude: latitude,
            longitude: longitude,
            softwareVersion: softwareVersion,
            tpmsDetails: tpms?.value,
            exteriorColor: exteriorColor,
            wheelType: wheelType,
            trimBadging: trimBadging,
            units: units?.value,
            currencyCode: currencyCode,
            totalCharges: totalCharges,
            totalDrives: totalDrives,
            totalUpdates: totalUpdates,
            vehicleState: vehicleState,
            vehicleStateSince: vehicleStateSince,
            currentSleepDuration: SleepDurationCalculator.currentDuration(
                state: vehicleState,
                stateSince: vehicleStateSince,
                now: now
            ),
            latestDrive: latestDrive,
            latestCharge: latestCharge,
            errorMessage: errorMessage,
            isUsingCachedData: true,
            cachedAt: savedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case savedAt, cars, selectedCarId, carName, vehicleModelName, batteryLevel, isCharging, isLocked
        case sentryModeActive, outsideTemperature, insideTemperature, ratedRange, odometer, locationText
        case latitude, longitude
        case softwareVersion, tpms, exteriorColor, wheelType, trimBadging
        case units, currencyCode, totalCharges, totalDrives, totalUpdates
        case vehicleState, vehicleStateSince, latestDrive, latestCharge
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        cars = try container.decodeIfPresent([DashboardSnapshotCar].self, forKey: .cars) ?? []
        selectedCarId = try container.decode(Int.self, forKey: .selectedCarId)
        carName = try container.decodeIfPresent(String.self, forKey: .carName) ?? "Tesla"
        vehicleModelName = try container.decodeIfPresent(String.self, forKey: .vehicleModelName)
        batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
        sentryModeActive = try container.decodeIfPresent(Bool.self, forKey: .sentryModeActive) ?? false
        outsideTemperature = try container.decodeIfPresent(Double.self, forKey: .outsideTemperature)
        insideTemperature = try container.decodeIfPresent(Double.self, forKey: .insideTemperature)
        ratedRange = try container.decodeIfPresent(Double.self, forKey: .ratedRange)
        odometer = try container.decodeIfPresent(Double.self, forKey: .odometer)
        locationText = try container.decodeIfPresent(String.self, forKey: .locationText)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        softwareVersion = try container.decodeIfPresent(String.self, forKey: .softwareVersion)
        tpms = try container.decodeIfPresent(DashboardSnapshotTPMS.self, forKey: .tpms)
        exteriorColor = try container.decodeIfPresent(String.self, forKey: .exteriorColor)
        wheelType = try container.decodeIfPresent(String.self, forKey: .wheelType)
        trimBadging = try container.decodeIfPresent(String.self, forKey: .trimBadging)
        units = try container.decodeIfPresent(DashboardSnapshotUnits.self, forKey: .units)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode)
            ?? MateDriveCurrencyFormatter.systemCurrencyCode()
        totalCharges = try container.decodeIfPresent(Int.self, forKey: .totalCharges)
        totalDrives = try container.decodeIfPresent(Int.self, forKey: .totalDrives)
        totalUpdates = try container.decodeIfPresent(Int.self, forKey: .totalUpdates)
        vehicleState = try container.decodeIfPresent(String.self, forKey: .vehicleState)
        vehicleStateSince = try container.decodeIfPresent(Date.self, forKey: .vehicleStateSince)
        latestDrive = try container.decodeIfPresent(DashboardLatestDrive.self, forKey: .latestDrive)
        latestCharge = try container.decodeIfPresent(DashboardLatestCharge.self, forKey: .latestCharge)
    }
}

public struct DashboardSnapshotCar: Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
}

public struct DashboardSnapshotUnits: Codable, Equatable, Sendable {
    public let unitOfLength: String?
    public let unitOfTemperature: String?
    public let unitOfPressure: String?

    public init(_ value: UnitPreferences) {
        unitOfLength = value.unitOfLength
        unitOfTemperature = value.unitOfTemperature
        unitOfPressure = value.unitOfPressure
    }

    public var value: UnitPreferences {
        UnitPreferences(unitOfLength: unitOfLength, unitOfTemperature: unitOfTemperature, unitOfPressure: unitOfPressure)
    }
}

public struct DashboardSnapshotTPMS: Codable, Equatable, Sendable {
    public let pressureFl: Double?
    public let pressureFr: Double?
    public let pressureRl: Double?
    public let pressureRr: Double?
    public let warningFl: Bool?
    public let warningFr: Bool?
    public let warningRl: Bool?
    public let warningRr: Bool?

    public init(_ value: TpmsDetails) {
        pressureFl = value.pressureFl
        pressureFr = value.pressureFr
        pressureRl = value.pressureRl
        pressureRr = value.pressureRr
        warningFl = value.warningFl
        warningFr = value.warningFr
        warningRl = value.warningRl
        warningRr = value.warningRr
    }

    public var value: TpmsDetails {
        TpmsDetails(pressureFl: pressureFl, pressureFr: pressureFr, pressureRl: pressureRl, pressureRr: pressureRr, warningFl: warningFl, warningFr: warningFr, warningRl: warningRl, warningRr: warningRr)
    }
}

public final class DashboardSnapshotStore: DashboardSnapshotStoring, @unchecked Sendable {
    public static let shared = DashboardSnapshotStore()
    public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func save(_ snapshot: DashboardSnapshot, serverURL: String) async {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key(serverURL: serverURL, carId: snapshot.selectedCarId))
    }

    public func load(serverURL: String, carId: Int, now: Date = Date()) async -> DashboardSnapshot? {
        guard let data = defaults.data(forKey: Self.key(serverURL: serverURL, carId: carId)),
              let snapshot = try? JSONDecoder().decode(DashboardSnapshot.self, from: data),
              now.timeIntervalSince(snapshot.savedAt) >= 0,
              now.timeIntervalSince(snapshot.savedAt) <= Self.maximumAge
        else { return nil }
        return snapshot
    }

    public func clearAll() async {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("dashboard.snapshot.") {
            defaults.removeObject(forKey: key)
        }
    }

    public func snapshotCount() async -> Int {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("dashboard.snapshot.") }.count
    }

    private static func key(serverURL: String, carId: Int) -> String {
        let canonical = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return "dashboard.snapshot.\(digest).\(carId)"
    }
}

public struct EmptyDashboardSnapshotStore: DashboardSnapshotStoring {
    public init() {}
    public func save(_: DashboardSnapshot, serverURL _: String) async {}
    public func load(serverURL _: String, carId _: Int, now _: Date) async -> DashboardSnapshot? { nil }
}
