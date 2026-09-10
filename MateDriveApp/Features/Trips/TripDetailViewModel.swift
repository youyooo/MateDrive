import Combine
import Foundation

public struct TripEditableLeg: Equatable, Identifiable, Sendable {
    public let reference: TripLegReference
    public let title: String
    public let startDate: String
    public let distanceKm: Double?
    public let energyKWh: Double?
    public let isDC: Bool

    public var id: String { reference.id }
}

public struct TripMergeCandidate: Equatable, Identifiable, Sendable {
    public let snapshot: SavedTripSnapshot
    public let trip: DetectedTrip
    public var id: String { snapshot.tripId }
}

public struct SavedTripRouteSegment: Equatable, Identifiable, Sendable {
    public let driveId: Int
    public let points: [GeocodeLocation]

    public var id: Int { driveId }

    public init(driveId: Int, positions: [DrivePosition]) {
        self.driveId = driveId
        points = GeoCoordinateValidator.sanitizedRoute(positions.map {
            GeocodeRouteSample(latitude: $0.latitude, longitude: $0.longitude, date: $0.date)
        })
    }

    public init(driveId: Int, points: [GeocodeLocation]) {
        self.driveId = driveId
        self.points = points
    }
}

public struct TripCountryStat: Equatable, Identifiable, Sendable {
    public let countryCode: String
    public let canonicalName: String
    public let firstVisitDate: String
    public let driveCount: Int
    public let chargeCount: Int
    public let distanceKm: Double
    public let chargedEnergyKWh: Double?
    public let chargedEnergyKnownCount: Int
    public let missingChargedEnergyCount: Int

    public var chargedEnergyIsComplete: Bool { missingChargedEnergyCount == 0 }

    public var id: String { countryCode }
}

public struct TripCountrySummary: Equatable, Sendable {
    public let countries: [TripCountryStat]
    public let classifiedRecordCount: Int
    public let totalRecordCount: Int

    public var unclassifiedRecordCount: Int { totalRecordCount - classifiedRecordCount }

    public static func build(trip: DetectedTrip) -> TripCountrySummary {
        var accumulators: [String: TripCountryAccumulator] = [:]
        var classified = 0

        for drive in trip.drives {
            guard let country = CountriesVisitedViewModel.country(from: drive.endAddress ?? drive.startAddress) else { continue }
            classified += 1
            accumulators[country.code, default: TripCountryAccumulator(code: country.code, name: country.name)]
                .addDrive(drive)
        }
        for charge in trip.charges {
            guard let country = CountriesVisitedViewModel.country(from: charge.address) else { continue }
            classified += 1
            accumulators[country.code, default: TripCountryAccumulator(code: country.code, name: country.name)]
                .addCharge(charge)
        }

        return TripCountrySummary(
            countries: accumulators.values.map(\.stat).sorted { $0.firstVisitDate < $1.firstVisitDate },
            classifiedRecordCount: classified,
            totalRecordCount: trip.drives.count + trip.charges.count
        )
    }
}

private struct TripCountryAccumulator {
    let code: String
    let name: String
    var firstVisitDate = "9999-12-31T23:59:59Z"
    var driveCount = 0
    var chargeCount = 0
    var distanceKm = 0.0
    var chargedEnergyValues: [Double] = []
    var missingChargedEnergyCount = 0

    mutating func addDrive(_ drive: TripDrive) {
        driveCount += 1
        distanceKm += drive.distance
        firstVisitDate = min(firstVisitDate, drive.startDate)
    }

    mutating func addCharge(_ charge: TripCharge) {
        chargeCount += 1
        if let energyAdded = charge.energyAdded {
            chargedEnergyValues.append(energyAdded)
        } else {
            missingChargedEnergyCount += 1
        }
        firstVisitDate = min(firstVisitDate, charge.startDate)
    }

