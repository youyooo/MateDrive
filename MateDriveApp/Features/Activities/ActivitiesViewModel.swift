import Combine
import Foundation

public enum ActivityFilter: String, CaseIterable, Codable, Hashable, Sendable {
    case all
    case drive
    case charge
    case park
}

public enum ActivityDataSource: String, Codable, Equatable, Sendable {
    case unifiedAPI
    case localFallback
}

public enum ActivityDateFilter: String, CaseIterable, Codable, Hashable, Sendable {
    case all, sevenDays, thirtyDays, thisYear
}

public struct ActivityPeriodSummary: Equatable, Sendable {
    public let activityCount: Int
    public let driveCount: Int
    public let chargeCount: Int
    public let parkingCount: Int
    public let distanceKm: Double?
    public let distanceRecordCount: Int
    public let distanceIsComplete: Bool
    public let chargedEnergyKWh: Double?
    public let chargedEnergyRecordCount: Int
    public let chargedEnergyIsComplete: Bool
    public let drivingEnergyKWh: Double?
    public let drivingEnergyRecordCount: Int
    public let drivingEnergyIsComplete: Bool
    public let knownChargeCost: Double?
    public let pricedChargeCount: Int
    public let missingChargeCostCount: Int
    public let chargeCostIsComplete: Bool
    public let parkingCost: ParkingCostSummary
}

public struct ActivitiesState: Codable, Equatable, Sendable {
    public var isLoading = false
    public var isLoadingMore = false
    public var errorMessage: String?
    public var items: [TeslaMateActivity] = []
    public var filter: ActivityFilter = .all
    public var dateFilter: ActivityDateFilter = .all
    public var locationQuery = ""
    public var hasMore = false
    public var source: ActivityDataSource = .unifiedAPI
    public var paginationIsDegraded = false
    public var isLoadingHistory = false
    public var historyFullyLoaded = false
    public var historyLoadCapped = false
    public var loadedPageCount = 0
    public var historyContinuityAnchorID: String?
    public var currencyCode = MateDriveCurrencyFormatter.systemCurrencyCode()
    public var units: UnitPreferences?
    public var isUsingCachedData = false

    public init() {}
}

@MainActor
public final class ActivitiesViewModel: ObservableObject {
    @Published public private(set) var state: ActivitiesState
    @Published public private(set) var mergeConfiguration: AdjacentDriveMergeConfiguration
    @Published public private(set) var sleepSummaries: [SleepDurationPeriod: SleepDurationSummary] = [:]
    @Published public private(set) var selectedSleepPeriod: SleepDurationPeriod = .today

    private let api: any ActivityAPIProviding
    private let requestedPageSize = 20
    private var carId: Int?
    private var nextPage = 1
    private var seenIDs: Set<String> = []
    private var chargeCostsEnriched = false
    private let now: @Sendable () -> Date
    private let settingsStore: (any SettingsStoring)?
    private let cache: any ActivitiesStateCaching
    private let sleepSummaryProvider: (any DashboardSummaryProviding)?
    private let historyProvider: (any MileageDataProviding)?
    private var parkingFeeRules: [ParkingFeeRule] = []
    private var cacheServerURL: String?

