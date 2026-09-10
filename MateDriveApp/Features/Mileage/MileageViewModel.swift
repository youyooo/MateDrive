import Combine
import Foundation

public struct YearlyMileage: Equatable, Identifiable, Sendable {
    public var id: Int { year }
    public let year: Int
    public let distance: Double
    public let distanceIsComplete: Bool
    public let distanceRecordCount: Int
    public let driveCount: Int
    public let energy: Double?
    public let energyIsComplete: Bool
    public let batteryUsage: Double
    public let energyCost: Double?
    public let energyCostIsComplete: Bool
    public let pricedChargeCount: Int
    public let chargeCount: Int
    public let drives: [DriveData]
}

public struct MonthlyMileage: Equatable, Identifiable, Sendable {
    public var id: String { yearMonth }
    public let yearMonth: String
    public let distance: Double
    public let distanceIsComplete: Bool
    public let distanceRecordCount: Int
    public let driveCount: Int
    public let energy: Double?
    public let energyIsComplete: Bool
    public let batteryUsage: Double
    public let energyCost: Double?
    public let energyCostIsComplete: Bool
    public let pricedChargeCount: Int
    public let chargeCount: Int
    public let drives: [DriveData]
}

public struct DailyMileage: Equatable, Identifiable, Sendable {
    public var id: String { date }
    public let date: String
    public let distance: Double
    public let distanceIsComplete: Bool
    public let distanceRecordCount: Int
    public let driveCount: Int
    public let energy: Double?
    public let energyIsComplete: Bool
    public let batteryUsage: Double
    public let energyCost: Double?
    public let energyCostIsComplete: Bool
    public let pricedChargeCount: Int
    public let chargeCount: Int
    public let drives: [DriveData]
}

public struct MileageState: Equatable, Sendable {
    public var isLoading: Bool
    public var errorMessage: String?
    public var years: [YearlyMileage]
    public var months: [MonthlyMileage]
    public var days: [DailyMileage]
    public var selectedYear: Int?
    public var selectedMonth: String?
    public var selectedDay: String?
    public var units: UnitPreferences?
    public var currencySymbol: String

    public init(isLoading: Bool = true, errorMessage: String? = nil, years: [YearlyMileage] = [], months: [MonthlyMileage] = [], days: [DailyMileage] = [], selectedYear: Int? = nil, selectedMonth: String? = nil, selectedDay: String? = nil, units: UnitPreferences? = nil, currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol()) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.years = years
        self.months = months
        self.days = days
        self.selectedYear = selectedYear
        self.selectedMonth = selectedMonth
        self.selectedDay = selectedDay
        self.units = units
        self.currencySymbol = currencySymbol
    }
}

public protocol MileageDataProviding: Sendable {
    func mileageDrives(carId: Int) async -> APIResult<[DriveData]>
    func mileageCharges(carId: Int) async -> APIResult<[ChargeData]>
    func mileageUnits(carId: Int) async -> APIResult<UnitPreferences?>
}

public struct APIMileageDataProvider: MileageDataProviding {
    private let api: any AnalyticsAPIProviding
    private let maximumEnergyEnrichmentCount: Int

    public init(
        api: any AnalyticsAPIProviding,
        maximumEnergyEnrichmentCount: Int = 120
    ) {
        self.api = api
        self.maximumEnergyEnrichmentCount = max(maximumEnergyEnrichmentCount, 0)
    }

