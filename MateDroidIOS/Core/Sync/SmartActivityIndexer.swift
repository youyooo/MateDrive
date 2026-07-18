import CryptoKit
import Foundation

public extension Notification.Name {
    static let smartActivityIndexDidChange = Notification.Name("SmartActivityIndexDidChange")
}

public struct SmartActivitySourceSnapshot: Sendable {
    public let carId: Int
    public let activities: [TeslaMateActivity]
    public let historyFullyLoaded: Bool
    public let sleepIntervals: [SleepInterval]
    public let geofences: [GeofenceRule]
    public let settings: AppSettings
    public let chargeCostOverrides: [Int: Double]
    public let tariffCatalog: RegionalChargingTariffCatalog
    public let chargePricingAggregates: [Int: ChargeDetailPricingAggregate]

    public init(
        carId: Int,
        activities: [TeslaMateActivity],
        historyFullyLoaded: Bool,
        sleepIntervals: [SleepInterval],
        geofences: [GeofenceRule],
        settings: AppSettings,
        chargeCostOverrides: [Int: Double],
        tariffCatalog: RegionalChargingTariffCatalog,
        chargePricingAggregates: [Int: ChargeDetailPricingAggregate] = [:]
    ) {
        self.carId = carId
        self.activities = activities
        self.historyFullyLoaded = historyFullyLoaded
        self.sleepIntervals = sleepIntervals
        self.geofences = geofences
        self.settings = settings
        self.chargeCostOverrides = chargeCostOverrides
        self.tariffCatalog = tariffCatalog
        self.chargePricingAggregates = chargePricingAggregates
    }
}

public protocol SmartActivitySourceLoading: Sendable {
    func snapshot(carId: Int) async throws -> SmartActivitySourceSnapshot?
}

public struct SmartActivityIndexReport: Equatable, Sendable {
    public let attemptedCarIds: [Int]
    public let completedCarIds: [Int]
    public let failedCarIds: [Int]
    public let unchangedCarIds: [Int]

    public init(
        attemptedCarIds: [Int],
        completedCarIds: [Int],
        failedCarIds: [Int],
        unchangedCarIds: [Int]
    ) {
        self.attemptedCarIds = attemptedCarIds
        self.completedCarIds = completedCarIds
        self.failedCarIds = failedCarIds
        self.unchangedCarIds = unchangedCarIds
    }
}

public protocol SmartActivityIndexing: Sendable {
    func rebuild(carIds: [Int]) async -> SmartActivityIndexReport
    func removeDerivedData() async throws
}

public struct CachedSmartActivitySourceLoader: SmartActivitySourceLoading {
    private let activitiesCache: any ActivitiesStateCaching
    private let sleepIntervalStore: any SleepIntervalStoring
    private let settingsStore: any SettingsStoring
    private let chargeCostOverrideStore: any ChargeCostOverriding
    private let chargePricingAggregateStore: any ChargePricingAggregateProviding
    private let tariffCatalog: @Sendable () throws -> RegionalChargingTariffCatalog
    private let now: @Sendable () -> Date

