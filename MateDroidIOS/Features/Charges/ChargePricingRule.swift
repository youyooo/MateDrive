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

public enum ChargePricingRuleOrigin: String, Codable, Equatable, Sendable {
    case user
    case stationLearned
    case regionalOfficial
}

public enum ChargePricingCurrencyCode {
    public static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    public static func isValid(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        return scalars.count == 3 && scalars.allSatisfy { (65...90).contains(Int($0.value)) }
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
    public var origin: ChargePricingRuleOrigin
    public var regionCode: String?
    public var sourceURL: String?
    public var verifiedAt: String?
    public var serviceFeePerKWh: Double
    public var parkingFeeRuleID: String?
    public var applicableWeekdays: [Int]?
    public var applicableMonths: [Int]?
    public var currencyCode: String?
    public var stationKey: String?

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
        priority: Int = 0,
        origin: ChargePricingRuleOrigin = .user,
        regionCode: String? = nil,
        sourceURL: String? = nil,
        verifiedAt: String? = nil,
        serviceFeePerKWh: Double = 0,
        parkingFeeRuleID: String? = nil,
        applicableWeekdays: [Int]? = nil,
        applicableMonths: [Int]? = nil,
        currencyCode: String? = nil,
        stationKey: String? = nil
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
        self.origin = origin
        self.regionCode = regionCode
        self.sourceURL = sourceURL
        self.verifiedAt = verifiedAt
        self.serviceFeePerKWh = serviceFeePerKWh
        self.parkingFeeRuleID = parkingFeeRuleID
        self.applicableWeekdays = applicableWeekdays
        self.applicableMonths = applicableMonths
        self.currencyCode = ChargePricingCurrencyCode.normalized(currencyCode)
        self.stationKey = stationKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
        case origin
        case regionCode
        case sourceURL
        case verifiedAt
        case serviceFeePerKWh
        case parkingFeeRuleID
        case applicableWeekdays
        case applicableMonths
        case currencyCode
        case stationKey
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
        origin = try container.decodeIfPresent(ChargePricingRuleOrigin.self, forKey: .origin) ?? .user
        regionCode = try container.decodeIfPresent(String.self, forKey: .regionCode)
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        verifiedAt = try container.decodeIfPresent(String.self, forKey: .verifiedAt)
        serviceFeePerKWh = try container.decodeIfPresent(Double.self, forKey: .serviceFeePerKWh) ?? 0
        parkingFeeRuleID = try container.decodeIfPresent(String.self, forKey: .parkingFeeRuleID)
        applicableWeekdays = try container.decodeIfPresent([Int].self, forKey: .applicableWeekdays)
        applicableMonths = try container.decodeIfPresent([Int].self, forKey: .applicableMonths)
        currencyCode = ChargePricingCurrencyCode.normalized(
            try container.decodeIfPresent(String.self, forKey: .currencyCode)
        )
        stationKey = try container.decodeIfPresent(String.self, forKey: .stationKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
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
        try container.encode(origin, forKey: .origin)
        try container.encodeIfPresent(regionCode, forKey: .regionCode)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
        try container.encode(serviceFeePerKWh, forKey: .serviceFeePerKWh)
        try container.encodeIfPresent(parkingFeeRuleID, forKey: .parkingFeeRuleID)
        try container.encodeIfPresent(applicableWeekdays, forKey: .applicableWeekdays)
        try container.encodeIfPresent(applicableMonths, forKey: .applicableMonths)
        try container.encodeIfPresent(currencyCode, forKey: .currencyCode)
        try container.encodeIfPresent(stationKey, forKey: .stationKey)
    }
}

public enum ChargePricingValidationIssue: Equatable, Sendable {
    case invalidPrice
    case invalidSessionFee
    case invalidServiceFee
    case invalidApplicableWeekdays
    case invalidApplicableMonths
    case invalidCurrency
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
        if !rule.serviceFeePerKWh.isFinite || rule.serviceFeePerKWh < 0 {
            issues.append(.invalidServiceFee)
        }
        if !isValidApplicability(rule.applicableWeekdays, allowed: 1...7) {
            issues.append(.invalidApplicableWeekdays)
        }
        if !isValidApplicability(rule.applicableMonths, allowed: 1...12) {
            issues.append(.invalidApplicableMonths)
        }
        if let currencyCode = ChargePricingCurrencyCode.normalized(rule.currencyCode),
           !ChargePricingCurrencyCode.isValid(currencyCode) {
            issues.append(.invalidCurrency)
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

    private static func isValidApplicability(_ values: [Int]?, allowed: ClosedRange<Int>) -> Bool {
        guard let values else { return true }
        return !values.isEmpty && values.allSatisfy(allowed.contains) && Set(values).count == values.count
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
    public let serviceFee: Double
    public let sessionFee: Double
    public let components: [ChargePricingCostComponent]

    public init(
        rule: ChargePricingRule,
        cost: Double,
        energyCost: Double,
        sessionFee: Double,
        serviceFee: Double = 0,
        components: [ChargePricingCostComponent]
    ) {
        self.rule = rule
        self.cost = cost
        self.energyCost = energyCost
        self.serviceFee = serviceFee
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
        guard let energy = input.energyAddedKWh,
              energy.isFinite,
              energy >= 0 else {
            return nil
        }

        let matchingRule = rules
            .filter { matches(rule: $0, input: input) }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .first
        guard let rule = matchingRule else {
            return nil
        }
        let allocation: [ChargePricingCostComponent]
        if energy == 0 {
            allocation = []
        } else {
            allocation = segmentedEnergyAllocation(for: rule, input: input) ?? [
                ChargePricingCostComponent(
                    startMinuteOfDay: nil,
                    endMinuteOfDay: nil,
                    energyKWh: energy,
                    pricePerKWh: pricePerKWh(for: rule, input: input),
                    cost: energy * pricePerKWh(for: rule, input: input)
                )
            ]
        }
        guard allocation.allSatisfy({
            $0.energyKWh.isFinite && $0.energyKWh >= 0 && $0.cost.isFinite
        }) else {
            return nil
        }
        let energyCost = allocation.reduce(0) { $0 + $1.cost }
        guard energyCost.isFinite else {
            return nil
        }
        let serviceFee = energy * rule.serviceFeePerKWh
        guard serviceFee.isFinite,
              rule.sessionFee.isFinite else {
            return nil
        }
        let subtotal = energyCost + serviceFee
        guard subtotal.isFinite else {
            return nil
        }
        let cost = subtotal + rule.sessionFee
        guard cost.isFinite else {
            return nil
        }
        return ChargePricingEstimate(
            rule: rule,
            cost: cost,
            energyCost: energyCost,
            sessionFee: rule.sessionFee,
            serviceFee: serviceFee,
            components: allocation
        )
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


        if rule.effectiveFromDate != nil || rule.effectiveToDate != nil ||
            rule.applicableWeekdays != nil || rule.applicableMonths != nil
        {
            guard let date = input.startDate.flatMap(DomainDateParser.date(from:)) else {
                return false
            }
            let calendar = pricingCalendar(for: rule, input: input)
            let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
            guard
                  let chargeDate = ChargePricingDate.dateString(from: components)
            else {
                return false
            }
            if let from = rule.effectiveFromDate, chargeDate < from { return false }
            if let to = rule.effectiveToDate, chargeDate > to { return false }
            if let weekdays = rule.applicableWeekdays,
               !weekdays.contains(components.weekday ?? 0)
            {
                return false
            }
            if let months = rule.applicableMonths,
               !months.contains(components.month ?? 0)
            {
                return false
            }
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
            let minute = minuteOfDay(for: date, timeZone: pricingTimeZone(for: rule, input: input))
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

        let minute = minuteOfDay(for: date, timeZone: pricingTimeZone(for: rule, input: input))
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

        guard let totalEnergy = input.energyAddedKWh,
              totalEnergy.isFinite,
              totalEnergy > 0 else {
            return nil
        }
        let sessionStart = input.startDate.flatMap(DomainDateParser.date(from:))
        let sessionEnd = input.endDate.flatMap(DomainDateParser.date(from:))
        let samples = input.energySamples
            .compactMap { sample -> (Date, Double)? in
                guard let date = sample.date.flatMap(DomainDateParser.date(from:)),
                      let energy = sample.cumulativeEnergyAddedKWh,
                      energy.isFinite,
                      energy >= 0
                else {
                    return nil
                }
                if let sessionStart, date < sessionStart { return nil }
                if let sessionEnd, date > sessionEnd { return nil }
                return (date, energy)
            }
            .sorted { $0.0 < $1.0 }

        if samples.isEmpty {
            guard let startDate = sessionStart,
                  let endDate = sessionEnd
            else {
                return nil
            }
            return energyAllocation(
                forEnergy: totalEnergy,
                from: startDate,
                to: max(endDate, startDate),
                rule: rule,
                timeZone: pricingTimeZone(for: rule, input: input)
            )
        }

        let timeZone = pricingTimeZone(for: rule, input: input)
        var previousDate = sessionStart ?? samples[0].0
        var previousEnergy = 0.0
        var allocation: [ChargePricingCostComponent] = []
        var allocatedEnergy = 0.0

        for sample in samples {
            guard sample.1 >= previousEnergy else { continue }
            let deltaEnergy = sample.1 - previousEnergy
            let acceptedEnergy = min(deltaEnergy, max(0, totalEnergy - allocatedEnergy))
            if acceptedEnergy > 0 {
                allocation.append(contentsOf: energyAllocation(
                    forEnergy: acceptedEnergy,
                    from: previousDate,
                    to: max(sample.0, previousDate),
                    rule: rule,
                    timeZone: timeZone
                ))
                allocatedEnergy += acceptedEnergy
            }
            previousDate = max(sample.0, previousDate)
            previousEnergy = sample.1
            if allocatedEnergy >= totalEnergy { break }
        }

        if totalEnergy > allocatedEnergy {
            let endDate = sessionEnd ?? previousDate
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

    private static func pricingTimeZone(for rule: ChargePricingRule, input: ChargePricingInput) -> TimeZone {
        if rule.origin == .regionalOfficial {
            return ChargePricingDate.mainlandTimeZone
        }
        return timeZone(from: input.startDate) ?? timeZone(from: input.endDate) ?? .current
    }

    private static func pricingCalendar(for rule: ChargePricingRule, input: ChargePricingInput) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pricingTimeZone(for: rule, input: input)
        return calendar
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
        if value.uppercased().hasSuffix("Z") {
            return .gmt
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
        mainlandComponents(from: timestamp).flatMap(dateString(from:))
    }

    static func localDate(from date: Date) -> String? {
        dateString(from: mainlandCalendar.dateComponents([.year, .month, .day], from: date))
    }

    static func mainlandComponents(from timestamp: String) -> DateComponents? {
        guard let date = DomainDateParser.date(from: timestamp) else { return nil }
        return mainlandCalendar.dateComponents([.year, .month, .day, .weekday], from: date)
    }

    static var mainlandTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .gmt
    }

    static func dateString(from components: DateComponents) -> String? {
        guard let year = components.year,
              let month = components.month,
              let day = components.day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static var mainlandCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = mainlandTimeZone
        return calendar
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
