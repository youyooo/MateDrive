import Foundation

public struct ParkingFeeRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    public var addressKeyword: String?
    public var latitude: Double?
    public var longitude: Double?
    public var radiusMeters: Double?
    public var freeMinutes: Int
    public var billingIncrementMinutes: Int
    public var hourlyRate: Double
    public var fixedFee: Double
    public var sessionCap: Double?
    public var monthlyFee: Double?
    public var priority: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        isEnabled: Bool = true,
        addressKeyword: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        radiusMeters: Double? = nil,
        freeMinutes: Int = 0,
        billingIncrementMinutes: Int = 60,
        hourlyRate: Double = 0,
        fixedFee: Double = 0,
        sessionCap: Double? = nil,
        monthlyFee: Double? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.addressKeyword = addressKeyword
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.freeMinutes = freeMinutes
        self.billingIncrementMinutes = billingIncrementMinutes
        self.hourlyRate = hourlyRate
        self.fixedFee = fixedFee
        self.sessionCap = sessionCap
        self.monthlyFee = monthlyFee
        self.priority = priority
    }
}

public enum ParkingFeeValidationIssue: Equatable, Sendable {
    case emptyName, invalidFreeMinutes, invalidIncrement, invalidHourlyRate, invalidFixedFee
    case invalidSessionCap, invalidMonthlyFee, incompleteLocation, invalidLocation, noChargeConfigured
}

public enum ParkingFeeRuleValidator {
    public static func issues(for rule: ParkingFeeRule) -> [ParkingFeeValidationIssue] {
        var issues: [ParkingFeeValidationIssue] = []
        if rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append(.emptyName) }
        if rule.freeMinutes < 0 { issues.append(.invalidFreeMinutes) }
        if rule.billingIncrementMinutes <= 0 || rule.billingIncrementMinutes > 1_440 { issues.append(.invalidIncrement) }
        if !rule.hourlyRate.isFinite || rule.hourlyRate < 0 { issues.append(.invalidHourlyRate) }
        if !rule.fixedFee.isFinite || rule.fixedFee < 0 { issues.append(.invalidFixedFee) }
        if let cap = rule.sessionCap, !cap.isFinite || cap < 0 { issues.append(.invalidSessionCap) }
        if let monthly = rule.monthlyFee, !monthly.isFinite || monthly < 0 { issues.append(.invalidMonthlyFee) }
        let locationParts = [rule.latitude != nil, rule.longitude != nil, rule.radiusMeters != nil]
        if locationParts.contains(true), locationParts.contains(false) {
            issues.append(.incompleteLocation)
        } else if let lat = rule.latitude, let lng = rule.longitude, let radius = rule.radiusMeters,
                  GeoCoordinateValidator.location(latitude: lat, longitude: lng) == nil || !radius.isFinite || radius <= 0 {
            issues.append(.invalidLocation)
        }
        if rule.hourlyRate == 0, rule.fixedFee == 0, (rule.monthlyFee ?? 0) == 0 { issues.append(.noChargeConfigured) }
        return issues
    }
}

public struct ParkingFeeInput: Equatable, Sendable {
    public let startDate: String?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let durationMinutes: Double?

    public init(startDate: String?, address: String?, latitude: Double?, longitude: Double?, durationMinutes: Double?) {
        self.startDate = startDate
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.durationMinutes = durationMinutes
    }
}

public struct ParkingFeeEstimate: Equatable, Sendable {
    public let rule: ParkingFeeRule
    public let sessionCost: Double
    public let billableMinutes: Int
    public let billedIncrements: Int
    public let usesMonthlyFee: Bool
}

public struct ParkingCostSummary: Equatable, Sendable {
    public let sessionCost: Double
    public let recurringMonthlyCost: Double
    public let matchedParkingCount: Int
    public let unmatchedParkingCount: Int
    public var totalCost: Double { sessionCost + recurringMonthlyCost }

