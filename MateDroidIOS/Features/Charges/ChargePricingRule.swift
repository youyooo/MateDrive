import Foundation

public enum ChargePricingChargeType: String, Codable, Equatable, Sendable {
    case any
    case ac
    case dc
    case teslaSupercharger
    case otherDC

    public func displayText(language: AppLanguage) -> String {
        switch self {
        case .any:
            return AppText.localized("Any", "任意", language: language)
        case .ac:
            return AppText.localized("AC", "交流", language: language)
        case .dc:
            return AppText.localized("DC", "直流", language: language)
        case .teslaSupercharger:
            return AppText.localized("Tesla Supercharger", "特斯拉超充", language: language)
        case .otherDC:
            return AppText.localized("Other DC", "其他直流桩", language: language)
        }
    }
}

public enum ChargePricingChargerIdentity: Equatable, Sendable {
    case ac
    case teslaSupercharger
    case otherDC
    case unknownDC
}

public enum ChargeCostSource: String, Equatable, Sendable {
    case none
    case api
    case pricingRule
    case manual

    public func displayText(language: AppLanguage) -> String {
        switch self {
        case .manual:
            return AppText.localized("Local manual price", "本地手动价格", language: language)
        case .pricingRule:
            return AppText.localized("Pricing rule", "价格规则", language: language)
        case .api:
            return AppText.localized("TeslaMate API price", "TeslaMate API 价格", language: language)
        case .none:
            return AppText.localized("No cost recorded", "未记录费用", language: language)
        }
    }
}

public struct ChargePricingTimeSegment: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var startMinuteOfDay: Int
    public var endMinuteOfDay: Int
    public var pricePerKWh: Double

    public init(
        id: String = UUID().uuidString,
        startMinuteOfDay: Int,
        endMinuteOfDay: Int,
        pricePerKWh: Double
    ) {
        self.id = id
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.pricePerKWh = pricePerKWh
    }
}

public struct ChargePricingRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var chargeType: ChargePricingChargeType
    public var addressKeyword: String?
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Double?
    public var startMinuteOfDay: Int?
    public var endMinuteOfDay: Int?
    public var effectiveFromDate: String?
    public var effectiveToDate: String?
    public var pricePerKWh: Double
    public var timeSegments: [ChargePricingTimeSegment]
    public var sessionFee: Double
    public var priority: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        chargeType: ChargePricingChargeType = .any,
        addressKeyword: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double? = nil,
        startMinuteOfDay: Int? = nil,
        endMinuteOfDay: Int? = nil,
        effectiveFromDate: String? = nil,
        effectiveToDate: String? = nil,
        pricePerKWh: Double,
        timeSegments: [ChargePricingTimeSegment] = [],
        sessionFee: Double = 0,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.chargeType = chargeType
        self.addressKeyword = addressKeyword
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.effectiveFromDate = effectiveFromDate
        self.effectiveToDate = effectiveToDate
        self.pricePerKWh = pricePerKWh
        self.timeSegments = timeSegments
        self.sessionFee = sessionFee
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case isEnabled
        case chargeType
        case addressKeyword
        case latitude
        case longitude
        case radiusMeters
        case startMinuteOfDay
        case endMinuteOfDay
        case effectiveFromDate
        case effectiveToDate
        case pricePerKWh
        case timeSegments
        case sessionFee
        case priority
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        chargeType = try container.decodeIfPresent(ChargePricingChargeType.self, forKey: .chargeType) ?? .any
        addressKeyword = try container.decodeIfPresent(String.self, forKey: .addressKeyword)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        radiusMeters = try container.decodeIfPresent(Double.self, forKey: .radiusMeters)
        startMinuteOfDay = try container.decodeIfPresent(Int.self, forKey: .startMinuteOfDay)
        endMinuteOfDay = try container.decodeIfPresent(Int.self, forKey: .endMinuteOfDay)
        effectiveFromDate = try container.decodeIfPresent(String.self, forKey: .effectiveFromDate)
        effectiveToDate = try container.decodeIfPresent(String.self, forKey: .effectiveToDate)
        pricePerKWh = try container.decodeIfPresent(Double.self, forKey: .pricePerKWh) ?? 0
        timeSegments = try container.decodeIfPresent([ChargePricingTimeSegment].self, forKey: .timeSegments) ?? []
        sessionFee = try container.decodeIfPresent(Double.self, forKey: .sessionFee) ?? 0
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(chargeType, forKey: .chargeType)
        try container.encodeIfPresent(addressKeyword, forKey: .addressKeyword)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
        try container.encodeIfPresent(radiusMeters, forKey: .radiusMeters)
        try container.encodeIfPresent(startMinuteOfDay, forKey: .startMinuteOfDay)
        try container.encodeIfPresent(endMinuteOfDay, forKey: .endMinuteOfDay)
        try container.encodeIfPresent(effectiveFromDate, forKey: .effectiveFromDate)
        try container.encodeIfPresent(effectiveToDate, forKey: .effectiveToDate)
        try container.encode(pricePerKWh, forKey: .pricePerKWh)
        try container.encode(timeSegments, forKey: .timeSegments)
        try container.encode(sessionFee, forKey: .sessionFee)
        try container.encode(priority, forKey: .priority)
    }
}

