import Combine
import Foundation

public enum DriveChartGranularity: String, Equatable, Sendable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
}

public enum DriveDistanceFilter: String, CaseIterable, Equatable, Sendable {
    case all = "All"
    case commute = "Commute"
    case dayTrip = "Day Trip"
    case roadTrip = "Road Trip"

    var minDistanceKm: Double? {
        switch self {
        case .all, .commute:
            return nil
        case .dayTrip:
            return 10
        case .roadTrip:
            return 100
        }
    }

    var maxDistanceKm: Double? {
        switch self {
        case .all, .roadTrip:
            return nil
        case .commute:
            return 10
        case .dayTrip:
            return 100
        }
    }

    func title(language: AppLanguage) -> String {
        let chinese: String
        switch self {
        case .all:
            chinese = "全部"
        case .commute:
            chinese = "通勤"
        case .dayTrip:
            chinese = "短途"
        case .roadTrip:
            chinese = "长途"
        }
        return AppText.localized(rawValue, chinese, language: language)
    }
}

public enum DriveDateFilter: String, CaseIterable, Equatable, Sendable {
    case today = "Today"
    case last7Days = "7 Days"
    case last30Days = "30 Days"
    case last90Days = "90 Days"
    case lastYear = "Year"
    case allTime = "All Time"

    var dayCount: Int? {
        switch self {
        case .today:
            return 1
        case .last7Days:
            return 7
        case .last30Days:
            return 30
        case .last90Days:
            return 90
        case .lastYear:
            return 365
        case .allTime:
            return nil
        }
    }

    func title(language: AppLanguage) -> String {
        let chinese: String
        switch self {
        case .today:
            chinese = "今天"
        case .last7Days:
            chinese = "7 天"
        case .last30Days:
            chinese = "30 天"
        case .last90Days:
            chinese = "90 天"
        case .lastYear:
            chinese = "一年"
        case .allTime:
            chinese = "全部"
        }
        return AppText.localized(rawValue, chinese, language: language)
    }
}

public struct DriveSummaryItem: Equatable, Identifiable, Sendable {
    public var id: Int { driveId }

    public let driveId: Int
    public let carId: Int
    public let startDate: String
    public let endDate: String?
    public let distance: Double?
    public let durationMin: Int?
    public let startAddress: String?
    public let endAddress: String?
    public let speedMax: Int?
    public let speedAvg: Double?
    public let energyConsumedNet: Double?
    public let efficiency: Double?
    public let efficiencySource: DriveEnergySource
    public let outsideTempAvg: Double?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let routeFingerprint: DriveRouteFingerprint?
    public let climateOnFraction: Double?
    public let elevationGainM: Double?
    public let elevationLossM: Double?
    public let isCached: Bool

    public var ratedRangeDropKm: Double? {
        DriveRange(startRange: startRatedRangeKm, endRange: endRatedRangeKm).usedDistance
    }

    public init(
        driveId: Int,
        carId: Int,
        startDate: String,
        endDate: String? = nil,
        distance: Double?,
        durationMin: Int?,
        startAddress: String? = nil,
        endAddress: String? = nil,
        speedMax: Int? = nil,
        speedAvg: Double? = nil,
        energyConsumedNet: Double? = nil,
        efficiency: Double? = nil,
        efficiencySource: DriveEnergySource = .unavailable,
        outsideTempAvg: Double? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        routeFingerprint: DriveRouteFingerprint? = nil,
        climateOnFraction: Double? = nil,
        elevationGainM: Double? = nil,
        elevationLossM: Double? = nil,
        isCached: Bool = false
    ) {
        self.driveId = driveId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.durationMin = durationMin
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.speedMax = speedMax
        self.speedAvg = speedAvg
        self.energyConsumedNet = energyConsumedNet
        self.efficiency = efficiency
        self.efficiencySource = efficiencySource
        self.outsideTempAvg = outsideTempAvg
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.startRatedRangeKm = startRatedRangeKm
        self.endRatedRangeKm = endRatedRangeKm
        self.routeFingerprint = routeFingerprint
        self.climateOnFraction = climateOnFraction
        self.elevationGainM = elevationGainM
        self.elevationLossM = elevationLossM
        self.isCached = isCached
    }

