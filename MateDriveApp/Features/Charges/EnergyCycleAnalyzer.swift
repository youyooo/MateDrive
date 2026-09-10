import Foundation

public enum EnergyCyclePeriod: String, CaseIterable, Equatable, Sendable {
    case today
    case yesterday
    case week
    case month

    public func title(language: AppLanguage) -> String {
        switch self {
        case .today:
            return AppText.localized("Today", "今天", language: language)
        case .yesterday:
            return AppText.localized("Yesterday", "昨天", language: language)
        case .week:
            return AppText.localized("Week", "本周", language: language)
        case .month:
            return AppText.localized("Month", "本月", language: language)
        }
    }

    public func comparisonTitle(language: AppLanguage) -> String {
        switch self {
        case .today:
            return AppText.localized("vs yesterday", "较昨天", language: language)
        case .yesterday:
            return AppText.localized("vs previous day", "较前天", language: language)
        case .week:
            return AppText.localized("vs last week", "较上周", language: language)
        case .month:
            return AppText.localized("vs last month", "较上月", language: language)
        }
    }
}

public struct EnergyCycleDataSet: Equatable, Sendable {
    public let charges: [ChargeSummaryRecord]
    public let drives: [DriveSummaryRecord]

    public init(charges: [ChargeSummaryRecord], drives: [DriveSummaryRecord]) {
        self.charges = charges
        self.drives = drives
    }

    public static let empty = EnergyCycleDataSet(charges: [], drives: [])
}

public struct EnergyPeriodSummary: Equatable, Sendable {
    public let chargeCount: Int
    public let driveCount: Int
    public let chargerInputKWh: Double?
    public let chargerInputRecordCount: Int
    public let batteryAddedKWh: Double?
    public let batteryAddedRecordCount: Int
    public let drivingEnergyKWh: Double?
    public let drivingEnergyRecordCount: Int
    public let distanceKm: Double?
    public let distanceRecordCount: Int
    public let chargeSOCAdded: Int?
    public let driveSOCUsed: Int?
    public let chargingEfficiency: Double?

    public var chargerInputIsComplete: Bool { chargerInputRecordCount == chargeCount }
    public var batteryAddedIsComplete: Bool { batteryAddedRecordCount == chargeCount }
    public var drivingEnergyIsComplete: Bool { drivingEnergyRecordCount == driveCount }
    public var distanceIsComplete: Bool { distanceRecordCount == driveCount }
    public var isEmpty: Bool { chargeCount == 0 && driveCount == 0 }
}

public enum EnergyCycleState: Equatable, Sendable {
    case complete
    case open
    case consecutiveCharge

    public func title(language: AppLanguage) -> String {
        switch self {
        case .complete:
            return AppText.localized("Complete", "完整", language: language)
        case .open:
            return AppText.localized("Current cycle", "当前周期", language: language)
        case .consecutiveCharge:
            return AppText.localized("Top-up", "连续补电", language: language)
        }
    }
}

public struct EnergyCycle: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let chargeStart: Date
    public let chargeEnd: Date
    public let address: String?
    public let chargeStartSOC: Int?
    public let chargeEndSOC: Int?
    public let dischargeEndSOC: Int?
    public let chargerInputKWh: Double?
    public let batteryAddedKWh: Double?
    public let chargingLossKWh: Double?
    public let chargingEfficiency: Double?
    public let drivingEnergyKWh: Double?
    public let drivingEnergyRecordCount: Int
    public let driveCount: Int
    public let distanceKm: Double?
    public let distanceRecordCount: Int
    public let state: EnergyCycleState

    public var chargeSOCDelta: Int? {
        guard let chargeStartSOC, let chargeEndSOC else { return nil }
        return chargeEndSOC - chargeStartSOC
    }

    public var dischargeSOCDelta: Int? {
        guard let chargeEndSOC, let dischargeEndSOC else { return nil }
        return chargeEndSOC - dischargeEndSOC
    }

    public var drivingEnergyIsComplete: Bool {
        drivingEnergyRecordCount == driveCount
    }

    public var distanceIsComplete: Bool {
        distanceRecordCount == driveCount
    }
}

public struct EnergyRangeTrendPoint: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let date: Date
    public let rangeAt100Km: Double
    public let odometerKm: Double?
}

