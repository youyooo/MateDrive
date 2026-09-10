import Foundation

public struct DashboardLatestDrive: Codable, Equatable, Sendable {
    public let driveId: Int
    public let startedAt: Date?
    public let endedAt: Date?
    public let distanceKm: Double?
    public let durationMinutes: Int?
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let intelligence: DriveIntelligenceResult?

    public var ratedRangeDropKm: Double? {
        guard let startRatedRangeKm,
              let endRatedRangeKm,
              startRatedRangeKm.isFinite,
              endRatedRangeKm.isFinite,
              startRatedRangeKm >= 0,
              endRatedRangeKm >= 0
        else { return nil }
        return max(startRatedRangeKm - endRatedRangeKm, 0)
    }

    public var remainingRatedRangeKm: Double? {
        guard let endRatedRangeKm, endRatedRangeKm.isFinite, endRatedRangeKm >= 0 else {
            return nil
        }
        return endRatedRangeKm
    }

    public init(
        driveId: Int,
        startedAt: Date?,
        endedAt: Date?,
        distanceKm: Double?,
        durationMinutes: Int?,
        energyConsumedNet: Double?,
        consumptionNet: Double?,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        intelligence: DriveIntelligenceResult? = nil
    ) {
        self.driveId = driveId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceKm = distanceKm
        self.durationMinutes = durationMinutes
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
        self.startRatedRangeKm = startRatedRangeKm
        self.endRatedRangeKm = endRatedRangeKm
        self.intelligence = intelligence
    }

    init(record: DriveSummaryRecord, intelligence: DriveIntelligenceResult? = nil) {
        self.init(
            driveId: record.driveId,
            startedAt: DomainDateParser.date(from: record.startDate),
            endedAt: DomainDateParser.date(from: record.endDate),
            distanceKm: record.distance,
            durationMinutes: record.durationMin,
            energyConsumedNet: record.energyConsumedNet,
            consumptionNet: record.consumptionNet,
            startRatedRangeKm: record.startRatedRangeKm,
            endRatedRangeKm: record.endRatedRangeKm,
            intelligence: intelligence
        )
    }
}

public struct DashboardLatestCharge: Codable, Equatable, Sendable {
    public let chargeId: Int
    public let startedAt: Date?
    public let endedAt: Date?
    public let energyAddedKWh: Double?
    public let cost: Double?
    public let durationMinutes: Int?
    public let address: String?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let odometerKm: Double?
    public let isCostEstimated: Bool?
    public let isCostHistoricalReference: Bool?

    public init(
        chargeId: Int,
        startedAt: Date?,
        endedAt: Date?,
        energyAddedKWh: Double?,
        cost: Double?,
        durationMinutes: Int?,
        address: String?,
        startBatteryLevel: Int?,
        endBatteryLevel: Int?,
        odometerKm: Double?,
        isCostEstimated: Bool? = nil,
        isCostHistoricalReference: Bool? = nil
    ) {
        self.chargeId = chargeId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.energyAddedKWh = energyAddedKWh
        self.cost = cost
        self.durationMinutes = durationMinutes
        self.address = address
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.odometerKm = odometerKm
        self.isCostEstimated = isCostEstimated
        self.isCostHistoricalReference = isCostHistoricalReference
    }

    init(
        record: ChargeSummaryRecord,
        cost: Double? = nil,
        address: String? = nil,
        isCostEstimated: Bool? = nil,
        isCostHistoricalReference: Bool? = nil
    ) {
        self.init(
            chargeId: record.chargeId,
            startedAt: DomainDateParser.date(from: record.startDate),
            endedAt: record.endDate.flatMap(DomainDateParser.date(from:)),
            energyAddedKWh: record.chargeEnergyAdded,
            cost: cost,
            durationMinutes: record.durationMin,
            address: address ?? record.address,
            startBatteryLevel: record.startBatteryLevel,
            endBatteryLevel: record.endBatteryLevel,
            odometerKm: record.odometerKm,
            isCostEstimated: isCostEstimated,
            isCostHistoricalReference: isCostHistoricalReference
        )
    }
}

