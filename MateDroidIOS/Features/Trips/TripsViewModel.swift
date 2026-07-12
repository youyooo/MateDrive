import Combine
import Foundation

public struct TripsState: Equatable, Sendable {
    public var isLoading: Bool
    public var trips: [DetectedTrip]
    public var totalDistance: Double
    public var totalDrivingMin: Int
    public var totalEnergyCharged: Double
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
        trips: [DetectedTrip] = [],
        totalDistance: Double = 0,
        totalDrivingMin: Int = 0,
        totalEnergyCharged: Double = 0,
        totalChargeCost: Double? = nil,
        pricedChargeCount: Int = 0,
        totalChargeCount: Int = 0,
        chargeCostIsComplete: Bool = true,
        currencySymbol: String = "€",
        availableYears: [Int] = [],
        selectedYear: Int? = nil,
        units: UnitPreferences? = nil,
        dcChargeIds: Set<Int> = [],
        showShortDrivesCharges: Bool = false,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.trips = trips
        self.totalDistance = totalDistance
        self.totalDrivingMin = totalDrivingMin
        self.totalEnergyCharged = totalEnergyCharged
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

@MainActor
public final class TripsViewModel: ObservableObject {
    @Published public private(set) var state: TripsState

    private let dataProvider: any TripDataProviding
    private let tripStore: any TripPersisting
    private let settingsStore: any SettingsStoring
    private var sourceData: TripSourceData?
    private var allTrips: [DetectedTrip] = []

    public init(
        dataProvider: any TripDataProviding,
        tripStore: any TripPersisting,
        settingsStore: any SettingsStoring,
        initialState: TripsState = TripsState()
    ) {
        self.dataProvider = dataProvider
        self.tripStore = tripStore
        self.settingsStore = settingsStore
        self.state = initialState
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil

        let settings = await settingsStore.load()
        state.showShortDrivesCharges = settings.showShortDrivesCharges
        state.currencySymbol = MateDroidCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())

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
                state.isLoading = false
            } catch {
                state.errorMessage = error.localizedDescription
                state.isLoading = false
            }
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
            state.isLoading = false
        }
    }

    public func setYear(_ year: Int?) {
        state.selectedYear = year
        applyFilter()
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
        state.totalEnergyCharged = filtered.reduce(0) { $0 + $1.totalEnergyCharged }
        let costs = filtered.compactMap(\.totalChargeCost)
        state.totalChargeCost = costs.isEmpty ? nil : costs.reduce(0, +)
        state.pricedChargeCount = filtered.reduce(0) { $0 + $1.pricedChargeCount }
        state.totalChargeCount = filtered.reduce(0) { $0 + $1.charges.count }
        state.chargeCostIsComplete = state.pricedChargeCount == state.totalChargeCount
    }

    private func autoPersistDetectedTrips(carId: Int, data: TripSourceData, saved: [SavedTripSnapshot]) async throws -> [SavedTripSnapshot] {
        let consumed = Set(saved.flatMap(\.consumedFingerprints))
        let existing = Set(saved.map { TripFingerprint.fingerprint(driveIds: $0.legs.driveIds) })
        let suppressed = consumed.union(existing)
        let usedDriveIds = Set(saved.flatMap(\.legs.driveIds))
        let usedChargeIds = Set(saved.flatMap(\.legs.chargeIds))

        let freeDrives = data.drives.filter { !usedDriveIds.contains($0.id) }
        let dcCharges = data.charges.filter { data.dcChargeIds.contains($0.id) && !usedChargeIds.contains($0.id) }
        let detected = TripDetector.detectTrips(drives: freeDrives, dcCharges: dcCharges)
        var created: [SavedTripSnapshot] = []
        for trip in detected {
            let fingerprint = TripFingerprint.fingerprint(trip)
            guard !suppressed.contains(fingerprint) else {
                continue
            }
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
            return TripAggregator.buildTrip(drives: drives, charges: charges, name: snapshot.name)
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
