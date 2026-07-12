import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case system
    case english
    case chinese
    case traditionalChinese
    case german
    case spanish
    case italian
    case catalan

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
        case .german:
            return "de"
        case .spanish:
            return "es"
        case .italian:
            return "it"
        case .catalan:
            return "ca"
        }
    }
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

public struct AppSettings: Codable, Equatable, Sendable {
    public static let currentFormatPreferencesVersion = 1

    public var serverURL: String
    public var secondaryServerURL: String
    public var acceptInvalidCerts: Bool
    public var currencyCode: String
    public var displayUnitSystem: DisplayUnitSystem
    public var formatPreferencesVersion: Int
    public var showShortDrivesCharges: Bool
    public var teslamateBaseURL: String
    public var lastSelectedCarId: Int?
    public var notificationPermissionAsked: Bool
    public var notificationEventSignatures: [String: String]
    public var appLanguage: AppLanguage
    public var batteryReferenceRangeKm: Double?
    public var batteryRecordingStartOdometerKm: Double?
    public var batteryCalibrations: [String: BatteryCalibration]
    public var chargePricingRules: [ChargePricingRule]
    public var parkingFeeRules: [ParkingFeeRule]
    public var driveAnnotations: [String: DriveAnnotation]

    public var forceChineseLanguage: Bool {
        get { appLanguage == .chinese }
        set { appLanguage = newValue ? .chinese : .system }
    }

    public init(
        serverURL: String = "",
        secondaryServerURL: String = "",
        acceptInvalidCerts: Bool = false,
        currencyCode: String = MateDroidCurrencyFormatter.automaticCode,
        displayUnitSystem: DisplayUnitSystem = .teslamate,
        formatPreferencesVersion: Int = AppSettings.currentFormatPreferencesVersion,
        showShortDrivesCharges: Bool = false,
        teslamateBaseURL: String = "",
        lastSelectedCarId: Int? = nil,
        notificationPermissionAsked: Bool = false,
        notificationEventSignatures: [String: String] = [:],
        appLanguage: AppLanguage = .system,
        batteryReferenceRangeKm: Double? = nil,
        batteryRecordingStartOdometerKm: Double? = nil,
        batteryCalibrations: [String: BatteryCalibration] = [:],
        chargePricingRules: [ChargePricingRule] = [],
        parkingFeeRules: [ParkingFeeRule] = [],
        driveAnnotations: [String: DriveAnnotation] = [:],
        forceChineseLanguage: Bool? = nil
    ) {
        self.serverURL = serverURL
        self.secondaryServerURL = secondaryServerURL
        self.acceptInvalidCerts = acceptInvalidCerts
        self.currencyCode = currencyCode
        self.displayUnitSystem = displayUnitSystem
        self.formatPreferencesVersion = formatPreferencesVersion
        self.showShortDrivesCharges = showShortDrivesCharges
        self.teslamateBaseURL = teslamateBaseURL
        self.lastSelectedCarId = lastSelectedCarId
        self.notificationPermissionAsked = notificationPermissionAsked
        self.notificationEventSignatures = notificationEventSignatures
        self.appLanguage = forceChineseLanguage == true ? .chinese : appLanguage
        self.batteryReferenceRangeKm = batteryReferenceRangeKm
        self.batteryRecordingStartOdometerKm = batteryRecordingStartOdometerKm
        self.batteryCalibrations = batteryCalibrations
        self.chargePricingRules = chargePricingRules
        self.parkingFeeRules = parkingFeeRules
        self.driveAnnotations = driveAnnotations
    }

    private enum CodingKeys: String, CodingKey {
        case serverURL
        case secondaryServerURL
        case acceptInvalidCerts
        case currencyCode
        case displayUnitSystem
        case formatPreferencesVersion
        case showShortDrivesCharges
        case teslamateBaseURL
        case lastSelectedCarId
        case notificationPermissionAsked
        case notificationEventSignatures
        case appLanguage
        case batteryReferenceRangeKm
        case batteryRecordingStartOdometerKm
        case batteryCalibrations
        case chargePricingRules
        case parkingFeeRules
        case driveAnnotations
        case forceChineseLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try container.decodeIfPresent(String.self, forKey: .serverURL) ?? ""
        secondaryServerURL = try container.decodeIfPresent(String.self, forKey: .secondaryServerURL) ?? ""
        acceptInvalidCerts = try container.decodeIfPresent(Bool.self, forKey: .acceptInvalidCerts) ?? false
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? MateDroidCurrencyFormatter.automaticCode
        displayUnitSystem = try container.decodeIfPresent(DisplayUnitSystem.self, forKey: .displayUnitSystem) ?? .teslamate
        formatPreferencesVersion = try container.decodeIfPresent(Int.self, forKey: .formatPreferencesVersion) ?? 0
        showShortDrivesCharges = try container.decodeIfPresent(Bool.self, forKey: .showShortDrivesCharges) ?? false
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
        parkingFeeRules = try container.decodeIfPresent([ParkingFeeRule].self, forKey: .parkingFeeRules) ?? []
        driveAnnotations = try container.decodeIfPresent([String: DriveAnnotation].self, forKey: .driveAnnotations) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(serverURL, forKey: .serverURL)
        try container.encode(secondaryServerURL, forKey: .secondaryServerURL)
        try container.encode(acceptInvalidCerts, forKey: .acceptInvalidCerts)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(displayUnitSystem, forKey: .displayUnitSystem)
        try container.encode(formatPreferencesVersion, forKey: .formatPreferencesVersion)
        try container.encode(showShortDrivesCharges, forKey: .showShortDrivesCharges)
        try container.encode(teslamateBaseURL, forKey: .teslamateBaseURL)
        try container.encodeIfPresent(lastSelectedCarId, forKey: .lastSelectedCarId)
        try container.encode(notificationPermissionAsked, forKey: .notificationPermissionAsked)
        try container.encode(notificationEventSignatures, forKey: .notificationEventSignatures)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encodeIfPresent(batteryReferenceRangeKm, forKey: .batteryReferenceRangeKm)
        try container.encodeIfPresent(batteryRecordingStartOdometerKm, forKey: .batteryRecordingStartOdometerKm)
        try container.encode(batteryCalibrations, forKey: .batteryCalibrations)
        try container.encode(chargePricingRules, forKey: .chargePricingRules)
        try container.encode(parkingFeeRules, forKey: .parkingFeeRules)
        try container.encode(driveAnnotations, forKey: .driveAnnotations)
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
        if normalized.isEmpty || normalized == MateDroidCurrencyFormatter.automaticCode {
            return MateDroidCurrencyFormatter.systemCurrencyCode(locale: locale)
        }
        return normalized == "RMB" ? "CNY" : normalized
    }

    public mutating func migrateFormattingPreferences() {
        guard formatPreferencesVersion < Self.currentFormatPreferencesVersion else { return }
        if currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "EUR" {
            currencyCode = MateDroidCurrencyFormatter.automaticCode
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