public enum ChargePricingValidationIssue: Equatable, Sendable {
    case invalidPrice
    case invalidSessionFee
    case incompleteLocation
    case invalidLocation
    case incompleteTimeWindow
    case invalidTimeWindow
    case invalidEffectiveDateRange
    case invalidTimeSegment
    case overlappingTimeSegments
}

public enum ChargePricingRuleValidator {
    public static func issues(for rule: ChargePricingRule) -> [ChargePricingValidationIssue] {
        var issues: [ChargePricingValidationIssue] = []
        if !rule.pricePerKWh.isFinite || rule.pricePerKWh < 0 {
            issues.append(.invalidPrice)
        }
        if !rule.sessionFee.isFinite || rule.sessionFee < 0 {
            issues.append(.invalidSessionFee)
        }

        let locationValuesPresent = [rule.latitude != nil, rule.longitude != nil, rule.radiusMeters != nil]
        if locationValuesPresent.contains(true), locationValuesPresent.contains(false) {
            issues.append(.incompleteLocation)
        } else if let latitude = rule.latitude, let longitude = rule.longitude, let radius = rule.radiusMeters,
                  (GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) == nil || !radius.isFinite || radius <= 0) {
            issues.append(.invalidLocation)
        }

        if (rule.startMinuteOfDay == nil) != (rule.endMinuteOfDay == nil) {
            issues.append(.incompleteTimeWindow)
        } else if let start = rule.startMinuteOfDay, let end = rule.endMinuteOfDay,
                  !(0...1_439).contains(start) || !(0...1_439).contains(end) {
            issues.append(.invalidTimeWindow)
        }

        if let from = rule.effectiveFromDate, !ChargePricingDate.isValid(from) {
            issues.append(.invalidEffectiveDateRange)
        } else if let to = rule.effectiveToDate, !ChargePricingDate.isValid(to) {
            issues.append(.invalidEffectiveDateRange)
        } else if let from = rule.effectiveFromDate, let to = rule.effectiveToDate, from > to {
            issues.append(.invalidEffectiveDateRange)
        }

        if rule.timeSegments.contains(where: {
            !(0...1_439).contains($0.startMinuteOfDay) ||
                !(0...1_439).contains($0.endMinuteOfDay) ||
                !$0.pricePerKWh.isFinite || $0.pricePerKWh < 0
        }) {
            issues.append(.invalidTimeSegment)
        } else if timeSegmentsOverlap(rule.timeSegments) {
            issues.append(.overlappingTimeSegments)
        }
        return issues
    }

    private static func timeSegmentsOverlap(_ segments: [ChargePricingTimeSegment]) -> Bool {
        var occupied = Array(repeating: false, count: 1_440)
        for segment in segments {
            let minutes: [Int]
            if segment.startMinuteOfDay <= segment.endMinuteOfDay {
                minutes = Array(segment.startMinuteOfDay...segment.endMinuteOfDay)
            } else {
                minutes = Array(segment.startMinuteOfDay...1_439) + Array(0...segment.endMinuteOfDay)
            }
            for minute in minutes {
                if occupied[minute] { return true }
                occupied[minute] = true
            }
        }
        return false
    }
}

public struct ChargePricingInput: Equatable, Sendable {
    public let startDate: String?
    public let endDate: String?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let energyAddedKWh: Double?
    public let energySamples: [ChargePricingEnergySample]
    public let isDc: Bool
    public let chargerIdentity: ChargePricingChargerIdentity

