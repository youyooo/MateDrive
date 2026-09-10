import Foundation

public enum ActivityMetricQuality: String, Codable, Equatable, Sendable {
    case complete, partial, estimated, unavailable
}

public struct ParkingIntervalInput: Equatable, Sendable {
    public let parking: TeslaMateActivity
    public let charges: [TeslaMateActivity]
    public let sleepIntervals: [SleepInterval]
    public let previousDrive: TeslaMateActivity?
    public let nextDrive: TeslaMateActivity?

    public init(
        parking: TeslaMateActivity,
        charges: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        previousDrive: TeslaMateActivity? = nil,
        nextDrive: TeslaMateActivity? = nil
    ) {
        self.parking = parking
        self.charges = charges
        self.sleepIntervals = sleepIntervals
        self.previousDrive = previousDrive
        self.nextDrive = nextDrive
    }
}

public struct ParkingIntervalMetrics: Codable, Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let startBatteryPercent: Int?
    public let endBatteryPercent: Int?
    public let netBatteryChangePercent: Int?
    public let chargeGainPercent: Int?
    public let standbyBatteryChangePercent: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let ratedRangeChangeKm: Double?
    public let vehicleReportedChargeEnergyKWh: Double?
    public let sleepDuration: TimeInterval
    public let awakeDuration: TimeInterval
    public let wakeCount: Int
    public let quality: ActivityMetricQuality
    public let missingReasonCodes: [String]
}

public enum SmartActivityPurpose: String, Codable, CaseIterable, Sendable {
    case replenishment, homeCharging, workCharging, commute, shopping
    case pickupDropoff, parking, custom, unclassified
    case leisure

    public func title(language: AppLanguage, customName: String? = nil) -> String {
        if self == .custom,
           let customName = customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customName.isEmpty {
            return customName
        }

        switch self {
        case .replenishment:
            return AppText.localized("Replenishment", "补能", language: language)
        case .homeCharging:
            return AppText.localized("Home charging", "家庭充电", language: language)
        case .workCharging:
            return AppText.localized("Work charging", "工作地充电", language: language)
        case .commute:
            return AppText.localized("Commute", "通勤", language: language)
        case .shopping:
            return AppText.localized("Shopping", "购物", language: language)
        case .pickupDropoff:
            return AppText.localized("Pickup or drop-off", "接送", language: language)
        case .parking:
            return AppText.localized("Parking", "停车", language: language)
        case .leisure:
            return AppText.localized("Leisure", "休闲游玩", language: language)
        case .custom:
            return AppText.localized("Custom activity", "自定义活动", language: language)
        case .unclassified:
            return AppText.localized("Unclassified", "未分类", language: language)
        }
    }

    public var systemImage: String {
        switch self {
        case .replenishment: return "bolt.car.fill"
        case .homeCharging: return "house.and.flag.fill"
        case .workCharging: return "building.2.fill"
        case .commute: return "car.fill"
        case .shopping: return "cart.fill"
        case .pickupDropoff: return "figure.2.and.child.holdinghands"
        case .parking: return "parkingsign.circle.fill"
        case .leisure: return "leaf.fill"
        case .custom: return "tag.fill"
        case .unclassified: return "questionmark.circle"
        }
    }
}

public enum ActivityClassificationSource: String, Codable, Equatable, Sendable {
    case userSession, userPlaceRule, geofence, learnedPattern, heuristic, none
}

public enum ActivityClassificationReason: String, Codable, Hashable, Sendable {
    case homeGeofence, workGeofence, chargingGeofence, shoppingGeofence
    case schoolGeofence, acCharging, dcCharging, promptDeparture
    case repeatedTimeWindow, repeatedRoute, confirmedOverride
    case weekdayTimeWindow, dwellPattern
}

public struct ActivityCustomPresentation: Codable, Equatable, Sendable {
    public let customName: String?
    public let icon: String
    public let colorHex: String

    public init(customName: String?, icon: String, colorHex: String) {
        self.customName = customName
        self.icon = icon
        self.colorHex = colorHex
    }
}

public struct ActivityClassificationResult: Codable, Equatable, Sendable {
    public let purpose: SmartActivityPurpose
    public let confidence: Double
    public let source: ActivityClassificationSource
    public let reasons: [ActivityClassificationReason]
    public let classifierVersion: Int
    public let customPresentation: ActivityCustomPresentation?

    public init(
        purpose: SmartActivityPurpose,
        confidence: Double,
        source: ActivityClassificationSource,
        reasons: [ActivityClassificationReason],
        classifierVersion: Int,
        customPresentation: ActivityCustomPresentation? = nil
    ) {
        self.purpose = purpose
        self.confidence = confidence
        self.source = source
        self.reasons = reasons
        self.classifierVersion = classifierVersion
        self.customPresentation = customPresentation
    }

    public func title(language: AppLanguage) -> String {
        purpose.title(language: language, customName: customPresentation?.customName)
    }

    public var systemImage: String {
        guard purpose == .custom,
              let icon = customPresentation?.icon.trimmingCharacters(in: .whitespacesAndNewlines),
              !icon.isEmpty
        else { return purpose.systemImage }
        return icon
    }

    public var colorHex: String? {
        purpose == .custom ? customPresentation?.colorHex : nil
    }
}

public struct ActivityClassificationExplanation: Equatable, Sendable {
    public let status: String
    public let confidenceText: String
    public let summary: String
    public let evidence: [String]
    public let isUserConfirmed: Bool

