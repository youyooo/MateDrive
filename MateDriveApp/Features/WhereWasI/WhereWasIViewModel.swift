import Combine
import Foundation

public enum CarActivityState: String, Sendable {
    case driving = "Driving"
    case charging = "Charging"
    case parked = "Parked"
}

public struct WhereWasIState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var errorMessage: String?
    public var carState: CarActivityState?
    public var latitude: Double?
    public var longitude: Double?
    public var odometer: Double?
    public var outsideTemp: Double?
    public var units: UnitPreferences?
    public var driveId: Int?
    public var speed: Int?
    public var driveDistance: Double?
    public var chargeId: Int?
    public var batteryLevel: Int?
    public var chargerPower: Int?
    public var parkedDurationMinutes: Int?
    public var parkedSince: String?
    public var lastActivityDriveId: Int?
    public var lastActivityChargeId: Int?
    public var targetDateTime: String?
    public var geofenceName: String?

    public init(isLoading: Bool = true, isRefreshing: Bool = false, errorMessage: String? = nil, carState: CarActivityState? = nil, latitude: Double? = nil, longitude: Double? = nil, odometer: Double? = nil, outsideTemp: Double? = nil, units: UnitPreferences? = nil, driveId: Int? = nil, speed: Int? = nil, driveDistance: Double? = nil, chargeId: Int? = nil, batteryLevel: Int? = nil, chargerPower: Int? = nil, parkedDurationMinutes: Int? = nil, parkedSince: String? = nil, lastActivityDriveId: Int? = nil, lastActivityChargeId: Int? = nil, targetDateTime: String? = nil, geofenceName: String? = nil) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.carState = carState
        self.latitude = latitude
        self.longitude = longitude
        self.odometer = odometer
        self.outsideTemp = outsideTemp
        self.units = units
        self.driveId = driveId
        self.speed = speed
        self.driveDistance = driveDistance
        self.chargeId = chargeId
        self.batteryLevel = batteryLevel
        self.chargerPower = chargerPower
        self.parkedDurationMinutes = parkedDurationMinutes
        self.parkedSince = parkedSince
        self.lastActivityDriveId = lastActivityDriveId
        self.lastActivityChargeId = lastActivityChargeId
        self.targetDateTime = targetDateTime
        self.geofenceName = geofenceName
    }
}