    public init(
        startDate: String?,
        endDate: String? = nil,
        address: String?,
        latitude: Double?,
        longitude: Double?,
        energyAddedKWh: Double?,
        energySamples: [ChargePricingEnergySample] = [],
        isDc: Bool,
        chargerIdentity: ChargePricingChargerIdentity? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.energyAddedKWh = energyAddedKWh
        self.energySamples = energySamples
        self.isDc = isDc
        self.chargerIdentity = chargerIdentity ?? (isDc ? .unknownDC : .ac)
    }
}

public struct ChargePricingEnergySample: Equatable, Sendable {
    public let date: String?
    public let cumulativeEnergyAddedKWh: Double?

    public init(date: String?, cumulativeEnergyAddedKWh: Double?) {
        self.date = date
        self.cumulativeEnergyAddedKWh = cumulativeEnergyAddedKWh
    }
}

public struct ChargePricingEstimate: Equatable, Sendable {
    public let rule: ChargePricingRule
    public let cost: Double
    public let energyCost: Double
    public let sessionFee: Double
    public let components: [ChargePricingCostComponent]

    public init(rule: ChargePricingRule, cost: Double, energyCost: Double, sessionFee: Double, components: [ChargePricingCostComponent]) {
        self.rule = rule
        self.cost = cost
        self.energyCost = energyCost
        self.sessionFee = sessionFee
        self.components = components
    }
}

public struct ChargePricingCostComponent: Equatable, Sendable {
    public let startMinuteOfDay: Int?
    public let endMinuteOfDay: Int?
    public let energyKWh: Double
    public let pricePerKWh: Double
    public let cost: Double
}

public enum ChargePricingRuleEngine {
    public static func estimateCost(for input: ChargePricingInput, rules: [ChargePricingRule]) -> ChargePricingEstimate? {
        guard let energy = input.energyAddedKWh, energy > 0 else {
            return nil
        }

        return rules
            .filter { matches(rule: $0, input: input) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .first
            .map { rule in
                let allocation = segmentedEnergyAllocation(for: rule, input: input) ?? [
                    ChargePricingCostComponent(
                        startMinuteOfDay: nil,
                        endMinuteOfDay: nil,
                        energyKWh: energy,
                        pricePerKWh: pricePerKWh(for: rule, input: input),
                        cost: energy * pricePerKWh(for: rule, input: input)
                    )
                ]
                let energyCost = allocation.reduce(0) { $0 + $1.cost }
                return ChargePricingEstimate(
                    rule: rule,
                    cost: max(0, rule.sessionFee + energyCost),
                    energyCost: energyCost,
                    sessionFee: rule.sessionFee,
                    components: allocation
                )
            }
    }

    private static func matches(rule: ChargePricingRule, input: ChargePricingInput) -> Bool {
        guard rule.isEnabled,
              ChargePricingRuleValidator.issues(for: rule).isEmpty,
              matchesChargeType(rule.chargeType, identity: input.chargerIdentity) else {
            return false
        }

        if let keyword = rule.addressKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
            guard input.address?.localizedCaseInsensitiveContains(keyword) == true else {
                return false
            }
        }


        if rule.effectiveFromDate != nil || rule.effectiveToDate != nil {
            guard let chargeDate = input.startDate.flatMap(ChargePricingDate.localDate(from:)) else {
                return false
            }
            if let from = rule.effectiveFromDate, chargeDate < from { return false }
            if let to = rule.effectiveToDate, chargeDate > to { return false }
        }

        if let ruleLatitude = rule.latitude,
           let ruleLongitude = rule.longitude,
           let radiusMeters = rule.radiusMeters,
           radiusMeters > 0
        {
            guard let latitude = input.latitude, let longitude = input.longitude else {
                return false
            }
            guard distanceMeters(from: (ruleLatitude, ruleLongitude), to: (latitude, longitude)) <= radiusMeters else {
                return false
            }
        }

        if let startMinute = normalizedMinute(rule.startMinuteOfDay),
           let endMinute = normalizedMinute(rule.endMinuteOfDay)
        {
            guard let date = input.startDate.flatMap(DomainDateParser.date(from:)) else {
                return false
            }
            let minute = minuteOfDay(for: date, timeZone: pricingTimeZone(for: input))
            guard minuteMatches(minute, startMinute: startMinute, endMinute: endMinute) else {
                return false
            }
        }

        return true
    }

