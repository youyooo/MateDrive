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

    public init(
        carId: Int,
        activities: [TeslaMateActivity],
        historyFullyLoaded: Bool,
        sleepIntervals: [SleepInterval],
        geofences: [GeofenceRule],
        settings: AppSettings,
        chargeCostOverrides: [Int: Double],
        tariffCatalog: RegionalChargingTariffCatalog
    ) {
        self.carId = carId
        self.activities = activities
        self.historyFullyLoaded = historyFullyLoaded
        self.sleepIntervals = sleepIntervals
        self.geofences = geofences
        self.settings = settings
        self.chargeCostOverrides = chargeCostOverrides
        self.tariffCatalog = tariffCatalog
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
    private let tariffCatalog: @Sendable () throws -> RegionalChargingTariffCatalog
    private let now: @Sendable () -> Date

    public init(
        activitiesCache: any ActivitiesStateCaching,
        sleepIntervalStore: any SleepIntervalStoring,
        settingsStore: any SettingsStoring,
        chargeCostOverrideStore: any ChargeCostOverriding,
        tariffCatalog: @escaping @Sendable () throws -> RegionalChargingTariffCatalog = {
            try RegionalChargingTariffCatalog.load()
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.activitiesCache = activitiesCache
        self.sleepIntervalStore = sleepIntervalStore
        self.settingsStore = settingsStore
        self.chargeCostOverrideStore = chargeCostOverrideStore
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
        async let sleepRecords = Self.loadSleepRecords(
            store: sleepIntervalStore,
            carId: carId,
            bounds: bounds
        )
        let catalog = try tariffCatalog()
        let (resolvedOverrides, resolvedSleepRecords) = try await (overrides, sleepRecords)
        try Task.checkCancellation()

        return SmartActivitySourceSnapshot(
            carId: carId,
            activities: cached.state.items,
            historyFullyLoaded: cached.state.historyFullyLoaded,
            sleepIntervals: resolvedSleepRecords.compactMap(Self.sleepInterval),
            geofences: settings.geofenceRules,
            settings: settings,
            chargeCostOverrides: resolvedOverrides,
            tariffCatalog: catalog
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
                if Self.matchesFingerprint(existing, sessions: derived.sessions, fingerprint: derived.fingerprint) {
                    unchanged.append(carId)
                    continue
                }

                try Task.checkCancellation()
                try await sessionStore.replace(carId: carId, sessions: derived.sessions)
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
        try await sessionStore.removeDerivedSessions()
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
            }
        )
        let pricing = PricingFingerprint(
            currencyCode: source.settings.resolvedCurrencyCode(),
            residentialTariffRegionCode: source.settings.residentialTariffRegionCode,
            rules: source.settings.chargePricingRules.sorted(by: pricingRulePrecedes)
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
        let rules = source.settings.chargePricingRules.filter { $0.origin != .regionalOfficial }
        let resolutions = charges.compactMap { reference -> ResolvedCharge? in
            let activity = reference.sourceActivity
            let pricingInput = ChargePricingInput(
                startDate: activity.startDate,
                endDate: activity.endDate,
                address: activity.startAddress ?? activity.endAddress,
                latitude: activity.startLatitude ?? activity.endLatitude,
                longitude: activity.startLongitude ?? activity.endLongitude,
                energyAddedKWh: activity.kwh ?? activity.kwhUsed,
                isDc: false,
                chargerIdentity: .ac
            )
            let regionalRule = regionalPricingRule(
                settings: source.settings,
                catalog: source.tariffCatalog,
                startDate: activity.startDate
            )
            guard let resolution = ChargeCostResolver.resolve(ChargeCostResolutionInput(
                manualCost: source.chargeCostOverrides[activity.id],
                apiCost: activity.cost,
                currencyCode: currencyCode,
                isAC: true,
                geofenceKind: geofenceKind,
                pricingInput: pricingInput,
                rules: rules,
                regionalRule: regionalRule
            )) else { return nil }
            return ResolvedCharge(chargeId: activity.id, resolution: resolution)
        }
        guard !resolutions.isEmpty else { return nil }

        let amount = resolutions.reduce(0) { $0 + $1.resolution.amount }
        let sources = Set(resolutions.map { $0.resolution.source })
        let ruleIds = Set(resolutions.compactMap { $0.resolution.ruleID })
        return SmartActivityChargeCost(
            amount: amount,
            currencyCode: currencyCode,
            source: sources.count == 1 ? resolutions[0].resolution.source : preferredSource(resolutions),
            ruleID: ruleIds.count == 1 ? ruleIds.first : nil,
            isEstimated: resolutions.contains { $0.resolution.isEstimated },
            isExplicitlyFree: amount == 0 && resolutions.allSatisfy { $0.resolution.isExplicitlyFree },
            components: resolutions.flatMap(costComponents)
        )
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
        fingerprint: String
    ) -> Bool {
        guard existing.count == sessions.count else { return false }
        return existing.isEmpty || existing.allSatisfy { $0.derivationFingerprint == fingerprint }
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

    nonisolated private static func pricingRulePrecedes(_ lhs: ChargePricingRule, _ rhs: ChargePricingRule) -> Bool {
        lhs.id == rhs.id ? lhs.name < rhs.name : lhs.id < rhs.id
    }

    nonisolated private static func labelOverridePrecedes(_ lhs: ActivityLabelOverride, _ rhs: ActivityLabelOverride) -> Bool {
        lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt < rhs.updatedAt
    }
}

private enum SmartActivityIndexError: Error {
    case missingCache
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
}

private struct DateRangeFingerprint: Encodable {
    let start: Date
    let end: Date
}

private struct ChargeOverrideFingerprint: Encodable {
    let chargeId: Int
    let amount: Double
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