    public init(sessionCost: Double, recurringMonthlyCost: Double, matchedParkingCount: Int, unmatchedParkingCount: Int) {
        self.sessionCost = sessionCost
        self.recurringMonthlyCost = recurringMonthlyCost
        self.matchedParkingCount = matchedParkingCount
        self.unmatchedParkingCount = unmatchedParkingCount
    }
}

public enum ParkingFeeRuleEngine {
    public static func estimate(for input: ParkingFeeInput, rules: [ParkingFeeRule]) -> ParkingFeeEstimate? {
        guard let rule = matchingRule(for: input, rules: rules) else { return nil }
        if (rule.monthlyFee ?? 0) > 0 {
            return ParkingFeeEstimate(rule: rule, sessionCost: 0, billableMinutes: 0, billedIncrements: 0, usesMonthlyFee: true)
        }
        guard let duration = input.durationMinutes, duration.isFinite, duration >= 0 else {
            guard rule.hourlyRate == 0, rule.fixedFee > 0 else { return nil }
            let cost = rule.sessionCap.map { min(rule.fixedFee, $0) } ?? rule.fixedFee
            return ParkingFeeEstimate(rule: rule, sessionCost: cost, billableMinutes: 0, billedIncrements: 0, usesMonthlyFee: false)
        }
        let billable = max(Int(ceil(duration)) - rule.freeMinutes, 0)
        let increments = billable == 0 ? 0 : Int(ceil(Double(billable) / Double(rule.billingIncrementMinutes)))
        let timeCost = Double(increments * rule.billingIncrementMinutes) / 60 * rule.hourlyRate
        var cost = rule.fixedFee + timeCost
        if let cap = rule.sessionCap { cost = min(cost, cap) }
        return ParkingFeeEstimate(rule: rule, sessionCost: max(cost, 0), billableMinutes: billable, billedIncrements: increments, usesMonthlyFee: false)
    }

    public static func summarize(_ inputs: [ParkingFeeInput], rules: [ParkingFeeRule]) -> ParkingCostSummary {
        var sessionCost = 0.0
        var monthlyCost = 0.0
        var matched = 0
        var unmatched = 0
        var chargedMonths: Set<String> = []
        for input in inputs {
            guard let estimate = estimate(for: input, rules: rules) else { unmatched += 1; continue }
            matched += 1
            if estimate.usesMonthlyFee, let fee = estimate.rule.monthlyFee {
                let month = input.startDate.flatMap(monthKey) ?? "unknown"
                let key = "\(estimate.rule.id)-\(month)"
                if chargedMonths.insert(key).inserted { monthlyCost += fee }
            } else {
                sessionCost += estimate.sessionCost
            }
        }
        return ParkingCostSummary(sessionCost: sessionCost, recurringMonthlyCost: monthlyCost, matchedParkingCount: matched, unmatchedParkingCount: unmatched)
    }

    private static func matchingRule(for input: ParkingFeeInput, rules: [ParkingFeeRule]) -> ParkingFeeRule? {
        rules.filter { rule in
            guard rule.isEnabled, ParkingFeeRuleValidator.issues(for: rule).isEmpty else { return false }
            if let keyword = rule.addressKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty,
               input.address?.localizedCaseInsensitiveContains(keyword) != true { return false }
            if let lat = rule.latitude, let lng = rule.longitude, let radius = rule.radiusMeters {
                guard let inputLat = input.latitude, let inputLng = input.longitude,
                      distanceMeters(from: (lat, lng), to: (inputLat, inputLng)) <= radius else { return false }
            }
            return true
        }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.first
    }

    private static func monthKey(_ value: String) -> String? {
        guard value.count >= 7 else { return nil }
        let prefix = String(value.prefix(7))
        return prefix.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil ? prefix : nil
    }

    private static func distanceMeters(from lhs: (Double, Double), to rhs: (Double, Double)) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = lhs.0 * .pi / 180
        let lat2 = rhs.0 * .pi / 180
        let deltaLat = (rhs.0 - lhs.0) * .pi / 180
        let deltaLon = (rhs.1 - lhs.1) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