    public init(data: DriveData, carId fallbackCarId: Int) {
        self.init(
            driveId: data.driveId ?? -1,
            carId: data.carId ?? fallbackCarId,
            startDate: data.startDate ?? "",
            endDate: data.endDate,
            distance: data.distance,
            durationMin: data.durationMin,
            startAddress: data.startAddress,
            endAddress: data.endAddress,
            speedMax: data.speedMax,
            speedAvg: data.speedAvg ?? data.averageSpeed,
            energyConsumedNet: data.usableEnergyConsumedNet,
            efficiency: data.efficiencyWhKm,
            efficiencySource: data.usableEnergyConsumedNet != nil || data.efficiencyWhKm != nil ? .api : .unavailable,
            outsideTempAvg: data.outsideTempAvg,
            startBatteryLevel: data.startBatteryLevel,
            endBatteryLevel: data.endBatteryLevel,
            startRatedRangeKm: data.rangeRated?.startRange,
            endRatedRangeKm: data.rangeRated?.endRange
        )
    }

    public init(record: DriveSummaryRecord) {
        let source = record.energySource.flatMap(DriveEnergySource.init(rawValue:))
            ?? (record.energyConsumedNet != nil || record.consumptionNet != nil ? .api : .unavailable)
        let efficiency = record.consumptionNet ?? record.distance.flatMap { distance in
            guard distance > 0, let energy = record.energyConsumedNet else { return nil }
            return energy * 1000 / distance
        }
        let routeFingerprint = record.routeFingerprintJSON
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(DriveRouteFingerprint.self, from: $0) }
        self.init(
            driveId: record.driveId,
            carId: record.carId,
            startDate: record.startDate,
            endDate: record.endDate,
            distance: record.distance,
            durationMin: record.durationMin,
            startAddress: record.startAddress,
            endAddress: record.endAddress,
            speedAvg: record.speedAvg,
            energyConsumedNet: record.energyConsumedNet,
            efficiency: efficiency,
            efficiencySource: source,
            outsideTempAvg: record.outsideTempAvg,
            startBatteryLevel: record.startBatteryLevel,
            endBatteryLevel: record.endBatteryLevel,
            startRatedRangeKm: record.startRatedRangeKm,
            endRatedRangeKm: record.endRatedRangeKm,
            routeFingerprint: routeFingerprint,
            climateOnFraction: record.climateOnFraction,
            elevationGainM: record.elevationGainM,
            elevationLossM: record.elevationLossM,
            isCached: true
        )
    }
}

public struct DriveRow: Equatable, Identifiable, Sendable {
    public var id: Int { driveId }

    public let driveId: Int
    public let startDate: String
    public let endDate: String?
    public let distance: Double?
    public let durationMin: Int?
    public let startAddress: String?
    public let endAddress: String?
    public let speedAvg: Double?
    public let efficiency: Double?
    public let efficiencySource: DriveEnergySource
    public let outsideTempAvg: Double?
    public let ratedRangeDropKm: Double?
    public let climateOnFraction: Double?
    public let elevationGainM: Double?
    public let elevationLossM: Double?
    public let intelligence: DriveIntelligenceResult?
}

public struct DrivesSummary: Equatable, Sendable {
    public let totalDrives: Int
    public let totalDistanceKm: Double?
    public let distanceRecordCount: Int
    public let distanceIsComplete: Bool
    public let totalRatedRangeDropKm: Double?
    public let ratedRangeRecordCount: Int
    public let ratedRangeIsComplete: Bool
    public let totalDurationMin: Int?
    public let durationRecordCount: Int
    public let durationIsComplete: Bool
    public let avgDistancePerDrive: Double?
    public let avgDurationPerDrive: Int?
    public let maxSpeedKmh: Int?
    public let avgEfficiencyWhKm: Double?
    public let efficiencyRecordCount: Int
    public let efficiencyIsComplete: Bool
    public let reconstructedEfficiencyCount: Int

    public static let empty = DrivesSummary(
        totalDrives: 0,
        totalDistanceKm: nil,
        distanceRecordCount: 0,
        distanceIsComplete: true,
        totalRatedRangeDropKm: nil,
        ratedRangeRecordCount: 0,
        ratedRangeIsComplete: true,
        totalDurationMin: nil,
        durationRecordCount: 0,
        durationIsComplete: true,
        avgDistancePerDrive: nil,
        avgDurationPerDrive: nil,
        maxSpeedKmh: nil,
        avgEfficiencyWhKm: nil,
        efficiencyRecordCount: 0,
        efficiencyIsComplete: true,
        reconstructedEfficiencyCount: 0
    )
}