    var stat: TripCountryStat {
        TripCountryStat(
            countryCode: code,
            canonicalName: name,
            firstVisitDate: firstVisitDate == "9999-12-31T23:59:59Z" ? "" : firstVisitDate,
            driveCount: driveCount,
            chargeCount: chargeCount,
            distanceKm: distanceKm,
            chargedEnergyKWh: chargedEnergyValues.isEmpty ? nil : chargedEnergyValues.reduce(0, +),
            chargedEnergyKnownCount: chargedEnergyValues.count,
            missingChargedEnergyCount: missingChargedEnergyCount
        )
    }
}

public struct TripDetailState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var trip: DetectedTrip?
    public var savedTripId: String?
    public var timeline: [TripTimelineSegment]
    public var routeSegments: [SavedTripRouteSegment]
    public var countrySummary: TripCountrySummary?
    public var editableLegs: [TripEditableLeg]
    public var availableLegs: [TripEditableLeg]
    public var mergeCandidates: [TripMergeCandidate]
    public var dcChargeIds: Set<Int>
    public var showShortDrivesCharges: Bool
    public var units: UnitPreferences?
    public var currencySymbol: String
    public var justDeleted: Bool
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        trip: DetectedTrip? = nil,
        savedTripId: String? = nil,
        timeline: [TripTimelineSegment] = [],
        routeSegments: [SavedTripRouteSegment] = [],
        countrySummary: TripCountrySummary? = nil,
        editableLegs: [TripEditableLeg] = [],
        availableLegs: [TripEditableLeg] = [],
        mergeCandidates: [TripMergeCandidate] = [],
        dcChargeIds: Set<Int> = [],
        showShortDrivesCharges: Bool = false,
        units: UnitPreferences? = nil,
        currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol(),
        justDeleted: Bool = false,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.trip = trip
        self.savedTripId = savedTripId
        self.timeline = timeline
        self.routeSegments = routeSegments
        self.countrySummary = countrySummary
        self.editableLegs = editableLegs
        self.availableLegs = availableLegs
        self.mergeCandidates = mergeCandidates
        self.dcChargeIds = dcChargeIds
        self.showShortDrivesCharges = showShortDrivesCharges
        self.units = units
        self.currencySymbol = currencySymbol
        self.justDeleted = justDeleted
        self.errorMessage = errorMessage
    }
}

public struct TripDetailCacheKey: Hashable, Sendable {
    public let serverURL: String
    public let carId: Int
    public let tripStartDate: String

    public init(serverURL: String, carId: Int, tripStartDate: String) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.carId = carId
        self.tripStartDate = tripStartDate
    }
}

public final class TripDetailStateCache: @unchecked Sendable {
    public static let shared = TripDetailStateCache()

    private let lock = NSLock()
    private let maximumEntryCount: Int
    private var states: [TripDetailCacheKey: TripDetailState] = [:]
    private var recency: [TripDetailCacheKey] = []

    public init(maximumEntryCount: Int = 24) {
        self.maximumEntryCount = max(maximumEntryCount, 1)
    }

    public func state(for key: TripDetailCacheKey) -> TripDetailState? {
        lock.withLock {
            guard let state = states[key] else { return nil }
            markRecentlyUsed(key)
            return state
        }
    }

    public func save(_ state: TripDetailState, for key: TripDetailCacheKey) {
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        lock.withLock {
            states[key] = snapshot
            markRecentlyUsed(key)
            while recency.count > maximumEntryCount, let oldest = recency.first {
                recency.removeFirst()
                states.removeValue(forKey: oldest)
            }
        }
    }

    public func remove(_ key: TripDetailCacheKey) {
        lock.withLock {
            states.removeValue(forKey: key)
            recency.removeAll { $0 == key }
        }
    }

    public func removeAll() {
        lock.withLock {
            states.removeAll()
            recency.removeAll()
        }
    }