public struct DashboardCachedSummary: Equatable, Sendable {
    public let latestDrive: DashboardLatestDrive?
    public let latestCharge: DashboardLatestCharge?
    public let odometerKm: Double?
    public let sleepSummaries: [SleepDurationPeriod: SleepDurationSummary]
    public let completedDriveCount: Int?
    public let completedChargeCount: Int?

    public init(
        latestDrive: DashboardLatestDrive?,
        latestCharge: DashboardLatestCharge?,
        odometerKm: Double?,
        sleepSummaries: [SleepDurationPeriod: SleepDurationSummary],
        completedDriveCount: Int? = nil,
        completedChargeCount: Int? = nil
    ) {
        self.latestDrive = latestDrive
        self.latestCharge = latestCharge
        self.odometerKm = odometerKm
        self.sleepSummaries = sleepSummaries
        self.completedDriveCount = completedDriveCount
        self.completedChargeCount = completedChargeCount
    }
}

public protocol DashboardSummaryProviding: Sendable {
    func summary(carId: Int) async throws -> DashboardCachedSummary
}

public struct EmptyDashboardSummaryProvider: DashboardSummaryProviding {
    public init() {}

    public func summary(carId _: Int) async throws -> DashboardCachedSummary {
        DashboardCachedSummary(
            latestDrive: nil,
            latestCharge: nil,
            odometerKm: nil,
            sleepSummaries: [:]
        )
    }
}