@MainActor
public final class WhereWasIViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<WhereWasIState>(maximumEntryCount: 24)

    @Published public private(set) var state: WhereWasIState

    private let api: any AnalyticsAPIProviding
    private let historyProvider: (any MileageDataProviding)?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<WhereWasIState>

    public init(
        api: any AnalyticsAPIProviding,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<WhereWasIState>? = nil,
        initialState: WhereWasIState = WhereWasIState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int, timestamp: String) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.carState == nil
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        guard let target = DomainDateParser.date(from: timestamp) else {
            state.errorMessage = "Invalid date"
            return
        }
        state.targetDateTime = target.formatted(date: .abbreviated, time: .shortened)

        async let drivesResult = loadDrives(carId: carId)
        async let chargesResult = loadCharges(carId: carId)
        async let unitsResult = loadUnits(carId: carId)

        if case let .success(units) = await unitsResult {
            state.units = units
        }

        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            if let drive = drives.first(where: { contains(target, start: $0.startDate, end: $0.endDate) }) {
                await handleDriving(carId: carId, drive: drive, target: target)
            } else if let charge = charges.first(where: { contains(target, start: $0.startDate, end: $0.endDate) }) {
                await handleCharging(carId: carId, charge: charge, target: target)
            } else {
                handleParked(drives: drives, charges: charges, target: target)
                saveCachedState()
            }
        case let (.failure(error), _), let (_, .failure(error)):
            state.errorMessage = error.analyticsMessage
        }
    }

    private func loadDrives(carId: Int) async -> APIResult<[DriveData]> {
        if let historyProvider {
            return await historyProvider.mileageDrives(carId: carId)
        }
        return await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private func loadCharges(carId: Int) async -> APIResult<[ChargeData]> {
        if let historyProvider {
            return await historyProvider.mileageCharges(carId: carId)
        }
        return await VehicleHistoryPaginator.charges(loadPage: { page, show in
            await self.api.charges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private func loadUnits(carId: Int) async -> APIResult<UnitPreferences?> {
        if let historyProvider {
            return await historyProvider.mileageUnits(carId: carId)
        }
        switch await api.carStatus(carId: carId) {
        case let .success(payload):
            return .success(UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            ))
        case let .failure(error):
            return .failure(error)
        }
    }

    private func handleDriving(carId: Int, drive: DriveData, target: Date) async {
        state.carState = .driving
        state.driveId = drive.driveId
        state.driveDistance = drive.distance
        state.outsideTemp = drive.outsideTempAvg
        state.odometer = drive.odometerDetails?.odometerEnd
        state.geofenceName = drive.endAddress
        state.isLoading = false
        saveCachedState()

        var nearest: DrivePosition?
        if let driveId = drive.driveId, case let .success(detail) = await api.driveDetail(carId: carId, driveId: driveId) {
            nearest = detail.positions?.min { lhs, rhs in
                abs((lhs.date.flatMap(DomainDateParser.date(from:))?.timeIntervalSince(target) ?? .greatestFiniteMagnitude)) <
                    abs((rhs.date.flatMap(DomainDateParser.date(from:))?.timeIntervalSince(target) ?? .greatestFiniteMagnitude))
                }
        }
        state.speed = nearest?.speed
        state.latitude = nearest?.latitude
        state.longitude = nearest?.longitude
        state.outsideTemp = nearest?.outsideTemp ?? state.outsideTemp
        saveCachedState()
    }

    private func handleCharging(carId: Int, charge: ChargeData, target: Date) async {
        state.carState = .charging
        state.chargeId = charge.chargeId
        state.latitude = charge.latitude
        state.longitude = charge.longitude
        state.batteryLevel = charge.endBatteryLevel
        state.chargerPower = charge.chargerPower.map(Int.init)
        state.outsideTemp = charge.outsideTempAvg
        state.odometer = charge.odometer
        state.geofenceName = charge.address
        state.isLoading = false
        saveCachedState()

        var nearest: ChargePoint?
        if let chargeId = charge.chargeId, case let .success(detail) = await api.chargeDetail(carId: carId, chargeId: chargeId) {
            nearest = detail.chargePoints?.min { lhs, rhs in
                abs((lhs.date.flatMap(DomainDateParser.date(from:))?.timeIntervalSince(target) ?? .greatestFiniteMagnitude)) <
                    abs((rhs.date.flatMap(DomainDateParser.date(from:))?.timeIntervalSince(target) ?? .greatestFiniteMagnitude))
                }
        }
        state.batteryLevel = nearest?.batteryLevel ?? state.batteryLevel
        state.chargerPower = nearest?.chargerPower ?? state.chargerPower
        state.outsideTemp = nearest?.outsideTemp ?? state.outsideTemp
        saveCachedState()
    }

    private func handleParked(drives: [DriveData], charges: [ChargeData], target: Date) {
        let driveEvents = drives.compactMap { drive -> (Date, DriveData)? in
            guard let end = drive.endDate.flatMap(DomainDateParser.date(from:)), end <= target else { return nil }
            return (end, drive)
        }
        let chargeEvents = charges.compactMap { charge -> (Date, ChargeData)? in
            guard let end = charge.endDate.flatMap(DomainDateParser.date(from:)), end <= target else { return nil }
            return (end, charge)
        }
        let lastDrive = driveEvents.max { $0.0 < $1.0 }
        let lastCharge = chargeEvents.max { $0.0 < $1.0 }
        state.carState = .parked
        state.isLoading = false
        switch (lastDrive, lastCharge) {
        case let (drive?, charge?) where drive.0 >= charge.0:
            applyParkedSince(drive.0, target: target)
            state.lastActivityDriveId = drive.1.driveId
            state.geofenceName = drive.1.endAddress
            state.odometer = drive.1.odometerDetails?.odometerEnd
        case let (_, charge?):
            applyParkedSince(charge.0, target: target)
            state.lastActivityChargeId = charge.1.chargeId
            state.geofenceName = charge.1.address
            state.odometer = charge.1.odometer
        case let (drive?, nil):
            applyParkedSince(drive.0, target: target)
            state.lastActivityDriveId = drive.1.driveId
            state.geofenceName = drive.1.endAddress
            state.odometer = drive.1.odometerDetails?.odometerEnd
        default:
            state.parkedDurationMinutes = nil
        }
    }

    private func applyParkedSince(_ date: Date, target: Date) {
        state.parkedSince = date.formatted(date: .abbreviated, time: .shortened)
        state.parkedDurationMinutes = max(Int(target.timeIntervalSince(date) / 60), 0)
    }

    private func contains(_ target: Date, start: String?, end: String?) -> Bool {
        guard let start = start.flatMap(DomainDateParser.date(from:)),
              let end = end.flatMap(DomainDateParser.date(from:))
        else { return false }
        return start <= target && target <= end
    }

    private func saveCachedState() {
        guard let cacheKey, state.carState != nil else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }
}