public struct DriveChartPoint: Equatable, Identifiable, Sendable {
    public var id: String { label }

    public let label: String
    public let count: Int
    public let totalDistance: Double?
    public let distanceRecordCount: Int
    public let distanceIsComplete: Bool
    public let totalRatedRangeDrop: Double?
    public let ratedRangeRecordCount: Int
    public let ratedRangeIsComplete: Bool
    public let totalDurationMin: Int
    public let maxSpeed: Int
}

public struct DrivesState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var rows: [DriveRow]
    public var summary: DrivesSummary
    public var chartData: [DriveChartPoint]
    public var chartGranularity: DriveChartGranularity
    public var dateFilter: DriveDateFilter
    public var distanceFilter: DriveDistanceFilter
    public var units: UnitPreferences?
    public var errorMessage: String?
    public var isUsingCachedData: Bool

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        rows: [DriveRow] = [],
        summary: DrivesSummary = .empty,
        chartData: [DriveChartPoint] = [],
        chartGranularity: DriveChartGranularity = .monthly,
        dateFilter: DriveDateFilter = .last7Days,
        distanceFilter: DriveDistanceFilter = .all,
        units: UnitPreferences? = nil,
        errorMessage: String? = nil,
        isUsingCachedData: Bool = false
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.rows = rows
        self.summary = summary
        self.chartData = chartData
        self.chartGranularity = chartGranularity
        self.dateFilter = dateFilter
        self.distanceFilter = distanceFilter
        self.units = units
        self.errorMessage = errorMessage
        self.isUsingCachedData = isUsingCachedData
    }
}

public protocol DriveSummaryProviding: Sendable {
    func cachedDriveSummaries(carId: Int) async -> [DriveSummaryItem]
    func driveSummaries(carId: Int) async -> APIResult<[DriveSummaryItem]>
    func driveUnits(carId: Int) async -> APIResult<UnitPreferences?>
    func enrichDriveSummaries(_ summaries: [DriveSummaryItem], carId: Int) async -> [DriveSummaryItem]
}

public extension DriveSummaryProviding {
    func cachedDriveSummaries(carId _: Int) async -> [DriveSummaryItem] {
        []
    }

    func enrichDriveSummaries(_ summaries: [DriveSummaryItem], carId _: Int) async -> [DriveSummaryItem] {
        summaries
    }
}

public protocol DriveSummaryCaching: Sendable {
    func load(carId: Int) async -> [DriveSummaryItem]
    func save(_ items: [DriveSummaryItem], carId: Int) async
}

public struct DatabaseBackedDriveSummaryCache: DriveSummaryCaching {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func load(carId: Int) async -> [DriveSummaryItem] {
        guard let database = try? await databaseProvider.database(),
              let records = try? await DriveSummaryStore(database: database).records(carId: carId)
        else { return [] }
        return records.map(DriveSummaryItem.init(record:))
    }

    public func save(_ items: [DriveSummaryItem], carId: Int) async {
        guard let database = try? await databaseProvider.database() else { return }
        let records = items.map { item in
            DriveSummaryRecord(
                driveId: item.driveId,
                carId: carId,
                startDate: item.startDate,
                endDate: item.endDate ?? "",
                distance: item.distance,
                durationMin: item.durationMin,
                energyConsumedNet: item.energyConsumedNet,
                consumptionNet: item.efficiency,
                energySource: item.efficiencySource.rawValue,
                startBatteryLevel: item.startBatteryLevel,
                endBatteryLevel: item.endBatteryLevel,
                startRatedRangeKm: item.startRatedRangeKm,
                endRatedRangeKm: item.endRatedRangeKm,
                startAddress: item.startAddress,
                endAddress: item.endAddress,
                speedAvg: item.speedAvg,
                outsideTempAvg: item.outsideTempAvg,
                routeFingerprintJSON: item.routeFingerprint.flatMap { fingerprint in
                    (try? JSONEncoder().encode(fingerprint)).flatMap { String(data: $0, encoding: .utf8) }
                },
                climateOnFraction: item.climateOnFraction,
                elevationGainM: item.elevationGainM,
                elevationLossM: item.elevationLossM
            )
        }
        try? await DriveSummaryStore(database: database).upsertAll(records)
    }
}