    public init(
        activitiesCache: any ActivitiesStateCaching,
        sleepIntervalStore: any SleepIntervalStoring,
        settingsStore: any SettingsStoring,
        chargeCostOverrideStore: any ChargeCostOverriding,
        chargePricingAggregateStore: any ChargePricingAggregateProviding = EmptyChargePricingAggregateStore(),
        tariffCatalog: @escaping @Sendable () throws -> RegionalChargingTariffCatalog = {
            try RegionalChargingTariffCatalog.load()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.activitiesCache = activitiesCache
        self.sleepIntervalStore = sleepIntervalStore
        self.settingsStore = settingsStore
        self.chargeCostOverrideStore = chargeCostOverrideStore
        self.chargePricingAggregateStore = chargePricingAggregateStore
        self.tariffCatalog = tariffCatalog
        self.now = now
    }

    public func snapshot(carId: Int) async throws -> SmartActivitySourceSnapshot? {
        try Task.checkCancellation()
        let settings = await settingsStore.load()
        guard let cached = await activitiesCache.load(
            serverURL: settings.serverURL,
            carId: carId,
            now: now()
        ) else {
            return nil
        }

        let bounds = Self.historyBounds(cached.state.items)
        async let overrides = chargeCostOverrideStore.costOverrides(carId: carId)
        async let pricingAggregates = chargePricingAggregateStore.chargePricingAggregates(carId: carId)
        async let sleepRecords = Self.loadSleepRecords(
            store: sleepIntervalStore,
            carId: carId,
            bounds: bounds
        )
        let catalog = try tariffCatalog()
        let (resolvedOverrides, resolvedPricingAggregates, resolvedSleepRecords) = try await (
            overrides,
            pricingAggregates,
            sleepRecords
        )
        try Task.checkCancellation()

        return SmartActivitySourceSnapshot(
            carId: carId,
            activities: cached.state.items,
            historyFullyLoaded: cached.state.historyFullyLoaded,
            sleepIntervals: resolvedSleepRecords.compactMap(Self.sleepInterval),
            geofences: settings.geofenceRules,
            settings: settings,
            chargeCostOverrides: resolvedOverrides,
            tariffCatalog: catalog,
            chargePricingAggregates: resolvedPricingAggregates
        )
    }

    private static func historyBounds(_ activities: [TeslaMateActivity]) -> (start: String, end: String)? {
        let dates = activities.flatMap { activity in
            [activity.startDate, activity.endDate].compactMap { $0?.flatMap(DomainDateParser.date(from:)) }
        }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let formatter = ISO8601DateFormatter()
        return (
            formatter.string(from: first),
            formatter.string(from: max(last, first.addingTimeInterval(1)))
        )
    }

    private static func loadSleepRecords(
        store: any SleepIntervalStoring,
        carId: Int,
        bounds: (start: String, end: String)?
    ) async throws -> [SleepIntervalRecord] {
        guard let bounds else { return [] }
        return try await store.records(carId: carId, start: bounds.start, end: bounds.end)
    }

    private static func sleepInterval(_ record: SleepIntervalRecord) -> SleepInterval? {
        guard let start = DomainDateParser.date(from: record.startDate),
              let end = DomainDateParser.date(from: record.endDate),
              start < end
        else { return nil }
        return SleepInterval(start: start, end: end)
    }
}

public actor SmartActivityIndexer: SmartActivityIndexing {
    private let source: any SmartActivitySourceLoading
    private let sessionStore: any SmartActivitySessionStoring
    private let labelStore: any ActivityLabelOverrideStoring
    private let postChange: @Sendable (Int) async -> Void
    private var operationInProgress = false
    private var operationWaiters: [OperationWaiter] = []

    var queuedOperationCount: Int { operationWaiters.count }

    public init(
        source: any SmartActivitySourceLoading,
        sessionStore: any SmartActivitySessionStoring,
        labelStore: any ActivityLabelOverrideStoring,
        postChange: @escaping @Sendable (Int) async -> Void = { carId in
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .smartActivityIndexDidChange,
                    object: nil,
                    userInfo: ["carId": carId]
                )
            }
        }
    ) {
        self.source = source
        self.sessionStore = sessionStore
        self.labelStore = labelStore
        self.postChange = postChange
    }

    public func rebuild(carIds: [Int]) async -> SmartActivityIndexReport {
        let attempted = Array(Set(carIds)).sorted()
        guard await acquireOperation() else {
            return SmartActivityIndexReport(
                attemptedCarIds: attempted,
                completedCarIds: [],
                failedCarIds: attempted,
                unchangedCarIds: []
            )
        }
        defer { releaseOperation() }
        guard !Task.isCancelled else {
            return SmartActivityIndexReport(
                attemptedCarIds: attempted,
                completedCarIds: [],
                failedCarIds: attempted,
                unchangedCarIds: []
            )
        }

        var completed: [Int] = []
        var failed: [Int] = []
        var unchanged: [Int] = []

        for (index, carId) in attempted.enumerated() {
            if Task.isCancelled {
                failed.append(contentsOf: attempted[index...])
                break
            }
            do {
                guard let sourceSnapshot = try await source.snapshot(carId: carId) else {
                    throw SmartActivityIndexError.missingCache
                }
                let overrides = try await labelStore.overrides(carId: carId)
                let derived = try await deriveOffMain(source: sourceSnapshot, labelOverrides: overrides)
                let existing = try await sessionStore.sessions(carId: carId)
                let storedFingerprint = try await sessionStore.derivationFingerprint(carId: carId)
                if Self.matchesFingerprint(
                    existing,
                    sessions: derived.sessions,
                    storedFingerprint: storedFingerprint,
                    fingerprint: derived.fingerprint
                ) {
                    unchanged.append(carId)
                    continue
                }

                try Task.checkCancellation()
                var replacementCommitted = false
                do {
                    try await sessionStore.replace(
                        carId: carId,
                        sessions: derived.sessions,
                        derivationFingerprint: derived.fingerprint
                    )
                    replacementCommitted = true
                    try Task.checkCancellation()
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        do {
                            try await restore(
                                carId: carId,
                                sessions: existing,
                                derivationFingerprint: storedFingerprint
                            )
                        } catch {
                            if replacementCommitted {
                                await postChange(carId)
                            }
                            throw SmartActivityIndexError.restorationFailed
                        }
                    }
                    throw error
                }
                completed.append(carId)
                await postChange(carId)
            } catch {
                failed.append(carId)
            }
        }

        return SmartActivityIndexReport(
            attemptedCarIds: attempted,
            completedCarIds: completed,
            failedCarIds: failed,
            unchangedCarIds: unchanged
        )
    }

    public func removeDerivedData() async throws {
        guard await acquireOperation() else {
            throw CancellationError()
        }
        defer { releaseOperation() }
        try Task.checkCancellation()
        try await sessionStore.removeDerivedSessions()
    }

    private func acquireOperation() async -> Bool {
        guard !Task.isCancelled else { return false }
        guard operationInProgress else {
            operationInProgress = true
            return true
        }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                operationWaiters.append(OperationWaiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelOperationWaiter(id: waiterID) }
        }
    }

    private func cancelOperationWaiter(id: UUID) {
        guard let index = operationWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = operationWaiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationInProgress = false
        } else {
            operationWaiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func restore(
        carId: Int,
        sessions: [SmartActivitySession],
        derivationFingerprint: String?
    ) async throws {
        if let restorationFingerprint = derivationFingerprint ?? sessions.first?.derivationFingerprint {
            try await sessionStore.replace(
                carId: carId,
                sessions: sessions,
                derivationFingerprint: restorationFingerprint
            )
        } else if sessions.isEmpty {
            try await sessionStore.removeDerivedSessions(carId: carId)
        } else {
            try await sessionStore.replace(carId: carId, sessions: sessions)
        }
    }

    private func deriveOffMain(
        source: SmartActivitySourceSnapshot,
        labelOverrides: [ActivityLabelOverride]
    ) async throws -> DerivedCarSnapshot {
        let task = Task.detached {
            try Task.checkCancellation()
            return try Self.derive(source: source, labelOverrides: labelOverrides)
        }
        return try await withTaskCancellationHandler(
            operation: { try await task.value },
            onCancel: { task.cancel() }
        )
    }

    nonisolated private static func derive(
        source: SmartActivitySourceSnapshot,
        labelOverrides: [ActivityLabelOverride]
    ) throws -> DerivedCarSnapshot {
        try Task.checkCancellation()
        var sessions = ActivitySessionReconstructor.reconstruct(
            carId: source.carId,
            events: source.activities,
            sleepIntervals: source.sleepIntervals,
            geofences: source.geofences,
            labelOverrides: labelOverrides
        )
        let relevantOverrides = relevantOverrides(labelOverrides, sessions: sessions)
        let fingerprint = try derivationFingerprint(
            source: source,
            labelOverrides: relevantOverrides
        )
        let boundaryDate = source.historyFullyLoaded ? nil : sessions.map(\.startDate).min()

        sessions = try sessions.map { session in
            try Task.checkCancellation()
            return copiedSession(
                session,
                quality: session.startDate == boundaryDate ? .partial : session.quality,
                chargeCost: resolvedChargeCost(session: session, source: source),
                derivationFingerprint: fingerprint
            )
        }
        return DerivedCarSnapshot(sessions: sessions, fingerprint: fingerprint)
    }

    nonisolated private static func relevantOverrides(
        _ overrides: [ActivityLabelOverride],
        sessions: [SmartActivitySession]
    ) -> [ActivityLabelOverride] {
        let sessionIds = Set(sessions.map(\.id))
        let placeKeys = Set(sessions.map(\.placeKey))
        return overrides.filter { value in
            switch value.scope {
            case .sessionOnly:
                return value.sessionId.map(sessionIds.contains) == true
            case .futureAtPlace:
                return value.placeKey.map(placeKeys.contains) == true
            }
        }
    }

    nonisolated private static func derivationFingerprint(
        source: SmartActivitySourceSnapshot,
        labelOverrides: [ActivityLabelOverride]
    ) throws -> String {
        let raw = RawSourceFingerprint(
            activities: source.activities.sorted(by: activityPrecedes),
            historyFullyLoaded: source.historyFullyLoaded,
            sleepIntervals: source.sleepIntervals.sorted { $0.start < $1.start }.map {
                DateRangeFingerprint(start: $0.start, end: $0.end)
            },
            geofences: source.geofences.sorted { $0.id < $1.id },
            chargeCostOverrides: source.chargeCostOverrides.keys.sorted().map {
                ChargeOverrideFingerprint(chargeId: $0, amount: source.chargeCostOverrides[$0] ?? 0)
            },
            chargePricingAggregates: source.chargePricingAggregates.keys.sorted().compactMap { chargeId in
                source.chargePricingAggregates[chargeId].map { aggregate in
                    ChargePricingAggregateFingerprint(
                        chargeId: chargeId,
                        isDc: aggregate.isDc,
                        chargerIdentity: chargerIdentityFingerprint(aggregate.chargerIdentity),
                        energySamples: aggregate.energySamples.map {
                            ChargeEnergySampleFingerprint(
                                date: $0.date,
                                cumulativeEnergyAddedKWh: $0.cumulativeEnergyAddedKWh
                            )
                        }
                    )
                }
            }
        )
        let pricing = PricingFingerprint(
            currencyCode: source.settings.resolvedCurrencyCode(),
            residentialTariffRegionCode: source.settings.residentialTariffRegionCode,
            rules: source.settings.chargePricingRules
        )
        let components = [
            "raw=\(try digest(raw))",
            "labels=\(try digest(labelOverrides.sorted(by: labelOverridePrecedes)))",
            "pricing=\(try digest(pricing))",
            "tariff=\(source.tariffCatalog.version)",
            "classifier=\(ActivityPurposeClassifier.classifierVersion)"
        ].joined(separator: "|")
        return sha256(Data(components.utf8))
    }

    nonisolated private static func resolvedChargeCost(
        session: SmartActivitySession,
        source: SmartActivitySourceSnapshot
    ) -> SmartActivityChargeCost? {
        let charges = session.eventReferences.filter { $0.kind == .charge }
        guard !charges.isEmpty else { return nil }
        let geofenceKind = session.geofenceID.flatMap { id in
            source.geofences.first { $0.id == id }?.kind
        }
        let currencyCode = source.settings.resolvedCurrencyCode()
        let configuredRules = source.settings.chargePricingRules.filter { $0.origin != .regionalOfficial }
        let resolutions = charges.compactMap { reference -> ResolvedCharge? in
            let activity = reference.sourceActivity
            let aggregate = source.chargePricingAggregates[activity.id]
            let resolvedIsDc = resolvedChargeType(activity: activity, aggregate: aggregate)
            let chargerIdentity: ChargePricingChargerIdentity
            if resolvedIsDc == true,
               let measuredIdentity = aggregate?.chargerIdentity,
               measuredIdentity != .ac
            {
                chargerIdentity = measuredIdentity
            } else if resolvedIsDc == true {
                chargerIdentity = ChargeStatsCalculator.chargerIdentity(
                    isDc: true,
                    fastChargerBrand: nil,
                    address: activity.startAddress ?? activity.endAddress
                )
            } else {
                chargerIdentity = .ac
            }
            let rules = resolvedIsDc == nil
                ? configuredRules.filter { $0.chargeType == .any }
                : configuredRules
            let pricingInput = ChargePricingInput(
                startDate: activity.startDate,
                endDate: activity.endDate,
                address: activity.startAddress ?? activity.endAddress,
                latitude: activity.startLatitude ?? activity.endLatitude,
                longitude: activity.startLongitude ?? activity.endLongitude,
                energyAddedKWh: activity.kwh ?? activity.kwhUsed,
                energySamples: aggregate?.energySamples ?? [],
                isDc: resolvedIsDc ?? false,
                chargerIdentity: chargerIdentity
            )
            let regionalRule = resolvedIsDc == false
                ? regionalPricingRule(
                    settings: source.settings,
                    catalog: source.tariffCatalog,
                    startDate: activity.startDate
                )
                : nil
            guard let resolution = ChargeCostResolver.resolve(ChargeCostResolutionInput(
                manualCost: source.chargeCostOverrides[activity.id],
                apiCost: activity.cost,
                currencyCode: currencyCode,
                isAC: resolvedIsDc == false,
                geofenceKind: geofenceKind,
                pricingInput: pricingInput,
                rules: rules,
                regionalRule: regionalRule
            )), isSafe(resolution) else { return nil }
            return ResolvedCharge(chargeId: activity.id, resolution: resolution)
        }
        guard !resolutions.isEmpty else { return nil }

        var amount = 0.0
        for resolution in resolutions {
            amount += resolution.resolution.amount
            guard amount.isFinite, amount >= 0 else { return nil }
        }
        let components = resolutions.flatMap(costComponents)
        guard components.allSatisfy(isSafe) else { return nil }
        let sources = Set(resolutions.map { $0.resolution.source })
        let ruleIds = Set(resolutions.compactMap { $0.resolution.ruleID })
        return SmartActivityChargeCost(
            amount: amount,
            currencyCode: currencyCode,
            source: sources.count == 1 ? resolutions[0].resolution.source : preferredSource(resolutions),
            ruleID: ruleIds.count == 1 ? ruleIds.first : nil,
            isEstimated: resolutions.contains { $0.resolution.isEstimated },
            isExplicitlyFree: amount == 0 && resolutions.allSatisfy { $0.resolution.isExplicitlyFree },
            components: components
        )
    }

    nonisolated private static func resolvedChargeType(
        activity: TeslaMateActivity,
        aggregate: ChargeDetailPricingAggregate?
    ) -> Bool? {
        if let identity = aggregate?.chargerIdentity {
            return identity != .ac
        }
        if let isDc = aggregate?.isDc {
            return isDc
        }
        guard let energy = activity.kwh ?? activity.kwhUsed,
              energy.isFinite,
              energy > 0,
              let duration = activity.durationMin,
              duration.isFinite,
              duration > 0
        else {
            return nil
        }
        let durationMinutes = max(1, Int(duration.rounded()))
        return ChargeStatsCalculator.isDcCharge(
            chargeId: activity.id,
            energyAddedKwh: energy,
            durationMin: durationMinutes,
            dcChargeIds: [],
            processedChargeIds: []
        )
    }

    nonisolated private static func isSafe(_ resolution: ChargeCostResolution) -> Bool {
        guard resolution.amount.isFinite,
              resolution.amount >= 0,
              resolution.serviceFee.isFinite,
              resolution.serviceFee >= 0,
              resolution.sessionFee.isFinite,
              resolution.sessionFee >= 0,
              resolution.unitPricePerKWh.map({ $0.isFinite && $0 >= 0 }) ?? true
        else { return false }
        return resolution.components.allSatisfy {
            $0.cost.isFinite && $0.cost >= 0 &&
                $0.energyKWh.isFinite && $0.energyKWh >= 0 &&
                $0.pricePerKWh.isFinite && $0.pricePerKWh >= 0
        }
    }

    nonisolated private static func isSafe(_ component: SmartActivityChargeCostComponent) -> Bool {
        component.amount.isFinite && component.amount >= 0 &&
            (component.energyKWh.map { $0.isFinite && $0 >= 0 } ?? true) &&
            (component.pricePerKWh.map { $0.isFinite && $0 >= 0 } ?? true)
    }

    nonisolated private static func costComponents(_ charge: ResolvedCharge) -> [SmartActivityChargeCostComponent] {
        let resolution = charge.resolution
        var components = resolution.components.map {
            SmartActivityChargeCostComponent(
                kind: "charge:\(charge.chargeId):energy",
                amount: $0.cost,
                energyKWh: $0.energyKWh,
                pricePerKWh: $0.pricePerKWh
            )
        }
        if resolution.serviceFee != 0 {
            components.append(SmartActivityChargeCostComponent(
                kind: "charge:\(charge.chargeId):service",
                amount: resolution.serviceFee,
                energyKWh: nil,
                pricePerKWh: nil
            ))
        }
        if resolution.sessionFee != 0 {
            components.append(SmartActivityChargeCostComponent(
                kind: "charge:\(charge.chargeId):session",
                amount: resolution.sessionFee,
                energyKWh: nil,
                pricePerKWh: nil
            ))
        }
        if components.isEmpty {
            components.append(SmartActivityChargeCostComponent(
                kind: "charge:\(charge.chargeId):total",
                amount: resolution.amount,
                energyKWh: nil,
                pricePerKWh: resolution.unitPricePerKWh
            ))
        }
        return components
    }

    nonisolated private static func preferredSource(_ resolutions: [ResolvedCharge]) -> SmartActivityChargeCostSource {
        let precedence: [SmartActivityChargeCostSource] = [
            .manual, .api, .stationRule, .homeRule, .regionalTariff
        ]
        return precedence.first { source in
            resolutions.contains { $0.resolution.source == source }
        } ?? resolutions[0].resolution.source
    }

    nonisolated private static func regionalPricingRule(
        settings: AppSettings,
        catalog: RegionalChargingTariffCatalog,
        startDate: String?
    ) -> ChargePricingRule? {
        guard let regionCode = settings.residentialTariffRegionCode,
              let date = startDate.flatMap(DomainDateParser.date(from:)),
              let entry = catalog.entry(regionCode: regionCode, date: date)
        else { return nil }
        return catalog.makePricingRule(regionCode: regionCode, from: entry)
    }

    nonisolated private static func copiedSession(
        _ session: SmartActivitySession,
        quality: ActivityMetricQuality,
        chargeCost: SmartActivityChargeCost?,
        derivationFingerprint: String
    ) -> SmartActivitySession {
        SmartActivitySession(
            id: session.id,
            carId: session.carId,
            startDate: session.startDate,
            endDate: session.endDate,
            placeKey: session.placeKey,
            latitude: session.latitude,
            longitude: session.longitude,
            geofenceID: session.geofenceID,
            provisionalKind: session.provisionalKind,
            classification: session.classification,
            parkingMetrics: session.parkingMetrics,
            chargeCost: chargeCost,
            eventReferences: session.eventReferences,
            isOpen: session.isOpen,
            quality: quality,
            derivationVersion: session.derivationVersion,
            sourceFingerprint: session.sourceFingerprint,
            derivationFingerprint: derivationFingerprint
        )
    }

    nonisolated private static func matchesFingerprint(
        _ existing: [SmartActivitySession],
        sessions: [SmartActivitySession],
        storedFingerprint: String?,
        fingerprint: String
    ) -> Bool {
        guard existing.count == sessions.count else { return false }
        return storedFingerprint == fingerprint
    }

    nonisolated private static func digest<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return sha256(try encoder.encode(value))
    }

    nonisolated private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func activityPrecedes(_ lhs: TeslaMateActivity, _ rhs: TeslaMateActivity) -> Bool {
        lhs.kind == rhs.kind ? lhs.id < rhs.id : lhs.kind.rawValue < rhs.kind.rawValue
    }

    nonisolated private static func chargerIdentityFingerprint(
        _ identity: ChargePricingChargerIdentity?
    ) -> String? {
        switch identity {
        case .ac: return "ac"
        case .teslaSupercharger: return "teslaSupercharger"
        case .otherDC: return "otherDC"
        case .unknownDC: return "unknownDC"
        case nil: return nil
        }
    }

    nonisolated private static func labelOverridePrecedes(_ lhs: ActivityLabelOverride, _ rhs: ActivityLabelOverride) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt < rhs.updatedAt
    }
}

