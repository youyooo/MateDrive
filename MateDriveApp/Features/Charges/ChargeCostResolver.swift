import Foundation

public enum ChargeBillingEvidence {
    public static func recordedCost(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    public static func energyAndSamples(
        wallEnergy: Double?,
        batteryEnergy: Double?,
        samples: [ChargePricingEnergySample]
    ) -> (energy: Double?, samples: [ChargePricingEnergySample]) {
        guard let wallEnergy, wallEnergy.isFinite, wallEnergy > 0 else {
            return (batteryEnergy, samples)
        }
        guard let batteryEnergy, batteryEnergy.isFinite, batteryEnergy > 0 else {
            return (wallEnergy, [])
        }

        let scale = wallEnergy / batteryEnergy
        return (
            wallEnergy,
            samples.map {
                ChargePricingEnergySample(
                    date: $0.date,
                    cumulativeEnergyAddedKWh: $0.cumulativeEnergyAddedKWh.map { $0 * scale }
                )
            }
        )
    }
}

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
    public let isHistoricalReference: Bool
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
        isHistoricalReference: Bool = false,
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
        self.isHistoricalReference = isHistoricalReference
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
            isHistoricalReference: estimate.rule.isHistoricalReference,
            isExplicitlyFree: false
        )
    }
}

public struct AutomaticChargeCostResult: Sendable {
    public let resolution: ChargeCostResolution?
    public let geofence: GeofenceRule?
    public let displayAddress: String?
    public let locationInference: ChargeLocationInference

    public init(
        resolution: ChargeCostResolution?,
        geofence: GeofenceRule?,
        displayAddress: String?,
        locationInference: ChargeLocationInference
    ) {
        self.resolution = resolution
        self.geofence = geofence
        self.displayAddress = displayAddress
        self.locationInference = locationInference
    }
}

public enum ChargeLocationInferenceSource: Equatable, Sendable {
    case none
    case savedGeofence
    case overnightACPattern
}

public struct ChargeLocationInference: Equatable, Sendable {
    public let kind: GeofenceKind?
    public let source: ChargeLocationInferenceSource
    public let confidence: Double

    public init(
        kind: GeofenceKind?,
        source: ChargeLocationInferenceSource,
        confidence: Double
    ) {
        self.kind = kind
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
    }
}

public enum AutomaticChargeCostEstimator {
    public static func resolve(
        record: ChargeSummaryRecord,
        settings: AppSettings,
        manualCost: Double?,
        catalog: RegionalChargingTariffCatalog?,
        isDC overrideIsDC: Bool? = nil,
        energySamples: [ChargePricingEnergySample] = []
    ) -> AutomaticChargeCostResult {
        let geofence = GeofenceRuleEngine.matchingRule(
            latitude: record.latitude,
            longitude: record.longitude,
            carId: record.carId,
            rules: settings.geofenceRules
        )
        let billing = ChargeBillingEvidence.energyAndSamples(
            wallEnergy: record.chargeEnergyUsed,
            batteryEnergy: record.chargeEnergyAdded,
            samples: energySamples
        )
        let isDC = overrideIsDC ?? inferredIsDC(record: record, geofence: geofence)
        let locationInference = inferLocation(record: record, geofence: geofence, isDC: isDC)
        let input = ChargePricingInput(
            startDate: record.startDate,
            endDate: record.endDate,
            address: record.address,
            latitude: record.latitude,
            longitude: record.longitude,
            energyAddedKWh: billing.energy,
            energySamples: billing.samples,
            isDc: isDC,
            chargerIdentity: isDC ? .unknownDC : .ac
        )
        let regionCode = settings.residentialTariffRegionCode
            ?? catalog?.regionCode(matchingAddress: record.address)
        let regionalRule = regionalEstimationRule(
            catalog: catalog,
            regionCode: regionCode,
            startDate: record.startDate
        )
        let resolution = ChargeCostResolver.resolve(ChargeCostResolutionInput(
            manualCost: manualCost,
            apiCost: record.cost,
            currencyCode: settings.resolvedCurrencyCode(),
            isAC: !isDC,
            geofenceKind: locationInference.kind,
            pricingInput: input,
            rules: settings.chargePricingRules.filter { $0.origin != .regionalOfficial },
            regionalRule: regionalRule
        ))
        return AutomaticChargeCostResult(
            resolution: resolution,
            geofence: geofence,
            displayAddress: geofence?.name.chargeCostNonBlank ?? record.address?.chargeCostNonBlank,
            locationInference: locationInference
        )
    }

    public static func inferLocation(
        record: ChargeSummaryRecord,
        settings: AppSettings,
        isDC: Bool
    ) -> ChargeLocationInference {
        let geofence = GeofenceRuleEngine.matchingRule(
            latitude: record.latitude,
            longitude: record.longitude,
            carId: record.carId,
            rules: settings.geofenceRules
        )
        return inferLocation(record: record, geofence: geofence, isDC: isDC)
    }

    private static func preferredBillingEnergy(_ record: ChargeSummaryRecord) -> Double? {
        if let value = record.chargeEnergyUsed, value.isFinite, value > 0 { return value }
        if let value = record.chargeEnergyAdded, value.isFinite, value >= 0 { return value }
        return nil
    }

    private static func inferredIsDC(record: ChargeSummaryRecord, geofence: GeofenceRule?) -> Bool {
        if geofence?.kind == .home { return false }
        guard let energy = preferredBillingEnergy(record), energy > 0,
              let duration = record.durationMin, duration > 0 else { return false }
        return energy / (Double(duration) / 60) > ChargingSessionAnalyzer.dcPowerFallbackThresholdKW
    }

    private static func inferLocation(
        record: ChargeSummaryRecord,
        geofence: GeofenceRule?,
        isDC: Bool
    ) -> ChargeLocationInference {
        if let geofence {
            return ChargeLocationInference(
                kind: geofence.kind,
                source: .savedGeofence,
                confidence: 1
            )
        }
        guard !isDC,
              let duration = record.durationMin,
              duration >= 45,
              record.address?.chargeCostNonBlank != nil,
              let start = DomainDateParser.date(from: record.startDate)
        else {
            return ChargeLocationInference(kind: nil, source: .none, confidence: 0)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DomainDateParser.timeZone(from: record.startDate) ?? .current
        let hour = calendar.component(.hour, from: start)
        guard hour >= 20 || hour < 7 else {
            return ChargeLocationInference(kind: nil, source: .none, confidence: 0)
        }

        var confidence = 0.45
        if duration >= 120 { confidence += 0.10 }
        if duration >= 240 { confidence += 0.10 }
        if hour >= 22 || hour < 6 { confidence += 0.05 }
        if let energy = preferredBillingEnergy(record), duration > 0 {
            let averagePower = energy / (Double(duration) / 60)
            if averagePower <= 11 { confidence += 0.05 }
        }
        return ChargeLocationInference(
            kind: .home,
            source: .overnightACPattern,
            confidence: min(confidence, 0.75)
        )
    }

    private static func regionalEstimationRule(
        catalog: RegionalChargingTariffCatalog?,
        regionCode: String?,
        startDate: String
    ) -> ChargePricingRule? {
        guard let catalog, let regionCode,
              let date = DomainDateParser.date(from: startDate)
        else { return nil }
        return catalog.estimationRule(regionCode: regionCode, date: date)
    }
}

private extension String {
    var chargeCostNonBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
