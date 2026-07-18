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
}

public struct ActivityClassificationResult: Codable, Equatable, Sendable {
    public let purpose: SmartActivityPurpose
    public let confidence: Double
    public let source: ActivityClassificationSource
    public let reasons: [ActivityClassificationReason]
    public let classifierVersion: Int
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
