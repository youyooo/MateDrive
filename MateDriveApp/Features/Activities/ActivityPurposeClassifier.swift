import Foundation

public struct ActivityClassificationInput: Sendable {
    public let session: SmartActivitySession
    public let sessionOverride: ActivityLabelOverride?
    public let placeOverride: ActivityLabelOverride?
    public let geofenceKind: GeofenceKind?
    public let recurrenceCount: Int
    public let chargeIdentity: ChargePricingChargerIdentity?
    public let chargeStartMinute: Int?
    public let hasCharge: Bool
    public let hasPromptDeparture: Bool
    public let isConfirmedCommute: Bool
    public let arrivalMinute: Int?
    public let isWeekday: Bool?
    public let dwellMinutes: Int?

    public init(
        session: SmartActivitySession,
        sessionOverride: ActivityLabelOverride? = nil,
        placeOverride: ActivityLabelOverride? = nil,
        geofenceKind: GeofenceKind? = nil,
        recurrenceCount: Int = 0,
        chargeIdentity: ChargePricingChargerIdentity? = nil,
        chargeStartMinute: Int? = nil,
        hasCharge: Bool = false,
        hasPromptDeparture: Bool = false,
        isConfirmedCommute: Bool = false,
        arrivalMinute: Int? = nil,
        isWeekday: Bool? = nil,
        dwellMinutes: Int? = nil
    ) {
        self.session = session
        self.sessionOverride = sessionOverride
        self.placeOverride = placeOverride
        self.geofenceKind = geofenceKind
        self.recurrenceCount = recurrenceCount
        self.chargeIdentity = chargeIdentity
        self.chargeStartMinute = chargeStartMinute
        self.hasCharge = hasCharge
        self.hasPromptDeparture = hasPromptDeparture
        self.isConfirmedCommute = isConfirmedCommute
        self.arrivalMinute = arrivalMinute
        self.isWeekday = isWeekday
        self.dwellMinutes = dwellMinutes
    }
}

public enum ActivityPurposeClassifier {
    public static let classifierVersion = 2
    public static let suggestionThreshold = 0.80

    public static func classify(_ input: ActivityClassificationInput) -> ActivityClassificationResult {
        if let override = input.sessionOverride {
            return override.result(source: .userSession)
        }
        if let override = input.placeOverride {
            return override.result(source: .userPlaceRule)
        }

        let scored = scoreGeofenceAndPatternEvidence(input)
        guard scored.confidence >= suggestionThreshold else {
            return ActivityClassificationResult(
                purpose: .unclassified,
                confidence: scored.confidence,
                source: .none,
                reasons: scored.reasons,
                classifierVersion: classifierVersion
            )
        }
        return scored
    }

    private static func scoreGeofenceAndPatternEvidence(_ input: ActivityClassificationInput) -> ActivityClassificationResult {
        if let geofence = geofenceClassification(input) {
            return applyingPatternEvidence(to: geofence, input: input)
        }

        if input.recurrenceCount >= 4 {
            let purpose: SmartActivityPurpose
            if input.isConfirmedCommute {
                purpose = .commute
            } else if input.hasCharge {
                purpose = .replenishment
            } else if input.session.provisionalKind != .unclassified {
                purpose = input.session.provisionalKind
            } else {
                purpose = .parking
            }
            return applyingPromptDeparture(
                to: ActivityClassificationResult(
                    purpose: purpose,
                    confidence: 0.80,
                    source: .learnedPattern,
                    reasons: [.repeatedTimeWindow] + chargeReasons(input),
                    classifierVersion: classifierVersion
                ),
                input: input
            )
        }

        if input.isConfirmedCommute {
            return ActivityClassificationResult(
                purpose: .commute,
                confidence: 0.85,
                source: .heuristic,
                reasons: [.repeatedRoute],
                classifierVersion: classifierVersion
            )
        }

        return applyingPromptDeparture(
            to: ActivityClassificationResult(
                purpose: input.hasCharge ? .replenishment : .unclassified,
                confidence: input.hasCharge ? 0.70 : 0,
                source: input.hasCharge ? .heuristic : .none,
                reasons: chargeReasons(input),
                classifierVersion: classifierVersion
            ),
            input: input
        )
    }

