import Combine
import Foundation

public enum ChargeCostSyncState: Equatable, Sendable {
    case none
    case server
    case localOnly
}

public struct ChargeDetailState: Equatable, Sendable {
    public var isLoading: Bool
    public var errorMessage: String?
    public var chargeDetail: ChargeDetail?
    public var units: UnitPreferences?
    public var stats: ChargeDetailStats?
    public var isDcCharge: Bool
    public var apiCost: Double?
    public var manualCost: Double?
    public var pricingRuleCost: Double?
    public var pricingRuleName: String?
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
        errorMessage: String? = nil,
        chargeDetail: ChargeDetail? = nil,
        units: UnitPreferences? = nil,
        stats: ChargeDetailStats? = nil,
        isDcCharge: Bool = false,
        apiCost: Double? = nil,
        manualCost: Double? = nil,
        pricingRuleCost: Double? = nil,
        pricingRuleName: String? = nil,
        pricingBreakdown: [ChargePricingCostComponent] = [],
        pricingSessionFee: Double = 0,
        hasPricingRules: Bool = false,
        effectiveCost: Double? = nil,
        costSource: ChargeCostSource = .none,
        costSyncState: ChargeCostSyncState = .none,
        currencySymbol: String = "€",
        tripMembership: TripMembership? = nil
    ) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.chargeDetail = chargeDetail
        self.units = units
        self.stats = stats
        self.isDcCharge = isDcCharge
        self.apiCost = apiCost
        self.manualCost = manualCost
        self.pricingRuleCost = pricingRuleCost
        self.pricingRuleName = pricingRuleName
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
    private let costOverrideStore: any ChargeCostOverriding
    private let tripMembershipManager: (any TripMembershipManaging)?
    private var costResolutionContext: ChargeCostResolutionContext?

    public init(
        api: any ChargeAPIProviding,
        settingsStore: (any SettingsStoring)? = nil,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        tripMembershipManager: (any TripMembershipManaging)? = nil,
        initialState: ChargeDetailState = ChargeDetailState()
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.costOverrideStore = costOverrideStore
        self.tripMembershipManager = tripMembershipManager
        self.state = initialState
    }

    public func load(carId: Int, chargeId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        state.costSyncState = .none

        let detailResult = await api.chargeDetail(carId: carId, chargeId: chargeId)
        async let membershipResult = loadMembership(carId: carId, chargeId: chargeId)
        let statusResult = await api.carStatus(carId: carId)
        var pricingRules: [ChargePricingRule] = []
        var loadedSettings: AppSettings?
        if case let .success(payload) = statusResult {
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
        }
        if let settingsStore {
            let settings = await settingsStore.load()
            loadedSettings = settings
            state.currencySymbol = MateDroidCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())
            pricingRules = settings.chargePricingRules
            state.hasPricingRules = !pricingRules.isEmpty
        }

        switch detailResult {
        case let .success(detail):
            let manualCost: Double?
            do {
                manualCost = try await costOverrideStore.costOverride(carId: carId, chargeId: chargeId)
            } catch {
                manualCost = nil
            }
            state.chargeDetail = detail
            state.stats = ChargeStatsCalculator.calculateStats(detail)
            state.isDcCharge = ChargeStatsCalculator.detectDcCharge(detail)
                || ChargeStatsCalculator.isDcCharge(
                    chargeId: detail.chargeId,
                    energyAddedKwh: state.stats?.energyAdded,
                    durationMin: state.stats?.durationMin,
                    dcChargeIds: [],
                    processedChargeIds: []
                )
            let measuredIdentity = ChargeStatsCalculator.chargerIdentity(detail)
            let pricingIdentity: ChargePricingChargerIdentity = state.isDcCharge && measuredIdentity == .ac
                ? .unknownDC
                : measuredIdentity
            let pricingInput = ChargePricingInput(
                startDate: detail.startDate,
                endDate: detail.endDate,
                address: detail.address,
                latitude: detail.latitude,
                longitude: detail.longitude,
                energyAddedKWh: detail.chargeEnergyAdded ?? state.stats?.energyAdded,
                energySamples: (detail.chargePoints ?? []).map {
                    ChargePricingEnergySample(date: $0.date, cumulativeEnergyAddedKWh: $0.chargeEnergyAdded)
                },
                isDc: state.isDcCharge,
                chargerIdentity: pricingIdentity
            )
            let currencyCode = loadedSettings?.resolvedCurrencyCode()
                ?? MateDroidCurrencyFormatter.systemCurrencyCode()
            let geofenceKind = loadedSettings.flatMap {
                GeofenceRuleEngine.matchingRule(
                    latitude: detail.latitude,
                    longitude: detail.longitude,
                    carId: carId,
                    rules: $0.geofenceRules
                )?.kind
            }
            let regionalRule = ChargePricingRuleEngine.estimateCost(
                for: pricingInput,
                rules: pricingRules.filter { $0.origin == .regionalOfficial }
            )?.rule
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
                regionalRule: nil
            ))
            let pricingEstimate = ruleResolution?.ruleID.flatMap { ruleID in
                pricingRules.first(where: { $0.id == ruleID }).flatMap {
                    ChargePricingRuleEngine.estimateCost(for: pricingInput, rules: [$0])
                }
            }
            state.apiCost = detail.cost
            state.manualCost = manualCost
            state.costSyncState = Self.costSyncState(manualCost: manualCost, apiCost: detail.cost)
            state.pricingRuleCost = pricingEstimate?.cost
            state.pricingRuleName = pricingEstimate?.rule.name
            state.pricingBreakdown = pricingEstimate?.components ?? []
            state.pricingSessionFee = pricingEstimate?.sessionFee ?? 0
            applyEffectiveCost()
            state.isLoading = false
        case let .failure(error):
            state.isLoading = false
            state.errorMessage = error.chargeMessage
        }
        state.tripMembership = await membershipResult
    }

    public func removeFromTrip(carId: Int, chargeId: Int) async {
        guard let tripMembershipManager else { return }
        do {
            try await tripMembershipManager.remove(carId: carId, leg: .charge(chargeId))
            state.tripMembership = nil
            state.errorMessage = nil
        } catch { state.errorMessage = error.localizedDescription }
    }

    private func loadMembership(carId: Int, chargeId: Int) async -> TripMembership? {
        try? await tripMembershipManager?.membership(carId: carId, leg: .charge(chargeId))
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
            return true
        case .failure:
            do {
                try await costOverrideStore.saveCostOverride(carId: carId, chargeId: chargeId, cost: cost)
                state.manualCost = cost
                state.costSyncState = .localOnly
                applyEffectiveCost()
                state.errorMessage = nil
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
        guard let resolution = costResolutionContext.flatMap({ context in
            ChargeCostResolver.resolve(context.input(
                manualCost: state.manualCost,
                apiCost: state.apiCost
            ))
        }) else {
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

}
