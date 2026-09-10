import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case english
    case chinese
    case traditionalChinese

    public var id: String { rawValue }

    public var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        case .traditionalChinese:
            return "zh-Hant"
        }
    }
}

public enum ServerAuthenticationMode: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case automatic
    case none
    case bearerToken
    case basic
    case apiKeys

    public var id: String { rawValue }
}

public struct BatteryCalibration: Codable, Equatable, Sendable {
    public var referenceRangeKm: Double?
    public var referenceCapacityKWh: Double?
    public var recordingStartOdometerKm: Double?

    public init(referenceRangeKm: Double? = nil, referenceCapacityKWh: Double? = nil, recordingStartOdometerKm: Double? = nil) {
        self.referenceRangeKm = referenceRangeKm
        self.referenceCapacityKWh = referenceCapacityKWh
        self.recordingStartOdometerKm = recordingStartOdometerKm
    }
}

public enum GeofenceKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case home
    case work
    case charging
    case shopping
    case schoolPickup
    case parking
    case garage
    case park
    case other

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = GeofenceKind(rawValue: value) ?? .other
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public func title(language: AppLanguage) -> String {
        switch self {
        case .home: return AppText.localized("Home", "家", language: language)
        case .work: return AppText.localized("Work", "公司", language: language)
        case .charging: return AppText.localized("Charging", "充电点", language: language)
        case .shopping: return AppText.localized("Shopping", "商场", language: language)
        case .schoolPickup: return AppText.localized("School or Pickup", "学校或接送", language: language)
        case .parking: return AppText.localized("Parking", "停车点", language: language)
        case .garage: return AppText.localized("Garage", "地库", language: language)
        case .park: return AppText.localized("Park", "公园", language: language)
        case .other: return AppText.localized("Other", "其他", language: language)
        }
    }

    public var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        case .charging: return "bolt.fill"
        case .shopping: return "cart.fill"
        case .schoolPickup: return "figure.2.and.child.holdinghands"
        case .parking: return "parkingsign.circle.fill"
        case .garage: return "building.fill"
        case .park: return "leaf.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}

public struct GeofenceRule: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var carId: Int?
    public var name: String
    public var kind: GeofenceKind
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Double
    public var isEnabled: Bool
    public var participatesInCommuteClassification: Bool

    public init(
        id: String = UUID().uuidString,
        carId: Int? = nil,
        name: String,
        kind: GeofenceKind = .other,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 100,
        isEnabled: Bool = true,
        participatesInCommuteClassification: Bool = true
    ) {
        self.id = id
        self.carId = carId
        self.name = name
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.isEnabled = isEnabled
        self.participatesInCommuteClassification = participatesInCommuteClassification
    }
}

public enum GeofenceRuleValidator {
    public static func isValid(_ rule: GeofenceRule) -> Bool {
        !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && GeoCoordinateValidator.location(latitude: rule.latitude, longitude: rule.longitude) != nil
            && rule.radiusMeters.isFinite
            && (50 ... 1_000).contains(rule.radiusMeters)
    }
}