    private func markRecentlyUsed(_ key: TripDetailCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

@MainActor
public final class TripDetailViewModel: ObservableObject {
    @Published public private(set) var state: TripDetailState

    private let dataProvider: any TripDataProviding
    private let tripStore: any TripPersisting
    private let settingsStore: any SettingsStoring
    private let cacheKey: TripDetailCacheKey?
    private let stateCache: TripDetailStateCache
    private var loadedSnapshot: SavedTripSnapshot?
    private var loadedSource: TripSourceData?
    private var otherUsedLegs: Set<TripLegReference> = []
    private var loadedSnapshots: [SavedTripSnapshot] = []

    public init(
        dataProvider: any TripDataProviding,
        tripStore: any TripPersisting,
        settingsStore: any SettingsStoring,
        cacheKey: TripDetailCacheKey? = nil,
        stateCache: TripDetailStateCache = .shared,
        initialState: TripDetailState = TripDetailState()
    ) {
        self.dataProvider = dataProvider
        self.tripStore = tripStore
        self.settingsStore = settingsStore
        self.cacheKey = cacheKey
        self.stateCache = stateCache
        self.state = cacheKey.flatMap { stateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int, tripStartDate: String) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.trip == nil
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }

        let settings = await settingsStore.load()
        state.showShortDrivesCharges = settings.showShortDrivesCharges
        state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())

        switch await dataProvider.sourceData(carId: carId) {
        case let .success(source):
            do {
                let snapshots = try await tripStore.savedTrips(carId: carId)
                guard let snapshot = snapshots.first(where: { $0.startDate == tripStartDate }) else {
                    state.trip = nil
                    state.timeline = []
                    state.routeSegments = []
                    state.countrySummary = nil
                    removeCachedState()
                    return
                }
                loadedSnapshot = snapshot
                loadedSource = source
                state.units = source.units
                loadedSnapshots = snapshots
                otherUsedLegs = Set(snapshots.filter { $0.tripId != snapshot.tripId }.flatMap(\.legs))
                state.savedTripId = snapshot.tripId
                state.dcChargeIds = source.dcChargeIds
                apply(snapshot: snapshot, source: source)
                saveCachedState()
                await refreshRoute(carId: carId, snapshot: snapshot)
                saveCachedState()
            } catch {
                if state.trip == nil {
                    state.errorMessage = error.localizedDescription
                }
            }
        case let .failure(error):
            if state.trip == nil {
                state.errorMessage = error.analyticsMessage
            }
        }
    }