public struct APIDriveSummaryProvider: DriveSummaryProviding {
    private let api: any DriveAPIProviding
    private let cache: (any DriveSummaryCaching)?

    public init(api: any DriveAPIProviding, cache: (any DriveSummaryCaching)? = nil) {
        self.api = api
        self.cache = cache
    }

    public func cachedDriveSummaries(carId: Int) async -> [DriveSummaryItem] {
        await cache?.load(carId: carId).map { $0.withCachedState() } ?? []
    }

    public func driveSummaries(carId: Int) async -> APIResult<[DriveSummaryItem]> {
        let cached = await cache?.load(carId: carId) ?? []
        switch await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        }) {
        case let .success(drives):
            let summaries = drives.map { DriveSummaryItem(data: $0, carId: carId) }.filter { $0.driveId >= 0 }
            let merged = mergeCachedEnergy(into: summaries, cached: cached)
            await cache?.save(merged, carId: carId)
            return .success(merged)
        case let .failure(error):
            if !cached.isEmpty {
                return .success(cached.map { $0.withCachedState() })
            }
            return .failure(error)
        }
    }

    public func enrichDriveSummaries(_ summaries: [DriveSummaryItem], carId: Int) async -> [DriveSummaryItem] {
        let missingIndices = Array(summaries.indices.filter {
            summaries[$0].energyConsumedNet == nil || summaries[$0].routeFingerprint?.isComplete != true
        }.prefix(120))
        guard !missingIndices.isEmpty else {
            return summaries
        }

        var enriched = summaries
        let batchSize = 8
        var offset = 0
        while offset < missingIndices.count {
            guard !Task.isCancelled else { return enriched }
            let end = min(offset + batchSize, missingIndices.count)
            let batch = Array(missingIndices[offset..<end])
            await withTaskGroup(of: (Int, DriveSummaryItem?).self) { group in
                for index in batch {
                    let summary = summaries[index]
                    group.addTask {
                        guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: summary.driveId) else {
                            return (index, nil)
                        }
                        return (index, summary.withDetailAnalytics(detail))
                    }
                }
                for await (index, item) in group {
                    if let item {
                        enriched[index] = item
                    }
                }
            }
            await cache?.save(enriched, carId: carId)
            offset = end
        }
        return enriched
    }

    private func mergeCachedEnergy(
        into summaries: [DriveSummaryItem],
        cached: [DriveSummaryItem]
    ) -> [DriveSummaryItem] {
        let cachedByID = Dictionary(cached.map { ($0.driveId, $0) }, uniquingKeysWith: { first, _ in first })
        return summaries.map { summary in
            guard let cachedItem = cachedByID[summary.driveId] else { return summary }
            return summary.mergingCachedAnalytics(cachedItem)
        }
    }

    public func driveUnits(carId: Int) async -> APIResult<UnitPreferences?> {
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
}

extension DriveSummaryItem {
    func withCachedState() -> DriveSummaryItem {
        DriveSummaryItem(
            driveId: driveId, carId: carId, startDate: startDate, endDate: endDate,
            distance: distance, durationMin: durationMin, startAddress: startAddress,
            endAddress: endAddress, speedMax: speedMax, speedAvg: speedAvg,
            energyConsumedNet: energyConsumedNet, efficiency: efficiency,
            efficiencySource: efficiencySource, outsideTempAvg: outsideTempAvg,
            startBatteryLevel: startBatteryLevel, endBatteryLevel: endBatteryLevel,
            startRatedRangeKm: startRatedRangeKm, endRatedRangeKm: endRatedRangeKm,
            routeFingerprint: routeFingerprint, climateOnFraction: climateOnFraction,
            elevationGainM: elevationGainM, elevationLossM: elevationLossM,
            isCached: true
        )
    }

