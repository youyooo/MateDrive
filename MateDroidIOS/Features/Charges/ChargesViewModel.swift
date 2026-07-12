import Combine
import Foundation

public enum ChargeTypeFilter: String, CaseIterable, Equatable, Sendable {
    case all = "All"
    case ac = "AC"
    case dc = "DC"

    func title(language: AppLanguage) -> String {
        switch self {
        case .all:
            return AppText.localized(rawValue, "全部", language: language)
        case .ac:
            return ChargePricingChargeType.ac.displayText(language: language)
        case .dc:
            return ChargePricingChargeType.dc.displayText(language: language)
        }
    }
}

public enum ChargeCostFilter: String, CaseIterable, Equatable, Sendable {
    case all = "All"
    case hasCost = "Has Cost"
    case noCost = "Missing Cost"
    case free = "Free"

    func title(language: AppLanguage) -> String {
        let chinese: String
        switch self {
        case .all:
            chinese = "全部"
        case .hasCost:
            chinese = "有费用"
        case .noCost:
            chinese = "缺少费用"
        case .free:
            chinese = "免费"
        }
        return AppText.localized(rawValue, chinese, language: language)
    }
}

public enum ChargeDateFilter: String, CaseIterable, Equatable, Sendable {
    case allTime = "All Time"
    case today = "Today"
    case last7Days = "7 Days"
    case last30Days = "30 Days"
    case last90Days = "90 Days"
    case lastYear = "Year"

    var dayCount: Int? {
        switch self {
        case .allTime:
            return nil
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
        }
    }

    func title(language: AppLanguage) -> String {
        let chinese: String
        switch self {
        case .allTime:
            chinese = "全部"
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
        }
        return AppText.localized(rawValue, chinese, language: language)
    }
}

public struct ChargeSummaryItem: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let carId: Int
    public let startDate: String
    public let endDate: String?
    public let chargeEnergyAdded: Double?
    public let cost: Double?
    public let durationMin: Int?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        chargeId: Int,
        carId: Int,
        startDate: String,
        endDate: String? = nil,
        chargeEnergyAdded: Double? = nil,
        cost: Double? = nil,
        durationMin: Int? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.chargeId = chargeId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.chargeEnergyAdded = chargeEnergyAdded
        self.cost = cost
        self.durationMin = durationMin
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(record: ChargeSummaryRecord) {
        self.init(
            chargeId: record.chargeId,
            carId: record.carId,
            startDate: record.startDate,
            endDate: record.endDate,
            chargeEnergyAdded: record.chargeEnergyAdded,
            cost: record.cost
        )
    }

    public init(data: ChargeData, carId fallbackCarId: Int) {
        self.init(
            chargeId: data.chargeId ?? -1,
            carId: data.carId ?? fallbackCarId,
            startDate: data.startDate ?? "",
            endDate: data.endDate,
            chargeEnergyAdded: data.chargeEnergyAdded,
            cost: data.cost,
            durationMin: data.durationMin,
            address: data.address,
            latitude: data.latitude,
            longitude: data.longitude
        )
    }
}

public struct ChargeRow: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let startDate: String
    public let endDate: String?
    public let energyAdded: Double?
    public let cost: Double?
    public let hasManualCost: Bool
    public let durationMin: Int?
    public let address: String?
    public let isDc: Bool
    public let costSource: ChargeCostSource
}

public struct ChargesSummary: Equatable, Sendable {
    public let totalCharges: Int
    public let totalEnergyAdded: Double?
    public let energyRecordCount: Int
    public let energyIsComplete: Bool
    public let totalCost: Double
    public let averageEnergyPerCharge: Double?
    public let averageCostPerCharge: Double
    public let pricedChargeCount: Int
    public let missingCostCount: Int
    public let apiCostCount: Int
    public let pricingRuleCostCount: Int
    public let manualCostCount: Int

    public static let empty = ChargesSummary(
        totalCharges: 0,
        totalEnergyAdded: nil,
        energyRecordCount: 0,
        energyIsComplete: true,
        totalCost: 0,
        averageEnergyPerCharge: nil,
        averageCostPerCharge: 0,
        pricedChargeCount: 0,
        missingCostCount: 0,
        apiCostCount: 0,
        pricingRuleCostCount: 0,
        manualCostCount: 0
    )
}

