import Combine
import Foundation

public enum ChargeCostSyncState: Equatable, Sendable {
    case none
    case server
    case localOnly
}

public struct ChargeDetailState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var isShowingSummary: Bool
    public var errorMessage: String?
    public var chargeDetail: ChargeDetail?
    public var units: UnitPreferences?
    public var stats: ChargeDetailStats?
    public var isDcCharge: Bool
    public var apiCost: Double?
    public var manualCost: Double?
    public var pricingRuleCost: Double?
    public var pricingRuleName: String?
    public var pricingRuleMatchFactors: [ChargePricingMatchFactor]
    public var pricingBreakdown: [ChargePricingCostComponent]
    public var pricingSessionFee: Double
    public var hasPricingRules: Bool
    public var effectiveCost: Double?
    public var costSource: ChargeCostSource
    public var costSyncState: ChargeCostSyncState
    public var currencySymbol: String
    public var tripMembership: TripMembership?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        isShowingSummary: Bool = false,
        errorMessage: String? = nil,
        chargeDetail: ChargeDetail? = nil,
        units: UnitPreferences? = nil,
        stats: ChargeDetailStats? = nil,
        isDcCharge: Bool = false,
        apiCost: Double? = nil,
        manualCost: Double? = nil,
        pricingRuleCost: Double? = nil,
        pricingRuleName: String? = nil,
        pricingRuleMatchFactors: [ChargePricingMatchFactor] = [],
        pricingBreakdown: [ChargePricingCostComponent] = [],
        pricingSessionFee: Double = 0,
        hasPricingRules: Bool = false,
        effectiveCost: Double? = nil,
        costSource: ChargeCostSource = .none,
        costSyncState: ChargeCostSyncState = .none,
        currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol(),
        tripMembership: TripMembership? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.isShowingSummary = isShowingSummary
        self.errorMessage = errorMessage
        self.chargeDetail = chargeDetail
        self.units = units
        self.stats = stats
        self.isDcCharge = isDcCharge
        self.apiCost = apiCost
        self.manualCost = manualCost
        self.pricingRuleCost = pricingRuleCost
        self.pricingRuleName = pricingRuleName
        self.pricingRuleMatchFactors = pricingRuleMatchFactors
        self.pricingBreakdown = pricingBreakdown
        self.pricingSessionFee = pricingSessionFee
        self.hasPricingRules = hasPricingRules
        self.effectiveCost = effectiveCost
        self.costSource = costSource
        self.costSyncState = costSyncState
        self.currencySymbol = currencySymbol
        self.tripMembership = tripMembership
    }
}

public struct ChargeDetailCacheKey: Hashable, Sendable {
    public let serverURL: String
    public let carId: Int
    public let chargeId: Int

    public init(serverURL: String, carId: Int, chargeId: Int) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.carId = carId
        self.chargeId = chargeId
    }
}

public final class ChargeDetailStateCache: @unchecked Sendable {
    public static let shared = ChargeDetailStateCache()

    private let lock = NSLock()
    private let maximumEntryCount: Int
    private var states: [ChargeDetailCacheKey: ChargeDetailState] = [:]
    private var recency: [ChargeDetailCacheKey] = []

    public init(maximumEntryCount: Int = 32) {
        self.maximumEntryCount = max(maximumEntryCount, 1)
    }

    public func state(for key: ChargeDetailCacheKey) -> ChargeDetailState? {
        lock.withLock {
            guard let state = states[key] else { return nil }
            markRecentlyUsed(key)
            return state
        }
    }

