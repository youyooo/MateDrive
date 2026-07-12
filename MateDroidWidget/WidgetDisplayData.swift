import Foundation

public enum WidgetConstants {
    public static let appGroupIdentifier = "group.com.matedrive.ios"
    public static let carStatusKind = "CarStatusWidget"
}

public enum WidgetDisplayLanguage: String, Codable, Equatable, Sendable {
    case system
    case english
    case chinese
    case traditionalChinese

    public var usesChineseLabels: Bool {
        switch self {
        case .chinese, .traditionalChinese:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
    }

    public var usesTraditionalChineseLabels: Bool {
        switch self {
        case .traditionalChinese:
            return true
        case .system:
            let preferred = Locale.preferredLanguages.first?.replacingOccurrences(of: "_", with: "-") ?? ""
            return preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") || preferred.hasPrefix("zh-MO")
        case .english, .chinese:
            return false
        }
    }
}

public enum WidgetDisplayUnitSystem: String, Codable, Equatable, Sendable {
    case metric
    case imperial

    public var usesImperial: Bool {
        self == .imperial
    }
}

public struct WidgetDisplayData: Codable, Equatable, Sendable {
    public let carName: String
    public let batteryLevel: Int?
    public let ratedRange: Double?
    public let isCharging: Bool
    public let isLocked: Bool?
    public let sentryModeActive: Bool
    public let insideTemperature: Double?
    public let outsideTemperature: Double?
    public let locationText: String?
    public let vehicleImageAssetID: String?
    public let carImagePath: String?
    public let carImageScaleFactor: Double
    public var carImageName: String? { carImagePath }
    public let isReadOnly: Bool
    public let displayLanguage: WidgetDisplayLanguage
    public let displayUnitSystem: WidgetDisplayUnitSystem?

    public init(
        carName: String,
        batteryLevel: Int? = nil,
        ratedRange: Double? = nil,
        isCharging: Bool = false,
        isLocked: Bool? = nil,
        sentryModeActive: Bool = false,
        insideTemperature: Double? = nil,
        outsideTemperature: Double? = nil,
        locationText: String? = nil,
        vehicleImageAssetID: String? = nil,
        carImageName: String? = nil,
        carImagePath: String? = nil,
        carImageScaleFactor: Double = 1,
        isReadOnly: Bool = true,
        displayLanguage: WidgetDisplayLanguage = .system,
        displayUnitSystem: WidgetDisplayUnitSystem? = nil
    ) {
        self.carName = carName
        self.batteryLevel = batteryLevel
        self.ratedRange = ratedRange
        self.isCharging = isCharging
        self.isLocked = isLocked
        self.sentryModeActive = sentryModeActive
        self.insideTemperature = insideTemperature
        self.outsideTemperature = outsideTemperature
        self.locationText = locationText
        self.vehicleImageAssetID = vehicleImageAssetID
        self.carImagePath = carImagePath ?? carImageName
        self.carImageScaleFactor = carImageScaleFactor
        self.isReadOnly = isReadOnly
        self.displayLanguage = displayLanguage
        self.displayUnitSystem = displayUnitSystem
    }

    public static func fixture(
        carName: String = "MateDrive",
        batteryLevel: Int? = 68,
        ratedRange: Double? = 320,
        isCharging: Bool = false,
        isLocked: Bool? = true,
        sentryModeActive: Bool = false,
        insideTemperature: Double? = 21,
        outsideTemperature: Double? = 18,
        locationText: String? = "Location",
        vehicleImageAssetID: String? = nil,
        carImageName: String? = nil,
        carImagePath: String? = nil,
        carImageScaleFactor: Double = 1,
        displayLanguage: WidgetDisplayLanguage = .system,
        displayUnitSystem: WidgetDisplayUnitSystem? = nil
    ) -> WidgetDisplayData {
        WidgetDisplayData(
            carName: carName,
            batteryLevel: batteryLevel,
            ratedRange: ratedRange,
            isCharging: isCharging,
            isLocked: isLocked,
            sentryModeActive: sentryModeActive,
            insideTemperature: insideTemperature,
            outsideTemperature: outsideTemperature,
            locationText: locationText,
            vehicleImageAssetID: vehicleImageAssetID,
            carImageName: carImageName,
            carImagePath: carImagePath,
            carImageScaleFactor: carImageScaleFactor,
            isReadOnly: true,
            displayLanguage: displayLanguage,
            displayUnitSystem: displayUnitSystem
        )
    }