public struct ChargeChartPoint: Equatable, Identifiable, Sendable {
    public var id: String { label }

    public let label: String
    public let count: Int
    public let totalEnergy: Double?
    public let energyRecordCount: Int
    public let energyIsComplete: Bool
    public let totalCost: Double
}

public struct ChargesState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var rows: [ChargeRow]
    public var summary: ChargesSummary
    public var chartData: [ChargeChartPoint]
    public var dateFilter: ChargeDateFilter
    public var typeFilter: ChargeTypeFilter
    public var costFilter: ChargeCostFilter
    public var currencySymbol: String
    public var pricingBatch: ChargePricingBatchState
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        rows: [ChargeRow] = [],
        summary: ChargesSummary = .empty,
        chartData: [ChargeChartPoint] = [],
        dateFilter: ChargeDateFilter = .allTime,
        typeFilter: ChargeTypeFilter = .all,
        costFilter: ChargeCostFilter = .all,
        currencySymbol: String = "€",
        pricingBatch: ChargePricingBatchState = ChargePricingBatchState(),
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.rows = rows
        self.summary = summary
        self.chartData = chartData
        self.dateFilter = dateFilter
        self.typeFilter = typeFilter
        self.costFilter = costFilter
        self.currencySymbol = currencySymbol
        self.pricingBatch = pricingBatch
        self.errorMessage = errorMessage
    }
}

public protocol ChargeSummaryProviding: Sendable {
    func chargeSummaries(carId: Int) async -> APIResult<[ChargeSummaryItem]>
}

public protocol ChargeAggregateClassifying: Sendable {
    func dcChargeIds(carId: Int) async throws -> Set<Int>
    func processedChargeIds(carId: Int) async throws -> Set<Int>
}

public struct APIChargeSummaryProvider: ChargeSummaryProviding {
    private let api: any ChargeAPIProviding

    public init(api: any ChargeAPIProviding) {
        self.api = api
    }

    public func chargeSummaries(carId: Int) async -> APIResult<[ChargeSummaryItem]> {
        switch await api.charges(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000) {
        case let .success(charges):
            return .success(charges.map { ChargeSummaryItem(data: $0, carId: carId) }.filter { $0.chargeId >= 0 })
        case let .failure(error):
            return .failure(error)
        }
    }
}

public struct EmptyChargeAggregateClassifier: ChargeAggregateClassifying {
    public init() {}

    public func dcChargeIds(carId _: Int) async throws -> Set<Int> {
        []
    }

    public func processedChargeIds(carId _: Int) async throws -> Set<Int> {
        []
    }
}

@MainActor
public final class ChargesViewModel: ObservableObject {
    @Published public private(set) var state: ChargesState

    private let store: any ChargeSummaryProviding
    private let aggregateClassifier: any ChargeAggregateClassifying
    private let costOverrideStore: any ChargeCostOverriding
    private let chargePricingAggregateStore: any ChargePricingAggregateProviding
    private let costUpdater: (any ChargeCostUpdating)?
    private let pricingAuditStore: any ChargePricingAuditStoring
    private let settingsStore: (any SettingsStoring)?
    private let fixedShowShortEntries: Bool?
    private var allItems: [ChargeSummaryItem] = []
    private var costOverrides: [Int: Double] = [:]
    private var pricingRules: [ChargePricingRule] = []
    private var currencyCode = "EUR"
    private var chargePricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    private var dcChargeIds: Set<Int> = []
    private var processedChargeIds: Set<Int> = []
    private var carId: Int?

    public init(
        store: any ChargeSummaryProviding,
        showShortEntries: Bool,
        aggregateClassifier: any ChargeAggregateClassifying = EmptyChargeAggregateClassifier(),
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        chargePricingAggregateStore: any ChargePricingAggregateProviding = EmptyChargePricingAggregateStore(),
        costUpdater: (any ChargeCostUpdating)? = nil,
        pricingAuditStore: any ChargePricingAuditStoring = EmptyChargePricingAuditStore(),
        initialState: ChargesState = ChargesState()
    ) {
        self.store = store
        self.fixedShowShortEntries = showShortEntries
        self.aggregateClassifier = aggregateClassifier
        self.costOverrideStore = costOverrideStore
        self.chargePricingAggregateStore = chargePricingAggregateStore
        self.costUpdater = costUpdater
        self.pricingAuditStore = pricingAuditStore
        self.settingsStore = nil
        self.state = initialState
    }

