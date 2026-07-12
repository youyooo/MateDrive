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
        outsideTempAvg: Double? = nil
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
            energyConsumedNet: data.energyConsumedNet,
            efficiency: data.efficiencyWhKm,
            efficiencySource: data.energyConsumedNet != nil || data.efficiencyWhKm != nil ? .api : .unavailable,
            outsideTempAvg: data.outsideTempAvg
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
}

public struct DrivesSummary: Equatable, Sendable {
    public let totalDrives: Int
    public let totalDistanceKm: Double?
    public let distanceRecordCount: Int
    public let distanceIsComplete: Bool
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
        errorMessage: String? = nil
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
    }
}

public protocol DriveSummaryProviding: Sendable {
    func driveSummaries(carId: Int) async -> APIResult<[DriveSummaryItem]>
    func driveUnits(carId: Int) async -> APIResult<UnitPreferences?>
}

public struct APIDriveSummaryProvider: DriveSummaryProviding {
    private let api: any DriveAPIProviding

    public init(api: any DriveAPIProviding) {
        self.api = api
    }

    public func driveSummaries(carId: Int) async -> APIResult<[DriveSummaryItem]> {
        switch await api.drives(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000) {
        case let .success(drives):
            let summaries = drives.map { DriveSummaryItem(data: $0, carId: carId) }.filter { $0.driveId >= 0 }
            return .success(await enrichMissingEnergy(in: summaries, carId: carId))
        case let .failure(error):
            return .failure(error)
        }
    }

    private func enrichMissingEnergy(in summaries: [DriveSummaryItem], carId: Int) async -> [DriveSummaryItem] {
        let missingIndices = summaries.indices.filter { summaries[$0].energyConsumedNet == nil }
        guard !missingIndices.isEmpty else {
            return summaries
        }

        var enriched = summaries
        let batchSize = 8
        var offset = 0
        while offset < missingIndices.count {
            let end = min(offset + batchSize, missingIndices.count)
            let batch = Array(missingIndices[offset..<end])
            await withTaskGroup(of: (Int, DriveSummaryItem?).self) { group in
                for index in batch {
                    let summary = summaries[index]
                    group.addTask {
                        guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: summary.driveId),
                              let energy = detail.energyConsumedNet ?? DriveStatsCalculator.estimatedNetEnergyKWh(from: detail.positions ?? [])
                        else {
                            return (index, nil)
                        }
                        let source: DriveEnergySource = detail.energyConsumedNet != nil ? .api : .powerSamples
                        return (index, summary.withEnergyConsumedNet(energy, source: source))
                    }
                }
                for await (index, item) in group {
                    if let item {
                        enriched[index] = item
                    }
                }
            }
            offset = end
        }
        return enriched
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

private extension DriveSummaryItem {
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
            outsideTempAvg: outsideTempAvg
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
        self.carId = carId
        state.isLoading = true
        state.errorMessage = nil
        if let settingsStore {
            settingsShowShortEntries = await settingsStore.load().showShortDrivesCharges
        }

        async let drivesResult = store.driveSummaries(carId: carId)
        async let unitsResult = store.driveUnits(carId: carId)

        switch await unitsResult {
        case let .success(units):
            state.units = units
        case .failure:
            state.units = nil
        }

        switch await drivesResult {
        case let .success(items):
            allItems = items
            applyFilters()
        case let .failure(error):
            state.isLoading = false
            state.isRefreshing = false
            state.errorMessage = error.driveMessage
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
        let rowsSource: [DriveSummaryItem]
        if showShortEntries {
            rowsSource = distanceFiltered
        } else {
            rowsSource = distanceFiltered.filter {
                guard let distance = $0.distance, let duration = $0.durationMin else { return true }
                return ShortEntryFilter.isSignificantDrive(distanceKilometers: distance, durationMinutes: duration)
            }
        }

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
                    outsideTempAvg: item.outsideTempAvg
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
        return DrivesSummary(
            totalDrives: items.count,
            totalDistanceKm: totalDistance,
            distanceRecordCount: distances.count,
            distanceIsComplete: distances.count == items.count,
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
                return DriveChartPoint(
                    label: label,
                    count: items.count,
                    totalDistance: distances.isEmpty ? nil : distances.reduce(0, +),
                    distanceRecordCount: distances.count,
                    distanceIsComplete: distances.count == items.count,
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
        case .emptyBody:
            return "TeslaMate returned no drive data."
        }
    }
}
