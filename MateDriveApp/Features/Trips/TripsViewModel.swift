import Combine
import Foundation

public enum TripEnergyPresentation {
    public static func text(_ value: Double?, isComplete: Bool) -> String {
        guard let value else { return "--" }
        return (isComplete ? "" : "≥") + String(format: "%.1f kWh", value)
    }
}

public enum JourneyCandidateDetector {
    private static let microDriveThresholdKm = 1.0
    private static let minimumTripDistanceKm = 300.0
    private static let maxDriveToChargeGapMin = 15
    private static let maxChargeToDriveGapMin = 180
    private static let maxDriveToDriveGapMin = 30

    private enum Event {
        case drive(TripDrive)
        case charge(TripCharge)

        var startDate: String {
            switch self {
            case let .drive(drive): drive.startDate
            case let .charge(charge): charge.startDate
            }
        }

        var endDate: String {
            switch self {
            case let .drive(drive): drive.endDate
            case let .charge(charge): charge.endDate
            }
        }
    }

    public static func detectTrips(drives: [TripDrive], dcCharges: [TripCharge]) -> [DetectedTrip] {
        let realDrives = drives.filter { $0.distance >= microDriveThresholdKm }
        var events = realDrives.map(Event.drive) + dcCharges.map(Event.charge)
        events.sort {
            (DomainDateParser.date(from: $0.startDate) ?? .distantPast) <
                (DomainDateParser.date(from: $1.startDate) ?? .distantPast)
        }

        var trips: [DetectedTrip] = []
        var currentDrives: [TripDrive] = []
        var currentCharges: [TripCharge] = []
        var lastEventEnd: Date?
        var lastWasDrive = false

        for event in events {
            guard let eventStart = DomainDateParser.date(from: event.startDate) else { continue }
            guard let previousEnd = lastEventEnd else {
                if case let .drive(drive) = event {
                    currentDrives.append(drive)
                    lastEventEnd = DomainDateParser.date(from: event.endDate)
                    lastWasDrive = true
                }
                continue
            }

            let gapMinutes = Int(eventStart.timeIntervalSince(previousEnd) / 60)
            switch (lastWasDrive, event) {
            case (true, let .charge(charge)) where gapMinutes <= maxDriveToChargeGapMin:
                currentCharges.append(charge)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = false
            case (false, let .drive(drive)) where gapMinutes <= maxChargeToDriveGapMin:
                currentDrives.append(drive)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = true
            case (true, let .drive(drive)) where gapMinutes <= maxDriveToDriveGapMin:
                currentDrives.append(drive)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = true
            case (false, let .charge(charge)) where gapMinutes <= maxChargeToDriveGapMin:
                currentCharges.append(charge)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = false
            default:
                emitTrip(drives: currentDrives, charges: currentCharges, into: &trips)
                currentDrives = []
                currentCharges = []
                lastEventEnd = nil
                lastWasDrive = false
                if case let .drive(drive) = event {
                    currentDrives.append(drive)
                    lastEventEnd = DomainDateParser.date(from: event.endDate)
                    lastWasDrive = true
                }
            }
        }

        emitTrip(drives: currentDrives, charges: currentCharges, into: &trips)
        return trips
    }

    private static func emitTrip(
        drives: [TripDrive],
        charges: [TripCharge],
        into trips: inout [DetectedTrip]
    ) {
        guard drives.count >= 2, !charges.isEmpty else { return }
        guard drives.reduce(0, { $0 + $1.distance }) >= minimumTripDistanceKm else { return }
        if let trip = JourneySummaryBuilder.makeSummary(drives: drives, charges: charges) {
            trips.append(trip)
        }
    }
}