    public init(
        store: any ChargeSummaryProviding,
        settingsStore: any SettingsStoring,
        aggregateClassifier: any ChargeAggregateClassifying = EmptyChargeAggregateClassifier(),
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        chargePricingAggregateStore: any ChargePricingAggregateProviding = EmptyChargePricingAggregateStore(),
        costUpdater: (any ChargeCostUpdating)? = nil,
        pricingAuditStore: any ChargePricingAuditStoring = EmptyChargePricingAuditStore(),
        initialState: ChargesState = ChargesState()
    ) {
        self.store = store
        self.fixedShowShortEntries = nil
        self.aggregateClassifier = aggregateClassifier
        self.costOverrideStore = costOverrideStore
        self.chargePricingAggregateStore = chargePricingAggregateStore
        self.costUpdater = costUpdater
        self.pricingAuditStore = pricingAuditStore
        self.settingsStore = settingsStore
        self.state = initialState
    }

    public func load(carId: Int) async {
        self.carId = carId
        state.isLoading = true
        state.errorMessage = nil

        if let settingsStore {
            let settings = await settingsStore.load()
            currencyCode = settings.resolvedCurrencyCode()
            state.currencySymbol = MateDroidCurrencyFormatter.symbol(for: currencyCode)
            pricingRules = settings.chargePricingRules
        }

        do {
            dcChargeIds = try await aggregateClassifier.dcChargeIds(carId: carId)
            processedChargeIds = try await aggregateClassifier.processedChargeIds(carId: carId)
        } catch {
            dcChargeIds = []
            processedChargeIds = []
        }

        do {
            costOverrides = try await costOverrideStore.costOverrides(carId: carId)
        } catch {
            costOverrides = [:]
        }

        do {
            chargePricingAggregates = try await chargePricingAggregateStore.chargePricingAggregates(carId: carId)
        } catch {
            chargePricingAggregates = [:]
        }

        await reloadPricingAuditHistory()

        switch await store.chargeSummaries(carId: carId) {
        case let .success(items):
            allItems = items
            applyFilters()
        case let .failure(error):
            state.isLoading = false
            state.isRefreshing = false
            state.errorMessage = error.chargeMessage
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

    public func setDateFilter(_ filter: ChargeDateFilter) {
        state.dateFilter = filter
        applyFilters()
    }

    public func setTypeFilter(_ filter: ChargeTypeFilter) {
        state.typeFilter = filter == state.typeFilter && filter != .all ? .all : filter
        applyFilters()
    }

    public func setCostFilter(_ filter: ChargeCostFilter) {
        state.costFilter = filter
        applyFilters()
    }

    public func reloadCostOverrides() async {
        guard let carId else {
            return
        }
        do {
            costOverrides = try await costOverrideStore.costOverrides(carId: carId)
        } catch {
            costOverrides = [:]
        }
        applyFilters()
    }

    public var hasPricingRules: Bool {
        !pricingRules.isEmpty
    }

    public func preparePricingBatchPreview() {
        rebuildPricingBatchPreview(preserving: nil, selectedChargeIDs: nil)
    }

    public func setPricingBatchSelection(chargeId: Int, isSelected: Bool) {
        guard state.pricingBatch.candidates.contains(where: { $0.chargeId == chargeId }) else {
            return
        }
        if isSelected {
            state.pricingBatch.selectedChargeIDs.insert(chargeId)
        } else {
            state.pricingBatch.selectedChargeIDs.remove(chargeId)
        }
    }

    public func applyPricingBatch() async {
        guard let costUpdater else {
            state.pricingBatch.errorMessage = "Charge cost writeback is unavailable."
            return
        }
        let selected = state.pricingBatch.candidates.filter { state.pricingBatch.selectedChargeIDs.contains($0.chargeId) }
        guard !selected.isEmpty else { return }

        state.pricingBatch.isApplying = true
        state.pricingBatch.errorMessage = nil
        var results: [ChargePricingBatchWriteResult] = []
        var successfulCosts: [Int: Double?] = [:]

        for candidate in selected {
            switch await costUpdater.updateChargeCost(chargeId: candidate.chargeId, cost: candidate.estimatedCost) {
            case .success:
                results.append(ChargePricingBatchWriteResult(
                    chargeId: candidate.chargeId,
                    startDate: candidate.startDate,
                    ruleID: candidate.ruleID,
                    ruleName: candidate.ruleName,
                    previousCost: candidate.previousCost,
                    newCost: candidate.estimatedCost,
                    succeeded: true,
                    message: nil
                ))
                successfulCosts[candidate.chargeId] = candidate.estimatedCost
                state.pricingBatch.selectedChargeIDs.remove(candidate.chargeId)
            case let .failure(error):
                results.append(ChargePricingBatchWriteResult(
                    chargeId: candidate.chargeId,
                    startDate: candidate.startDate,
                    ruleID: candidate.ruleID,
                    ruleName: candidate.ruleName,
                    previousCost: candidate.previousCost,
                    newCost: candidate.estimatedCost,
                    succeeded: false,
                    message: error.chargeMessage
                ))
            }
        }

        replaceAPICosts(successfulCosts)
        let receipt = ChargePricingBatchReceipt(createdAt: Date(), results: results, rollbackResults: nil)
        await persistPricingAudit(receipt)
        let failedIDs = Set(results.filter { !$0.succeeded }.map(\.chargeId))
        rebuildPricingBatchPreview(preserving: receipt, selectedChargeIDs: failedIDs)
        state.pricingBatch.isApplying = false
        applyFilters()
    }

    public func rollbackLastPricingBatch() async {
        guard let costUpdater, var receipt = state.pricingBatch.lastReceipt else { return }
        let successfulWrites = receipt.results.filter(\.succeeded)
        guard !successfulWrites.isEmpty else { return }

        state.pricingBatch.isRollingBack = true
        state.pricingBatch.errorMessage = nil
        var rollbackResults: [ChargePricingBatchRollbackResult] = []
        var restoredCosts: [Int: Double?] = [:]

        for result in successfulWrites {
            switch await costUpdater.updateChargeCost(chargeId: result.chargeId, cost: result.previousCost) {
            case .success:
                rollbackResults.append(ChargePricingBatchRollbackResult(
                    chargeId: result.chargeId,
                    restoredCost: result.previousCost,
                    succeeded: true,
                    message: nil
                ))
                restoredCosts[result.chargeId] = .some(result.previousCost)
            case let .failure(error):
                rollbackResults.append(ChargePricingBatchRollbackResult(
                    chargeId: result.chargeId,
                    restoredCost: result.previousCost,
                    succeeded: false,
                    message: error.chargeMessage
                ))
            }
        }

        replaceAPICosts(restoredCosts)
        receipt.rollbackResults = rollbackResults
        await persistPricingAudit(receipt)
        rebuildPricingBatchPreview(
            preserving: receipt,
            selectedChargeIDs: state.pricingBatch.selectedChargeIDs
        )
        state.pricingBatch.isRollingBack = false
        applyFilters()
    }

    private func rebuildPricingBatchPreview(
        preserving receipt: ChargePricingBatchReceipt?,
        selectedChargeIDs preservedSelection: Set<Int>?
    ) {
        var candidates: [ChargePricingBatchCandidate] = []
        var selectedIDs: Set<Int> = []
        var manualOverrideExcludedCount = 0
        var alreadyCorrectCount = 0
        var unmatchedCount = 0

        for item in allItems {
            if costOverrides[item.chargeId] != nil {
                manualOverrideExcludedCount += 1
                continue
            }
            guard let estimate = pricingEstimate(for: item),
                  let energy = item.chargeEnergyAdded,
                  energy.isFinite,
                  energy >= 0,
                  estimate.cost.isFinite,
                  estimate.cost >= 0
            else {
                unmatchedCount += 1
                continue
            }
            if let cost = item.cost, abs(cost - estimate.cost) < 0.005 {
                alreadyCorrectCount += 1
                continue
            }
            let changeKind: ChargePricingBatchChangeKind = item.cost == nil ? .fillMissing : .replaceRecorded
            candidates.append(ChargePricingBatchCandidate(
                chargeId: item.chargeId,
                startDate: item.startDate,
                address: item.address,
                energyKWh: energy,
                previousCost: item.cost,
                estimatedCost: estimate.cost,
                ruleID: estimate.rule.id,
                ruleName: estimate.rule.name,
                changeKind: changeKind
            ))
            if preservedSelection == nil, changeKind == .fillMissing {
                selectedIDs.insert(item.chargeId)
            }
        }

        candidates.sort { $0.startDate > $1.startDate }
        if let preservedSelection {
            let candidateIDs = Set(candidates.map(\.chargeId))
            selectedIDs = preservedSelection.intersection(candidateIDs)
        }
        state.pricingBatch = ChargePricingBatchState(
            candidates: candidates,
            selectedChargeIDs: selectedIDs,
            manualOverrideExcludedCount: manualOverrideExcludedCount,
            alreadyCorrectCount: alreadyCorrectCount,
            unmatchedCount: unmatchedCount,
            lastReceipt: receipt,
            auditHistory: state.pricingBatch.auditHistory,
            auditErrorMessage: state.pricingBatch.auditErrorMessage
        )
    }

    private func persistPricingAudit(_ receipt: ChargePricingBatchReceipt) async {
        guard let carId else { return }
        do {
            try await pricingAuditStore.save(carId: carId, currencyCode: currencyCode, receipt: receipt)
            state.pricingBatch.auditHistory = try await pricingAuditStore.records(carId: carId, limit: 100)
            state.pricingBatch.auditErrorMessage = nil
        } catch {
            state.pricingBatch.auditErrorMessage = error.localizedDescription
        }
    }

    private func reloadPricingAuditHistory() async {
        guard let carId else { return }
        do {
            state.pricingBatch.auditHistory = try await pricingAuditStore.records(carId: carId, limit: 100)
            state.pricingBatch.auditErrorMessage = nil
        } catch {
            state.pricingBatch.auditHistory = []
            state.pricingBatch.auditErrorMessage = error.localizedDescription
        }
    }

    private func replaceAPICosts(_ costs: [Int: Double?]) {
        guard !costs.isEmpty else { return }
        allItems = allItems.map { item in
            guard costs.keys.contains(item.chargeId) else { return item }
            return ChargeSummaryItem(
                chargeId: item.chargeId,
                carId: item.carId,
                startDate: item.startDate,
                endDate: item.endDate,
                chargeEnergyAdded: item.chargeEnergyAdded,
                cost: costs[item.chargeId] ?? nil,
                durationMin: item.durationMin,
                address: item.address,
                latitude: item.latitude,
                longitude: item.longitude
            )
        }
    }

    private func applyFilters() {
        let showShortEntries = fixedShowShortEntries ?? true
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

        let shortFiltered = showShortEntries
            ? dateFiltered
            : dateFiltered.filter {
                guard let energy = $0.chargeEnergyAdded else { return true }
                return ShortEntryFilter.isSignificantCharge(energyKilowattHours: energy)
            }

        let typed = shortFiltered.filter { item in
            let isDc = isDc(item)
            switch state.typeFilter {
            case .all:
                return true
            case .ac:
                return !isDc
            case .dc:
                return isDc
            }
        }

        let costed = typed.filter { item in
            let cost = effectiveCost(for: item)
            switch state.costFilter {
            case .all:
                return true
            case .hasCost:
                return cost != nil
            case .noCost:
                return cost == nil
            case .free:
                return cost == 0
            }
        }

        let rows = costed
            .sorted { lhs, rhs in lhs.startDate > rhs.startDate }
            .map { item in
                ChargeRow(
                    chargeId: item.chargeId,
                    startDate: item.startDate,
                    endDate: item.endDate,
                    energyAdded: item.chargeEnergyAdded,
                    cost: effectiveCost(for: item),
                    hasManualCost: costOverrides[item.chargeId] != nil,
                    durationMin: item.durationMin,
                    address: item.address,
                    isDc: isDc(item),
                    costSource: costSource(for: item)
                )
            }

        state.rows = rows
        state.summary = Self.summary(for: rows)
        state.chartData = Self.chartData(for: rows)
        state.isLoading = false
        state.isRefreshing = false
        state.errorMessage = nil
    }

    private func isDc(_ item: ChargeSummaryItem) -> Bool {
        ChargeStatsCalculator.isDcCharge(
            chargeId: item.chargeId,
            energyAddedKwh: item.chargeEnergyAdded,
            durationMin: item.durationMin,
            dcChargeIds: dcChargeIds,
            processedChargeIds: processedChargeIds
        )
    }

    private func effectiveCost(for item: ChargeSummaryItem) -> Double? {
        costOverrides[item.chargeId] ?? pricingEstimate(for: item)?.cost ?? item.cost
    }

    private func costSource(for item: ChargeSummaryItem) -> ChargeCostSource {
        if costOverrides[item.chargeId] != nil {
            return .manual
        }
        if pricingEstimate(for: item) != nil {
            return .pricingRule
        }
        if item.cost != nil {
            return .api
        }
        return .none
    }

    private func pricingEstimate(for item: ChargeSummaryItem) -> ChargePricingEstimate? {
        let pricingAggregate = chargePricingAggregates[item.chargeId]
        let summaryIsDc = isDc(item)
        return ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: item.startDate,
                endDate: item.endDate,
                address: item.address,
                latitude: item.latitude,
                longitude: item.longitude,
                energyAddedKWh: item.chargeEnergyAdded,
                energySamples: pricingAggregate?.energySamples ?? [],
                isDc: pricingAggregate?.isDc ?? summaryIsDc,
                chargerIdentity: pricingAggregate?.chargerIdentity
            ),
            rules: pricingRules
        )
    }