    func withEnergyConsumedNet(_ energy: Double, source: DriveEnergySource) -> DriveSummaryItem {
        DriveSummaryItem(
            driveId: driveId,
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            durationMin: durationMin,
            startAddress: startAddress,
            endAddress: endAddress,
            speedMax: speedMax,
            speedAvg: speedAvg,
            energyConsumedNet: energy,
            efficiency: distance.map { $0 > 0 ? energy * 1000 / $0 : efficiency } ?? efficiency,
            efficiencySource: source,
            outsideTempAvg: outsideTempAvg,
            startBatteryLevel: startBatteryLevel,
            endBatteryLevel: endBatteryLevel,
            startRatedRangeKm: startRatedRangeKm,
            endRatedRangeKm: endRatedRangeKm,
            routeFingerprint: routeFingerprint,
            climateOnFraction: climateOnFraction,
            elevationGainM: elevationGainM,
            elevationLossM: elevationLossM,
            isCached: isCached
        )
    }

    func withDetailAnalytics(_ detail: DriveDetail) -> DriveSummaryItem {
        let positions = detail.positions ?? []
        let fingerprint = DriveRouteFingerprint(positions: positions)
        let climateSamples = positions.compactMap { $0.climateInfo?.isClimateOn }
        let climateFraction = climateSamples.isEmpty
            ? climateOnFraction
            : Double(climateSamples.filter { $0 }.count) / Double(climateSamples.count)
        let elevations = positions.compactMap(\.elevation).map(Double.init)
        let elevationChanges = zip(elevations, elevations.dropFirst()).map { $1 - $0 }
        let gained = elevationChanges.filter { $0 > 0 }.reduce(0, +)
        let lost = abs(elevationChanges.filter { $0 < 0 }.reduce(0, +))
        let resolvedDistance = detail.distance ?? distance
        let energy = detail.usableEnergyConsumedNet
            ?? DriveStatsCalculator.estimatedNetEnergyKWh(from: positions)
            ?? energyConsumedNet
        let source: DriveEnergySource = detail.usableEnergyConsumedNet != nil
            ? .api
            : (energy != nil ? .powerSamples : efficiencySource)
        return DriveSummaryItem(
            driveId: driveId,
            carId: carId,
            startDate: detail.startDate ?? startDate,
            endDate: detail.endDate ?? endDate,
            distance: detail.distance ?? distance,
            durationMin: detail.durationMin ?? durationMin,
            startAddress: detail.startAddress ?? startAddress,
            endAddress: detail.endAddress ?? endAddress,
            speedMax: detail.speedMax ?? speedMax,
            speedAvg: detail.speedAvg ?? speedAvg,
            energyConsumedNet: energy,
            efficiency: resolvedDistance.flatMap { distance in
                guard distance > 0, let energy else { return detail.usableConsumptionNet ?? efficiency }
                return energy * 1000 / distance
            } ?? detail.usableConsumptionNet ?? efficiency,
            efficiencySource: source,
            outsideTempAvg: detail.outsideTempAvg ?? outsideTempAvg,
            startBatteryLevel: detail.startBatteryLevel ?? startBatteryLevel,
            endBatteryLevel: detail.endBatteryLevel ?? endBatteryLevel,
            startRatedRangeKm: detail.rangeRated?.startRange ?? startRatedRangeKm,
            endRatedRangeKm: detail.rangeRated?.endRange ?? endRatedRangeKm,
            routeFingerprint: fingerprint.isComplete ? fingerprint : routeFingerprint,
            climateOnFraction: climateFraction,
            elevationGainM: elevations.count > 1 ? gained : elevationGainM,
            elevationLossM: elevations.count > 1 ? lost : elevationLossM,
            isCached: isCached
        )
    }