private enum SmartActivityIndexError: Error {
    case missingCache
    case restorationFailed
}

private struct OperationWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
}

private struct DerivedCarSnapshot: Sendable {
    let sessions: [SmartActivitySession]
    let fingerprint: String
}

private struct RawSourceFingerprint: Encodable {
    let activities: [TeslaMateActivity]
    let historyFullyLoaded: Bool
    let sleepIntervals: [DateRangeFingerprint]
    let geofences: [GeofenceRule]
    let chargeCostOverrides: [ChargeOverrideFingerprint]
    let chargePricingAggregates: [ChargePricingAggregateFingerprint]
}

private struct DateRangeFingerprint: Encodable {
    let start: Date
    let end: Date
}

private struct ChargeOverrideFingerprint: Encodable {
    let chargeId: Int
    let amount: Double
}

private struct ChargePricingAggregateFingerprint: Encodable {
    let chargeId: Int
    let isDc: Bool?
    let chargerIdentity: String?
    let energySamples: [ChargeEnergySampleFingerprint]
}

private struct ChargeEnergySampleFingerprint: Encodable {
    let date: String?
    let cumulativeEnergyAddedKWh: Double?
}

private struct PricingFingerprint: Encodable {
    let currencyCode: String
    let residentialTariffRegionCode: String?
    let rules: [ChargePricingRule]
}

private struct ResolvedCharge: Sendable {
    let chargeId: Int
    let resolution: ChargeCostResolution
}
