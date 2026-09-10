import Foundation

public struct ChargeTariffTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var chargeType: ChargePricingChargeType
    public var startMinuteOfDay: Int?
    public var endMinuteOfDay: Int?
    public var pricePerKWh: Double
    public var timeSegments: [ChargePricingTimeSegment]
    public var sessionFee: Double

    public init(
        id: String = UUID().uuidString,
        name: String,
        chargeType: ChargePricingChargeType = .any,
        startMinuteOfDay: Int? = nil,
        endMinuteOfDay: Int? = nil,
        pricePerKWh: Double,
        timeSegments: [ChargePricingTimeSegment] = [],
        sessionFee: Double = 0
    ) {
        self.id = id
        self.name = name
        self.chargeType = chargeType
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
        self.pricePerKWh = pricePerKWh
        self.timeSegments = timeSegments
        self.sessionFee = sessionFee
    }

    public init(id: String = UUID().uuidString, name: String, rule: ChargePricingRule) {
        self.init(
            id: id,
            name: name,
            chargeType: rule.chargeType,
            startMinuteOfDay: rule.startMinuteOfDay,
            endMinuteOfDay: rule.endMinuteOfDay,
            pricePerKWh: rule.pricePerKWh,
            timeSegments: Self.clonedSegments(rule.timeSegments),
            sessionFee: rule.sessionFee
        )
    }

    public var validationIssues: [ChargePricingValidationIssue] {
        ChargePricingRuleValidator.issues(for: makeRule())
    }

    public func makeRule(id: String = UUID().uuidString, name: String? = nil) -> ChargePricingRule {
        ChargePricingRule(
            id: id,
            name: normalizedName(name ?? self.name),
            chargeType: chargeType,
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            pricePerKWh: pricePerKWh,
            timeSegments: Self.clonedSegments(timeSegments),
            sessionFee: sessionFee,
            priority: 0
        )
    }

    public func applying(to rule: ChargePricingRule) -> ChargePricingRule {
        ChargePricingRule(
            id: rule.id,
            name: rule.name,
            isEnabled: rule.isEnabled,
            chargeType: chargeType,
            addressKeyword: rule.addressKeyword,
            latitude: rule.latitude,
            longitude: rule.longitude,
            radiusMeters: rule.radiusMeters,
            startMinuteOfDay: startMinuteOfDay,
            endMinuteOfDay: endMinuteOfDay,
            effectiveFromDate: rule.effectiveFromDate,
            effectiveToDate: rule.effectiveToDate,
            pricePerKWh: pricePerKWh,
            timeSegments: Self.clonedSegments(timeSegments),
            sessionFee: sessionFee,
            priority: rule.priority
        )
    }

    private func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clonedSegments(_ segments: [ChargePricingTimeSegment]) -> [ChargePricingTimeSegment] {
        segments.map {
            ChargePricingTimeSegment(
                startMinuteOfDay: $0.startMinuteOfDay,
                endMinuteOfDay: $0.endMinuteOfDay,
                pricePerKWh: $0.pricePerKWh
            )
        }
    }
}