    func mergingCachedAnalytics(_ cached: DriveSummaryItem) -> DriveSummaryItem {
        let mergedEnergy = energyConsumedNet ?? cached.energyConsumedNet
        let mergedEfficiency = efficiency ?? cached.efficiency ?? distance.flatMap { distance in
            guard distance > 0, let mergedEnergy else { return nil }
            return mergedEnergy * 1000 / distance
        }
        return DriveSummaryItem(
            driveId: driveId,
            carId: carId,
            startDate: startDate,
            endDate: endDate ?? cached.endDate,
            distance: distance ?? cached.distance,
            durationMin: durationMin ?? cached.durationMin,
            startAddress: startAddress ?? cached.startAddress,
            endAddress: endAddress ?? cached.endAddress,
            speedMax: speedMax ?? cached.speedMax,
            speedAvg: speedAvg ?? cached.speedAvg,
            energyConsumedNet: mergedEnergy,
            efficiency: mergedEfficiency,
            efficiencySource: energyConsumedNet != nil ? efficiencySource : cached.efficiencySource,
            outsideTempAvg: outsideTempAvg ?? cached.outsideTempAvg,
            startBatteryLevel: startBatteryLevel ?? cached.startBatteryLevel,
            endBatteryLevel: endBatteryLevel ?? cached.endBatteryLevel,
            startRatedRangeKm: startRatedRangeKm ?? cached.startRatedRangeKm,
            endRatedRangeKm: endRatedRangeKm ?? cached.endRatedRangeKm,
            routeFingerprint: routeFingerprint ?? cached.routeFingerprint,
            climateOnFraction: climateOnFraction ?? cached.climateOnFraction,
            elevationGainM: elevationGainM ?? cached.elevationGainM,
            elevationLossM: elevationLossM ?? cached.elevationLossM,
            isCached: isCached
        )
    }
}

@MainActor
public final class DrivesViewModel: ObservableObject {
    @Published public private(set) var state: DrivesState

    private let store: any DriveSummaryProviding
    private let settingsStore: (any SettingsStoring)?
    private let fixedShowShortEntries: Bool?
    private var allItems: [DriveSummaryItem] = []
    private var carId: Int?
    private var settingsShowShortEntries = true
    private var loadedSettings = AppSettings()
    private var energyEnrichmentTask: Task<Void, Never>?

    public init(
        store: any DriveSummaryProviding,
        showShortEntries: Bool,
        initialState: DrivesState = DrivesState()
    ) {
        self.store = store
        self.settingsStore = nil
        self.fixedShowShortEntries = showShortEntries
        self.state = initialState
    }

    public init(
        store: any DriveSummaryProviding,
        settingsStore: any SettingsStoring,
        initialState: DrivesState = DrivesState()
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.fixedShowShortEntries = nil
        self.state = initialState
    }

    public func load(carId: Int) async {
        energyEnrichmentTask?.cancel()
        self.carId = carId
        state.isLoading = true
        state.errorMessage = nil
        state.isUsingCachedData = false
        if let settingsStore {
            loadedSettings = await settingsStore.load()
            settingsShowShortEntries = loadedSettings.showShortDrivesCharges
        }

        async let cachedItems = store.cachedDriveSummaries(carId: carId)
        async let drivesResult = store.driveSummaries(carId: carId)
        async let unitsResult = store.driveUnits(carId: carId)

        let cached = await cachedItems
        if !cached.isEmpty {
            allItems = cached
            applyFilters()
            state.isUsingCachedData = true
        }

        switch await drivesResult {
        case let .success(items):
            allItems = items
            applyFilters()
            state.isUsingCachedData = items.contains(where: \.isCached)
            startEnergyEnrichment(items: items, carId: carId)
        case let .failure(error):
            if cached.isEmpty {
                state.errorMessage = error.driveMessage
            }
            state.isLoading = false
            state.isRefreshing = false
        }

        switch await unitsResult {
        case let .success(units):
            state.units = units
        case .failure:
            state.units = nil
        }
    }

    private func startEnergyEnrichment(items: [DriveSummaryItem], carId: Int) {
        guard items.contains(where: { $0.energyConsumedNet == nil }) else { return }
        let store = self.store
        energyEnrichmentTask = Task { [weak self] in
            let enriched = await store.enrichDriveSummaries(items, carId: carId)
            guard !Task.isCancelled, let self, self.carId == carId else { return }
            self.allItems = enriched
            self.applyFilters()
        }
    }

    public func refresh() async {
        guard let carId else {
            return
        }
        state.isRefreshing = true
        await load(carId: carId)
        state.isRefreshing = false
    }

    public func setDateFilter(_ filter: DriveDateFilter) {
        state.dateFilter = filter
        state.chartGranularity = Self.granularity(for: filter)
        applyFilters()
    }

    public func setDistanceFilter(_ filter: DriveDistanceFilter) {
        state.distanceFilter = filter
        applyFilters()
    }

