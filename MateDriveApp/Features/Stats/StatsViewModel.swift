import Combine
import Foundation

public enum StatsYearFilter: Hashable, Sendable {
    case allTime
    case year(Int)

    public var label: String {
        switch self {
        case .allTime:
            return "All Time"
        case let .year(year):
            return "\(year)"
        }
    }
}

public struct StatsSummary: Equatable, Sendable {
    public let totalDrives: Int
    public let totalDistance: Double
    public let totalDrivingMin: Int
    public let missingDriveDistanceCount: Int
    public let missingDriveDurationCount: Int
    public let totalCharges: Int
    public let totalChargeEnergy: Double
    public let missingChargeEnergyCount: Int
    public let totalChargeCost: Double
    public let pricedChargeCount: Int
    public let missingChargeCostCount: Int
    public let apiChargeCostCount: Int
    public let pricingRuleChargeCostCount: Int
    public let manualChargeCostCount: Int
    public let acCharges: Int
    public let dcCharges: Int
    public let longestDrive: DriveData?
    public let mostEfficientDrive: DriveData?

    public static let empty = StatsSummary(totalDrives: 0, totalDistance: 0, totalDrivingMin: 0, missingDriveDistanceCount: 0, missingDriveDurationCount: 0, totalCharges: 0, totalChargeEnergy: 0, missingChargeEnergyCount: 0, totalChargeCost: 0, pricedChargeCount: 0, missingChargeCostCount: 0, apiChargeCostCount: 0, pricingRuleChargeCostCount: 0, manualChargeCostCount: 0, acCharges: 0, dcCharges: 0, longestDrive: nil, mostEfficientDrive: nil)
}

public struct StatsDailyActivity: Equatable, Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let driveCount: Int
    public let distanceKm: Double
    public let chargeCount: Int
    public let chargeEnergyKWh: Double
}

public struct StatsState: Equatable, Sendable {
    public var isLoading: Bool
    public var errorMessage: String?
    public var availableYears: [Int]
    public var selectedFilter: StatsYearFilter
    public var summary: StatsSummary
    public var units: UnitPreferences?
    public var currencySymbol: String
    public var serverStats: TeslaMateServerStatsSummary?
    public var serverStatsCheckedAt: Date?
    public var heatmapYear: Int?
    public var dailyActivity: [StatsDailyActivity]
    public var parkingCost: ParkingCostSummary
    public var parkingCostAvailable: Bool
    public var parkingHistoryComplete: Bool

    public init(isLoading: Bool = true, errorMessage: String? = nil, availableYears: [Int] = [], selectedFilter: StatsYearFilter = .allTime, summary: StatsSummary = .empty, units: UnitPreferences? = nil, currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol(), serverStats: TeslaMateServerStatsSummary? = nil, serverStatsCheckedAt: Date? = nil, heatmapYear: Int? = nil, dailyActivity: [StatsDailyActivity] = [], parkingCost: ParkingCostSummary = ParkingCostSummary(sessionCost: 0, recurringMonthlyCost: 0, matchedParkingCount: 0, unmatchedParkingCount: 0), parkingCostAvailable: Bool = false, parkingHistoryComplete: Bool = false) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.availableYears = availableYears
        self.selectedFilter = selectedFilter
        self.summary = summary
        self.units = units
        self.currencySymbol = currencySymbol
        self.serverStats = serverStats
        self.serverStatsCheckedAt = serverStatsCheckedAt
        self.heatmapYear = heatmapYear
        self.dailyActivity = dailyActivity
        self.parkingCost = parkingCost
        self.parkingCostAvailable = parkingCostAvailable
        self.parkingHistoryComplete = parkingHistoryComplete
    }
}

public struct StatsPageSnapshot: Sendable {
    public let state: StatsState
    public let drives: [DriveData]
    public let charges: [ChargeData]
    public let chargeCostOverrides: [Int: Double]
    public let chargePricingRules: [ChargePricingRule]
    public let chargePricingAggregates: [Int: ChargeDetailPricingAggregate]
    public let parkingFeeRules: [ParkingFeeRule]
    public let parkingActivities: [TeslaMateActivity]
}