public struct TripsState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var hasLoadedData: Bool
    public var trips: [DetectedTrip]
    public var totalDistance: Double
    public var totalDrivingMin: Int
    public var totalEnergyCharged: Double?
    public var chargedEnergyKnownCount: Int
    public var missingChargedEnergyCount: Int
    public var chargedEnergyIsComplete: Bool
    public var totalChargeCost: Double?
    public var pricedChargeCount: Int
    public var totalChargeCount: Int
    public var chargeCostIsComplete: Bool
    public var currencySymbol: String
    public var availableYears: [Int]
    public var selectedYear: Int?
    public var units: UnitPreferences?
    public var dcChargeIds: Set<Int>
    public var showShortDrivesCharges: Bool
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        hasLoadedData: Bool = false,
        trips: [DetectedTrip] = [],
        totalDistance: Double = 0,
        totalDrivingMin: Int = 0,
        totalEnergyCharged: Double? = nil,
        chargedEnergyKnownCount: Int = 0,
        missingChargedEnergyCount: Int = 0,
        chargedEnergyIsComplete: Bool = true,
        totalChargeCost: Double? = nil,
        pricedChargeCount: Int = 0,
        totalChargeCount: Int = 0,
        chargeCostIsComplete: Bool = true,
        currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol(),
        availableYears: [Int] = [],
        selectedYear: Int? = nil,
        units: UnitPreferences? = nil,
        dcChargeIds: Set<Int> = [],
        showShortDrivesCharges: Bool = false,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.hasLoadedData = hasLoadedData
        self.trips = trips
        self.totalDistance = totalDistance
        self.totalDrivingMin = totalDrivingMin
        self.totalEnergyCharged = totalEnergyCharged
        self.chargedEnergyKnownCount = chargedEnergyKnownCount
        self.missingChargedEnergyCount = missingChargedEnergyCount
        self.chargedEnergyIsComplete = chargedEnergyIsComplete
        self.totalChargeCost = totalChargeCost
        self.pricedChargeCount = pricedChargeCount
        self.totalChargeCount = totalChargeCount
        self.chargeCostIsComplete = chargeCostIsComplete
        self.currencySymbol = currencySymbol
        self.availableYears = availableYears
        self.selectedYear = selectedYear
        self.units = units
        self.dcChargeIds = dcChargeIds
        self.showShortDrivesCharges = showShortDrivesCharges
        self.errorMessage = errorMessage
    }
}

public struct TripsPageSnapshot: Sendable {
    public var state: TripsState
    public var sourceData: TripSourceData?
    public var allTrips: [DetectedTrip]

    public init(
        state: TripsState,
        sourceData: TripSourceData?,
        allTrips: [DetectedTrip]
    ) {
        self.state = state
        self.sourceData = sourceData
        self.allTrips = allTrips
    }
}