    public func primeDetailSnapshot(
        driveId: Int,
        cacheKey: DriveDetailCacheKey,
        stateCache: DriveDetailStateCache = .shared
    ) {
        guard stateCache.state(for: cacheKey) == nil,
              let item = allItems.first(where: { $0.driveId == driveId })
        else { return }

        let detail = item.previewDetail
        stateCache.save(
            DriveDetailState(
                isLoading: false,
                isShowingSummary: true,
                driveDetail: detail,
                units: state.units,
                stats: DriveStatsCalculator.calculateStats(detail),
                intelligence: state.rows.first(where: { $0.driveId == driveId })?.intelligence
            ),
            for: cacheKey
        )
    }

    public func confirmSuggestion(for driveId: Int) async {
        guard let settingsStore,
              let suggestion = state.rows.first(where: { $0.driveId == driveId })?.intelligence?.suggestion
        else { return }
        var settings = await settingsStore.load()
        let rule = DriveIntelligenceEngine.confirmedRule(from: suggestion, carId: carId ?? 0)
        guard !settings.driveRouteLabelRules.contains(where: {
            $0.carId == rule.carId && $0.name == rule.name
                && DriveIntelligenceEngine.similarity($0.fingerprint, rule.fingerprint) >= 0.72
        }) else { return }
        settings.driveRouteLabelRules.append(rule)
        await settingsStore.save(settings)
        loadedSettings = settings
        applyFilters()
    }

    private func applyFilters() {
        let cutoffDate = cutoffDate(for: state.dateFilter)
        let dateFiltered = allItems.filter { item in
            guard let cutoffDate else {
                return true
            }
            guard let date = DomainDateParser.date(from: item.startDate) else {
                return true
            }
            return date >= cutoffDate
        }

        let distanceFiltered = dateFiltered.filter { item in
            Self.matchesDistanceFilter(item.distance, filter: state.distanceFilter)
        }

        let showShortEntries = fixedShowShortEntries ?? settingsShowShortEntries
        let rowsSource = showShortEntries
            ? distanceFiltered
            : distanceFiltered.filter {
                guard let distance = $0.distance, let duration = $0.durationMin else { return true }
                return EntryVisibilityPolicy.isSignificantDrive(
                    distanceKilometers: distance,
                    durationMinutes: duration
                )
            }

        let intelligence = DriveIntelligenceEngine.analyze(
            items: allItems,
            carId: carId ?? rowsSource.first?.carId ?? 0,
            routeLabels: loadedSettings.driveRouteLabelRules,
            annotations: loadedSettings.driveAnnotations,
            geofences: loadedSettings.usesGeofencesForCommuteClassification ? loadedSettings.geofenceRules : []
        )

        state.rows = rowsSource
            .sorted { lhs, rhs in lhs.startDate > rhs.startDate }
            .map { item in
                DriveRow(
                    driveId: item.driveId,
                    startDate: item.startDate,
                    endDate: item.endDate,
                    distance: item.distance,
                    durationMin: item.durationMin,
                    startAddress: item.startAddress,
                    endAddress: item.endAddress,
                    speedAvg: item.speedAvg,
                    efficiency: item.efficiency,
                    efficiencySource: item.efficiencySource,
                    outsideTempAvg: item.outsideTempAvg,
                    ratedRangeDropKm: item.ratedRangeDropKm,
                    climateOnFraction: item.climateOnFraction,
                    elevationGainM: item.elevationGainM,
                    elevationLossM: item.elevationLossM,
                    intelligence: intelligence[item.driveId]
                )
            }

        state.summary = Self.summary(for: distanceFiltered)
        state.chartGranularity = Self.granularity(for: state.dateFilter)
        state.chartData = Self.chartData(for: distanceFiltered, granularity: state.chartGranularity)
        state.isLoading = false
        state.isRefreshing = false
        state.errorMessage = nil
    }

    private func cutoffDate(for filter: DriveDateFilter) -> Date? {
        guard let dayCount = filter.dayCount else {
            return nil
        }
        return Calendar.current.date(byAdding: .day, value: -(dayCount - 1), to: Calendar.current.startOfDay(for: Date()))
    }

    private static func matchesDistanceFilter(_ distance: Double?, filter: DriveDistanceFilter) -> Bool {
        guard let distance else { return filter == .all }
        let minOk = filter.minDistanceKm.map { distance >= $0 } ?? true
        let maxOk = filter.maxDistanceKm.map { distance < $0 } ?? true
        return minOk && maxOk
    }