@MainActor
public final class StatsViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<StatsPageSnapshot>(maximumEntryCount: 4)

    @Published public private(set) var state: StatsState

    private let api: any AnalyticsAPIProviding
    private let settingsStore: (any SettingsStoring)?
    private let costOverrideStore: any ChargeCostOverriding
    private let chargePricingAggregateStore: any ChargePricingAggregateProviding
    private let activityAPI: (any ActivityAPIProviding)?
    private let historyProvider: (any MileageDataProviding)?
    private var allDrives: [DriveData] = []
    private var allCharges: [ChargeData] = []
    private var chargeCostOverrides: [Int: Double] = [:]
    private var chargePricingRules: [ChargePricingRule] = []
    private var chargePricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    private var parkingFeeRules: [ParkingFeeRule] = []
    private var allParkingActivities: [TeslaMateActivity] = []
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<StatsPageSnapshot>
    private var isRefreshing = false

    public init(
        api: any AnalyticsAPIProviding,
        settingsStore: (any SettingsStoring)? = nil,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        chargePricingAggregateStore: any ChargePricingAggregateProviding = EmptyChargePricingAggregateStore(),
        activityAPI: (any ActivityAPIProviding)? = nil,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<StatsPageSnapshot>? = nil,
        initialState: StatsState = StatsState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let cachedSnapshot = cacheKey.flatMap { resolvedStateCache.state(for: $0) }
        self.api = api
        self.settingsStore = settingsStore
        self.costOverrideStore = costOverrideStore
        self.chargePricingAggregateStore = chargePricingAggregateStore
        self.activityAPI = activityAPI
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cachedSnapshot?.state ?? initialState
        allDrives = cachedSnapshot?.drives ?? []
        allCharges = cachedSnapshot?.charges ?? []
        chargeCostOverrides = cachedSnapshot?.chargeCostOverrides ?? [:]
        chargePricingRules = cachedSnapshot?.chargePricingRules ?? []
        chargePricingAggregates = cachedSnapshot?.chargePricingAggregates ?? [:]
        parkingFeeRules = cachedSnapshot?.parkingFeeRules ?? []
        allParkingActivities = cachedSnapshot?.parkingActivities ?? []
    }

    public func load(carId: Int) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let hadVisibleContent = hasVisibleContent
        state.isLoading = !hadVisibleContent
        state.errorMessage = nil
        if let settingsStore {
            let settings = await settingsStore.load()
            state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())
            chargePricingRules = settings.chargePricingRules
            parkingFeeRules = settings.parkingFeeRules
        }
        do {
            chargeCostOverrides = try await costOverrideStore.costOverrides(carId: carId)
        } catch {
            chargeCostOverrides = [:]
        }
        do {
            chargePricingAggregates = try await chargePricingAggregateStore.chargePricingAggregates(carId: carId)
        } catch {
            chargePricingAggregates = [:]
        }

        async let drivesResult = loadDrives(carId: carId)
        async let chargesResult = loadCharges(carId: carId)
        async let unitsResult = loadUnits(carId: carId)
        async let serverStatsResult = api.serverStats(carId: carId)
        async let parkingResult = Self.loadParkingActivities(api: activityAPI, carId: carId)

        if case let .success(units) = await unitsResult {
            state.units = units
        }
        if case let .success(response) = await serverStatsResult {
            state.serverStats = response.summary
            state.serverStatsCheckedAt = Date()
            if state.units == nil, let units = response.units {
                state.units = UnitPreferences(
                    unitOfLength: units.unitOfLength,
                    unitOfTemperature: units.unitOfTemperature,
                    unitOfPressure: units.unitOfPressure
                )
            }
        } else if !hadVisibleContent {
            state.serverStats = nil
            state.serverStatsCheckedAt = nil
        }

        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            allDrives = drives
            allCharges = charges
            let parking = await parkingResult
            allParkingActivities = parking.items
            state.parkingCostAvailable = parking.available
            state.parkingHistoryComplete = parking.complete
            state.availableYears = Self.availableYears(drives: drives, charges: charges, parking: parking.items)
            applyFilter()
            state.isLoading = false
            saveCachedState()
        case let (.failure(error), _), let (_, .failure(error)):
            state.isLoading = false
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

    public func setFilter(_ filter: StatsYearFilter) {
        state.selectedFilter = filter
        applyFilter()
        saveCachedState()
    }

    public var usesServerAllTimeSummary: Bool {
        state.selectedFilter == .allTime && state.serverStats != nil
    }

    public var displayedTotalDistance: Double {
        usesServerAllTimeSummary ? (state.serverStats?.totalDistanceKm ?? state.summary.totalDistance) : state.summary.totalDistance
    }

    public var displayedDistanceMissingCount: Int {
        if usesServerAllTimeSummary, state.serverStats?.totalDistanceKm != nil { return 0 }
        return state.summary.missingDriveDistanceCount
    }

    public var displayedTotalChargeCost: Double {
        if usesServerAllTimeSummary && !hasLocalChargeCostCustomization {
            return state.serverStats?.totalChargingCost ?? state.summary.totalChargeCost
        }
        return state.summary.totalChargeCost
    }

    public var displayedTotalVehicleCost: Double? {
        guard chargeCostIsComplete,
              state.parkingCostAvailable,
              state.parkingHistoryComplete,
              state.parkingCost.unmatchedParkingCount == 0 else { return nil }
        return displayedTotalChargeCost + state.parkingCost.totalCost
    }

    public var usesLocalChargeCostTotal: Bool {
        !chargeCostOverrides.isEmpty || !chargePricingRules.isEmpty
    }

    public var chargeCostIsComplete: Bool {
        if usesServerAllTimeSummary, !hasLocalChargeCostCustomization {
            return state.serverStats?.totalChargingCost != nil
        }
        return state.summary.missingChargeCostCount == 0
    }

    private var hasLocalChargeCostCustomization: Bool {
        usesLocalChargeCostTotal
    }

    private func applyFilter() {
        let drives = allDrives.filter { matches($0.startDate, filter: state.selectedFilter) }
        let charges = allCharges.filter { matches($0.startDate, filter: state.selectedFilter) }
        let parking = allParkingActivities.filter { matches($0.startDate, filter: state.selectedFilter) }
        state.summary = Self.summary(
            drives: drives,
            charges: charges,
            costOverrides: chargeCostOverrides,
            pricingRules: chargePricingRules,
            pricingAggregates: chargePricingAggregates
        )
        state.parkingCost = ParkingFeeRuleEngine.summarize(parking.map {
            ParkingFeeInput(startDate: $0.startDate, address: $0.startAddress, latitude: $0.startLatitude, longitude: $0.startLongitude, durationMinutes: $0.durationMin)
        }, rules: parkingFeeRules)
        let heatmapYear: Int?
        switch state.selectedFilter {
        case let .year(year):
            heatmapYear = year
        case .allTime:
            heatmapYear = state.availableYears.first
        }
        state.heatmapYear = heatmapYear
        state.dailyActivity = heatmapYear.map {
            Self.dailyActivity(year: $0, drives: allDrives, charges: allCharges)
        } ?? []
    }

    private var hasVisibleContent: Bool {
        state.serverStats != nil
            || !state.availableYears.isEmpty
            || state.summary != .empty
            || !state.dailyActivity.isEmpty
    }

    private func saveCachedState() {
        guard let cacheKey else { return }
        stateCache.save(
            StatsPageSnapshot(
                state: state,
                drives: allDrives,
                charges: allCharges,
                chargeCostOverrides: chargeCostOverrides,
                chargePricingRules: chargePricingRules,
                chargePricingAggregates: chargePricingAggregates,
                parkingFeeRules: parkingFeeRules,
                parkingActivities: allParkingActivities
            ),
            for: cacheKey
        )
    }

    private func matches(_ dateString: String?, filter: StatsYearFilter) -> Bool {
        switch filter {
        case .allTime:
            return true
        case let .year(year):
            return Self.year(from: dateString) == year
        }
    }

    public static func summary(
        drives: [DriveData],
        charges: [ChargeData],
        costOverrides: [Int: Double] = [:],
        pricingRules: [ChargePricingRule] = [],
        pricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    ) -> StatsSummary {
        let longest = drives.filter { $0.distance != nil }.max { ($0.distance ?? 0) < ($1.distance ?? 0) }
        let efficient = drives
            .filter { ($0.efficiencyWhKm ?? .greatestFiniteMagnitude) > 0 }
            .min { ($0.efficiencyWhKm ?? .greatestFiniteMagnitude) < ($1.efficiencyWhKm ?? .greatestFiniteMagnitude) }
        var ac = 0
        var dc = 0
        for charge in charges {
            let isDc = ChargingSessionAnalyzer.isDcCharge(
                chargeId: charge.chargeId ?? -1,
                energyAddedKwh: charge.chargeEnergyAdded,
                durationMin: charge.durationMin,
                dcChargeIds: [],
                processedChargeIds: []
            )
            if isDc { dc += 1 } else { ac += 1 }
        }
        let resolvedCosts = charges.compactMap {
            resolvedCost(
                for: $0,
                costOverrides: costOverrides,
                pricingRules: pricingRules,
                pricingAggregate: $0.chargeId.flatMap { pricingAggregates[$0] }
            )
        }
        return StatsSummary(
            totalDrives: drives.count,
            totalDistance: drives.reduce(0) { $0 + ($1.distance ?? 0) },
            totalDrivingMin: drives.reduce(0) { $0 + ($1.durationMin ?? 0) },
            missingDriveDistanceCount: drives.filter { $0.distance == nil }.count,
            missingDriveDurationCount: drives.filter { $0.durationMin == nil }.count,
            totalCharges: charges.count,
            totalChargeEnergy: charges.reduce(0) { $0 + ($1.chargeEnergyAdded ?? 0) },
            missingChargeEnergyCount: charges.filter { $0.chargeEnergyAdded == nil }.count,
            totalChargeCost: resolvedCosts.reduce(0) { $0 + $1.value },
            pricedChargeCount: resolvedCosts.count,
            missingChargeCostCount: charges.count - resolvedCosts.count,
            apiChargeCostCount: resolvedCosts.filter { $0.source == .api }.count,
            pricingRuleChargeCostCount: resolvedCosts.filter { $0.source == .pricingRule }.count,
            manualChargeCostCount: resolvedCosts.filter { $0.source == .manual }.count,
            acCharges: ac,
            dcCharges: dc,
            longestDrive: longest,
            mostEfficientDrive: efficient
        )
    }

    public static func dailyActivity(
        year: Int,
        drives: [DriveData],
        charges: [ChargeData],
        calendar sourceCalendar: Calendar = .current
    ) -> [StatsDailyActivity] {
        var calendar = sourceCalendar
        let timeZone = sourceCalendar.timeZone
        calendar.timeZone = timeZone
        guard let start = calendar.date(from: DateComponents(timeZone: timeZone, year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start)
        else {
            return []
        }

        var driveValues: [Date: (count: Int, distance: Double)] = [:]
        for drive in drives {
            guard let date = drive.startDate.flatMap(DomainDateParser.date(from:)),
                  calendar.component(.year, from: date) == year
            else { continue }
            let day = calendar.startOfDay(for: date)
            var value = driveValues[day] ?? (0, 0)
            value.count += 1
            value.distance += max(drive.distance ?? 0, 0)
            driveValues[day] = value
        }

        var chargeValues: [Date: (count: Int, energy: Double)] = [:]
        for charge in charges {
            guard let date = charge.startDate.flatMap(DomainDateParser.date(from:)),
                  calendar.component(.year, from: date) == year
            else { continue }
            let day = calendar.startOfDay(for: date)
            var value = chargeValues[day] ?? (0, 0)
            value.count += 1
            value.energy += max(charge.chargeEnergyAdded ?? 0, 0)
            chargeValues[day] = value
        }

        var result: [StatsDailyActivity] = []
        var date = start
        while date < end {
            let drive = driveValues[date] ?? (0, 0)
            let charge = chargeValues[date] ?? (0, 0)
            result.append(StatsDailyActivity(
                date: date,
                driveCount: drive.count,
                distanceKm: drive.distance,
                chargeCount: charge.count,
                chargeEnergyKWh: charge.energy
            ))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return result
    }

    private static func availableYears(drives: [DriveData], charges: [ChargeData], parking: [TeslaMateActivity] = []) -> [Int] {
        Array(Set(drives.compactMap { year(from: $0.startDate) } + charges.compactMap { year(from: $0.startDate) } + parking.compactMap { year(from: $0.startDate) }))
            .sorted(by: >)
    }

    private static func loadParkingActivities(api: (any ActivityAPIProviding)?, carId: Int, maximumPages: Int = 250) async -> (items: [TeslaMateActivity], available: Bool, complete: Bool) {
        guard let api else { return ([], false, false) }
        var page = 1
        var items: [TeslaMateActivity] = []
        var seen: Set<String> = []
        while page <= maximumPages {
            switch await api.activities(carId: carId, page: page, show: 200) {
            case let .success(response):
                let newItems = response.data.filter { seen.insert($0.stableID).inserted }
                items.append(contentsOf: newItems.filter { $0.kind == .park })
                let limit = max(response.pagination?.limit ?? 200, 1)
                if response.data.count < limit || newItems.isEmpty { return (items, true, true) }
                page = (response.pagination?.page ?? page) + 1
            case .failure:
                return (items, false, false)
            }
        }
        return (items, true, false)
    }

    private static func year(from value: String?) -> Int? {
        guard let date = value.flatMap(DomainDateParser.date(from:)) else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: date)
    }

    private static func resolvedCost(for charge: ChargeData, costOverrides: [Int: Double], pricingRules: [ChargePricingRule], pricingAggregate: ChargeDetailPricingAggregate?) -> (value: Double, source: ChargeCostSource)? {
        if let chargeId = charge.chargeId, let cost = costOverrides[chargeId] {
            return (cost, .manual)
        }
        if let cost = ChargeBillingEvidence.recordedCost(charge.cost) {
            return (cost, .api)
        }
        if let cost = pricingEstimate(for: charge, pricingRules: pricingRules, pricingAggregate: pricingAggregate)?.cost {
            return (cost, .pricingRule)
        }
        return nil
    }

    private static func pricingEstimate(for charge: ChargeData, pricingRules: [ChargePricingRule], pricingAggregate: ChargeDetailPricingAggregate?) -> ChargePricingEstimate? {
        let summaryIsDc = ChargingSessionAnalyzer.isDcCharge(
            chargeId: charge.chargeId ?? -1,
            energyAddedKwh: charge.chargeEnergyAdded,
            durationMin: charge.durationMin,
            dcChargeIds: [],
            processedChargeIds: []
        )
        let billing = ChargeBillingEvidence.energyAndSamples(
            wallEnergy: charge.chargeEnergyUsed,
            batteryEnergy: charge.chargeEnergyAdded,
            samples: pricingAggregate?.energySamples ?? []
        )
        return ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: charge.startDate,
                endDate: charge.endDate,
                address: charge.address,
                latitude: charge.latitude,
                longitude: charge.longitude,
                energyAddedKWh: billing.energy,
                energySamples: billing.samples,
                isDc: pricingAggregate?.isDc ?? summaryIsDc,
                chargerIdentity: pricingAggregate?.chargerIdentity
            ),
            rules: pricingRules
        )
    }

}