@MainActor
public final class TripsViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<TripsPageSnapshot>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: TripsState

    private let dataProvider: any TripDataProviding
    private let tripStore: any TripPersisting
    private let settingsStore: any SettingsStoring
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<TripsPageSnapshot>
    private var sourceData: TripSourceData?
    private var allTrips: [DetectedTrip] = []
    private var carId: Int?

    public init(
        dataProvider: any TripDataProviding,
        tripStore: any TripPersisting,
        settingsStore: any SettingsStoring,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<TripsPageSnapshot>? = nil,
        initialState: TripsState = TripsState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let restored = cacheKey.flatMap { resolvedStateCache.state(for: $0) }
        self.dataProvider = dataProvider
        self.tripStore = tripStore
        self.settingsStore = settingsStore
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = restored?.state ?? initialState
        self.sourceData = restored?.sourceData
        self.allTrips = restored?.allTrips ?? []
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        self.carId = carId
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }

        let settings = await settingsStore.load()
        state.showShortDrivesCharges = settings.showShortDrivesCharges
        state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())

        switch await dataProvider.sourceData(carId: carId) {
        case let .success(data):
            sourceData = data
            state.units = data.units
            state.dcChargeIds = data.dcChargeIds
            do {
                var snapshots = try await tripStore.savedTrips(carId: carId)
                let created = try await autoPersistDetectedTrips(carId: carId, data: data, saved: snapshots)
                snapshots.append(contentsOf: created)
                allTrips = Self.buildTrips(from: snapshots, source: data).sorted { $0.startDate > $1.startDate }
                state.availableYears = Self.availableYears(in: allTrips)
                applyFilter()
                state.hasLoadedData = true
                saveCachedState()
            } catch {
                state.errorMessage = error.localizedDescription
            }
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
    }

    public func setYear(_ year: Int?) {
        state.selectedYear = year
        applyFilter()
        saveCachedState()
    }

    public func refresh() async {
        guard let carId else { return }
        await load(carId: carId)
    }

    private func applyFilter() {
        let filtered: [DetectedTrip]
        if let selectedYear = state.selectedYear {
            filtered = allTrips.filter { Self.year(from: $0.startDate) == selectedYear }
        } else {
            filtered = allTrips
        }
        state.trips = filtered
        state.totalDistance = filtered.reduce(0) { $0 + $1.totalDistance }
        state.totalDrivingMin = filtered.reduce(0) { $0 + $1.totalDrivingDurationMin }
        let chargedEnergies = filtered.compactMap(\.totalEnergyCharged)
        state.totalEnergyCharged = chargedEnergies.isEmpty ? nil : chargedEnergies.reduce(0, +)
        state.chargedEnergyKnownCount = filtered.reduce(0) { $0 + $1.chargedEnergyKnownCount }
        state.missingChargedEnergyCount = filtered.reduce(0) { $0 + $1.missingChargedEnergyCount }
        state.chargedEnergyIsComplete = state.missingChargedEnergyCount == 0
        let costs = filtered.compactMap(\.totalChargeCost)
        state.totalChargeCost = costs.isEmpty ? nil : costs.reduce(0, +)
        state.pricedChargeCount = filtered.reduce(0) { $0 + $1.pricedChargeCount }
        state.totalChargeCount = filtered.reduce(0) { $0 + $1.charges.count }
        state.chargeCostIsComplete = state.pricedChargeCount == state.totalChargeCount
    }

    private func saveCachedState() {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(
            TripsPageSnapshot(
                state: snapshot,
                sourceData: sourceData,
                allTrips: allTrips
            ),
            for: cacheKey
        )
    }

    private func autoPersistDetectedTrips(
        carId: Int,
        data: TripSourceData,
        saved: [SavedTripSnapshot]
    ) async throws -> [SavedTripSnapshot] {
        let consumed = Set(saved.flatMap(\.consumedFingerprints))
        let existing = Set(saved.map { TripFingerprint.fingerprint(driveIds: $0.legs.driveIds) })
        let suppressed = consumed.union(existing)
        let usedDriveIds = Set(saved.flatMap(\.legs.driveIds))
        let usedChargeIds = Set(saved.flatMap(\.legs.chargeIds))

        let freeDrives = data.drives.filter { !usedDriveIds.contains($0.id) }
        let dcCharges = data.charges.filter {
            data.dcChargeIds.contains($0.id) && !usedChargeIds.contains($0.id)
        }
        let detected = JourneyCandidateDetector.detectTrips(drives: freeDrives, dcCharges: dcCharges)
        var created: [SavedTripSnapshot] = []
        for trip in detected {
            let fingerprint = TripFingerprint.fingerprint(trip)
            guard !suppressed.contains(fingerprint) else { continue }
            let snapshot = try await tripStore.saveTrip(
                carId: carId,
                name: nil,
                startDate: trip.startDate,
                endDate: trip.endDate,
                legs: Self.legs(from: trip),
                consumedFingerprints: [fingerprint]
            )
            created.append(snapshot)
        }
        return created
    }

    public static func buildTrips(from snapshots: [SavedTripSnapshot], source: TripSourceData) -> [DetectedTrip] {
        let drivesById = Dictionary(uniqueKeysWithValues: source.drives.map { ($0.id, $0) })
        let chargesById = Dictionary(uniqueKeysWithValues: source.charges.map { ($0.id, $0) })
        return snapshots.compactMap { snapshot in
            let drives = snapshot.legs.compactMap { leg -> TripDrive? in
                if case let .drive(id) = leg { return drivesById[id] }
                return nil
            }.sorted { $0.startDate < $1.startDate }
            let charges = snapshot.legs.compactMap { leg -> TripCharge? in
                if case let .charge(id) = leg { return chargesById[id] }
                return nil
            }.sorted { $0.startDate < $1.startDate }
            return JourneySummaryBuilder.makeSummary(drives: drives, charges: charges, name: snapshot.name)
        }
    }

    public static func legs(from trip: DetectedTrip) -> [TripLegReference] {
        enum Event {
            case drive(TripDrive)
            case charge(TripCharge)

            var startDate: String {
                switch self {
                case let .drive(drive): drive.startDate
                case let .charge(charge): charge.startDate
                }
            }

            var leg: TripLegReference {
                switch self {
                case let .drive(drive): .drive(drive.id)
                case let .charge(charge): .charge(charge.id)
                }
            }
        }

        return (trip.drives.map(Event.drive) + trip.charges.map(Event.charge))
            .sorted { $0.startDate < $1.startDate }
            .map(\.leg)
    }

    private static func availableYears(in trips: [DetectedTrip]) -> [Int] {
        Array(Set(trips.compactMap { year(from: $0.startDate) })).sorted(by: >)
    }

    private static func year(from dateString: String) -> Int? {
        guard let date = DomainDateParser.date(from: dateString) else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: date)
    }

}

private extension Array where Element == TripLegReference {
    var driveIds: [Int] {
        compactMap {
            if case let .drive(id) = $0 { return id }
            return nil
        }
    }

    var chargeIds: [Int] {
        compactMap {
            if case let .charge(id) = $0 { return id }
            return nil
        }
    }
}