    private enum CodingKeys: String, CodingKey {
        case carName, batteryLevel, ratedRange, isCharging, isLocked, sentryModeActive
        case insideTemperature, outsideTemperature, locationText, vehicleImageAssetID, carImageName, carImagePath
        case carImageScaleFactor, isReadOnly, displayLanguage, displayUnitSystem
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        carName = try container.decodeIfPresent(String.self, forKey: .carName) ?? "MateDrive"
        batteryLevel = try container.decodeIfPresent(Int.self, forKey: .batteryLevel)
        ratedRange = try container.decodeIfPresent(Double.self, forKey: .ratedRange)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
        sentryModeActive = try container.decodeIfPresent(Bool.self, forKey: .sentryModeActive) ?? false
        insideTemperature = try container.decodeIfPresent(Double.self, forKey: .insideTemperature)
        outsideTemperature = try container.decodeIfPresent(Double.self, forKey: .outsideTemperature)
        locationText = try container.decodeIfPresent(String.self, forKey: .locationText)
        vehicleImageAssetID = try container.decodeIfPresent(String.self, forKey: .vehicleImageAssetID)
        carImagePath = try container.decodeIfPresent(String.self, forKey: .carImagePath)
            ?? container.decodeIfPresent(String.self, forKey: .carImageName)
        carImageScaleFactor = try container.decodeIfPresent(Double.self, forKey: .carImageScaleFactor) ?? 1
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? true
        displayLanguage = try container.decodeIfPresent(WidgetDisplayLanguage.self, forKey: .displayLanguage) ?? .system
        displayUnitSystem = try container.decodeIfPresent(WidgetDisplayUnitSystem.self, forKey: .displayUnitSystem)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(carName, forKey: .carName)
        try container.encodeIfPresent(batteryLevel, forKey: .batteryLevel)
        try container.encodeIfPresent(ratedRange, forKey: .ratedRange)
        try container.encode(isCharging, forKey: .isCharging)
        try container.encodeIfPresent(isLocked, forKey: .isLocked)
        try container.encode(sentryModeActive, forKey: .sentryModeActive)
        try container.encodeIfPresent(insideTemperature, forKey: .insideTemperature)
        try container.encodeIfPresent(outsideTemperature, forKey: .outsideTemperature)
        try container.encodeIfPresent(locationText, forKey: .locationText)
        try container.encodeIfPresent(vehicleImageAssetID, forKey: .vehicleImageAssetID)
        try container.encodeIfPresent(carImagePath, forKey: .carImagePath)
        try container.encode(carImageScaleFactor, forKey: .carImageScaleFactor)
        try container.encode(isReadOnly, forKey: .isReadOnly)
        try container.encode(displayLanguage, forKey: .displayLanguage)
        try container.encodeIfPresent(displayUnitSystem, forKey: .displayUnitSystem)
    }

    public var batteryText: String {
        batteryLevel.map { "\($0)%" } ?? "--"
    }

    public var statusText: String {
        statusText(language: displayLanguage)
    }

    public func statusText(language: WidgetDisplayLanguage) -> String {
        if isCharging {
            return localized("Charging", "正在充电", "正在充電", language: language)
        }
        if sentryModeActive {
            return localized("Sentry", "哨兵", "哨兵", language: language)
        }
        return isLocked == false
            ? localized("Unlocked", "已解锁", "已解鎖", language: language)
            : localized("Parked", "已停车", "已停車", language: language)
    }

    public var lockText: String? {
        lockText(language: displayLanguage)
    }

    public func lockText(language: WidgetDisplayLanguage) -> String? {
        guard let isLocked else {
            return nil
        }
        return isLocked
            ? localized("Locked", "已锁定", "已鎖定", language: language)
            : localized("Unlocked", "已解锁", "已解鎖", language: language)
    }

    public var rangeText: String {
        guard let ratedRange else {
            return "--"
        }
        let units = resolvedUnitSystem
        if units.usesImperial {
            return String(format: "%.0f mi", ratedRange * 0.621371)
        }
        return String(format: "%.0f km", ratedRange)
    }

    public var temperatureText: String {
        let units = resolvedUnitSystem
        let inside = insideTemperature.map { formatTemperature($0, units: units) }
        let outside = outsideTemperature.map { formatTemperature($0, units: units) }
        return [inside, outside].compactMap { $0 }.joined(separator: " / ")
    }

    private var resolvedUnitSystem: WidgetDisplayUnitSystem {
        if let displayUnitSystem {
            return displayUnitSystem
        }
        return displayLanguage == .english ? .imperial : .metric
    }

    private func formatTemperature(_ celsius: Double, units: WidgetDisplayUnitSystem) -> String {
        if units.usesImperial {
            return String(format: "%.0f°F", celsius * 9 / 5 + 32)
        }
        return String(format: "%.0f°C", celsius)
    }

    private func localized(_ english: String, _ chinese: String, _ traditionalChinese: String, language: WidgetDisplayLanguage) -> String {
        if language.usesTraditionalChineseLabels {
            return traditionalChinese
        }
        return language.usesChineseLabels ? chinese : english
    }
}

public struct WidgetSnapshotStore: @unchecked Sendable {
    public static let shared = WidgetSnapshotStore(
        defaults: UserDefaults(suiteName: WidgetConstants.appGroupIdentifier) ?? .standard
    )

    private let defaults: UserDefaults
    private let key: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults, key: String = "latestWidgetDisplayData") {
        self.defaults = defaults
        self.key = key
    }

    public func save(_ data: WidgetDisplayData) {
        guard let encoded = try? encoder.encode(data) else {
            return
        }
        defaults.set(encoded, forKey: key)
    }

    public func load() -> WidgetDisplayData? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(WidgetDisplayData.self, from: data)
    }

    public func remove() {
        defaults.removeObject(forKey: key)
    }
}
