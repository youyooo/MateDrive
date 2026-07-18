import Foundation

public struct ChargeCostResolution: Equatable, Sendable {
    public let amount: Double
    public let source: SmartActivityChargeCostSource
    public let currencyCode: String
    public let ruleID: String?
    public let unitPricePerKWh: Double?
    public let serviceFee: Double
    public let sessionFee: Double
    public let parkingFeeRuleID: String?
    public let components: [ChargePricingCostComponent]
    public let isEstimated: Bool
    public let isExplicitlyFree: Bool

    public init(
        amount: Double,
        source: SmartActivityChargeCostSource,
        currencyCode: String,
        ruleID: String? = nil,
        unitPricePerKWh: Double? = nil,
        serviceFee: Double = 0,
        sessionFee: Double = 0,
        parkingFeeRuleID: String? = nil,
        components: [ChargePricingCostComponent] = [],
        isEstimated: Bool,
        isExplicitlyFree: Bool
    ) {
        self.amount = amount
        self.source = source
        self.currencyCode = currencyCode
        self.ruleID = ruleID
        self.unitPricePerKWh = unitPricePerKWh
        self.serviceFee = serviceFee
        self.sessionFee = sessionFee
        self.parkingFeeRuleID = parkingFeeRuleID
        self.components = components
        self.isEstimated = isEstimated
        self.isExplicitlyFree = isExplicitlyFree
    }
}

public struct ChargeCostResolutionInput: Sendable {
    public let manualCost: Double?
    public let apiCost: Double?
    public let currencyCode: String
    public let isAC: Bool
    public let geofenceKind: GeofenceKind?
    public let pricingInput: ChargePricingInput
    public let rules: [ChargePricingRule]
    public let regionalRule: ChargePricingRule?

    public init(
        manualCost: Double?,
        apiCost: Double?,
        currencyCode: String,
        isAC: Bool,
        geofenceKind: GeofenceKind?,
        pricingInput: ChargePricingInput,
        rules: [ChargePricingRule],
        regionalRule: ChargePricingRule?
    ) {
        self.manualCost = manualCost
        self.apiCost = apiCost
        self.currencyCode = currencyCode
        self.isAC = isAC
        self.geofenceKind = geofenceKind
        self.pricingInput = pricingInput
        self.rules = rules
        self.regionalRule = regionalRule
    }
}

public enum ChargeCostResolver {
    public static func resolve(_ input: ChargeCostResolutionInput) -> ChargeCostResolution? {
        guard let selectedCurrency = ChargePricingCurrencyCode.normalized(input.currencyCode),
              ChargePricingCurrencyCode.isValid(selectedCurrency) else {
            return nil
        }
        if let manualCost = input.manualCost,
           manualCost.isFinite,
           manualCost >= 0
        {
            return ChargeCostResolution(
                amount: manualCost,
                source: .manual,
                currencyCode: selectedCurrency,
                isEstimated: false,
                isExplicitlyFree: manualCost == 0
            )
        }

        if let apiCost = input.apiCost,
           apiCost.isFinite,
           apiCost > 0
        {
            return ChargeCostResolution(
                amount: apiCost,
                source: .api,
                currencyCode: selectedCurrency,
                isEstimated: false,
                isExplicitlyFree: false
            )
        }

        if let estimate = bestUserOrStationEstimate(input, currencyCode: selectedCurrency) {
            let source: SmartActivityChargeCostSource
            switch estimate.rule.origin {
            case .stationLearned:
                source = .stationRule
            case .user:
                source = input.geofenceKind == .home ? .homeRule : .stationRule
            case .regionalOfficial:
                return nil
            }
            return resolution(
                from: estimate,
                source: source,
                selectedCurrency: selectedCurrency,
                input: input
            )
        }

        guard input.isAC,
              input.geofenceKind == .home,
              let regionalRule = input.regionalRule,
              isValidRegionalRule(regionalRule, currencyCode: selectedCurrency),
              let estimate = ChargePricingRuleEngine.estimateCost(
                  for: input.pricingInput,
                  rules: [regionalRule]
              )
        else {
            return nil
        }
        return resolution(
            from: estimate,
            source: .regionalTariff,
            selectedCurrency: selectedCurrency,
            input: input
        )
    }

    private static func bestUserOrStationEstimate(
        _ input: ChargeCostResolutionInput,
        currencyCode: String
    ) -> ChargePricingEstimate? {
        input.rules
            .filter {
                $0.origin != .regionalOfficial &&
                    currencyMatches(rule: $0, selectedCurrency: currencyCode)
            }
            .sorted(by: rulePrecedes)
            .lazy
            .compactMap {
                ChargePricingRuleEngine.estimateCost(for: input.pricingInput, rules: [$0])
            }
            .first
    }

    private static func currencyMatches(
        rule: ChargePricingRule,
        selectedCurrency: String
    ) -> Bool {
        guard let ruleCurrency = ChargePricingCurrencyCode.normalized(rule.currencyCode) else {
            return rule.origin == .user
        }
        return ruleCurrency == selectedCurrency
    }

    private static func isValidRegionalRule(
        _ rule: ChargePricingRule,
        currencyCode: String
    ) -> Bool {
        guard rule.origin == .regionalOfficial,
              rule.regionCode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              let source = rule.sourceURL.flatMap(URL.init(string:)),
              ["http", "https"].contains(source.scheme?.lowercased() ?? ""),
              let verifiedAt = rule.verifiedAt,
              ChargePricingDate.isValid(verifiedAt),
              let effectiveFromDate = rule.effectiveFromDate,
              ChargePricingDate.isValid(effectiveFromDate),
              let ruleCurrency = rule.currencyCode,
              ChargePricingCurrencyCode.isValid(ruleCurrency),
              ruleCurrency == currencyCode
        else {
            return false
        }
        return true
    }

    private static func rulePrecedes(_ lhs: ChargePricingRule, _ rhs: ChargePricingRule) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        let lhsOrigin = originPrecedence(lhs.origin)
        let rhsOrigin = originPrecedence(rhs.origin)
        if lhsOrigin != rhsOrigin {
            return lhsOrigin > rhsOrigin
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func originPrecedence(_ origin: ChargePricingRuleOrigin) -> Int {
        switch origin {
        case .user: return 2
        case .stationLearned: return 1
        case .regionalOfficial: return 0
        }
    }

    private static func resolution(
        from estimate: ChargePricingEstimate,
        source: SmartActivityChargeCostSource,
        selectedCurrency: String,
        input: ChargeCostResolutionInput
    ) -> ChargeCostResolution {
        let energy = input.pricingInput.energyAddedKWh
        let unitPrice = energy.flatMap { value in
            value > 0 ? estimate.energyCost / value : nil
        }
        return ChargeCostResolution(
            amount: estimate.cost,
            source: source,
            currencyCode: estimate.rule.currencyCode ?? selectedCurrency,
            ruleID: estimate.rule.id,
            unitPricePerKWh: unitPrice,
            serviceFee: estimate.serviceFee,
            sessionFee: estimate.sessionFee,
            parkingFeeRuleID: estimate.rule.parkingFeeRuleID,
            components: estimate.components,
            isEstimated: true,
            isExplicitlyFree: false
        )
    }
}
