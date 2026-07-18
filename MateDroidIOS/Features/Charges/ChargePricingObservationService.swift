import Foundation

public struct ChargePricingConfirmation: Equatable, Sendable {
    public let carId: Int
    public let chargeId: Int
    public let stationKey: String
    public let scope: ChargePricingObservationScope
    public let finalAmount: Double
    public let billedEnergyKWh: Double?
    public let pricePerKWh: Double?
    public let serviceFeePerKWh: Double?
    public let fixedFee: Double?
    public let currencyCode: String
    public let coordinates: GeocodeLocation?
    public let chargerIdentity: ChargePricingChargerIdentity
    public let startMinute: Int?
    public let endMinute: Int?

    public init(
        carId: Int,
        chargeId: Int,
        stationKey: String,
        scope: ChargePricingObservationScope,
        finalAmount: Double,
        billedEnergyKWh: Double?,
        pricePerKWh: Double?,
        serviceFeePerKWh: Double?,
        fixedFee: Double?,
        currencyCode: String,
        coordinates: GeocodeLocation?,
        chargerIdentity: ChargePricingChargerIdentity,
        startMinute: Int?,
        endMinute: Int?
    ) {
        self.carId = carId
        self.chargeId = chargeId
        self.stationKey = stationKey
        self.scope = scope
        self.finalAmount = finalAmount
        self.billedEnergyKWh = billedEnergyKWh
        self.pricePerKWh = pricePerKWh
        self.serviceFeePerKWh = serviceFeePerKWh
        self.fixedFee = fixedFee
        self.currencyCode = currencyCode
        self.coordinates = coordinates
        self.chargerIdentity = chargerIdentity
        self.startMinute = startMinute
        self.endMinute = endMinute
    }
}

public protocol ChargePricingObservationServicing: Sendable {
    func confirm(_ value: ChargePricingConfirmation) async throws
}

public enum ChargePricingObservationServiceError: Error, Equatable, Sendable {
    case invalidFinalAmount
    case invalidBilledEnergy
    case invalidUnitPrice
    case invalidServiceFee
    case invalidFixedFee
    case invalidCurrency
    case missingStationCoordinates
    case missingFutureUnitPrice
    case incompleteTimeWindow
    case invalidTimeWindow
}