    public func rename(_ name: String) async {
        guard let tripId = state.savedTripId else { return }
        do {
            try await tripStore.renameTrip(tripId: tripId, name: name)
            if let snapshot = loadedSnapshot {
                loadedSnapshot = SavedTripSnapshot(
                    tripId: snapshot.tripId,
                    carId: snapshot.carId,
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: snapshot.startDate,
                    endDate: snapshot.endDate,
                    legs: snapshot.legs,
                    consumedFingerprints: snapshot.consumedFingerprints
                )
            }
            if let trip = state.trip {
                state.trip = JourneySummaryBuilder.makeSummary(drives: trip.drives, charges: trip.charges, name: name)
            }
            saveCachedState()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func deleteTrip() async {
        guard let tripId = state.savedTripId else { return }
        do {
            try await tripStore.deleteTrip(tripId: tripId)
            state.justDeleted = true
            state.trip = nil
            removeCachedState()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func removeLeg(_ leg: TripLegReference) async {
        guard let snapshot = loadedSnapshot else { return }
        let remaining = snapshot.legs.filter { $0 != leg }
        guard remaining.contains(where: { if case .drive = $0 { return true }; return false }) else {
            await deleteTrip()
            return
        }
        await persist(legs: remaining, from: snapshot)
    }

    public func addLegs(_ legs: Set<TripLegReference>) async {
        guard let snapshot = loadedSnapshot, !legs.isEmpty else { return }
        let allowed = legs.subtracting(otherUsedLegs)
        let combined = Array(Set(snapshot.legs).union(allowed))
        await persist(legs: combined, from: snapshot)
    }

    public func merge(with candidate: TripMergeCandidate) async {
        guard let current = loadedSnapshot, let source = loadedSource else { return }
        let lowerEnd = min(current.endDate, candidate.snapshot.endDate)
        let upperStart = max(current.startDate, candidate.snapshot.startDate)
        let occupied = Set(current.legs + candidate.snapshot.legs)
        let allReferences = source.drives.map { TripLegReference.drive($0.id) } + source.charges.map { TripLegReference.charge($0.id) }
        let gapLegs = allReferences.filter {
            let date = startDate(for: $0, source: source)
            return !occupied.contains($0) && date >= lowerEnd && date <= upperStart
        }
        let combined = Array(occupied.union(gapLegs)).sorted { startDate(for: $0, source: source) < startDate(for: $1, source: source) }
        guard let preview = trip(from: combined, name: current.name ?? candidate.snapshot.name, source: source) else { return }
        let fingerprints = current.consumedFingerprints
            .union(candidate.snapshot.consumedFingerprints)
            .union([
                TripFingerprint.fingerprint(driveIds: current.legs.driveIds),
                TripFingerprint.fingerprint(driveIds: candidate.snapshot.legs.driveIds)
            ])
        let merged = SavedTripSnapshot(
            tripId: UUID().uuidString,
            carId: current.carId,
            name: current.name ?? candidate.snapshot.name,
            startDate: preview.startDate,
            endDate: preview.endDate,
            legs: combined,
            consumedFingerprints: fingerprints
        )
        do {
            try await tripStore.mergeTrips(keptTripId: current.tripId, consumedTripId: candidate.snapshot.tripId, merged: merged)
            loadedSnapshot = merged
            loadedSnapshots.removeAll { $0.tripId == current.tripId || $0.tripId == candidate.snapshot.tripId }
            loadedSnapshots.append(merged)
            otherUsedLegs = Set(loadedSnapshots.filter { $0.tripId != merged.tripId }.flatMap(\.legs))
            state.savedTripId = merged.tripId
            state.errorMessage = nil
            apply(snapshot: merged, source: source)
            await refreshRoute(carId: merged.carId, snapshot: merged)
            saveCachedState()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func persist(legs: [TripLegReference], from snapshot: SavedTripSnapshot) async {
        guard let source = loadedSource else { return }
        let sorted = legs.sorted { startDate(for: $0, source: source) < startDate(for: $1, source: source) }
        let preview = trip(from: sorted, name: snapshot.name, source: source)
        guard let preview else {
            state.errorMessage = "A trip must contain at least one drive."
            return
        }
        do {
            let previousFingerprint = TripFingerprint.fingerprint(driveIds: snapshot.legs.driveIds)
            let consumed = snapshot.consumedFingerprints.union([previousFingerprint])
            try await tripStore.updateTrip(
                tripId: snapshot.tripId,
                name: snapshot.name,
                startDate: preview.startDate,
                endDate: preview.endDate,
                legs: sorted,
                consumedFingerprints: consumed
            )
            let updated = SavedTripSnapshot(
                tripId: snapshot.tripId,
                carId: snapshot.carId,
                name: snapshot.name,
                startDate: preview.startDate,
                endDate: preview.endDate,
                legs: sorted,
                consumedFingerprints: consumed
            )
            loadedSnapshot = updated
            state.savedTripId = updated.tripId
            state.errorMessage = nil
            apply(snapshot: updated, source: source)
            await refreshRoute(carId: updated.carId, snapshot: updated)
            saveCachedState()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func apply(snapshot: SavedTripSnapshot, source: TripSourceData) {
        let trip = TripsViewModel.buildTrips(from: [snapshot], source: source).first
        state.trip = trip
        state.countrySummary = trip.map(TripCountrySummary.build)
        state.timeline = trip.map {
            TripTimelineBuilder.build(
                trip: $0,
                dcChargeIds: source.dcChargeIds,
                showShort: state.showShortDrivesCharges
            )
        } ?? []
        state.editableLegs = snapshot.legs.compactMap { editableLeg(for: $0, source: source) }
        let unavailable = Set(snapshot.legs).union(otherUsedLegs)
        let window = candidateWindow(for: snapshot)
        let candidates = source.drives.map { TripLegReference.drive($0.id) } + source.charges.map { TripLegReference.charge($0.id) }
        state.availableLegs = candidates
            .filter { reference in
                guard !unavailable.contains(reference), let window else { return false }
                guard let date = DomainDateParser.date(from: startDate(for: reference, source: source)) else { return false }
                return date >= window.start && date <= window.end
            }
            .compactMap { editableLeg(for: $0, source: source) }
            .sorted { $0.startDate < $1.startDate }
        state.mergeCandidates = loadedSnapshots
            .filter { $0.tripId != snapshot.tripId && isAdjacent($0, to: snapshot) }
            .compactMap { candidate in
                TripsViewModel.buildTrips(from: [candidate], source: source).first.map {
                    TripMergeCandidate(snapshot: candidate, trip: $0)
                }
            }
            .sorted { $0.snapshot.startDate < $1.snapshot.startDate }
    }

    private func refreshRoute(carId: Int, snapshot: SavedTripSnapshot) async {
        let driveIds = snapshot.legs.compactMap { reference -> Int? in
            if case let .drive(id) = reference { return id }
            return nil
        }
        state.routeSegments = await dataProvider.routeSegments(carId: carId, driveIds: driveIds)
            .filter { $0.points.count >= 2 }
    }

    private func saveCachedState() {
        guard let cacheKey else { return }
        stateCache.save(state, for: cacheKey)
    }

    private func removeCachedState() {
        guard let cacheKey else { return }
        stateCache.remove(cacheKey)
    }

    private func isAdjacent(_ candidate: SavedTripSnapshot, to current: SavedTripSnapshot) -> Bool {
        guard
            let candidateStart = DomainDateParser.date(from: candidate.startDate),
            let candidateEnd = DomainDateParser.date(from: candidate.endDate),
            let currentStart = DomainDateParser.date(from: current.startDate),
            let currentEnd = DomainDateParser.date(from: current.endDate)
        else { return false }
        let gap = candidateEnd < currentStart ? currentStart.timeIntervalSince(candidateEnd) : candidateStart.timeIntervalSince(currentEnd)
        return gap >= 0 && gap <= 2 * 24 * 60 * 60
    }

    private func candidateWindow(for snapshot: SavedTripSnapshot) -> (start: Date, end: Date)? {
        guard
            let first = DomainDateParser.date(from: snapshot.startDate),
            let last = DomainDateParser.date(from: snapshot.endDate)
        else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        guard
            let start = calendar.date(byAdding: .day, value: -2, to: first),
            let end = calendar.date(byAdding: .day, value: 2, to: last)
        else { return nil }
        return (start, end)
    }

    private func editableLeg(for reference: TripLegReference, source: TripSourceData) -> TripEditableLeg? {
        switch reference {
        case let .drive(id):
            guard let drive = source.drives.first(where: { $0.id == id }) else { return nil }
            let start = drive.startAddress?.split(separator: ",").first.map(String.init)
            let end = drive.endAddress?.split(separator: ",").first.map(String.init)
            let title = [start, end].compactMap { $0 }.joined(separator: " → ")
            return TripEditableLeg(reference: reference, title: title, startDate: drive.startDate, distanceKm: drive.distance, energyKWh: nil, isDC: false)
        case let .charge(id):
            guard let charge = source.charges.first(where: { $0.id == id }) else { return nil }
            let title = charge.address?.split(separator: ",").first.map(String.init) ?? ""
            return TripEditableLeg(reference: reference, title: title, startDate: charge.startDate, distanceKm: nil, energyKWh: charge.energyAdded, isDC: source.dcChargeIds.contains(id))
        }
    }

    private func trip(from legs: [TripLegReference], name: String?, source: TripSourceData) -> DetectedTrip? {
        let snapshot = SavedTripSnapshot(tripId: "preview", carId: 0, name: name, startDate: "", endDate: "", legs: legs)
        return TripsViewModel.buildTrips(from: [snapshot], source: source).first
    }

    private func startDate(for leg: TripLegReference, source: TripSourceData) -> String {
        switch leg {
        case let .drive(id): source.drives.first { $0.id == id }?.startDate ?? ""
        case let .charge(id): source.charges.first { $0.id == id }?.startDate ?? ""
        }
    }
}

private extension Array where Element == TripLegReference {
    var driveIds: [Int] {
        compactMap {
            if case let .drive(id) = $0 { return id }
            return nil
        }
    }
}