    public init(
        api: any ActivityAPIProviding,
        settingsStore: (any SettingsStoring)? = nil,
        cache: any ActivitiesStateCaching = EmptyActivitiesStateCache(),
        sleepSummaryProvider: (any DashboardSummaryProviding)? = nil,
        historyProvider: (any MileageDataProviding)? = nil,
        initialState: ActivitiesState = ActivitiesState(),
        mergeConfiguration: AdjacentDriveMergeConfiguration = AdjacentDriveMergeConfiguration(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.cache = cache
        self.sleepSummaryProvider = sleepSummaryProvider
        self.historyProvider = historyProvider
        self.state = initialState
        self.mergeConfiguration = mergeConfiguration
        self.now = now
    }

    public var filteredItems: [TeslaMateActivity] {
        let typeFiltered = state.filter == .all
            ? state.items
            : state.items.filter { $0.kind.rawValue == state.filter.rawValue }
        let dateFiltered = typeFiltered.filter { matchesDateFilter($0) }
        let query = state.locationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return dateFiltered }
        return dateFiltered.filter {
            [$0.startAddress, $0.endAddress]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var selectedSleepSummary: SleepDurationSummary? {
        sleepSummaries[selectedSleepPeriod]
    }

    public var periodSummary: ActivityPeriodSummary {
        let items = filteredItems
        let parkingInputs = items.filter { $0.kind == .park }.map {
            ParkingFeeInput(startDate: $0.startDate, address: $0.startAddress, latitude: $0.startLatitude, longitude: $0.startLongitude, durationMinutes: $0.durationMin)
        }
        let charges = items.filter { $0.kind == .charge }
        let drives = items.filter { $0.kind == .drive }
        let distances = drives.compactMap(\.distanceKm)
        let chargedEnergy = charges.compactMap(\.kwh)
        let drivingEnergy = drives.compactMap { $0.kwhUsed ?? $0.kwh.map(abs) }
        let knownChargeCosts = charges.compactMap(\.cost)
        return ActivityPeriodSummary(
            activityCount: items.count,
            driveCount: drives.count,
            chargeCount: charges.count,
            parkingCount: items.filter { $0.kind == .park }.count,
            distanceKm: distances.isEmpty ? nil : distances.reduce(0, +),
            distanceRecordCount: distances.count,
            distanceIsComplete: distances.count == drives.count,
            chargedEnergyKWh: chargedEnergy.isEmpty ? nil : chargedEnergy.reduce(0, +),
            chargedEnergyRecordCount: chargedEnergy.count,
            chargedEnergyIsComplete: chargedEnergy.count == charges.count,
            drivingEnergyKWh: drivingEnergy.isEmpty ? nil : drivingEnergy.reduce(0, +),
            drivingEnergyRecordCount: drivingEnergy.count,
            drivingEnergyIsComplete: drivingEnergy.count == drives.count,
            knownChargeCost: knownChargeCosts.isEmpty ? nil : knownChargeCosts.reduce(0, +),
            pricedChargeCount: knownChargeCosts.count,
            missingChargeCostCount: charges.count - knownChargeCosts.count,
            chargeCostIsComplete: charges.count == knownChargeCosts.count,
            parkingCost: ParkingFeeRuleEngine.summarize(parkingInputs, rules: parkingFeeRules)
        )
    }

    public var periodDateRange: ActivityPeriodDateRange? {
        let dates = filteredItems.flatMap { item -> [Date] in
            [item.startDate, item.endDate].compactMap { value in
                value.flatMap(DomainDateParser.date(from:))
            }
        }
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        return ActivityPeriodDateRange(start: earliest, end: latest)
    }

    public var mappableItems: [TeslaMateActivity] {
        filteredItems.filter {
            GeoCoordinateValidator.location(latitude: $0.startLatitude, longitude: $0.startLongitude) != nil ||
                GeoCoordinateValidator.location(latitude: $0.endLatitude, longitude: $0.endLongitude) != nil
        }
    }

    public var timelineEntries: [ActivityTimelineEntry] {
        AdjacentDriveMerger.entries(from: filteredItems, configuration: mergeConfiguration)
    }

    public var mergedDriveGroupCount: Int {
        timelineEntries.reduce(0) { count, entry in
            if case .mergedDrive = entry { return count + 1 }
            return count
        }
    }

    public func load(carId: Int) async {
        self.carId = carId
        await loadSleepSummaries(carId: carId)
        nextPage = 1
        seenIDs = []
        chargeCostsEnriched = false
        state.errorMessage = nil
        var restoredCache = false
        if let settingsStore {
            let settings = await settingsStore.load()
            parkingFeeRules = settings.parkingFeeRules
            state.currencyCode = settings.resolvedCurrencyCode()
            mergeConfiguration = AdjacentDriveMergeConfiguration(
                isEnabled: settings.mergeAdjacentDrives,
                maximumGapMinutes: settings.adjacentDriveMergeMaximumGapMinutes
            )
            cacheServerURL = settings.serverURL
            if let snapshot = await cache.load(serverURL: settings.serverURL, carId: carId, now: now()) {
                state = snapshot.state
                restoredCache = true
                seenIDs = Set(state.items.map(\.stableID))
                nextPage = max(state.loadedPageCount + 1, 1)
            }
        } else {
            parkingFeeRules = []
            cacheServerURL = nil
        }
        if !restoredCache {
            state.items = []
            state.source = .unifiedAPI
            state.paginationIsDegraded = false
            state.historyFullyLoaded = false
            state.historyLoadCapped = false
            state.loadedPageCount = 0
            state.units = nil
            state.isUsingCachedData = false
        }
        let restoredCompleteHistory = restoredCache && state.historyFullyLoaded
        state.isLoading = true

        switch await api.activities(carId: carId, page: 1, show: requestedPageSize) {
        case let .success(response):
            let emptyResponseHasConflictingMetadata = response.data.isEmpty && (
                (response.pagination?.totalRecords ?? 0) > 0 ||
                    (response.pagination?.totalPages ?? 0) >= 9_999
            )
            if emptyResponseHasConflictingMetadata {
                applyUnits(response.units)
                await loadFallback(carId: carId)
            } else if restoredCache {
                applyUnits(response.units)
                mergeFreshFirstPage(response.data)
                if restoredCompleteHistory {
                    state.hasMore = false
                    state.historyFullyLoaded = true
                    state.historyLoadCapped = false
                }
            } else {
                resetForFreshResponse()
                append(response)
                if state.historyFullyLoaded {
                    await enrichChargeCosts(carId: carId)
                }
            }
        case let .failure(.httpStatus(code)) where code == 404 || code == 405:
            await loadFallback(carId: carId)
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
            if !restoredCache {
                state.hasMore = false
            }
        }
        state.isLoading = false
        if state.errorMessage == nil {
            state.isUsingCachedData = restoredCache
            await persistCache()
        }
    }

    public func loadMoreIfNeeded(currentItem: TeslaMateActivity) async {
        guard state.source == .unifiedAPI,
              state.hasMore,
              !state.isLoadingMore,
              !state.isLoadingHistory,
              currentItem.stableID == filteredItems.last?.stableID,
              carId != nil
        else { return }

        await loadMore()
    }

    public func loadMore() async {
        guard state.source == .unifiedAPI, state.hasMore, !state.isLoading, !state.isLoadingMore, let carId else { return }
        state.isLoadingMore = true
        defer { state.isLoadingMore = false }
        switch await api.activities(carId: carId, page: nextPage, show: requestedPageSize) {
        case let .success(response):
            append(response)
            if state.historyFullyLoaded {
                await enrichChargeCosts(carId: carId)
            }
            await persistCache()
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
            state.hasMore = false
        }
    }

    public func setFilter(_ filter: ActivityFilter) {
        state.filter = filter
    }

    public func setDateFilter(_ filter: ActivityDateFilter) {
        state.dateFilter = filter
    }

    public func setSleepPeriod(_ period: SleepDurationPeriod) {
        selectedSleepPeriod = period
    }

    public func setLocationQuery(_ query: String) {
        state.locationQuery = query
    }

    public func setAdjacentDriveMergingEnabled(_ isEnabled: Bool) async {
        mergeConfiguration.isEnabled = isEnabled
        await persistMergeConfiguration()
    }

    public func setAdjacentDriveMergeMaximumGapMinutes(_ minutes: Int) async {
        mergeConfiguration.maximumGapMinutes = min(max(minutes, 5), 180)
        await persistMergeConfiguration()
    }

    public func loadCompleteHistory(maximumPages: Int = 250) async {
        guard state.source == .unifiedAPI, state.hasMore, !state.isLoadingHistory, !state.isLoadingMore else { return }
        state.isLoadingHistory = true
        state.historyLoadCapped = false
        defer { state.isLoadingHistory = false }
        while state.hasMore, state.loadedPageCount < maximumPages {
            let countBefore = state.items.count
            await loadMore()
            if state.items.count == countBefore { break }
        }
        state.historyLoadCapped = state.hasMore
        state.historyFullyLoaded = !state.hasMore
    }

    private func append(_ response: TeslaMateActivitiesResponse) {
        applyUnits(response.units)
        let pageItems = response.data
        let newItems = pageItems.filter { seenIDs.insert($0.stableID).inserted }
        state.items.append(contentsOf: newItems)
        state.items.sort { activityDate($0) > activityDate($1) }

        let serverLimit = max(response.pagination?.limit ?? requestedPageSize, 1)
        let metadataConflicts = (!pageItems.isEmpty && response.pagination?.totalRecords == 0)
            || (response.pagination?.totalPages ?? 0) >= 9_999
        state.paginationIsDegraded = state.paginationIsDegraded || metadataConflicts
        state.hasMore = pageItems.count >= serverLimit && !newItems.isEmpty
        state.loadedPageCount += 1
        state.historyFullyLoaded = !state.hasMore
        nextPage = (response.pagination?.page ?? nextPage) + 1
    }

    private func resetForFreshResponse() {
        nextPage = 1
        seenIDs = []
        chargeCostsEnriched = false
        state.items = []
        state.source = .unifiedAPI
        state.paginationIsDegraded = false
        state.historyFullyLoaded = false
        state.historyLoadCapped = false
        state.loadedPageCount = 0
        state.units = nil
        state.isUsingCachedData = false
    }

    private func mergeFreshFirstPage(_ freshItems: [TeslaMateActivity]) {
        let freshIDs = Set(freshItems.map(\.stableID))
        state.items.removeAll { freshIDs.contains($0.stableID) }
        state.items.append(contentsOf: freshItems)
        state.items.sort { activityDate($0) > activityDate($1) }
        seenIDs = Set(state.items.map(\.stableID))
        state.loadedPageCount = max(state.loadedPageCount, 1)
    }

    private func persistCache() async {
        guard let carId, let cacheServerURL, !state.items.isEmpty else { return }
        await cache.save(
            ActivitiesCacheSnapshot(state: state, savedAt: now()),
            serverURL: cacheServerURL,
            carId: carId
        )
    }

    private func loadSleepSummaries(carId: Int) async {
        guard let sleepSummaryProvider,
              let summary = try? await sleepSummaryProvider.summary(carId: carId)
        else { return }
        sleepSummaries = summary.sleepSummaries
    }

    private func persistMergeConfiguration() async {
        guard let settingsStore else { return }
        var settings = await settingsStore.load()
        settings.mergeAdjacentDrives = mergeConfiguration.isEnabled
        settings.adjacentDriveMergeMaximumGapMinutes = mergeConfiguration.maximumGapMinutes
        await settingsStore.save(settings)
    }

    private func applyUnits(_ responseUnits: TeslaMateServerStatsUnits?) {
        guard let responseUnits else { return }
        state.units = UnitPreferences(
            unitOfLength: responseUnits.unitOfLength,
            unitOfTemperature: responseUnits.unitOfTemperature,
            unitOfPressure: responseUnits.unitOfPressure
        )
    }

    private func loadFallback(carId: Int) async {
        async let drivesResult = loadFallbackDrives(carId: carId)
        async let chargesResult = loadFallbackCharges(carId: carId)
        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            state.source = .localFallback
            state.items = drives.map(Self.activity(from:)) + charges.map(Self.activity(from:))
            state.items.sort { activityDate($0) > activityDate($1) }
            state.hasMore = false
            state.loadedPageCount = 1
            state.historyFullyLoaded = true
        case let (.failure(error), _), let (_, .failure(error)):
            state.errorMessage = error.analyticsMessage
            state.hasMore = false
        }
    }

    private func loadFallbackDrives(carId: Int) async -> APIResult<[DriveData]> {
        if let historyProvider {
            return await historyProvider.mileageDrives(carId: carId)
        }
        return await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private func loadFallbackCharges(carId: Int) async -> APIResult<[ChargeData]> {
        if let historyProvider {
            return await historyProvider.mileageCharges(carId: carId)
        }
        return await VehicleHistoryPaginator.charges(loadPage: { page, show in
            await self.api.charges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private func enrichChargeCosts(carId: Int) async {
        guard state.source == .unifiedAPI, !chargeCostsEnriched else { return }
        let missingIDs = Set(state.items.filter { $0.kind == .charge && $0.cost == nil }.map(\.id))
        guard !missingIDs.isEmpty else {
            chargeCostsEnriched = true
            return
        }
        guard case let .success(charges) = await loadFallbackCharges(carId: carId) else {
            return
        }
        var costs: [Int: Double] = [:]
        for charge in charges {
            guard let id = charge.chargeId, let cost = charge.cost else { continue }
            costs[id] = cost
        }
        state.items = state.items.map { item in
            guard item.kind == .charge, item.cost == nil, let cost = costs[item.id] else { return item }
            return item.withCost(cost)
        }
        chargeCostsEnriched = true
    }

    private func activityDate(_ activity: TeslaMateActivity) -> Date {
        activity.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
    }

    private func matchesDateFilter(_ activity: TeslaMateActivity) -> Bool {
        guard state.dateFilter != .all else { return true }
        guard let date = activity.startDate.flatMap(DomainDateParser.date(from:)) else { return false }
        let calendar = Calendar(identifier: .gregorian)
        let cutoff: Date?
        switch state.dateFilter {
        case .all: cutoff = nil
        case .sevenDays: cutoff = calendar.date(byAdding: .day, value: -7, to: now())
        case .thirtyDays: cutoff = calendar.date(byAdding: .day, value: -30, to: now())
        case .thisYear: cutoff = calendar.date(from: calendar.dateComponents([.year], from: now()))
        }
        return cutoff.map { date >= $0 } ?? true
    }

    private static func activity(from drive: DriveData) -> TeslaMateActivity {
        TeslaMateActivity(
            id: drive.driveId ?? -1,
            type: "drive",
            startDate: drive.startDate,
            endDate: drive.endDate,
            durationMin: drive.durationMin.map(Double.init),
            startAddress: drive.startAddress,
            endAddress: drive.endAddress,
            startLatitude: nil,
            startLongitude: nil,
            endLatitude: nil,
            endLongitude: nil,
            kwh: drive.usableEnergyConsumedNet.map { -abs($0) },
            kwhUsed: nil,
            cost: nil,
            rangeDiffKm: nil,
            soc: drive.batteryDetails?.endBatteryLevel,
            socDiff: batteryDifference(drive.batteryDetails?.startBatteryLevel, drive.batteryDetails?.endBatteryLevel),
            odometerKm: drive.odometerDetails?.odometerEnd,
            distanceKm: drive.distance,
            endRangeKm: nil
        )
    }

    private static func activity(from charge: ChargeData) -> TeslaMateActivity {
        TeslaMateActivity(
            id: charge.chargeId ?? -1,
            type: "charge",
            startDate: charge.startDate,
            endDate: charge.endDate,
            durationMin: charge.durationMin.map(Double.init),
            startAddress: charge.address,
            endAddress: nil,
            startLatitude: charge.latitude,
            startLongitude: charge.longitude,
            endLatitude: nil,
            endLongitude: nil,
            kwh: charge.chargeEnergyAdded,
            kwhUsed: nil,
            cost: charge.cost,
            rangeDiffKm: nil,
            soc: nil,
            socDiff: nil,
            odometerKm: nil,
            distanceKm: nil,
            endRangeKm: nil
        )
    }

    private static func batteryDifference(_ start: Int?, _ end: Int?) -> Int? {
        guard let start, let end else { return nil }
        return end - start
    }
}