public enum GeofenceRuleEngine {
    public static func matchingRule(
        latitude: Double?,
        longitude: Double?,
        carId: Int,
        rules: [GeofenceRule]
    ) -> GeofenceRule? {
        guard let latitude, let longitude,
              GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil
        else { return nil }

        return rules
            .compactMap { rule -> (rule: GeofenceRule, distance: Double)? in
                guard rule.isEnabled,
                      rule.carId == nil || rule.carId == carId,
                      GeofenceRuleValidator.isValid(rule)
                else { return nil }
                let distance = distanceMeters(
                    from: (rule.latitude, rule.longitude),
                    to: (latitude, longitude)
                )
                guard distance <= rule.radiusMeters else { return nil }
                return (rule, distance)
            }
            .sorted { lhs, rhs in
                let lhsIsVehicleSpecific = lhs.rule.carId != nil
                let rhsIsVehicleSpecific = rhs.rule.carId != nil
                if lhsIsVehicleSpecific != rhsIsVehicleSpecific {
                    return lhsIsVehicleSpecific
                }
                if abs(lhs.distance - rhs.distance) > 0.001 {
                    return lhs.distance < rhs.distance
                }
                if lhs.rule.radiusMeters != rhs.rule.radiusMeters {
                    return lhs.rule.radiusMeters < rhs.rule.radiusMeters
                }
                return lhs.rule.name.localizedStandardCompare(rhs.rule.name) == .orderedAscending
            }
            .first?
            .rule
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

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentFormatPreferencesVersion = 1

    public var serverURL: String
    public var secondaryServerURL: String
    public var authenticationMode: ServerAuthenticationMode
    public var usesCloudflareAccess: Bool
    public var acceptInvalidCerts: Bool
    public var currencyCode: String
    public var residentialTariffRegionCode: String?
    public var homeTariffRegionCode: String? {
        get { residentialTariffRegionCode }
        set {
            residentialTariffRegionCode = newValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
                .nilIfEmpty
        }
    }
    public var displayUnitSystem: DisplayUnitSystem
    public var formatPreferencesVersion: Int
    public var showShortDrivesCharges: Bool
    public var mergeAdjacentDrives: Bool
    public var adjacentDriveMergeMaximumGapMinutes: Int
    public var teslamateBaseURL: String
    public var lastSelectedCarId: Int?
    public var notificationPermissionAsked: Bool
    public var notificationEventSignatures: [String: String]
    public var appLanguage: AppLanguage
    public var batteryReferenceRangeKm: Double?
    public var batteryRecordingStartOdometerKm: Double?
    public var batteryCalibrations: [String: BatteryCalibration]
    public var chargePricingRules: [ChargePricingRule]
    public var chargeTariffTemplates: [ChargeTariffTemplate]
    public var parkingFeeRules: [ParkingFeeRule]
    public var geofenceRules: [GeofenceRule]
    public var usesGeofencesForCommuteClassification: Bool
    public var allowsThirdPartyRouteWeather: Bool
    public var driveAnnotations: [String: DriveAnnotation]
    public var driveRouteLabelRules: [DriveRouteLabelRule]

    public var forceChineseLanguage: Bool {
        get { appLanguage == .chinese }
        set { appLanguage = newValue ? .chinese : .system }
    }

    public init(
        serverURL: String = "",
        secondaryServerURL: String = "",
        authenticationMode: ServerAuthenticationMode = .none,
        usesCloudflareAccess: Bool = false,
        acceptInvalidCerts: Bool = false,
        currencyCode: String = MateDriveCurrencyFormatter.automaticCode,
        residentialTariffRegionCode: String? = nil,
        displayUnitSystem: DisplayUnitSystem = .teslamate,
        formatPreferencesVersion: Int = AppSettings.currentFormatPreferencesVersion,
        showShortDrivesCharges: Bool = false,
        mergeAdjacentDrives: Bool = true,
        adjacentDriveMergeMaximumGapMinutes: Int = 30,
        teslamateBaseURL: String = "",
        lastSelectedCarId: Int? = nil,
        notificationPermissionAsked: Bool = false,
        notificationEventSignatures: [String: String] = [:],
        appLanguage: AppLanguage = .system,
        batteryReferenceRangeKm: Double? = nil,
        batteryRecordingStartOdometerKm: Double? = nil,
        batteryCalibrations: [String: BatteryCalibration] = [:],
        chargePricingRules: [ChargePricingRule] = [],
        chargeTariffTemplates: [ChargeTariffTemplate] = [],
        parkingFeeRules: [ParkingFeeRule] = [],
        geofenceRules: [GeofenceRule] = [],
        usesGeofencesForCommuteClassification: Bool = true,
        allowsThirdPartyRouteWeather: Bool = false,
        driveAnnotations: [String: DriveAnnotation] = [:],
        driveRouteLabelRules: [DriveRouteLabelRule] = [],
        forceChineseLanguage: Bool? = nil
    ) {
        self.serverURL = serverURL
        self.secondaryServerURL = secondaryServerURL
        self.authenticationMode = authenticationMode
        self.usesCloudflareAccess = usesCloudflareAccess
        self.acceptInvalidCerts = acceptInvalidCerts
        self.currencyCode = currencyCode
        self.residentialTariffRegionCode = residentialTariffRegionCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .nilIfEmpty
        self.displayUnitSystem = displayUnitSystem
        self.formatPreferencesVersion = formatPreferencesVersion
        self.showShortDrivesCharges = showShortDrivesCharges
        self.mergeAdjacentDrives = mergeAdjacentDrives
        self.adjacentDriveMergeMaximumGapMinutes = min(max(adjacentDriveMergeMaximumGapMinutes, 5), 180)
        self.teslamateBaseURL = teslamateBaseURL
        self.lastSelectedCarId = lastSelectedCarId
        self.notificationPermissionAsked = notificationPermissionAsked
        self.notificationEventSignatures = notificationEventSignatures
        self.appLanguage = forceChineseLanguage == true ? .chinese : appLanguage
        self.batteryReferenceRangeKm = batteryReferenceRangeKm
        self.batteryRecordingStartOdometerKm = batteryRecordingStartOdometerKm
        self.batteryCalibrations = batteryCalibrations
        self.chargePricingRules = chargePricingRules
        self.chargeTariffTemplates = chargeTariffTemplates
        self.parkingFeeRules = parkingFeeRules
        self.geofenceRules = geofenceRules
        self.usesGeofencesForCommuteClassification = usesGeofencesForCommuteClassification
        self.allowsThirdPartyRouteWeather = allowsThirdPartyRouteWeather
        self.driveAnnotations = driveAnnotations
        self.driveRouteLabelRules = driveRouteLabelRules
    }

    private enum CodingKeys: String, CodingKey {
        case serverURL
        case secondaryServerURL
        case authenticationMode
        case usesCloudflareAccess
        case acceptInvalidCerts
        case currencyCode
        case residentialTariffRegionCode
        case homeTariffRegionCode
        case displayUnitSystem
        case formatPreferencesVersion
        case showShortDrivesCharges
        case mergeAdjacentDrives
        case adjacentDriveMergeMaximumGapMinutes
        case teslamateBaseURL
        case lastSelectedCarId
        case notificationPermissionAsked
        case notificationEventSignatures
        case appLanguage
        case batteryReferenceRangeKm
        case batteryRecordingStartOdometerKm
        case batteryCalibrations
        case chargePricingRules
        case chargeTariffTemplates
        case parkingFeeRules
        case geofenceRules
        case usesGeofencesForCommuteClassification
        case allowsThirdPartyRouteWeather
        case driveAnnotations
        case driveRouteLabelRules
        case forceChineseLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        secondaryServerURL = try container.decodeIfPresent(String.self, forKey: .secondaryServerURL) ?? ""
        authenticationMode = try container.decodeIfPresent(ServerAuthenticationMode.self, forKey: .authenticationMode) ?? .automatic
        usesCloudflareAccess = try container.decodeIfPresent(Bool.self, forKey: .usesCloudflareAccess) ?? false
        acceptInvalidCerts = try container.decodeIfPresent(Bool.self, forKey: .acceptInvalidCerts) ?? false
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? MateDriveCurrencyFormatter.automaticCode
        residentialTariffRegionCode = try (
            container.decodeIfPresent(String.self, forKey: .residentialTariffRegionCode)
                ?? container.decodeIfPresent(String.self, forKey: .homeTariffRegionCode)
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .nilIfEmpty
        displayUnitSystem = try container.decodeIfPresent(DisplayUnitSystem.self, forKey: .displayUnitSystem) ?? .teslamate
        formatPreferencesVersion = try container.decodeIfPresent(Int.self, forKey: .formatPreferencesVersion) ?? 0
        showShortDrivesCharges = try container.decodeIfPresent(Bool.self, forKey: .showShortDrivesCharges) ?? false
        mergeAdjacentDrives = try container.decodeIfPresent(Bool.self, forKey: .mergeAdjacentDrives) ?? true
        adjacentDriveMergeMaximumGapMinutes = min(
            max(try container.decodeIfPresent(Int.self, forKey: .adjacentDriveMergeMaximumGapMinutes) ?? 30, 5),
            180
        )
        teslamateBaseURL = try container.decodeIfPresent(String.self, forKey: .teslamateBaseURL) ?? ""
        lastSelectedCarId = try container.decodeIfPresent(Int.self, forKey: .lastSelectedCarId)
        notificationPermissionAsked = try container.decodeIfPresent(Bool.self, forKey: .notificationPermissionAsked) ?? false
        notificationEventSignatures = try container.decodeIfPresent([String: String].self, forKey: .notificationEventSignatures) ?? [:]
        if let appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) {
            self.appLanguage = appLanguage
        } else if try container.decodeIfPresent(Bool.self, forKey: .forceChineseLanguage) == true {
            appLanguage = .chinese
        } else {
            appLanguage = .system
        }
        batteryReferenceRangeKm = try container.decodeIfPresent(Double.self, forKey: .batteryReferenceRangeKm)
        batteryRecordingStartOdometerKm = try container.decodeIfPresent(Double.self, forKey: .batteryRecordingStartOdometerKm)
        batteryCalibrations = try container.decodeIfPresent([String: BatteryCalibration].self, forKey: .batteryCalibrations) ?? [:]
        if let lastSelectedCarId, batteryCalibrations[String(lastSelectedCarId)] == nil,
           batteryReferenceRangeKm != nil || batteryRecordingStartOdometerKm != nil {
            batteryCalibrations[String(lastSelectedCarId)] = BatteryCalibration(
                referenceRangeKm: batteryReferenceRangeKm,
                recordingStartOdometerKm: batteryRecordingStartOdometerKm
            )
        }
        chargePricingRules = try container.decodeIfPresent([ChargePricingRule].self, forKey: .chargePricingRules) ?? []
        chargeTariffTemplates = try container.decodeIfPresent([ChargeTariffTemplate].self, forKey: .chargeTariffTemplates) ?? []
        parkingFeeRules = try container.decodeIfPresent([ParkingFeeRule].self, forKey: .parkingFeeRules) ?? []
        geofenceRules = try container.decodeIfPresent([GeofenceRule].self, forKey: .geofenceRules) ?? []
        usesGeofencesForCommuteClassification = try container.decodeIfPresent(Bool.self, forKey: .usesGeofencesForCommuteClassification) ?? true
        allowsThirdPartyRouteWeather = try container.decodeIfPresent(Bool.self, forKey: .allowsThirdPartyRouteWeather) ?? false
        driveAnnotations = try container.decodeIfPresent([String: DriveAnnotation].self, forKey: .driveAnnotations) ?? [:]
        driveRouteLabelRules = try container.decodeIfPresent([DriveRouteLabelRule].self, forKey: .driveRouteLabelRules) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(secondaryServerURL, forKey: .secondaryServerURL)
        try container.encode(authenticationMode, forKey: .authenticationMode)
        try container.encode(usesCloudflareAccess, forKey: .usesCloudflareAccess)
        try container.encode(acceptInvalidCerts, forKey: .acceptInvalidCerts)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encodeIfPresent(residentialTariffRegionCode, forKey: .residentialTariffRegionCode)
        try container.encode(displayUnitSystem, forKey: .displayUnitSystem)
        try container.encode(formatPreferencesVersion, forKey: .formatPreferencesVersion)
        try container.encode(showShortDrivesCharges, forKey: .showShortDrivesCharges)
        try container.encode(mergeAdjacentDrives, forKey: .mergeAdjacentDrives)
        try container.encode(adjacentDriveMergeMaximumGapMinutes, forKey: .adjacentDriveMergeMaximumGapMinutes)
        try container.encode(teslamateBaseURL, forKey: .teslamateBaseURL)
        try container.encodeIfPresent(lastSelectedCarId, forKey: .lastSelectedCarId)
        try container.encode(notificationPermissionAsked, forKey: .notificationPermissionAsked)
        try container.encode(notificationEventSignatures, forKey: .notificationEventSignatures)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encodeIfPresent(batteryReferenceRangeKm, forKey: .batteryReferenceRangeKm)
        try container.encodeIfPresent(batteryRecordingStartOdometerKm, forKey: .batteryRecordingStartOdometerKm)
        try container.encode(batteryCalibrations, forKey: .batteryCalibrations)
        try container.encode(chargePricingRules, forKey: .chargePricingRules)
        try container.encode(chargeTariffTemplates, forKey: .chargeTariffTemplates)
        try container.encode(parkingFeeRules, forKey: .parkingFeeRules)
        try container.encode(geofenceRules, forKey: .geofenceRules)
        try container.encode(usesGeofencesForCommuteClassification, forKey: .usesGeofencesForCommuteClassification)
        try container.encode(allowsThirdPartyRouteWeather, forKey: .allowsThirdPartyRouteWeather)
        try container.encode(driveAnnotations, forKey: .driveAnnotations)
        try container.encode(driveRouteLabelRules, forKey: .driveRouteLabelRules)
        try container.encode(forceChineseLanguage, forKey: .forceChineseLanguage)
    }

    public var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var hasSecondaryServer: Bool {
        !secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func resolvedCurrencyCode(locale: Locale = .autoupdatingCurrent) -> String {
        let normalized = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.isEmpty || normalized == MateDriveCurrencyFormatter.automaticCode {
            return MateDriveCurrencyFormatter.systemCurrencyCode(locale: locale)
        }
        return normalized == "RMB" ? "CNY" : normalized
    }

    public mutating func migrateFormattingPreferences() {
        guard formatPreferencesVersion < Self.currentFormatPreferencesVersion else { return }
        if currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "EUR" {
            currencyCode = MateDriveCurrencyFormatter.automaticCode
        }
        displayUnitSystem = .teslamate
        formatPreferencesVersion = Self.currentFormatPreferencesVersion
    }

    public func batteryCalibration(for carId: Int) -> BatteryCalibration {
        if let calibration = batteryCalibrations[String(carId)] {
            return calibration
        }
        if lastSelectedCarId == carId {
            return BatteryCalibration(
                referenceRangeKm: batteryReferenceRangeKm,
                recordingStartOdometerKm: batteryRecordingStartOdometerKm
            )
        }
        return BatteryCalibration()
    }

    public mutating func setBatteryCalibration(_ calibration: BatteryCalibration, for carId: Int) {
        let key = String(carId)
        if calibration.referenceRangeKm == nil && calibration.referenceCapacityKWh == nil && calibration.recordingStartOdometerKm == nil {
            batteryCalibrations.removeValue(forKey: key)
        } else {
            batteryCalibrations[key] = calibration
        }
        if lastSelectedCarId == carId {
            batteryReferenceRangeKm = calibration.referenceRangeKm
            batteryRecordingStartOdometerKm = calibration.recordingStartOdometerKm
        }
    }

    public func driveAnnotation(carId: Int, driveId: Int) -> DriveAnnotation {
        driveAnnotations["\(carId):\(driveId)"] ?? DriveAnnotation()
    }

    public mutating func setDriveAnnotation(_ annotation: DriveAnnotation, carId: Int, driveId: Int) {
        let key = "\(carId):\(driveId)"
        if annotation.isEmpty { driveAnnotations.removeValue(forKey: key) } else { driveAnnotations[key] = annotation }
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