    public func save(_ state: ChargeDetailState, for key: ChargeDetailCacheKey) {
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

    public func removeAll() {
        lock.withLock {
            states.removeAll()
            recency.removeAll()
        }
    }

    private func markRecentlyUsed(_ key: ChargeDetailCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

private struct ChargeCostResolutionContext {
    let currencyCode: String
    let isAC: Bool
    let geofenceKind: GeofenceKind?
    let pricingInput: ChargePricingInput
    let rules: [ChargePricingRule]
    let regionalRule: ChargePricingRule?

    func input(manualCost: Double?, apiCost: Double?) -> ChargeCostResolutionInput {
        ChargeCostResolutionInput(
            manualCost: manualCost,
            apiCost: apiCost,
            currencyCode: currencyCode,
            isAC: isAC,
            geofenceKind: geofenceKind,
            pricingInput: pricingInput,
            rules: rules,
            regionalRule: regionalRule
        )
    }
}

@MainActor
public final class ChargeDetailViewModel: ObservableObject {
    @Published public private(set) var state: ChargeDetailState

    private let api: any ChargeAPIProviding
    private let settingsStore: (any SettingsStoring)?
    private let summaryCache: (any ChargeSummaryCaching)?
    private let costOverrideStore: any ChargeCostOverriding
    private let tripMembershipManager: (any TripMembershipManaging)?
    private let regionalTariffCatalog: @Sendable () throws -> RegionalChargingTariffCatalog
    private let cacheKey: ChargeDetailCacheKey?
    private let stateCache: ChargeDetailStateCache
    private var costResolutionContext: ChargeCostResolutionContext?

    public init(
        api: any ChargeAPIProviding,
        settingsStore: (any SettingsStoring)? = nil,
        summaryCache: (any ChargeSummaryCaching)? = nil,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        tripMembershipManager: (any TripMembershipManaging)? = nil,
        regionalTariffCatalog: @escaping @Sendable () throws -> RegionalChargingTariffCatalog = {
            try RegionalChargingTariffCatalog.load()
        },
        cacheKey: ChargeDetailCacheKey? = nil,
        stateCache: ChargeDetailStateCache = .shared,
        initialState: ChargeDetailState = ChargeDetailState()
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.summaryCache = summaryCache
        self.costOverrideStore = costOverrideStore
        self.tripMembershipManager = tripMembershipManager
        self.regionalTariffCatalog = regionalTariffCatalog
        self.cacheKey = cacheKey
        self.stateCache = stateCache
        self.state = cacheKey.flatMap { stateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int, chargeId: Int) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.chargeDetail == nil
        state.errorMessage = nil
        if state.chargeDetail == nil {
            state.costSyncState = .none
            state.hasPricingRules = false
        }

        let cachedSummary = await loadCachedSummary(carId: carId, chargeId: chargeId)
        if state.chargeDetail == nil, let cachedSummary {
            applyDetail(cachedSummary.previewDetail, isShowingSummary: true)
        }

        async let detailResult = api.chargeDetail(carId: carId, chargeId: chargeId)
        async let statusResult = api.carStatus(carId: carId)
        async let membershipResult = loadMembership(carId: carId, chargeId: chargeId)
        async let settingsResult = loadSettings()
        async let manualCostResult = loadManualCost(carId: carId, chargeId: chargeId)

        switch await detailResult {
        case let .success(detail):
            applyDetail(detail, isShowingSummary: false)
            let settings = await settingsResult
            let manualCost = await manualCostResult
            applyCosts(detail: detail, settings: settings, manualCost: manualCost, carId: carId)
            saveCachedState()
        case let .failure(error):
            state.isLoading = false
            let settings = await settingsResult
            let manualCost = await manualCostResult
            if let detail = state.chargeDetail {
                state.errorMessage = error.chargeMessage
                applyCosts(detail: detail, settings: settings, manualCost: manualCost, carId: carId)
                saveCachedState()
            } else {
                state.errorMessage = error.chargeMessage
            }
        }

        if case let .success(payload) = await statusResult {
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
        }
        state.tripMembership = await membershipResult
        state.isRefreshing = false
        saveCachedState()
    }

    public func removeFromTrip(carId: Int, chargeId: Int) async {
        guard let tripMembershipManager else { return }
        do {
            try await tripMembershipManager.remove(carId: carId, leg: .charge(chargeId))
            state.tripMembership = nil
            state.errorMessage = nil
            saveCachedState()
        } catch { state.errorMessage = error.localizedDescription }
    }

    private func loadMembership(carId: Int, chargeId: Int) async -> TripMembership? {
        try? await tripMembershipManager?.membership(carId: carId, leg: .charge(chargeId))
    }

    private func loadSettings() async -> AppSettings? {
        await settingsStore?.load()
    }

    private func loadManualCost(carId: Int, chargeId: Int) async -> Double? {
        try? await costOverrideStore.costOverride(carId: carId, chargeId: chargeId)
    }

    private func loadCachedSummary(carId: Int, chargeId: Int) async -> ChargeSummaryItem? {
        await summaryCache?.load(carId: carId).first { $0.chargeId == chargeId }
    }

    private func applyDetail(_ detail: ChargeDetail, isShowingSummary: Bool) {
        state.chargeDetail = detail
        state.stats = ChargingSessionAnalyzer.calculateStats(detail)
        state.isDcCharge = ChargingSessionAnalyzer.detectDcCharge(detail)
            || ChargingSessionAnalyzer.isDcCharge(
                chargeId: detail.chargeId,
                energyAddedKwh: state.stats?.energyAdded,
                durationMin: state.stats?.durationMin,
                dcChargeIds: [],
                processedChargeIds: []
            )
        state.isShowingSummary = isShowingSummary
        state.isLoading = false
        saveCachedState()
    }

    private func applyCosts(
        detail: ChargeDetail,
        settings: AppSettings?,
        manualCost: Double?,
        carId: Int
    ) {
        let pricingRules = (settings?.chargePricingRules ?? []).filter { $0.origin != .regionalOfficial }
        let currencyCode = settings?.resolvedCurrencyCode() ?? MateDriveCurrencyFormatter.systemCurrencyCode()
        state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: currencyCode)
        state.hasPricingRules = !pricingRules.isEmpty
        let measuredIdentity = ChargingSessionAnalyzer.chargerIdentity(detail)
        let pricingIdentity: ChargePricingChargerIdentity = state.isDcCharge && measuredIdentity == .ac
            ? .unknownDC
            : measuredIdentity
        let billing = ChargeBillingEvidence.energyAndSamples(
            wallEnergy: detail.chargeEnergyUsed ?? state.stats?.energyUsed,
            batteryEnergy: detail.chargeEnergyAdded ?? state.stats?.energyAdded,
            samples: (detail.chargePoints ?? []).map {
                ChargePricingEnergySample(date: $0.date, cumulativeEnergyAddedKWh: $0.chargeEnergyAdded)
            }
        )
        let pricingInput = ChargePricingInput(
            startDate: detail.startDate,
            endDate: detail.endDate,
            address: detail.address,
            latitude: detail.latitude,
            longitude: detail.longitude,
            energyAddedKWh: billing.energy,
            energySamples: billing.samples,
            isDc: state.isDcCharge,
            chargerIdentity: pricingIdentity
        )
        let inferenceRecord = ChargeSummaryRecord(
            chargeId: detail.chargeId,
            carId: carId,
            startDate: detail.startDate ?? "",
            endDate: detail.endDate,
            chargeEnergyAdded: detail.chargeEnergyAdded ?? state.stats?.energyAdded,
            cost: detail.cost,
            durationMin: detail.durationMin ?? state.stats?.durationMin,
            address: detail.address,
            latitude: detail.latitude,
            longitude: detail.longitude,
            chargeEnergyUsed: detail.chargeEnergyUsed ?? state.stats?.energyUsed
        )
        let locationInference = settings.map {
            AutomaticChargeCostEstimator.inferLocation(
                record: inferenceRecord,
                settings: $0,
                isDC: state.isDcCharge
            )
        } ?? ChargeLocationInference(kind: nil, source: .none, confidence: 0)
        let geofenceKind = locationInference.kind
        let regionalRule = regionalPricingRule(settings: settings, pricingInput: pricingInput)
        state.hasPricingRules = !pricingRules.isEmpty || regionalRule != nil
        costResolutionContext = ChargeCostResolutionContext(
            currencyCode: currencyCode,
            isAC: !state.isDcCharge,
            geofenceKind: geofenceKind,
            pricingInput: pricingInput,
            rules: pricingRules,
            regionalRule: regionalRule
        )

        let ruleResolution = ChargeCostResolver.resolve(ChargeCostResolutionInput(
            manualCost: nil,
            apiCost: nil,
            currencyCode: currencyCode,
            isAC: !state.isDcCharge,
            geofenceKind: geofenceKind,
            pricingInput: pricingInput,
            rules: pricingRules,
            regionalRule: regionalRule
        ))
        let resolvedRule = ruleResolution?.ruleID.flatMap { ruleID in
            (pricingRules + [regionalRule].compactMap { $0 }).first { $0.id == ruleID }
        }
        state.apiCost = detail.cost
        state.manualCost = manualCost
        state.costSyncState = Self.costSyncState(manualCost: manualCost, apiCost: detail.cost)
        state.pricingRuleCost = ruleResolution?.amount
        state.pricingRuleName = resolvedRule?.name
        state.pricingRuleMatchFactors = resolvedRule.map { rule in
            var factors = Self.matchFactors(rule)
            if rule.origin == .regionalOfficial,
               locationInference.source == .overnightACPattern
            {
                factors.append(.inferredHome)
            }
            return factors
        } ?? []
        state.pricingBreakdown = ruleResolution?.components ?? []
        state.pricingSessionFee = ruleResolution?.sessionFee ?? 0
        applyEffectiveCost()
    }

    private static func matchFactors(_ rule: ChargePricingRule) -> [ChargePricingMatchFactor] {
        var factors: [ChargePricingMatchFactor] = []
        if rule.origin == .regionalOfficial {
            factors.append(.regionalTariff)
        }
        if rule.isHistoricalReference {
            factors.append(.historicalReference)
        }
        if rule.addressKeyword?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || (rule.latitude != nil && rule.longitude != nil && rule.radiusMeters != nil)
            || rule.stationKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            factors.append(.savedLocation)
        }
        if rule.startMinuteOfDay != nil || rule.endMinuteOfDay != nil || !rule.timeSegments.isEmpty {
            factors.append(.chargingTime)
        }
        if rule.chargeType != .any {
            factors.append(.chargerType)
        }
        if rule.applicableWeekdays?.isEmpty == false {
            factors.append(.weekday)
        }
        if rule.effectiveFromDate != nil || rule.effectiveToDate != nil || rule.applicableMonths?.isEmpty == false {
            factors.append(.seasonalDate)
        }
        return factors
    }

    private func regionalPricingRule(
        settings: AppSettings?,
        pricingInput: ChargePricingInput
    ) -> ChargePricingRule? {
        guard let catalog = try? regionalTariffCatalog(),
              let regionCode = settings?.residentialTariffRegionCode
                ?? catalog.regionCode(matchingAddress: pricingInput.address),
              let startDate = pricingInput.startDate.flatMap(DomainDateParser.date(from:)),
              var rule = catalog.estimationRule(regionCode: regionCode, date: startDate)
        else {
            return nil
        }
        rule.name = catalog.localizedRuleName(
            regionCode: regionCode,
            isHistoricalReference: rule.isHistoricalReference,
            language: settings?.appLanguage ?? .system
        )
        return rule
    }

    @discardableResult
    public func saveCostOverride(carId: Int, chargeId: Int, cost: Double?) async -> Bool {
        guard Self.isValidManualCost(cost) else {
            state.errorMessage = "Charge cost must be zero or greater."
            return false
        }

        let serverResult = await api.updateChargeCost(chargeId: chargeId, cost: cost)
        switch serverResult {
        case .success:
            do {
                try await costOverrideStore.saveCostOverride(carId: carId, chargeId: chargeId, cost: cost)
            } catch {
                state.errorMessage = error.localizedDescription
                return false
            }
            state.apiCost = cost
            state.manualCost = cost
            state.costSyncState = .server
            applyEffectiveCost()
            state.errorMessage = nil
            saveCachedState()
            return true
        case .failure:
            do {
                try await costOverrideStore.saveCostOverride(carId: carId, chargeId: chargeId, cost: cost)
                state.manualCost = cost
                state.costSyncState = .localOnly
                applyEffectiveCost()
                state.errorMessage = nil
                saveCachedState()
                return true
            } catch {
                state.errorMessage = error.localizedDescription
                return false
            }
        }
    }

    @discardableResult
    public func saveCostOverrideInput(carId: Int, chargeId: Int, input: String) async -> Bool {
        let normalized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else {
            return await saveCostOverride(carId: carId, chargeId: chargeId, cost: nil)
        }
        guard let cost = Double(normalized), cost.isFinite else {
            state.errorMessage = "Enter a valid charge cost."
            return false
        }
        return await saveCostOverride(carId: carId, chargeId: chargeId, cost: cost)
    }

    private func applyEffectiveCost() {
        let resolution = costResolutionContext.flatMap({ context in
            ChargeCostResolver.resolve(context.input(
                manualCost: state.manualCost,
                apiCost: state.apiCost
            ))
        })
        if resolution == nil,
           let manualCost = state.manualCost,
           manualCost.isFinite,
           manualCost >= 0 {
            state.effectiveCost = manualCost
            state.costSource = .manual
            return
        }
        guard let resolution else {
            state.effectiveCost = nil
            state.costSource = .none
            return
        }

        state.effectiveCost = resolution.amount
        switch resolution.source {
        case .manual:
            state.costSource = .manual
        case .api:
            state.costSource = .api
        case .stationRule, .homeRule, .regionalTariff:
            state.costSource = .pricingRule
        }
    }

    private static func isValidManualCost(_ cost: Double?) -> Bool {
        guard let cost else {
            return true
        }
        return cost.isFinite && cost >= 0
    }

    private static func costSyncState(manualCost: Double?, apiCost: Double?) -> ChargeCostSyncState {
        guard let manualCost else {
            return .none
        }
        guard let apiCost else {
            return .localOnly
        }
        return abs(manualCost - apiCost) < 0.000_001 ? .server : .localOnly
    }

    private func saveCachedState() {
        guard let cacheKey, state.chargeDetail != nil else { return }
        stateCache.save(state, for: cacheKey)
    }

}

private extension ChargeSummaryItem {
    var previewDetail: ChargeDetail {
        ChargeDetail(
            chargeId: chargeId,
            startDate: startDate,
            endDate: endDate,
            address: address,
            chargeEnergyAdded: chargeEnergyAdded,
            chargeEnergyUsed: chargeEnergyUsed,
            cost: cost,
            durationMin: durationMin,
            batteryDetails: ChargeBatteryDetails(
                startBatteryLevel: startBatteryLevel,
                endBatteryLevel: endBatteryLevel
            ),
            rangeRated: ChargeRange(
                startRange: startRatedRangeKm,
                endRange: endRatedRangeKm
            ),
            odometer: odometerKm,
            latitude: latitude,
            longitude: longitude
        )
    }
}