    private func cutoffDate(for filter: ChargeDateFilter) -> Date? {
        guard let dayCount = filter.dayCount else {
            return nil
        }
        return Calendar.current.date(byAdding: .day, value: -(dayCount - 1), to: Calendar.current.startOfDay(for: Date()))
    }

    private static func summary(for rows: [ChargeRow]) -> ChargesSummary {
        guard !rows.isEmpty else {
            return .empty
        }
        let energies = rows.compactMap(\.energyAdded)
        let energy = energies.isEmpty ? nil : energies.reduce(0, +)
        let pricedRows = rows.filter { $0.cost != nil }
        let cost = pricedRows.reduce(0) { $0 + ($1.cost ?? 0) }
        return ChargesSummary(
            totalCharges: rows.count,
            totalEnergyAdded: energy,
            energyRecordCount: energies.count,
            energyIsComplete: energies.count == rows.count,
            totalCost: cost,
            averageEnergyPerCharge: energy.map { $0 / Double(energies.count) },
            averageCostPerCharge: pricedRows.isEmpty ? 0 : cost / Double(pricedRows.count),
            pricedChargeCount: pricedRows.count,
            missingCostCount: rows.count - pricedRows.count,
            apiCostCount: rows.filter { $0.costSource == .api }.count,
            pricingRuleCostCount: rows.filter { $0.costSource == .pricingRule }.count,
            manualCostCount: rows.filter { $0.costSource == .manual }.count
        )
    }

    private static func chartData(for rows: [ChargeRow]) -> [ChargeChartPoint] {
        let calendar = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: rows) { row -> String in
            guard let date = DomainDateParser.date(from: row.startDate) else {
                return "Unknown"
            }
            let components = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }
        return grouped
            .map { label, rows in
                let energies = rows.compactMap(\.energyAdded)
                return ChargeChartPoint(
                    label: label,
                    count: rows.count,
                    totalEnergy: energies.isEmpty ? nil : energies.reduce(0, +),
                    energyRecordCount: energies.count,
                    energyIsComplete: energies.count == rows.count,
                    totalCost: rows.reduce(0) { $0 + ($1.cost ?? 0) }
                )
            }
            .sorted { $0.label < $1.label }
    }

}

extension APIError {
    var chargeMessage: String {
        switch self {
        case .serverNotConfigured:
            return "Configure your TeslaMate server before loading charges."
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
            return "TeslaMate returned no charge data."
        }
    }
}