    private static func pricePerKWh(for rule: ChargePricingRule, input: ChargePricingInput) -> Double {
        guard !rule.timeSegments.isEmpty,
              let date = input.startDate.flatMap(DomainDateParser.date(from:))
        else {
            return rule.pricePerKWh
        }

        let minute = minuteOfDay(for: date, timeZone: pricingTimeZone(for: input))
        let segment = rule.timeSegments
            .filter { $0.pricePerKWh >= 0 }
            .first {
                minuteMatches(
                    minute,
                    startMinute: normalizedMinute($0.startMinuteOfDay) ?? 0,
                    endMinute: normalizedMinute($0.endMinuteOfDay) ?? 1_439
                )
            }
        return segment?.pricePerKWh ?? rule.pricePerKWh
    }

    private static func segmentedEnergyAllocation(for rule: ChargePricingRule, input: ChargePricingInput) -> [ChargePricingCostComponent]? {
        guard !rule.timeSegments.isEmpty else {
            return nil
        }

        let samples = input.energySamples
            .compactMap { sample -> (Date, Double)? in
                guard let date = sample.date.flatMap(DomainDateParser.date(from:)),
                      let energy = sample.cumulativeEnergyAddedKWh,
                      energy >= 0
                else {
                    return nil
                }
                return (date, energy)
            }
            .sorted { $0.0 < $1.0 }

        if samples.isEmpty {
            guard let totalEnergy = input.energyAddedKWh,
                  totalEnergy > 0,
                  let startDate = input.startDate.flatMap(DomainDateParser.date(from:)),
                  let endDate = input.endDate.flatMap(DomainDateParser.date(from:))
            else {
                return nil
            }
            return energyAllocation(
                forEnergy: totalEnergy,
                from: startDate,
                to: max(endDate, startDate),
                rule: rule,
                timeZone: pricingTimeZone(for: input)
            )
        }

        let timeZone = pricingTimeZone(for: input)
        var previousDate = input.startDate.flatMap(DomainDateParser.date(from:)) ?? samples[0].0
        var previousEnergy = 0.0
        var allocation: [ChargePricingCostComponent] = []
        var allocatedEnergy = 0.0

        for sample in samples {
            let deltaEnergy = sample.1 - previousEnergy
            if deltaEnergy > 0 {
                allocation.append(contentsOf: energyAllocation(
                    forEnergy: deltaEnergy,
                    from: previousDate,
                    to: max(sample.0, previousDate),
                    rule: rule,
                    timeZone: timeZone
                ))
                allocatedEnergy += deltaEnergy
            }
            previousDate = max(sample.0, previousDate)
            previousEnergy = max(sample.1, previousEnergy)
        }

        if let totalEnergy = input.energyAddedKWh,
           totalEnergy > allocatedEnergy
        {
            let endDate = input.endDate.flatMap(DomainDateParser.date(from:)) ?? previousDate
            allocation.append(contentsOf: energyAllocation(
                forEnergy: totalEnergy - allocatedEnergy,
                from: previousDate,
                to: max(endDate, previousDate),
                rule: rule,
                timeZone: timeZone
            ))
            allocatedEnergy = totalEnergy
        }

        return allocatedEnergy > 0 ? merged(allocation) : nil
    }

    private static func energyAllocation(forEnergy energy: Double, from startDate: Date, to endDate: Date, rule: ChargePricingRule, timeZone: TimeZone) -> [ChargePricingCostComponent] {
        guard energy > 0 else {
            return []
        }
        let duration = endDate.timeIntervalSince(startDate)
        guard duration > 0 else {
            let price = pricePerKWh(for: rule, date: endDate, timeZone: timeZone)
            return [component(energy: energy, price: price, date: endDate, rule: rule, timeZone: timeZone)]
        }

        var cursor = startDate
        var allocation: [ChargePricingCostComponent] = []
        while cursor < endDate {
            let next = min(nextMinuteBoundary(after: cursor), endDate)
            let fraction = next.timeIntervalSince(cursor) / duration
            let price = pricePerKWh(for: rule, date: cursor, timeZone: timeZone)
            allocation.append(component(energy: energy * fraction, price: price, date: cursor, rule: rule, timeZone: timeZone))
            cursor = next
        }
        return merged(allocation)
    }

    private static func component(energy: Double, price: Double, date: Date, rule: ChargePricingRule, timeZone: TimeZone) -> ChargePricingCostComponent {
        let minute = minuteOfDay(for: date, timeZone: timeZone)
        let segment = rule.timeSegments.first {
            minuteMatches(minute, startMinute: normalizedMinute($0.startMinuteOfDay) ?? 0, endMinute: normalizedMinute($0.endMinuteOfDay) ?? 1_439)
        }
        return ChargePricingCostComponent(
            startMinuteOfDay: segment?.startMinuteOfDay,
            endMinuteOfDay: segment?.endMinuteOfDay,
            energyKWh: energy,
            pricePerKWh: price,
            cost: energy * price
        )
    }