public struct DashboardSummaryProvider: DashboardSummaryProviding {
    private let driveStore: (any DriveSummaryStoring)?
    private let chargeStore: (any ChargeSummaryStoring)?
    private let sleepIntervalStore: (any SleepIntervalStoring)?
    private let databaseProvider: (any AppDatabaseProviding)?
    private let settingsStore: (any SettingsStoring)?
    private let costOverrideStore: any ChargeCostOverriding
    private let tariffCatalog: @Sendable () -> RegionalChargingTariffCatalog?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        driveStore: any DriveSummaryStoring,
        chargeStore: any ChargeSummaryStoring,
        sleepIntervalStore: any SleepIntervalStoring,
        settingsStore: (any SettingsStoring)? = nil,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        tariffCatalog: @escaping @Sendable () -> RegionalChargingTariffCatalog? = { try? RegionalChargingTariffCatalog.load() },
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.driveStore = driveStore
        self.chargeStore = chargeStore
        self.sleepIntervalStore = sleepIntervalStore
        self.databaseProvider = nil
        self.settingsStore = settingsStore
        self.costOverrideStore = costOverrideStore
        self.tariffCatalog = tariffCatalog
        self.calendar = calendar
        self.now = now
    }

    public init(
        databaseProvider: any AppDatabaseProviding,
        settingsStore: (any SettingsStoring)? = nil,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.driveStore = nil
        self.chargeStore = nil
        self.sleepIntervalStore = nil
        self.databaseProvider = databaseProvider
        self.settingsStore = settingsStore
        self.costOverrideStore = DatabaseBackedChargeCostOverrideStore(databaseProvider: databaseProvider)
        self.tariffCatalog = { try? RegionalChargingTariffCatalog.load() }
        self.calendar = calendar
        self.now = now
    }

    public func summary(carId: Int) async throws -> DashboardCachedSummary {
        let settings = await settingsStore?.load() ?? AppSettings()
        if let databaseProvider {
            let database = try await databaseProvider.database()
            let syncState = try? await SQLiteSyncStateStore(database: database).state(carId: carId)
            return try await summary(
                carId: carId,
                driveStore: DriveSummaryStore(database: database),
                chargeStore: ChargeSummaryStore(database: database),
                sleepIntervalStore: SleepIntervalStore(database: database),
                settings: settings,
                historyCountsAreAuthoritative: syncState?.summariesSynced == true
            )
        }

        guard let driveStore, let chargeStore, let sleepIntervalStore else {
            return try await EmptyDashboardSummaryProvider().summary(carId: carId)
        }
        return try await summary(
            carId: carId,
            driveStore: driveStore,
            chargeStore: chargeStore,
            sleepIntervalStore: sleepIntervalStore,
            settings: settings,
            historyCountsAreAuthoritative: true
        )
    }

    private func summary(
        carId: Int,
        driveStore: any DriveSummaryStoring,
        chargeStore: any ChargeSummaryStoring,
        sleepIntervalStore: any SleepIntervalStoring,
        settings: AppSettings,
        historyCountsAreAuthoritative: Bool
    ) async throws -> DashboardCachedSummary {
        async let driveRecords = driveStore.records(carId: carId)
        async let chargeRecords = chargeStore.records(carId: carId)
        let (drives, charges) = try await (driveRecords, chargeRecords)
        let currentDate = now()
        let monthStart = calendar.dateInterval(of: .month, for: currentDate)?.start ?? currentDate
        let latestCompletedChargeEnd = charges.lazy
            .compactMap { $0.endDate.flatMap(DomainDateParser.date(from:)) }
            .first
        let sleepStart = latestCompletedChargeEnd.map { min(monthStart, $0) } ?? monthStart
        let sleepRecords = try await sleepIntervalStore.records(
            carId: carId,
            start: Self.dateString(sleepStart),
            end: Self.dateString(currentDate)
        )
        let intervals = sleepRecords.compactMap { record -> SleepInterval? in
            guard let start = DomainDateParser.date(from: record.startDate),
                  let end = DomainDateParser.date(from: record.endDate)
            else { return nil }
            return SleepInterval(start: start, end: end)
        }
        let driveItems = drives.map(DriveSummaryItem.init(record:))
        let intelligence = DriveIntelligenceEngine.analyze(
            items: driveItems,
            carId: carId,
            routeLabels: settings.driveRouteLabelRules,
            annotations: settings.driveAnnotations,
            geofences: settings.usesGeofencesForCommuteClassification ? settings.geofenceRules : [],
            calendar: calendar
        )
        let latestDrive = drives.first.map {
            DashboardLatestDrive(record: $0, intelligence: intelligence[$0.driveId])
        }
        let latestCharge: DashboardLatestCharge?
        if let record = charges.first {
            let manualCost = try? await costOverrideStore.costOverride(carId: carId, chargeId: record.chargeId)
            let estimate = AutomaticChargeCostEstimator.resolve(
                record: record,
                settings: settings,
                manualCost: manualCost,
                catalog: tariffCatalog()
            )
            latestCharge = DashboardLatestCharge(
                record: record,
                cost: estimate.resolution?.amount,
                address: estimate.displayAddress,
                isCostEstimated: estimate.resolution?.isEstimated,
                isCostHistoricalReference: estimate.resolution?.isHistoricalReference
            )
        } else {
            latestCharge = nil
        }
        let odometerKm = charges.lazy.compactMap(\.odometerKm).first

        return DashboardCachedSummary(
            latestDrive: latestDrive,
            latestCharge: latestCharge,
            odometerKm: odometerKm,
            sleepSummaries: sleepSummaries(
                intervals: intervals,
                latestCompletedChargeEnd: latestCompletedChargeEnd,
                now: currentDate,
                monthStart: monthStart
            ),
            completedDriveCount: historyCountsAreAuthoritative ? drives.count : nil,
            completedChargeCount: historyCountsAreAuthoritative ? charges.count : nil
        )
    }

    private func sleepSummaries(
        intervals: [SleepInterval],
        latestCompletedChargeEnd: Date?,
        now: Date,
        monthStart: Date
    ) -> [SleepDurationPeriod: SleepDurationSummary] {
        let dayStart = calendar.startOfDay(for: now)
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = calendar.timeZone
        let weekStart = isoCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? dayStart
        var summaries = [
            SleepDurationPeriod.today: availableSummary(.today, intervals: intervals, from: dayStart, to: now),
            .week: availableSummary(.week, intervals: intervals, from: weekStart, to: now),
            .month: availableSummary(.month, intervals: intervals, from: monthStart, to: now)
        ]
        summaries[.sinceCharge] = latestCompletedChargeEnd.map {
            availableSummary(.sinceCharge, intervals: intervals, from: $0, to: now)
        } ?? SleepDurationSummary(period: .sinceCharge, duration: nil, isAvailable: false)
        return summaries
    }

    private func availableSummary(
        _ period: SleepDurationPeriod,
        intervals: [SleepInterval],
        from start: Date,
        to end: Date
    ) -> SleepDurationSummary {
        SleepDurationSummary(
            period: period,
            duration: SleepDurationCalculator.total(intervals: intervals, from: start, to: end),
            isAvailable: true
        )
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
