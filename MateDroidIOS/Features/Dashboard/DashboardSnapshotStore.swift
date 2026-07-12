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
    public let softwareVersion: String?
    public let tpms: DashboardSnapshotTPMS?
    public let carImagePath: String?
    public let carImageScaleFactor: Double
    public let exteriorColor: String?
    public let wheelType: String?
    public let trimBadging: String?
    public let units: DashboardSnapshotUnits?
    public let totalCharges: Int?
    public let totalDrives: Int?
    public let totalUpdates: Int?

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
        self.softwareVersion = state.softwareVersion
        self.tpms = state.tpmsDetails.map(DashboardSnapshotTPMS.init)
        self.carImagePath = state.carImagePath
        self.carImageScaleFactor = state.carImageScaleFactor
        self.exteriorColor = state.exteriorColor
        self.wheelType = state.wheelType
        self.trimBadging = state.trimBadging
        self.units = state.units.map(DashboardSnapshotUnits.init)
        self.totalCharges = state.totalCharges
        self.totalDrives = state.totalDrives
        self.totalUpdates = state.totalUpdates
    }

    public func state(errorMessage: String) -> DashboardState {
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
            softwareVersion: softwareVersion,
            tpmsDetails: tpms?.value,
            carImagePath: carImagePath,
            carImageScaleFactor: carImageScaleFactor,
            exteriorColor: exteriorColor,
            wheelType: wheelType,
            trimBadging: trimBadging,
            units: units?.value,
            totalCharges: totalCharges,
            totalDrives: totalDrives,
            totalUpdates: totalUpdates,
            errorMessage: errorMessage,
            isUsingCachedData: true,
            cachedAt: savedAt
        )
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