    private static func granularity(for filter: DriveDateFilter) -> DriveChartGranularity {
        switch filter {
        case .today, .last7Days, .last30Days:
            return .daily
        case .last90Days:
            return .weekly
        case .lastYear, .allTime:
            return .monthly
        }
    }

    private static func summary(for items: [DriveSummaryItem]) -> DrivesSummary {
        guard !items.isEmpty else {
            return .empty
        }
        let distances = items.compactMap(\.distance)
        let durations = items.compactMap(\.durationMin)
        let totalDistance = distances.isEmpty ? nil : distances.reduce(0, +)
        let totalDuration = durations.isEmpty ? nil : durations.reduce(0, +)
        let speeds = items.compactMap { $0.speedMax ?? $0.speedAvg.map(Int.init) }
        let efficiencies = items.compactMap(\.efficiency)
        let ratedRangeDrops = items.compactMap(\.ratedRangeDropKm)
        return DrivesSummary(
            totalDrives: items.count,
            totalDistanceKm: totalDistance,
            distanceRecordCount: distances.count,
            distanceIsComplete: distances.count == items.count,
            totalRatedRangeDropKm: ratedRangeDrops.isEmpty ? nil : ratedRangeDrops.reduce(0, +),
            ratedRangeRecordCount: ratedRangeDrops.count,
            ratedRangeIsComplete: ratedRangeDrops.count == items.count,
            totalDurationMin: totalDuration,
            durationRecordCount: durations.count,
            durationIsComplete: durations.count == items.count,
            avgDistancePerDrive: totalDistance.map { $0 / Double(distances.count) },
            avgDurationPerDrive: totalDuration.map { $0 / durations.count },
            maxSpeedKmh: speeds.max(),
            avgEfficiencyWhKm: efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count),
            efficiencyRecordCount: efficiencies.count,
            efficiencyIsComplete: efficiencies.count == items.count,
            reconstructedEfficiencyCount: items.filter {
                $0.efficiency != nil && $0.efficiencySource == .powerSamples
            }.count
        )
    }

    private static func chartData(for items: [DriveSummaryItem], granularity: DriveChartGranularity) -> [DriveChartPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: items) { item -> String in
            guard let date = DomainDateParser.date(from: item.startDate) else {
                return "Unknown"
            }
            switch granularity {
            case .daily:
                let components = calendar.dateComponents([.month, .day], from: date)
                return String(format: "%02d/%02d", components.month ?? 0, components.day ?? 0)
            case .weekly:
                let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
                return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
            case .monthly:
                let components = calendar.dateComponents([.year, .month], from: date)
                return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            }
        }

        return grouped
            .map { label, items in
                let distances = items.compactMap(\.distance)
                let ratedRangeDrops = items.compactMap(\.ratedRangeDropKm)
                return DriveChartPoint(
                    label: label,
                    count: items.count,
                    totalDistance: distances.isEmpty ? nil : distances.reduce(0, +),
                    distanceRecordCount: distances.count,
                    distanceIsComplete: distances.count == items.count,
                    totalRatedRangeDrop: ratedRangeDrops.isEmpty ? nil : ratedRangeDrops.reduce(0, +),
                    ratedRangeRecordCount: ratedRangeDrops.count,
                    ratedRangeIsComplete: ratedRangeDrops.count == items.count,
                    totalDurationMin: items.compactMap(\.durationMin).reduce(0, +),
                    maxSpeed: items.map { $0.speedMax ?? Int($0.speedAvg ?? 0) }.max() ?? 0
                )
            }
            .sorted { $0.label < $1.label }
    }
}

extension APIError {
    var driveMessage: String {
        switch self {
        case .serverNotConfigured:
            return "Configure your TeslaMate server before loading drives."
        case let .invalidURL(url):
            return "Invalid TeslaMate URL: \(url)"
        case let .httpStatus(status):
            return "TeslaMate returned HTTP \(status)."
        case let .sslCertificate(message):
            return "SSL certificate error: \(message)"
        case let .invalidResponse(message):
            return "Invalid TeslaMate response: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        case .cancelled:
            return "Request cancelled."
        case .emptyBody:
            return "TeslaMate returned no drive data."
        }
    }
}
