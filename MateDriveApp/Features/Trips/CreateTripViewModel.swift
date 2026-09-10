import Combine
import Foundation

public struct CreateTripState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var hasLoadedData: Bool
    public var isSaving: Bool
    public var name: String
    public var availableDrives: [TripDrive]
    public var availableCharges: [TripCharge]
    public var draftLegs: [TripLegReference]
    public var preview: DetectedTrip?
    public var units: UnitPreferences?
    public var createdStartDate: String?
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        hasLoadedData: Bool = false,
        isSaving: Bool = false,
        name: String = "",
        availableDrives: [TripDrive] = [],
        availableCharges: [TripCharge] = [],
        draftLegs: [TripLegReference] = [],
        preview: DetectedTrip? = nil,
        units: UnitPreferences? = nil,
        createdStartDate: String? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.hasLoadedData = hasLoadedData
        self.isSaving = isSaving
        self.name = name
        self.availableDrives = availableDrives
        self.availableCharges = availableCharges
        self.draftLegs = draftLegs
        self.preview = preview
        self.units = units
        self.createdStartDate = createdStartDate
        self.errorMessage = errorMessage
    }
}

public struct CreateTripPageSnapshot: Sendable {
    public var state: CreateTripState
    public var sourceData: TripSourceData

    public init(state: CreateTripState, sourceData: TripSourceData) {
        self.state = state
        self.sourceData = sourceData
    }
}

@MainActor
public final class CreateTripViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<CreateTripPageSnapshot>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: CreateTripState

    private let tripStore: any TripPersisting
    private let dataProvider: (any TripDataProviding)?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<CreateTripPageSnapshot>
    private var sourceData: TripSourceData?

    public init(
        tripStore: any TripPersisting,
        dataProvider: (any TripDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<CreateTripPageSnapshot>? = nil,
        initialState: CreateTripState = CreateTripState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let restored = cacheKey.flatMap { resolvedStateCache.state(for: $0) }
        self.tripStore = tripStore
        self.dataProvider = dataProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = restored?.state ?? initialState
        self.sourceData = restored?.sourceData
    }

    public func load(carId: Int) async {
        guard let dataProvider, !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        switch await dataProvider.sourceData(carId: carId) {
        case let .success(data):
            let used: [SavedTripSnapshot]
            do {
                used = try await tripStore.savedTrips(carId: carId)
            } catch {
                state.errorMessage = error.localizedDescription
                return
            }
            let usedDriveIds = Set(used.flatMap { $0.legs.compactMap { leg -> Int? in if case let .drive(id) = leg { return id }; return nil } })
            let usedChargeIds = Set(used.flatMap { $0.legs.compactMap { leg -> Int? in if case let .charge(id) = leg { return id }; return nil } })
            state.availableDrives = data.drives.filter { !usedDriveIds.contains($0.id) }
            state.availableCharges = data.charges.filter { !usedChargeIds.contains($0.id) }
            let availableDriveIds = Set(state.availableDrives.map(\.id))
            let availableChargeIds = Set(state.availableCharges.map(\.id))
            state.draftLegs = state.draftLegs.filter { leg in
                switch leg {
                case let .drive(id):
                    return availableDriveIds.contains(id)
                case let .charge(id):
                    return availableChargeIds.contains(id)
                }
            }
            sourceData = data
            state.units = data.units
            state.hasLoadedData = true
            rebuildPreview()
            saveCachedState()
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
    }

    public func setName(_ name: String) {
        state.name = name
        rebuildPreview()
        saveCachedState()
    }

    public func toggleLeg(_ leg: TripLegReference) {
        if state.draftLegs.contains(leg) {
            state.draftLegs.removeAll { $0 == leg }
        } else {
            state.draftLegs.append(leg)
        }
        rebuildPreview()
        saveCachedState()
    }

    public func createTrip(
        carId: Int,
        name: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String> = []
    ) async {
        state.isSaving = true
        state.errorMessage = nil

        let resolved = resolve(legs: legs)
        let sortedLegs = sort(legs: legs, drives: resolved.drives, charges: resolved.charges)
        let preview = JourneySummaryBuilder.makeSummary(
            drives: resolved.drives,
            charges: resolved.charges,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let startDate = preview?.startDate ?? resolved.firstDate ?? "1970-01-01T00:00:00Z"
        let endDate = preview?.endDate ?? resolved.lastDate ?? startDate

        do {
            let snapshot = try await tripStore.saveTrip(
                carId: carId,
                name: name,
                startDate: startDate,
                endDate: endDate,
                legs: sortedLegs,
                consumedFingerprints: consumedFingerprints
            )
            state.createdStartDate = snapshot.startDate
            state.preview = preview
            state.isSaving = false
            if let cacheKey {
                stateCache.remove(for: cacheKey)
            }
        } catch {
            state.errorMessage = error.localizedDescription
            state.isSaving = false
            saveCachedState()
        }
    }

    public func save(carId: Int) async {
        await createTrip(
            carId: carId,
            name: state.name,
            legs: state.draftLegs,
            consumedFingerprints: state.preview.map { Set([TripFingerprint.fingerprint($0)]) } ?? []
        )
    }

    private func rebuildPreview() {
        let resolved = resolve(legs: state.draftLegs)
        state.preview = JourneySummaryBuilder.makeSummary(
            drives: resolved.drives,
            charges: resolved.charges,
            name: state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func saveCachedState() {
        guard let cacheKey, let sourceData, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.isSaving = false
        snapshot.createdStartDate = nil
        snapshot.errorMessage = nil
        stateCache.save(
            CreateTripPageSnapshot(state: snapshot, sourceData: sourceData),
            for: cacheKey
        )
    }

    private func resolve(legs: [TripLegReference]) -> (drives: [TripDrive], charges: [TripCharge], firstDate: String?, lastDate: String?) {
        let driveMap = Dictionary(uniqueKeysWithValues: (sourceData?.drives ?? state.availableDrives).map { ($0.id, $0) })
        let chargeMap = Dictionary(uniqueKeysWithValues: (sourceData?.charges ?? state.availableCharges).map { ($0.id, $0) })
        let drives = legs.compactMap { leg -> TripDrive? in
            if case let .drive(id) = leg { return driveMap[id] }
            return nil
        }.sorted { $0.startDate < $1.startDate }
        let charges = legs.compactMap { leg -> TripCharge? in
            if case let .charge(id) = leg { return chargeMap[id] }
            return nil
        }.sorted { $0.startDate < $1.startDate }
        let dates = (drives.flatMap { [$0.startDate, $0.endDate] } + charges.flatMap { [$0.startDate, $0.endDate] }).sorted()
        return (drives, charges, dates.first, dates.last)
    }

    private func sort(legs: [TripLegReference], drives: [TripDrive], charges: [TripCharge]) -> [TripLegReference] {
        let driveDates = Dictionary(uniqueKeysWithValues: drives.map { ($0.id, $0.startDate) })
        let chargeDates = Dictionary(uniqueKeysWithValues: charges.map { ($0.id, $0.startDate) })
        return legs.distinct().sorted { lhs, rhs in
            startDate(for: lhs, driveDates: driveDates, chargeDates: chargeDates) <
                startDate(for: rhs, driveDates: driveDates, chargeDates: chargeDates)
        }
    }

    private func startDate(for leg: TripLegReference, driveDates: [Int: String], chargeDates: [Int: String]) -> String {
        switch leg {
        case let .drive(id):
            return driveDates[id] ?? ""
        case let .charge(id):
            return chargeDates[id] ?? ""
        }
    }
}

private extension Array where Element: Hashable {
    func distinct() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