    private static func merged(_ components: [ChargePricingCostComponent]) -> [ChargePricingCostComponent] {
        components.reduce(into: [ChargePricingCostComponent]()) { result, component in
            if let index = result.firstIndex(where: {
                $0.startMinuteOfDay == component.startMinuteOfDay &&
                    $0.endMinuteOfDay == component.endMinuteOfDay &&
                    abs($0.pricePerKWh - component.pricePerKWh) < 0.000_001
            }) {
                let existing = result[index]
                result[index] = ChargePricingCostComponent(
                    startMinuteOfDay: existing.startMinuteOfDay,
                    endMinuteOfDay: existing.endMinuteOfDay,
                    energyKWh: existing.energyKWh + component.energyKWh,
                    pricePerKWh: existing.pricePerKWh,
                    cost: existing.cost + component.cost
                )
            } else {
                result.append(component)
            }
        }
    }

    private static func nextMinuteBoundary(after date: Date) -> Date {
        let calendar = Calendar.current
        let second = calendar.component(.second, from: date)
        let nanosecond = calendar.component(.nanosecond, from: date)
        let secondsToAdd = max(1, 60 - second)
        let boundary = calendar.date(byAdding: .second, value: secondsToAdd, to: date) ?? date.addingTimeInterval(TimeInterval(secondsToAdd))
        if nanosecond == 0 {
            return boundary
        }
        return calendar.date(bySetting: .nanosecond, value: 0, of: boundary) ?? boundary
    }

    private static func pricePerKWh(for rule: ChargePricingRule, date: Date, timeZone: TimeZone) -> Double {
        let minute = minuteOfDay(for: date, timeZone: timeZone)
        return rule.timeSegments
            .filter { $0.pricePerKWh >= 0 }
            .first {
                minuteMatches(
                    minute,
                    startMinute: normalizedMinute($0.startMinuteOfDay) ?? 0,
                    endMinute: normalizedMinute($0.endMinuteOfDay) ?? 1_439
                )
            }?
            .pricePerKWh ?? rule.pricePerKWh
    }

    private static func pricingTimeZone(for input: ChargePricingInput) -> TimeZone {
        timeZone(from: input.startDate) ?? timeZone(from: input.endDate) ?? .current
    }

    private static func minuteOfDay(for date: Date, timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    private static func timeZone(from value: String?) -> TimeZone? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let pattern = #"([+-])(\d{2}):?(\d{2})$"#
        guard let match = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let suffix = String(value[match])
        let sign = suffix.hasPrefix("-") ? -1 : 1
        let digits = suffix.dropFirst().replacingOccurrences(of: ":", with: "")
        guard digits.count == 4,
              let hours = Int(digits.prefix(2)),
              let minutes = Int(digits.suffix(2)),
              hours <= 23,
              minutes <= 59
        else {
            return nil
        }

        return TimeZone(secondsFromGMT: sign * ((hours * 60 + minutes) * 60))
    }

    private static func matchesChargeType(_ type: ChargePricingChargeType, identity: ChargePricingChargerIdentity) -> Bool {
        switch type {
        case .any:
            return true
        case .ac:
            return identity == .ac
        case .dc:
            return identity != .ac
        case .teslaSupercharger:
            return identity == .teslaSupercharger
        case .otherDC:
            return identity == .otherDC
        }
    }

    private static func normalizedMinute(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return min(max(value, 0), 1_439)
    }

    private static func minuteMatches(_ minute: Int, startMinute: Int, endMinute: Int) -> Bool {
        if startMinute <= endMinute {
            return minute >= startMinute && minute <= endMinute
        }
        return minute >= startMinute || minute <= endMinute
    }

    private static func distanceMeters(from lhs: (Double, Double), to rhs: (Double, Double)) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = lhs.0 * .pi / 180
        let lat2 = rhs.0 * .pi / 180
        let deltaLat = (rhs.0 - lhs.0) * .pi / 180
        let deltaLon = (rhs.1 - lhs.1) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
            cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

public enum ChargePricingDate {
    public static func isValid(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    public static func localDate(from timestamp: String) -> String? {
        guard timestamp.count >= 10 else { return nil }
        let value = String(timestamp.prefix(10))
        return isValid(value) ? value : nil
    }
}