public struct EnergyCycleAnalysis: Equatable, Sendable {
    public let selectedPeriod: EnergyCyclePeriod
    public let current: EnergyPeriodSummary
    public let previous: EnergyPeriodSummary
    public let recentCycles: [EnergyCycle]
    public let rangeTrend: [EnergyRangeTrendPoint]
}

public enum EnergyCycleAnalyzer {
    public static func analyze(
        dataSet: EnergyCycleDataSet,
        period: EnergyCyclePeriod,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> EnergyCycleAnalysis {
        let interval = selectedInterval(period: period, now: now, calendar: calendar)
        let previousInterval = precedingInterval(for: interval, period: period, calendar: calendar)

        return EnergyCycleAnalysis(
            selectedPeriod: period,
            current: summarize(charges: dataSet.charges, drives: dataSet.drives, interval: interval),
            previous: summarize(charges: dataSet.charges, drives: dataSet.drives, interval: previousInterval),
            recentCycles: cycles(charges: dataSet.charges, drives: dataSet.drives, now: now),
            rangeTrend: rangeTrend(charges: dataSet.charges)
        )
    }

    private static func summarize(
        charges: [ChargeSummaryRecord],
        drives: [DriveSummaryRecord],
        interval: DateInterval
    ) -> EnergyPeriodSummary {
        let periodCharges = charges.filter { record in
            eventDate(end: record.endDate, start: record.startDate).map(interval.containsHalfOpen) == true
        }
        let periodDrives = drives.filter { record in
            DomainDateParser.date(from: record.startDate).map(interval.containsHalfOpen) == true
        }

        let chargerInputValues = periodCharges.compactMap { nonnegativeFinite($0.chargeEnergyUsed) }
        let batteryAddedValues = periodCharges.compactMap { nonnegativeFinite($0.chargeEnergyAdded) }
        let drivingEnergyValues = periodDrives.compactMap { positiveFinite($0.energyConsumedNet) }
        let distanceValues = periodDrives.compactMap { nonnegativeFinite($0.distance) }
        let chargeSOCDeltas = periodCharges.compactMap {
            positiveDelta(start: validSOC($0.startBatteryLevel), end: validSOC($0.endBatteryLevel))
        }
        let driveSOCDeltas = periodDrives.compactMap {
            positiveDelta(start: validSOC($0.endBatteryLevel), end: validSOC($0.startBatteryLevel))
        }
        let pairedChargeEnergy = periodCharges.compactMap { record -> (added: Double, used: Double)? in
            guard let added = nonnegativeFinite(record.chargeEnergyAdded),
                  let used = positiveFinite(record.chargeEnergyUsed)
            else { return nil }
            return (added, used)
        }
        let pairedAdded = pairedChargeEnergy.reduce(0) { $0 + $1.added }
        let pairedUsed = pairedChargeEnergy.reduce(0) { $0 + $1.used }

        return EnergyPeriodSummary(
            chargeCount: periodCharges.count,
            driveCount: periodDrives.count,
            chargerInputKWh: sumOrNil(chargerInputValues),
            chargerInputRecordCount: chargerInputValues.count,
            batteryAddedKWh: sumOrNil(batteryAddedValues),
            batteryAddedRecordCount: batteryAddedValues.count,
            drivingEnergyKWh: sumOrNil(drivingEnergyValues),
            drivingEnergyRecordCount: drivingEnergyValues.count,
            distanceKm: sumOrNil(distanceValues),
            distanceRecordCount: distanceValues.count,
            chargeSOCAdded: chargeSOCDeltas.isEmpty ? nil : chargeSOCDeltas.reduce(0, +),
            driveSOCUsed: driveSOCDeltas.isEmpty ? nil : driveSOCDeltas.reduce(0, +),
            chargingEfficiency: pairedUsed > 0 ? pairedAdded / pairedUsed * 100 : nil
        )
    }

    private static func cycles(
        charges: [ChargeSummaryRecord],
        drives: [DriveSummaryRecord],
        now: Date
    ) -> [EnergyCycle] {
        let datedCharges = charges.compactMap { charge -> (record: ChargeSummaryRecord, start: Date, end: Date)? in
            guard let start = DomainDateParser.date(from: charge.startDate),
                  let end = charge.endDate.flatMap(DomainDateParser.date(from:)),
                  end >= start
            else { return nil }
            return (charge, start, end)
        }
        .sorted { $0.start < $1.start }

        let datedDrives = drives.compactMap { drive -> (record: DriveSummaryRecord, start: Date, end: Date)? in
            guard let start = DomainDateParser.date(from: drive.startDate),
                  let end = DomainDateParser.date(from: drive.endDate),
                  end >= start
            else { return nil }
            return (drive, start, end)
        }
        .sorted { $0.start < $1.start }

        return datedCharges.indices.map { index in
            let charge = datedCharges[index]
            let nextCharge = datedCharges.indices.contains(index + 1) ? datedCharges[index + 1] : nil
            let windowEnd = nextCharge?.start ?? now
            let cycleDrives = datedDrives.filter {
                $0.start >= charge.end && $0.start < windowEnd && $0.end <= windowEnd
            }
            let driveEnergyValues = cycleDrives.compactMap { positiveFinite($0.record.energyConsumedNet) }
            let distanceValues = cycleDrives.compactMap { nonnegativeFinite($0.record.distance) }
            let chargerInput = nonnegativeFinite(charge.record.chargeEnergyUsed)
            let batteryAdded = nonnegativeFinite(charge.record.chargeEnergyAdded)
            let dischargeEndSOC = validSOC(nextCharge?.record.startBatteryLevel)
                ?? cycleDrives.last.flatMap { validSOC($0.record.endBatteryLevel) }
            let state: EnergyCycleState
            if nextCharge == nil {
                state = .open
            } else if cycleDrives.isEmpty {
                state = .consecutiveCharge
            } else {
                state = .complete
            }

            return EnergyCycle(
                chargeId: charge.record.chargeId,
                chargeStart: charge.start,
                chargeEnd: charge.end,
                address: charge.record.address,
                chargeStartSOC: validSOC(charge.record.startBatteryLevel),
                chargeEndSOC: validSOC(charge.record.endBatteryLevel),
                dischargeEndSOC: dischargeEndSOC,
                chargerInputKWh: chargerInput,
                batteryAddedKWh: batteryAdded,
                chargingLossKWh: chargerInput.flatMap { used in batteryAdded.map { used - $0 } },
                chargingEfficiency: chargerInput.flatMap { used in
                    guard used > 0, let batteryAdded else { return nil }
                    return batteryAdded / used * 100
                },
                drivingEnergyKWh: sumOrNil(driveEnergyValues),
                drivingEnergyRecordCount: driveEnergyValues.count,
                driveCount: cycleDrives.count,
                distanceKm: sumOrNil(distanceValues),
                distanceRecordCount: distanceValues.count,
                state: state
            )
        }
        .sorted { $0.chargeEnd > $1.chargeEnd }
    }

    private static func rangeTrend(charges: [ChargeSummaryRecord]) -> [EnergyRangeTrendPoint] {
        charges.compactMap { charge in
            guard let date = eventDate(end: charge.endDate, start: charge.startDate),
                  let soc = validSOC(charge.endBatteryLevel), soc >= 20,
                  let endRange = positiveFinite(charge.endRatedRangeKm)
            else { return nil }
            let normalized = endRange * 100 / Double(soc)
            guard normalized >= 50, normalized <= 1_000 else { return nil }
            return EnergyRangeTrendPoint(
                chargeId: charge.chargeId,
                date: date,
                rangeAt100Km: normalized,
                odometerKm: nonnegativeFinite(charge.odometerKm)
            )
        }
        .sorted { $0.date < $1.date }
    }

    private static func selectedInterval(period: EnergyCyclePeriod, now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        switch period {
        case .today:
            return today
        case .yesterday:
            return precedingInterval(for: today, period: .today, calendar: calendar)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? today
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? today
        }
    }

    private static func precedingInterval(
        for interval: DateInterval,
        period: EnergyCyclePeriod,
        calendar: Calendar
    ) -> DateInterval {
        let component: Calendar.Component
        switch period {
        case .today, .yesterday:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        let previousReference = interval.start.addingTimeInterval(-1)
        return calendar.dateInterval(of: component, for: previousReference)
            ?? DateInterval(start: interval.start.addingTimeInterval(-interval.duration), duration: interval.duration)
    }

    private static func eventDate(end: String?, start: String) -> Date? {
        end.flatMap(DomainDateParser.date(from:)) ?? DomainDateParser.date(from: start)
    }

    private static func validSOC(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else { return nil }
        return value
    }

    private static func positiveDelta(start: Int?, end: Int?) -> Int? {
        guard let start, let end else { return nil }
        let delta = end - start
        return delta >= 0 ? delta : nil
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func sumOrNil(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +)
    }
}

private extension DateInterval {
    func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}