public actor ChargePricingObservationService: ChargePricingObservationServicing {
    private let observationStore: any ChargePricingObservationStoring
    private let costOverrideStore: any ChargeCostOverriding
    private let settingsStore: any SettingsStoring
    private let now: @Sendable () -> Date
    private let idGenerator: @Sendable () -> String
    private var confirmationInProgress = false
    private var confirmationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        observationStore: any ChargePricingObservationStoring,
        costOverrideStore: any ChargeCostOverriding,
        settingsStore: any SettingsStoring,
        now: @escaping @Sendable () -> Date = Date.init,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.observationStore = observationStore
        self.costOverrideStore = costOverrideStore
        self.settingsStore = settingsStore
        self.now = now
        self.idGenerator = idGenerator
    }

    public func confirm(_ value: ChargePricingConfirmation) async throws {
        await acquireConfirmationSlot()
        do {
            try await performConfirmation(value)
            releaseConfirmationSlot()
        } catch {
            releaseConfirmationSlot()
            throw error
        }
    }

    private func performConfirmation(_ value: ChargePricingConfirmation) async throws {
        let currencyCode = try Self.validate(value)
        let stationKey = try Self.stationKey(for: value)
        let resolvedUnitPrice = Self.resolvedUnitPrice(for: value)
        let observationID = idGenerator()
        let ruleID = idGenerator()
        let confirmedAt = now()
        let learnedRule: ChargePricingRule?
        if value.scope == .futureAtStation {
            guard let resolvedUnitPrice else {
                throw ChargePricingObservationServiceError.missingFutureUnitPrice
            }
            guard let coordinates = value.coordinates,
                  GeoCoordinateValidator.location(
                      latitude: coordinates.latitude,
                      longitude: coordinates.longitude
                  ) != nil
            else {
                throw ChargePricingObservationServiceError.missingStationCoordinates
            }
            learnedRule = Self.learnedRule(
                for: value,
                stationKey: stationKey,
                coordinates: coordinates,
                unitPrice: resolvedUnitPrice,
                currencyCode: currencyCode,
                id: ruleID
            )
        } else {
            learnedRule = nil
        }

        let observation = ChargePricingObservation(
            id: observationID,
            carId: value.carId,
            chargeId: value.chargeId,
            stationKey: stationKey,
            scope: value.scope,
            finalAmount: value.finalAmount,
            billedEnergyKWh: value.billedEnergyKWh,
            pricePerKWh: resolvedUnitPrice,
            serviceFeePerKWh: value.serviceFeePerKWh,
            fixedFee: value.fixedFee,
            currencyCode: currencyCode,
            confirmedAt: confirmedAt
        )

        let previousOverride = try await costOverrideStore.costOverride(
            carId: value.carId,
            chargeId: value.chargeId
        )
        let previousSettings: AppSettings?
        let updatedSettings: AppSettings?
        if let learnedRule {
            let settings = await settingsStore.load()
            previousSettings = settings
            updatedSettings = Self.upserting(learnedRule, in: settings)
        } else {
            previousSettings = nil
            updatedSettings = nil
        }

        var observationAttempted = false
        var overrideAttempted = false
        var settingsAttempted = false
        do {
            observationAttempted = true
            try await observationStore.save(observation)

            overrideAttempted = true
            try await costOverrideStore.saveCostOverride(
                carId: value.carId,
                chargeId: value.chargeId,
                cost: value.finalAmount
            )

            if let updatedSettings {
                settingsAttempted = true
                try await settingsStore.saveThrowing(updatedSettings)
            }
        } catch {
            if settingsAttempted, let previousSettings {
                try? await settingsStore.saveThrowing(previousSettings)
            }
            if overrideAttempted {
                try? await costOverrideStore.saveCostOverride(
                    carId: value.carId,
                    chargeId: value.chargeId,
                    cost: previousOverride
                )
            }
            if observationAttempted {
                try? await observationStore.remove(id: observation.id)
            }
            throw error
        }
    }

    private func acquireConfirmationSlot() async {
        if !confirmationInProgress {
            confirmationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            confirmationWaiters.append(continuation)
        }
    }

    private func releaseConfirmationSlot() {
        guard !confirmationWaiters.isEmpty else {
            confirmationInProgress = false
            return
        }
        confirmationWaiters.removeFirst().resume()
    }

    private static func validate(_ value: ChargePricingConfirmation) throws -> String {
        guard value.finalAmount.isFinite, value.finalAmount >= 0 else {
            throw ChargePricingObservationServiceError.invalidFinalAmount
        }
        if let energy = value.billedEnergyKWh, !energy.isFinite || energy < 0 {
            throw ChargePricingObservationServiceError.invalidBilledEnergy
        }
        if let price = value.pricePerKWh, !price.isFinite || price < 0 {
            throw ChargePricingObservationServiceError.invalidUnitPrice
        }
        if let fee = value.serviceFeePerKWh, !fee.isFinite || fee < 0 {
            throw ChargePricingObservationServiceError.invalidServiceFee
        }
        if let fee = value.fixedFee, !fee.isFinite || fee < 0 {
            throw ChargePricingObservationServiceError.invalidFixedFee
        }
        if (value.startMinute == nil) != (value.endMinute == nil) {
            throw ChargePricingObservationServiceError.incompleteTimeWindow
        }
        if let startMinute = value.startMinute,
           let endMinute = value.endMinute,
           (!(0...1_439).contains(startMinute) || !(0...1_439).contains(endMinute)) {
            throw ChargePricingObservationServiceError.invalidTimeWindow
        }
        guard let currencyCode = ChargePricingCurrencyCode.normalized(value.currencyCode),
              ChargePricingCurrencyCode.isValid(currencyCode) else {
            throw ChargePricingObservationServiceError.invalidCurrency
        }
        return currencyCode
    }

    private static func resolvedUnitPrice(for value: ChargePricingConfirmation) -> Double? {
        if let price = value.pricePerKWh {
            return price
        }
        guard let energy = value.billedEnergyKWh,
              energy.isFinite,
              energy > 0
        else {
            return nil
        }
        let serviceFee = value.serviceFeePerKWh.map { $0 * energy } ?? 0
        let fixedFee = value.fixedFee ?? 0
        let derived = (value.finalAmount - serviceFee - fixedFee) / energy
        return derived.isFinite && derived >= 0 ? derived : nil
    }

    private static func stationKey(for value: ChargePricingConfirmation) throws -> String {
        let matchedGeofenceKey = value.stationKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !matchedGeofenceKey.isEmpty {
            return matchedGeofenceKey
        }
        guard let coordinates = value.coordinates,
              GeoCoordinateValidator.location(
                  latitude: coordinates.latitude,
                  longitude: coordinates.longitude
              ) != nil
        else {
            throw ChargePricingObservationServiceError.missingStationCoordinates
        }
        return String(
            format: "%.4f,%.4f:%@",
            locale: Locale(identifier: "en_US_POSIX"),
            coordinates.latitude,
            coordinates.longitude,
            chargerKey(value.chargerIdentity)
        )
    }

    private static func learnedRule(
        for value: ChargePricingConfirmation,
        stationKey: String,
        coordinates: GeocodeLocation,
        unitPrice: Double,
        currencyCode: String,
        id: String
    ) -> ChargePricingRule {
        ChargePricingRule(
            id: id,
            name: "Learned \(stationKey)",
            isEnabled: true,
            chargeType: chargeType(value.chargerIdentity),
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            radiusMeters: 150,
            startMinuteOfDay: value.startMinute,
            endMinuteOfDay: value.endMinute,
            pricePerKWh: unitPrice,
            sessionFee: value.fixedFee ?? 0,
            priority: 100,
            origin: .stationLearned,
            serviceFeePerKWh: value.serviceFeePerKWh ?? 0,
            currencyCode: currencyCode,
            stationKey: stationKey
        )
    }

    private static func upserting(
        _ learnedRule: ChargePricingRule,
        in settings: AppSettings
    ) -> AppSettings {
        var updated = settings
        updated.chargePricingRules.removeAll { existing in
            existing.origin == .stationLearned &&
                existing.stationKey == learnedRule.stationKey &&
                existing.chargeType == learnedRule.chargeType &&
                (ChargePricingCurrencyCode.normalized(existing.currencyCode) == learnedRule.currencyCode ||
                    ChargePricingCurrencyCode.normalized(existing.currencyCode) == nil)
        }
        updated.chargePricingRules.append(learnedRule)
        return updated
    }

    private static func chargeType(
        _ identity: ChargePricingChargerIdentity
    ) -> ChargePricingChargeType {
        switch identity {
        case .ac: return .ac
        case .teslaSupercharger: return .teslaSupercharger
        case .otherDC: return .otherDC
        case .unknownDC: return .dc
        }
    }

    private static func chargerKey(_ identity: ChargePricingChargerIdentity) -> String {
        switch identity {
        case .ac: return "ac"
        case .teslaSupercharger: return "teslaSupercharger"
        case .otherDC: return "otherDC"
        case .unknownDC: return "unknownDC"
        }
    }
}