    public init(
        status: String,
        confidenceText: String,
        summary: String,
        evidence: [String],
        isUserConfirmed: Bool
    ) {
        self.status = status
        self.confidenceText = confidenceText
        self.summary = summary
        self.evidence = evidence
        self.isUserConfirmed = isUserConfirmed
    }
}

public enum ActivityClassificationExplanationBuilder {
    public static func build(
        _ result: ActivityClassificationResult,
        language: AppLanguage
    ) -> ActivityClassificationExplanation {
        let isConfirmed = result.source == .userSession || result.source == .userPlaceRule
        let percent = Int((min(max(result.confidence, 0), 1) * 100).rounded())
        let evidence = unique(result.reasons.map { reasonText($0, language: language) })

        return ActivityClassificationExplanation(
            status: sourceText(result.source, language: language),
            confidenceText: isConfirmed
                ? localized("User confirmed", "用户已确认", language: language)
                : localized("\(percent)% confidence", "可信度 \(percent)%", language: language),
            summary: isConfirmed
                ? localized(
                    "Your confirmed label takes priority over automatic classification.",
                    "你确认的标签优先于自动判断。",
                    language: language
                )
                : localized(
                    "MateDrive inferred this activity from the available trip, place, time and charging evidence.",
                    "MateDrive 根据可用的行程、地点、时间和充电证据推断此动态。",
                    language: language
                ),
            evidence: evidence,
            isUserConfirmed: isConfirmed
        )
    }

    private static func sourceText(
        _ source: ActivityClassificationSource,
        language: AppLanguage
    ) -> String {
        switch source {
        case .userSession:
            return localized("This activity", "本次动态", language: language)
        case .userPlaceRule:
            return localized("Saved place rule", "常用地点规则", language: language)
        case .geofence:
            return localized("Geofence match", "围栏匹配", language: language)
        case .learnedPattern:
            return localized("Learned pattern", "学习到的规律", language: language)
        case .heuristic:
            return localized("Smart suggestion", "智能建议", language: language)
        case .none:
            return localized("Not classified", "暂未分类", language: language)
        }
    }

    private static func reasonText(
        _ reason: ActivityClassificationReason,
        language: AppLanguage
    ) -> String {
        switch reason {
        case .homeGeofence:
            return localized("Inside the saved Home geofence", "位于已保存的家庭围栏内", language: language)
        case .workGeofence:
            return localized("Inside the saved Work geofence", "位于已保存的公司围栏内", language: language)
        case .chargingGeofence:
            return localized("Inside a saved charging geofence", "位于已保存的充电围栏内", language: language)
        case .shoppingGeofence:
            return localized("Inside a saved shopping geofence", "位于已保存的商场围栏内", language: language)
        case .schoolGeofence:
            return localized("Inside a saved school geofence", "位于已保存的学校围栏内", language: language)
        case .acCharging:
            return localized("AC charging was recorded", "记录到交流充电", language: language)
        case .dcCharging:
            return localized("DC fast charging was recorded", "记录到直流快充", language: language)
        case .promptDeparture:
            return localized("The vehicle left soon after charging", "充电后不久车辆即离开", language: language)
        case .repeatedTimeWindow:
            return localized("Repeated at a similar time", "多次出现在相近时段", language: language)
        case .repeatedRoute:
            return localized("Matched a repeated route", "匹配到重复路线", language: language)
        case .confirmedOverride:
            return localized("Confirmed by you", "由你确认", language: language)
        case .weekdayTimeWindow:
            return localized("Matched a weekday commute window", "符合工作日通勤时段", language: language)
        case .dwellPattern:
            return localized("Matched the typical stay duration", "符合典型停留时长", language: language)
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func localized(
        _ english: String,
        _ chinese: String,
        language: AppLanguage
    ) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public enum SmartActivityChargeCostSource: String, Codable, Equatable, Sendable {
    case manual, api, stationRule, homeRule, regionalTariff
}

public struct SmartActivityChargeCostComponent: Codable, Equatable, Sendable {
    public let kind: String
    public let amount: Double
    public let energyKWh: Double?
    public let pricePerKWh: Double?
}

public struct SmartActivityChargeCost: Codable, Equatable, Sendable {
    public let amount: Double
    public let currencyCode: String
    public let source: SmartActivityChargeCostSource
    public let ruleID: String?
    public let isEstimated: Bool
    public let isExplicitlyFree: Bool
    public let components: [SmartActivityChargeCostComponent]
}

public struct SmartActivityEventReference: Codable, Equatable, Sendable {
    public let kind: TeslaMateActivityKind
    public let sourceID: Int
    public let startDate: String?
    public let endDate: String?
    public let sourceActivity: TeslaMateActivity

    public init(sourceActivity: TeslaMateActivity) {
        kind = sourceActivity.kind
        sourceID = sourceActivity.id
        startDate = sourceActivity.startDate
        endDate = sourceActivity.endDate
        self.sourceActivity = sourceActivity
    }
}

public struct SmartActivitySession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let startDate: Date
    public let endDate: Date?
    public let placeKey: String
    public let latitude: Double?
    public let longitude: Double?
    public let geofenceID: String?
    public let provisionalKind: SmartActivityPurpose
    public let classification: ActivityClassificationResult?
    public let parkingMetrics: ParkingIntervalMetrics?
    public let chargeCost: SmartActivityChargeCost?
    public let eventReferences: [SmartActivityEventReference]
    public let isOpen: Bool
    public let quality: ActivityMetricQuality
    public let derivationVersion: Int
    public let sourceFingerprint: String
    public let derivationFingerprint: String
}