    private static func geofenceClassification(_ input: ActivityClassificationInput) -> ActivityClassificationResult? {
        guard let geofenceKind = input.geofenceKind else { return nil }

        let classification: (SmartActivityPurpose, Double, [ActivityClassificationReason])
        switch geofenceKind {
        case .home:
            classification = input.hasCharge
                ? (.homeCharging, 0.92, [.homeGeofence])
                : commuteOrParking(input, reason: .homeGeofence)
        case .work:
            classification = input.hasCharge
                ? (.workCharging, 0.90, [.workGeofence])
                : commuteOrParking(input, reason: .workGeofence)
        case .charging:
            classification = (input.hasCharge ? .replenishment : .parking, input.hasCharge ? 0.90 : 0.85, [.chargingGeofence])
        case .shopping:
            if prefersReplenishment(input) {
                classification = (.replenishment, 0.92, [.shoppingGeofence])
            } else {
                classification = (.shopping, input.hasCharge ? 0.90 : 0.85, [.shoppingGeofence] + dwellReason(input))
            }
        case .schoolPickup:
            classification = (.pickupDropoff, 0.85, [.schoolGeofence])
        case .parking:
            classification = (.parking, 0.85, [])
        case .garage:
            classification = (input.hasCharge ? .replenishment : .parking, input.hasCharge ? 0.86 : 0.90, dwellReason(input))
        case .park:
            classification = (.leisure, 0.88, dwellReason(input))
        case .other:
            return nil
        }

        return ActivityClassificationResult(
            purpose: classification.0,
            confidence: classification.1,
            source: .geofence,
            reasons: classification.2 + chargeReasons(input),
            classifierVersion: classifierVersion
        )
    }

    private static func commuteOrParking(
        _ input: ActivityClassificationInput,
        reason: ActivityClassificationReason
    ) -> (SmartActivityPurpose, Double, [ActivityClassificationReason]) {
        let minute = input.arrivalMinute
        let commuteWindow = minute.map { (6 * 60 ... 11 * 60).contains($0) || (15 * 60 ... 22 * 60).contains($0) } == true
        let hasPattern = input.recurrenceCount >= 2 || input.isConfirmedCommute
        if input.isWeekday == true, commuteWindow, hasPattern {
            return (.commute, input.isConfirmedCommute ? 0.96 : 0.88, [reason, .weekdayTimeWindow, .repeatedRoute])
        }
        return (.parking, 0.85, [reason] + dwellReason(input))
    }

    private static func prefersReplenishment(_ input: ActivityClassificationInput) -> Bool {
        guard input.hasCharge, input.hasPromptDeparture else { return false }
        switch input.chargeIdentity {
        case .teslaSupercharger, .otherDC, .unknownDC:
            return (input.dwellMinutes ?? 0) <= 120
        case .ac, nil:
            return false
        }
    }

    private static func dwellReason(_ input: ActivityClassificationInput) -> [ActivityClassificationReason] {
        input.dwellMinutes == nil ? [] : [.dwellPattern]
    }

    private static func applyingPatternEvidence(
        to result: ActivityClassificationResult,
        input: ActivityClassificationInput
    ) -> ActivityClassificationResult {
        guard input.recurrenceCount >= 4 else {
            return applyingPromptDeparture(to: result, input: input)
        }
        return applyingPromptDeparture(
            to: ActivityClassificationResult(
                purpose: result.purpose,
                confidence: min(result.confidence + 0.10, 0.95),
                source: result.source,
                reasons: result.reasons + [.repeatedTimeWindow],
                classifierVersion: classifierVersion
            ),
            input: input
        )
    }

    private static func applyingPromptDeparture(
        to result: ActivityClassificationResult,
        input: ActivityClassificationInput
    ) -> ActivityClassificationResult {
        guard input.hasCharge, input.hasPromptDeparture else { return result }
        return ActivityClassificationResult(
            purpose: result.purpose,
            confidence: min(result.confidence + 0.05, 1),
            source: result.source,
            reasons: result.reasons + [.promptDeparture],
            classifierVersion: classifierVersion
        )
    }

    private static func chargeReasons(_ input: ActivityClassificationInput) -> [ActivityClassificationReason] {
        guard input.hasCharge else { return [] }
        switch input.chargeIdentity {
        case .ac:
            return [.acCharging]
        case .teslaSupercharger, .otherDC, .unknownDC:
            return [.dcCharging]
        case nil:
            return []
        }
    }
}

private extension ActivityLabelOverride {
    func result(source: ActivityClassificationSource) -> ActivityClassificationResult {
        ActivityClassificationResult(
            purpose: purpose,
            confidence: 1,
            source: source,
            reasons: [.confirmedOverride],
            classifierVersion: ActivityPurposeClassifier.classifierVersion,
            customPresentation: purpose == .custom
                ? ActivityCustomPresentation(customName: customName, icon: icon, colorHex: colorHex)
                : nil
        )
    }
}
