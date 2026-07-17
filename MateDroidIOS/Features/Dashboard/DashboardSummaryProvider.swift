import Foundation

public struct DashboardLatestDrive: Codable, Equatable, Sendable {
    public let driveId: Int
    public let startedAt: Date?
    public let endedAt: Date?
    public let distanceKm: Double?
    public let durationMinutes: Int?
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?

    public init(
        driveId: Int,
        startedAt: Date?,
        endedAt: Date?,
        distanceKm: Double?,
        durationMinutes: Int?,
        energyConsumedNet: Double?,
        consumptionNet: Double?
    ) {
        self.driveId = driveId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceKm = distanceKm
        self.durationMinutes = durationMinutes
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
    }

    init(record: DriveSummaryRecord) {
        self.init(
            driveId: record.driveId,
            startedAt: DomainDateParser.date(from: record.startDate),
            endedAt: DomainDateParser.date(from: record.endDate),
            distanceKm: record.distance,
            durationMinutes: record.durationMin,
            energyConsumedNet: record.energyConsumedNet,
            consumptionNet: record.consumptionNet
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
        odometerKm: Double?
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
    }

    init(record: ChargeSummaryRecord) {
        self.init(
            chargeId: record.chargeId,
            startedAt: DomainDateParser.date(from: record.startDate),
            endedAt: record.endDate.flatMap(DomainDateParser.date(from:)),
            energyAddedKWh: record.chargeEnergyAdded,
            cost: record.cost,
            durationMinutes: record.durationMin,
            address: record.address,
            startBatteryLevel: record.startBatteryLevel,
            endBatteryLevel: record.endBatteryLevel,
            odometerKm: record.odometerKm
        )
    }
}

public struct DashboardCachedSummary: Equatable, Sendable {
    public let latestDrive: DashboardLatestDrive?
    public let latestCharge: DashboardLatestCharge?
    public let odometerKm: Double?
    public let sleepSummaries: [SleepDurationPeriod: SleepDurationSummary]

    public init(
        latestDrive: DashboardLatestDrive?,
        latestCharge: DashboardLatestCharge?,
        odometerKm: Double?,
        sleepSummaries: [SleepDurationPeriod: SleepDurationSummary]
    ) {
        self.latestDrive = latestDrive
        self.latestCharge = latestCharge
        self.odometerKm = odometerKm
        self.sleepSummaries = sleepSummaries
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
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(
        driveStore: any DriveSummaryStoring,
        chargeStore: any ChargeSummaryStoring,
        sleepIntervalStore: any SleepIntervalStoring,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.driveStore = driveStore
        self.chargeStore = chargeStore
        self.sleepIntervalStore = sleepIntervalStore
        self.databaseProvider = nil
        self.calendar = calendar
        self.now = now
    }

    public init(
        databaseProvider: any AppDatabaseProviding,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.driveStore = nil
        self.chargeStore = nil
        self.sleepIntervalStore = nil
        self.databaseProvider = databaseProvider
        self.calendar = calendar
        self.now = now
    }

    public func summary(carId: Int) async throws -> DashboardCachedSummary {
        if let databaseProvider {
            let database = try await databaseProvider.database()
            return try await summary(
                carId: carId,
                driveStore: DriveSummaryStore(database: database),
                chargeStore: ChargeSummaryStore(database: database),
                sleepIntervalStore: SleepIntervalStore(database: database)
            )
        }

        guard let driveStore, let chargeStore, let sleepIntervalStore else {
            return try await EmptyDashboardSummaryProvider().summary(carId: carId)
        }
        return try await summary(
            carId: carId,
            driveStore: driveStore,
            chargeStore: chargeStore,
            sleepIntervalStore: sleepIntervalStore
        )
    }

    private func summary(
        carId: Int,
        driveStore: any DriveSummaryStoring,
        chargeStore: any ChargeSummaryStoring,
        sleepIntervalStore: any SleepIntervalStoring
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
        let latestDrive = drives.first.map(DashboardLatestDrive.init(record:))
        let latestCharge = charges.first.map(DashboardLatestCharge.init(record:))
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
            )
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