    public func mileageDrives(carId: Int) async -> APIResult<[DriveData]> {
        switch await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        }) {
        case let .success(drives):
            return .success(await enrichMissingEnergy(in: drives, carId: carId))
        case let .failure(error):
            return .failure(error)
        }
    }

    private func enrichMissingEnergy(in drives: [DriveData], carId: Int) async -> [DriveData] {
        let missingIndices = Array(
            drives.indices
                .filter { drives[$0].usableEnergyConsumedNet == nil && drives[$0].driveId != nil }
                .prefix(maximumEnergyEnrichmentCount)
        )
        guard !missingIndices.isEmpty else { return drives }

        var enriched = drives
        for offset in stride(from: 0, to: missingIndices.count, by: 8) {
            guard !Task.isCancelled else { return enriched }
            let batch = missingIndices[offset..<min(offset + 8, missingIndices.count)]
            let api = self.api
            await withTaskGroup(of: (Int, Double?).self) { group in
                for index in batch {
                    guard let driveId = drives[index].driveId else { continue }
                    group.addTask {
                        guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: driveId) else {
                            return (index, nil)
                        }
                        return (index, detail.usableEnergyConsumedNet ?? DriveStatsCalculator.estimatedNetEnergyKWh(from: detail.positions ?? []))
                    }
                }
                for await (index, energy) in group {
                    if let energy {
                        enriched[index] = drives[index].withEnergyConsumedNet(energy)
                    }
                }
            }
        }
        return enriched
    }

    public func mileageCharges(carId: Int) async -> APIResult<[ChargeData]> {
        await VehicleHistoryPaginator.charges(loadPage: { page, show in
            await self.api.charges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    public func mileageUnits(carId: Int) async -> APIResult<UnitPreferences?> {
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

public struct DatabaseMileageDataProvider: MileageDataProviding {
    private let databaseProvider: any AppDatabaseProviding
    private let settingsStore: any SettingsStoring
    private let snapshotStore: any DashboardSnapshotStoring

    public init(
        databaseProvider: any AppDatabaseProviding,
        settingsStore: any SettingsStoring,
        snapshotStore: any DashboardSnapshotStoring = DashboardSnapshotStore.shared
    ) {
        self.databaseProvider = databaseProvider
        self.settingsStore = settingsStore
        self.snapshotStore = snapshotStore
    }

    public func mileageDrives(carId: Int) async -> APIResult<[DriveData]> {
        do {
            let records = try await DriveSummaryStore(database: databaseProvider.database()).records(carId: carId)
            return .success(records.map(Self.drive))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    public func mileageCharges(carId: Int) async -> APIResult<[ChargeData]> {
        do {
            let records = try await ChargeSummaryStore(database: databaseProvider.database()).records(carId: carId)
            return .success(records.compactMap(Self.charge))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    public func mileageUnits(carId: Int) async -> APIResult<UnitPreferences?> {
        let settings = await settingsStore.load()
        let snapshot = await snapshotStore.load(serverURL: settings.serverURL, carId: carId, now: Date())
        return .success(snapshot?.units?.value)
    }

    private static func drive(_ record: DriveSummaryRecord) -> DriveData {
        DriveData(
            driveId: record.driveId,
            carId: record.carId,
            startDate: record.startDate,
            endDate: record.endDate,
            distance: record.distance,
            durationMin: record.durationMin,
            startAddress: record.startAddress,
            endAddress: record.endAddress,
            speedAvg: record.speedAvg,
            batteryDetails: DriveBatteryDetails(
                startBatteryLevel: record.startBatteryLevel,
                endBatteryLevel: record.endBatteryLevel
            ),
            rangeRated: DriveRange(
                startRange: record.startRatedRangeKm,
                endRange: record.endRatedRangeKm
            ),
            outsideTempAvg: record.outsideTempAvg,
            energyConsumedNet: record.energyConsumedNet,
            consumptionNet: record.consumptionNet
        )
    }

    private static func charge(_ record: ChargeSummaryRecord) -> ChargeData? {
        guard record.endDate != nil else { return nil }
        return ChargeData(
            chargeId: record.chargeId,
            carId: record.carId,
            startDate: record.startDate,
            endDate: record.endDate,
            address: record.address,
            chargeEnergyAdded: record.chargeEnergyAdded,
            chargeEnergyUsed: record.chargeEnergyUsed,
            cost: record.cost,
            durationMin: record.durationMin,
            rangeRated: ChargeRange(
                startRange: record.startRatedRangeKm,
                endRange: record.endRatedRangeKm
            ),
            odometer: record.odometerKm,
            latitude: record.latitude,
            longitude: record.longitude,
            startBatteryLevel: record.startBatteryLevel,
            endBatteryLevel: record.endBatteryLevel
        )
    }
}

public struct MileagePageSnapshot: Sendable {
    public let state: MileageState
    public let drives: [DriveData]
    public let charges: [ChargeData]
    public let chargeCostOverrides: [Int: Double]
    public let chargePricingRules: [ChargePricingRule]
    public let chargePricingAggregates: [Int: ChargeDetailPricingAggregate]
}

@MainActor
public final class MileageViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<MileagePageSnapshot>(maximumEntryCount: 4)

    @Published public private(set) var state: MileageState

    public var years: [YearlyMileage] { state.years }

    private let provider: any MileageDataProviding
    private let settingsStore: (any SettingsStoring)?
    private let costOverrideStore: any ChargeCostOverriding
    private let chargePricingAggregateStore: any ChargePricingAggregateProviding
    private var allDrives: [DriveData] = []
    private var allCharges: [ChargeData] = []
    private var chargeCostOverrides: [Int: Double] = [:]
    private var chargePricingRules: [ChargePricingRule] = []
    private var chargePricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    private var carId: Int?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<MileagePageSnapshot>
    private var isRefreshing = false

    public init(
        provider: any MileageDataProviding,
        settingsStore: (any SettingsStoring)? = nil,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        chargePricingAggregateStore: any ChargePricingAggregateProviding = EmptyChargePricingAggregateStore(),
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<MileagePageSnapshot>? = nil,
        initialState: MileageState = MileageState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let cachedSnapshot = cacheKey.flatMap { resolvedStateCache.state(for: $0) }
        self.provider = provider
        self.settingsStore = settingsStore
        self.costOverrideStore = costOverrideStore
        self.chargePricingAggregateStore = chargePricingAggregateStore
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cachedSnapshot?.state ?? initialState
        allDrives = cachedSnapshot?.drives ?? []
        allCharges = cachedSnapshot?.charges ?? []
        chargeCostOverrides = cachedSnapshot?.chargeCostOverrides ?? [:]
        chargePricingRules = cachedSnapshot?.chargePricingRules ?? []
        chargePricingAggregates = cachedSnapshot?.chargePricingAggregates ?? [:]
    }

    public func load(carId: Int) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        self.carId = carId
        state.isLoading = state.years.isEmpty
        state.errorMessage = nil
        if let settingsStore {
            let settings = await settingsStore.load()
            state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())
            chargePricingRules = settings.chargePricingRules
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

        async let drivesResult = provider.mileageDrives(carId: carId)
        async let chargesResult = provider.mileageCharges(carId: carId)
        async let unitsResult = provider.mileageUnits(carId: carId)

        if case let .success(units) = await unitsResult {
            state.units = units
        }

        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            allDrives = drives
            allCharges = charges
            state.years = Self.aggregateYears(drives: drives, charges: charges, costOverrides: chargeCostOverrides, pricingRules: chargePricingRules, pricingAggregates: chargePricingAggregates)
            state.isLoading = false
            saveCachedState()
        case let (.failure(error), _), let (_, .failure(error)):
            state.isLoading = false
            state.errorMessage = error.analyticsMessage
        }
    }

    public func selectYear(_ year: Int) {
        state.selectedYear = year
        state.selectedMonth = nil
        state.selectedDay = nil
        state.months = Self.aggregateMonths(year: year, drives: allDrives, charges: allCharges, costOverrides: chargeCostOverrides, pricingRules: chargePricingRules, pricingAggregates: chargePricingAggregates)
        state.days = []
        saveCachedState()
    }

    public func selectMonth(_ yearMonth: String) {
        state.selectedMonth = yearMonth
        state.selectedDay = nil
        state.days = Self.aggregateDays(yearMonth: yearMonth, drives: allDrives, charges: allCharges, costOverrides: chargeCostOverrides, pricingRules: chargePricingRules, pricingAggregates: chargePricingAggregates)
        saveCachedState()
    }

    public func selectDay(_ day: String) {
        state.selectedDay = day
        saveCachedState()
    }

    private func saveCachedState() {
        guard let cacheKey else { return }
        stateCache.save(
            MileagePageSnapshot(
                state: state,
                drives: allDrives,
                charges: allCharges,
                chargeCostOverrides: chargeCostOverrides,
                chargePricingRules: chargePricingRules,
                chargePricingAggregates: chargePricingAggregates
            ),
            for: cacheKey
        )
    }

    private static func aggregateYears(
        drives: [DriveData],
        charges: [ChargeData],
        costOverrides: [Int: Double] = [:],
        pricingRules: [ChargePricingRule] = [],
        pricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    ) -> [YearlyMileage] {
        let grouped = Dictionary(grouping: drives) { year(from: $0.startDate) ?? 0 }
            .filter { $0.key > 0 }
        return grouped.map { year, drives in
            let charges = charges.filter { Self.year(from: $0.startDate) == year }
            let distances = drives.compactMap(\.distance)
            let energy = energySummary(for: drives)
            let cost = energyCost(for: charges, costOverrides: costOverrides, pricingRules: pricingRules, pricingAggregates: pricingAggregates)
            return YearlyMileage(
                year: year,
                distance: distances.reduce(0, +),
                distanceIsComplete: distances.count == drives.count,
                distanceRecordCount: distances.count,
                driveCount: drives.count,
                energy: energy.value,
                energyIsComplete: energy.isComplete,
                batteryUsage: drives.reduce(0) { $0 + Double(max(($1.startBatteryLevel ?? 0) - ($1.endBatteryLevel ?? 0), 0)) },
                energyCost: cost.value,
                energyCostIsComplete: cost.isComplete,
                pricedChargeCount: cost.pricedCount,
                chargeCount: charges.count,
                drives: drives.sorted { ($0.startDate ?? "") < ($1.startDate ?? "") }
            )
        }
        .sorted { $0.year > $1.year }
    }

    private static func aggregateMonths(
        year: Int,
        drives: [DriveData],
        charges: [ChargeData],
        costOverrides: [Int: Double] = [:],
        pricingRules: [ChargePricingRule] = [],
        pricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    ) -> [MonthlyMileage] {
        let drives = drives.filter { Self.year(from: $0.startDate) == year }
        let grouped = Dictionary(grouping: drives) { monthKey(from: $0.startDate) ?? "" }
            .filter { !$0.key.isEmpty }
        return grouped.map { yearMonth, drives in
            let charges = charges.filter { Self.monthKey(from: $0.startDate) == yearMonth }
            let distances = drives.compactMap(\.distance)
            let energy = energySummary(for: drives)
            let cost = energyCost(for: charges, costOverrides: costOverrides, pricingRules: pricingRules, pricingAggregates: pricingAggregates)
            return MonthlyMileage(
                yearMonth: yearMonth,
                distance: distances.reduce(0, +),
                distanceIsComplete: distances.count == drives.count,
                distanceRecordCount: distances.count,
                driveCount: drives.count,
                energy: energy.value,
                energyIsComplete: energy.isComplete,
                batteryUsage: drives.reduce(0) { $0 + Double(max(($1.startBatteryLevel ?? 0) - ($1.endBatteryLevel ?? 0), 0)) },
                energyCost: cost.value,
                energyCostIsComplete: cost.isComplete,
                pricedChargeCount: cost.pricedCount,
                chargeCount: charges.count,
                drives: drives.sorted { ($0.startDate ?? "") < ($1.startDate ?? "") }
            )
        }
        .sorted { $0.yearMonth > $1.yearMonth }
    }

    private static func aggregateDays(
        yearMonth: String,
        drives: [DriveData],
        charges: [ChargeData],
        costOverrides: [Int: Double] = [:],
        pricingRules: [ChargePricingRule] = [],
        pricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    ) -> [DailyMileage] {
        let drives = drives.filter { Self.monthKey(from: $0.startDate) == yearMonth }
        let grouped = Dictionary(grouping: drives) { dayKey(from: $0.startDate) ?? "" }
            .filter { !$0.key.isEmpty }
        return grouped.map { day, drives in
            let charges = charges.filter { Self.dayKey(from: $0.startDate) == day }
            let distances = drives.compactMap(\.distance)
            let energy = energySummary(for: drives)
            let cost = energyCost(for: charges, costOverrides: costOverrides, pricingRules: pricingRules, pricingAggregates: pricingAggregates)
            return DailyMileage(
                date: day,
                distance: distances.reduce(0, +),
                distanceIsComplete: distances.count == drives.count,
                distanceRecordCount: distances.count,
                driveCount: drives.count,
                energy: energy.value,
                energyIsComplete: energy.isComplete,
                batteryUsage: drives.reduce(0) { $0 + Double(max(($1.startBatteryLevel ?? 0) - ($1.endBatteryLevel ?? 0), 0)) },
                energyCost: cost.value,
                energyCostIsComplete: cost.isComplete,
                pricedChargeCount: cost.pricedCount,
                chargeCount: charges.count,
                drives: drives.sorted { ($0.startDate ?? "") < ($1.startDate ?? "") }
            )
        }
        .sorted { $0.date > $1.date }
    }

    private static func year(from value: String?) -> Int? {
        guard let date = value.flatMap(DomainDateParser.date(from:)) else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: date)
    }

    private static func energySummary(for drives: [DriveData]) -> (value: Double?, isComplete: Bool) {
        let values = drives.compactMap(\.usableEnergyConsumedNet)
        return (values.isEmpty ? nil : values.reduce(0, +), values.count == drives.count)
    }

    private static func monthKey(from value: String?) -> String? {
        guard let date = value.flatMap(DomainDateParser.date(from:)) else { return nil }
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private static func dayKey(from value: String?) -> String? {
        guard let date = value.flatMap(DomainDateParser.date(from:)) else { return nil }
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func energyCost(for charges: [ChargeData], costOverrides: [Int: Double], pricingRules: [ChargePricingRule], pricingAggregates: [Int: ChargeDetailPricingAggregate]) -> (value: Double?, isComplete: Bool, pricedCount: Int) {
        var pricedCount = 0
        let total = charges.reduce(0) { partialResult, charge in
            let apiCost = ChargeBillingEvidence.recordedCost(charge.cost)
            let manualCost = charge.chargeId.flatMap { costOverrides[$0] }
            let aggregate = charge.chargeId.flatMap { pricingAggregates[$0] }
            let ruleCost = pricingEstimate(for: charge, pricingRules: pricingRules, pricingAggregate: aggregate)?.cost
            if apiCost != nil || manualCost != nil || ruleCost != nil {
                pricedCount += 1
            }
            return partialResult + (manualCost ?? apiCost ?? ruleCost ?? 0)
        }
        return (pricedCount > 0 ? total : nil, pricedCount == charges.count, pricedCount)
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

private extension DriveData {
    func withEnergyConsumedNet(_ energy: Double) -> DriveData {
        DriveData(
            driveId: driveId,
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            durationMin: durationMin,
            durationStr: durationStr,
            startAddress: startAddress,
            endAddress: endAddress,
            averageSpeed: averageSpeed,
            speedMax: speedMax,
            speedAvg: speedAvg,
            powerMax: powerMax,
            powerMin: powerMin,
            odometerDetails: odometerDetails,
            batteryDetails: batteryDetails,
            rangeIdeal: rangeIdeal,
            rangeRated: rangeRated,
            outsideTempAvg: outsideTempAvg,
            insideTempAvg: insideTempAvg,
            energyConsumedNet: energy,
            consumptionNet: consumptionNet
        )
    }
}
