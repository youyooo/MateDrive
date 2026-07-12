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

public struct VehicleImageOverride: Codable, Equatable, Sendable {
    public let generationID: String
    public let trimID: String
    public let colorID: String
    public let wheelID: String
    public let assetID: String?

    public init(
        generationID: String,
        trimID: String,
        colorID: String,
        wheelID: String,
        assetID: String? = nil
    ) {
        self.generationID = generationID
        self.trimID = trimID
        self.colorID = colorID
        self.wheelID = wheelID
        self.assetID = assetID
    }

    public func manualOverride(in catalog: VehicleImageCatalog) -> VehicleImageManualOverride? {
        guard let generation = catalog.generations.first(where: { $0.id == generationID }),
              generation.trims.contains(where: { $0.id == trimID }),
              generation.colors.contains(where: { $0.id == colorID }),
              generation.wheels.contains(where: { $0.id == wheelID })
        else { return nil }

        guard let asset = catalog.preferredAsset(
            generationID: generationID,
            trimID: trimID,
            colorID: colorID,
            wheelID: wheelID,
            requestedAssetID: assetID
        ) else { return nil }

        return VehicleImageManualOverride(
            generationID: generation.id,
            trimID: trimID,
            colorID: colorID,
            wheelID: wheelID,
            assetID: asset.id
        )
    }

    public static func migrateLegacy(
        variant: String,
        wheelCode: String,
        catalog: VehicleImageCatalog
    ) -> VehicleImageOverride? {
        guard let compatibleGenerationIDs = legacyCompatibleGenerationIDs[
            variant.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ] else { return nil }
        let normalizedWheelCode = wheelCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = catalog.generations.compactMap { generation -> VehicleImageOverride? in
            guard compatibleGenerationIDs.contains(generation.id) else { return nil }
            let matchingWheels = generation.wheels.filter { wheel in
                ([wheel.id] + wheel.aliases).contains {
                    $0.caseInsensitiveCompare(normalizedWheelCode) == .orderedSame
                }
            }
            guard matchingWheels.count == 1, let wheel = matchingWheels.first else { return nil }

            guard let asset = catalog.preferredAsset(
                generationID: generation.id,
                trimID: generation.defaultTrimID,
                colorID: generation.defaultColorID,
                wheelID: wheel.id
            ) else { return nil }

            return VehicleImageOverride(
                generationID: generation.id,
                trimID: generation.defaultTrimID,
                colorID: generation.defaultColorID,
                wheelID: wheel.id,
                assetID: asset.id
            )
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static let legacyCompatibleGenerationIDs: [String: Set<String>] = [
        "m3": ["model-3-early", "model-3-refresh", "model-3-refresh-performance"],
        "m3h": ["model-3-highland"],
        "m3hp": ["model-3-highland-performance"],
        "my": ["model-y-legacy", "model-y-legacy-performance"],
        "myjs": ["model-y-juniper-standard"],
        "myj": ["model-y-juniper-premium"],
        "myjp": ["model-y-juniper-performance"],
        "ms": ["model-s-nosecone", "model-s-facelift", "model-s-refresh", "model-s-plaid"],
        "mx": ["model-x-legacy", "model-x-refresh", "model-x-plaid"]
    ]
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
    private var vehicleImageOverrides: [String: VehicleImageOverride]
    private var legacyVehicleImageVariants: [String: String]
    private var legacyVehicleImageWheels: [String: String]

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
        vehicleImageOverrides = [:]
        legacyVehicleImageVariants = [:]
        legacyVehicleImageWheels = [:]
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
        case vehicleImageOverrides
        case vehicleImageOverrideVariants
        case vehicleImageOverrideWheels
        case carImageVariants
        case carImageWheelCodes
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
        vehicleImageOverrides = try container.decodeIfPresent([String: VehicleImageOverride].self, forKey: .vehicleImageOverrides) ?? [:]
        legacyVehicleImageVariants = Self.legacyValues(
            from: container,
            keys: [.vehicleImageOverrideVariants, .carImageVariants]
        )
        legacyVehicleImageWheels = Self.legacyValues(
            from: container,
            keys: [.vehicleImageOverrideWheels, .carImageWheelCodes]
        )
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
        try container.encode(vehicleImageOverrides, forKey: .vehicleImageOverrides)
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

    public func vehicleImageOverride(for serverURL: URL, carID: Int) -> VehicleImageOverride? {
        vehicleImageOverrides[vehicleImageOverrideKey(for: serverURL, carID: carID)]
    }

    public func manualVehicleImageOverride(
        for serverURL: URL,
        carID: Int,
        catalog: VehicleImageCatalog
    ) -> VehicleImageManualOverride? {
        vehicleImageOverride(for: serverURL, carID: carID)?.manualOverride(in: catalog)
    }

    public mutating func setVehicleImageOverride(
        _ override: VehicleImageOverride,
        for serverURL: URL,
        carID: Int
    ) {
        vehicleImageOverrides[vehicleImageOverrideKey(for: serverURL, carID: carID)] = override
    }

    public mutating func clearVehicleImageOverride(for serverURL: URL, carID: Int) {
        vehicleImageOverrides.removeValue(forKey: vehicleImageOverrideKey(for: serverURL, carID: carID))
    }

    var hasLegacyVehicleImageOverrideValues: Bool {
        !legacyVehicleImageVariants.isEmpty || !legacyVehicleImageWheels.isEmpty
    }

    public mutating func migrateLegacyVehicleImageOverrides(catalog: VehicleImageCatalog) -> Bool {
        let hadLegacyValues = hasLegacyVehicleImageOverrideValues
        defer {
            legacyVehicleImageVariants.removeAll()
            legacyVehicleImageWheels.removeAll()
        }
        guard hadLegacyValues,
              let serverURL = Self.validServerURL(from: serverURL)
        else { return hadLegacyValues }

        for (carIDText, variant) in legacyVehicleImageVariants {
            guard let carID = Int(carIDText),
                  let wheelCode = legacyVehicleImageWheels[carIDText],
                  vehicleImageOverride(for: serverURL, carID: carID) == nil,
                  let override = VehicleImageOverride.migrateLegacy(
                      variant: variant,
                      wheelCode: wheelCode,
                      catalog: catalog
                  )
            else { continue }
            setVehicleImageOverride(override, for: serverURL, carID: carID)
        }
        return true
    }

    private func vehicleImageOverrideKey(for serverURL: URL, carID: Int) -> String {
        "\(TeslaMateServerIdentity.key(for: serverURL)):\(carID)"
    }

    private static func validServerURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    private static func legacyValues(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> [String: String] {
        for key in keys {
            if let values = try? container.decodeIfPresent([String: String].self, forKey: key) {
                return values
            }
        }
        return [:]
    }
}
