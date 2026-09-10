import CryptoKit
import Foundation

public enum WidgetConstants {
    public static let appGroupIdentifier = "group.com.matedrive.ios"
    public static let carStatusKind = "CarStatusWidget"
    public static let batteryTrendKind = "BatteryTrendWidget"
    public static let chargingTrendKind = "ChargingTrendWidget"
    public static let currentChargeKind = "CurrentChargeWidget"
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

    private var resolved: WidgetDisplayLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased() ?? "en"
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") || preferred.hasPrefix("zh-mo") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") { return .chinese }
        return .english
    }

    func value(
        english: String,
        chinese: String,
        traditionalChinese: String
    ) -> String {
        switch resolved {
        case .system, .english: english
        case .chinese: chinese
        case .traditionalChinese: traditionalChinese
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
            isReadOnly: true,
            displayLanguage: displayLanguage,
            displayUnitSystem: displayUnitSystem
        )
    }

    private enum CodingKeys: String, CodingKey {
        case carName, batteryLevel, ratedRange, isCharging, isLocked, sentryModeActive
        case insideTemperature, outsideTemperature, locationText
        case isReadOnly, displayLanguage, displayUnitSystem
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
            return language.value(
                english: "Charging",
                chinese: "正在充电",
                traditionalChinese: "正在充電"
            )
        }
        if sentryModeActive {
            return language.value(
                english: "Sentry",
                chinese: "哨兵",
                traditionalChinese: "哨兵"
            )
        }
        return isLocked == false
            ? language.value(
                english: "Unlocked",
                chinese: "已解锁",
                traditionalChinese: "已解鎖"
            )
            : language.value(
                english: "Parked",
                chinese: "已停车",
                traditionalChinese: "已停車"
            )
    }

    public var lockText: String? {
        lockText(language: displayLanguage)
    }

    public func lockText(language: WidgetDisplayLanguage) -> String? {
        guard let isLocked else {
            return nil
        }
        return isLocked
            ? language.value(
                english: "Locked",
                chinese: "已锁定",
                traditionalChinese: "已鎖定"
            )
            : language.value(
                english: "Unlocked",
                chinese: "已解锁",
                traditionalChinese: "已解鎖"
            )
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

}

public enum WidgetVehicleIdentity {
    public static func isCanonicalIdentifier(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                (48...57).contains($0) || (97...102).contains($0)
            }
    }

    public static func identifier(serverURL: String, carID: Int) -> String? {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !scheme.isEmpty,
              !host.isEmpty
        else { return nil }

        let normalizedHost = host.contains(":") ? "[\(host)]" : host
        let port = url.port.flatMap { port in
            (scheme == "http" && port == 80) || (scheme == "https" && port == 443) ? nil : port
        }
        let authority = port.map { "\(normalizedHost):\($0)" } ?? normalizedHost
        var path = url.path
        while path.last == "/" { path.removeLast() }
        let canonical = "\(scheme)://\(authority)\(path)|\(carID)"
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum WidgetBatteryTrendMetric: String, Codable, Equatable, Sendable {
    case capacity
    case range
}

public enum WidgetChargePhase: String, Codable, Equatable, Sendable {
    case charging
    case starting
    case idle
}

public enum WidgetChargeDataQuality: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case offline
}

public struct WidgetCurrentChargeData: Codable, Equatable, Sendable {
    public let phase: WidgetChargePhase
    public let quality: WidgetChargeDataQuality
    public let batteryLevel: Int?
    public let chargeLimitSoc: Int?
    public let chargerPowerKW: Int?
    public let energyAddedKWh: Double?
    public let timeToFullMinutes: Int?
    public let isDC: Bool?
    public let updatedAt: Date

    public init(
        phase: WidgetChargePhase,
        quality: WidgetChargeDataQuality,
        batteryLevel: Int? = nil,
        chargeLimitSoc: Int? = nil,
        chargerPowerKW: Int? = nil,
        energyAddedKWh: Double? = nil,
        timeToFullMinutes: Int? = nil,
        isDC: Bool? = nil,
        updatedAt: Date
    ) {
        self.phase = phase
        self.quality = quality
        self.batteryLevel = batteryLevel.map { min(max($0, 0), 100) }
        self.chargeLimitSoc = chargeLimitSoc.map { min(max($0, 0), 100) }
        self.chargerPowerKW = chargerPowerKW.flatMap { $0 >= 0 ? $0 : nil }
        self.energyAddedKWh = energyAddedKWh.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.timeToFullMinutes = timeToFullMinutes.map { max($0, 0) }
        self.isDC = isDC
        self.updatedAt = updatedAt
    }

    public func markingOffline() -> Self {
        Self(
            phase: phase,
            quality: .offline,
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            updatedAt: updatedAt
        )
    }

    public func isStale(at now: Date, threshold: TimeInterval = 30 * 60) -> Bool {
        now.timeIntervalSince(updatedAt) > threshold
    }
}

public struct WidgetBatteryTrendData: Codable, Equatable, Sendable {
    public let healthPercent: Double?
    public let showsAbsoluteHealth: Bool
    public let metric: WidgetBatteryTrendMetric
    public let samples: [Double]
    public let currentValue: Double?
    public let recordedDays: Int
    public let qualityScore: Int?
    public let displayLanguage: WidgetDisplayLanguage
    public let displayUnitSystem: WidgetDisplayUnitSystem?

    public init(
        healthPercent: Double? = nil,
        showsAbsoluteHealth: Bool = false,
        metric: WidgetBatteryTrendMetric,
        samples: [Double],
        currentValue: Double? = nil,
        recordedDays: Int = 0,
        qualityScore: Int? = nil,
        displayLanguage: WidgetDisplayLanguage = .system,
        displayUnitSystem: WidgetDisplayUnitSystem? = nil
    ) {
        self.healthPercent = healthPercent.flatMap { $0.isFinite ? min(max($0, 0), 100) : nil }
        self.showsAbsoluteHealth = showsAbsoluteHealth
        self.metric = metric
        self.samples = Array(samples.filter { $0.isFinite && $0 > 0 }.suffix(24))
        self.currentValue = currentValue.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.recordedDays = max(recordedDays, 0)
        self.qualityScore = qualityScore.map { min(max($0, 0), 100) }
        self.displayLanguage = displayLanguage
        self.displayUnitSystem = displayUnitSystem
    }

    public var headlineText: String {
        guard let healthPercent else { return "--" }
        return String(format: "%.1f%%", healthPercent)
    }

    public var headlineLabel: String {
        if showsAbsoluteHealth {
            return displayLanguage.value(
                english: "Battery health", chinese: "电池健康度", traditionalChinese: "電池健康度"
            )
        }
        return displayLanguage.value(
            english: "Recorded retention", chinese: "记录期保持率", traditionalChinese: "記錄期保持率"
        )
    }

    public var metricTitle: String {
        switch metric {
        case .capacity:
            return displayLanguage.value(
                english: "Capacity trend", chinese: "容量趋势", traditionalChinese: "容量趨勢"
            )
        case .range:
            return displayLanguage.value(
                english: "Range trend", chinese: "续航趋势", traditionalChinese: "續航趨勢"
            )
        }
    }

    public var currentValueText: String {
        guard let currentValue else { return "--" }
        switch metric {
        case .capacity:
            return String(format: "%.1f kWh", currentValue)
        case .range:
            if resolvedUnitSystem.usesImperial {
                return String(format: "%.0f mi", currentValue * 0.621371)
            }
            return String(format: "%.0f km", currentValue)
        }
    }

    public var periodText: String {
        guard recordedDays > 0 else { return metricTitle }
        return displayLanguage.value(
            english: "\(recordedDays) recorded days",
            chinese: "已记录 \(recordedDays) 天",
            traditionalChinese: "已記錄 \(recordedDays) 天"
        )
    }

    private var resolvedUnitSystem: WidgetDisplayUnitSystem {
        displayUnitSystem ?? (displayLanguage == .english ? .imperial : .metric)
    }
}

public struct WidgetChargingTrendData: Codable, Equatable, Sendable {
    public let periodDays: Int
    public let sessionCount: Int
    public let energyKWh: Double?
    public let energyKnownCount: Int
    public let cost: Double?
    public let costKnownCount: Int
    public let currencyCode: String
    public let energyBuckets: [Double]
    public let displayLanguage: WidgetDisplayLanguage

    public init(
        periodDays: Int = 30,
        sessionCount: Int,
        energyKWh: Double? = nil,
        energyKnownCount: Int = 0,
        cost: Double? = nil,
        costKnownCount: Int = 0,
        currencyCode: String,
        energyBuckets: [Double],
        displayLanguage: WidgetDisplayLanguage = .system
    ) {
        self.periodDays = max(periodDays, 1)
        self.sessionCount = max(sessionCount, 0)
        self.energyKWh = energyKWh.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.energyKnownCount = min(max(energyKnownCount, 0), self.sessionCount)
        self.cost = cost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.costKnownCount = min(max(costKnownCount, 0), self.sessionCount)
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.currencyCode = normalizedCurrency.isEmpty ? "USD" : normalizedCurrency
        self.energyBuckets = Array(energyBuckets.map { $0.isFinite ? max($0, 0) : 0 }.suffix(6))
        self.displayLanguage = displayLanguage
    }

    public var title: String {
        displayLanguage.value(
            english: "Charging trend", chinese: "充电趋势", traditionalChinese: "充電趨勢"
        )
    }

    public var periodText: String {
        displayLanguage.value(
            english: "Last \(periodDays) days",
            chinese: "最近 \(periodDays) 天",
            traditionalChinese: "最近 \(periodDays) 天"
        )
    }

    public var sessionText: String {
        displayLanguage.value(
            english: "\(sessionCount) sessions",
            chinese: "\(sessionCount) 次充电",
            traditionalChinese: "\(sessionCount) 次充電"
        )
    }

    public var energyText: String {
        guard let energyKWh else { return "-- kWh" }
        return String(format: "%.1f kWh", energyKWh)
    }

    public var costText: String {
        guard let cost else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: cost)) ?? "\(currencyCode) \(String(format: "%.2f", cost))"
    }

    public var costLabel: String {
        costKnownCount == sessionCount && sessionCount > 0
            ? displayLanguage.value(
                english: "Total cost", chinese: "总费用", traditionalChinese: "總費用"
            )
            : displayLanguage.value(
                english: "Known cost \(costKnownCount)/\(sessionCount)",
                chinese: "已知费用 \(costKnownCount)/\(sessionCount)",
                traditionalChinese: "已知費用 \(costKnownCount)/\(sessionCount)"
            )
    }
}

public struct WidgetVehicleSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let data: WidgetDisplayData
    public let batteryTrend: WidgetBatteryTrendData?
    public let chargingTrend: WidgetChargingTrendData?
    public let currentCharge: WidgetCurrentChargeData?
    public let updatedAt: Date

    public init(
        id: String,
        data: WidgetDisplayData,
        batteryTrend: WidgetBatteryTrendData? = nil,
        chargingTrend: WidgetChargingTrendData? = nil,
        currentCharge: WidgetCurrentChargeData? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.data = data
        self.batteryTrend = batteryTrend
        self.chargingTrend = chargingTrend
        self.currentCharge = currentCharge
        self.updatedAt = updatedAt
    }
}

public struct WidgetSnapshotStore: @unchecked Sendable {
    public static let shared = WidgetSnapshotStore(
        defaults: UserDefaults(suiteName: WidgetConstants.appGroupIdentifier) ?? .standard
    )

    private let defaults: UserDefaults
    private let key: String
    private let vehicleSnapshotsKey: String
    private let preferredVehicleIdentifierKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private static let lock = NSLock()

    public init(
        defaults: UserDefaults,
        key: String = "latestWidgetDisplayData",
        vehicleSnapshotsKey: String = "widgetVehicleSnapshots.v2",
        preferredVehicleIdentifierKey: String = "preferredWidgetVehicleIdentifier.v2"
    ) {
        self.defaults = defaults
        self.key = key
        self.vehicleSnapshotsKey = vehicleSnapshotsKey
        self.preferredVehicleIdentifierKey = preferredVehicleIdentifierKey
    }

    public func save(_ data: WidgetDisplayData) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let encoded = try? encoder.encode(data) else {
            return
        }
        defaults.set(encoded, forKey: key)
    }

    public func save(_ data: WidgetDisplayData, vehicleIdentifier: String, makeLatest: Bool = true, updatedAt: Date = Date()) {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        var snapshots = decodedVehicleSnapshots()
        let existing = snapshots.first(where: { $0.id == vehicleIdentifier })
        snapshots.removeAll { $0.id == vehicleIdentifier }
        snapshots.append(WidgetVehicleSnapshot(
            id: vehicleIdentifier,
            data: data,
            batteryTrend: existing?.batteryTrend,
            chargingTrend: existing?.chargingTrend,
            currentCharge: existing?.currentCharge,
            updatedAt: updatedAt
        ))
        snapshots.sort { $0.data.carName.localizedStandardCompare($1.data.carName) == .orderedAscending }
        saveVehicleSnapshots(snapshots)
        if makeLatest, let encoded = try? encoder.encode(data) {
            defaults.set(encoded, forKey: key)
            defaults.set(vehicleIdentifier, forKey: preferredVehicleIdentifierKey)
        }
    }

    public func replaceVehicleSnapshots(_ snapshots: [WidgetVehicleSnapshot], preferredIdentifier: String?) {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        let unique = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
            .values
            .sorted { $0.data.carName.localizedStandardCompare($1.data.carName) == .orderedAscending }
        saveVehicleSnapshots(unique)
        if let preferredIdentifier,
           let preferred = unique.first(where: { $0.id == preferredIdentifier }),
           let encoded = try? encoder.encode(preferred.data) {
            defaults.set(encoded, forKey: key)
            defaults.set(preferred.id, forKey: preferredVehicleIdentifierKey)
        } else if let first = unique.first, let encoded = try? encoder.encode(first.data) {
            defaults.set(encoded, forKey: key)
            defaults.set(first.id, forKey: preferredVehicleIdentifierKey)
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: preferredVehicleIdentifierKey)
        }
    }

    @discardableResult
    public func updateCurrentCharge(_ currentCharge: WidgetCurrentChargeData?, vehicleIdentifier: String) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }

        var snapshots = decodedVehicleSnapshots()
        guard let index = snapshots.firstIndex(where: { $0.id == vehicleIdentifier }),
              snapshots[index].currentCharge != currentCharge
        else {
            return false
        }

        let existing = snapshots[index]
        snapshots[index] = WidgetVehicleSnapshot(
            id: existing.id,
            data: existing.data,
            batteryTrend: existing.batteryTrend,
            chargingTrend: existing.chargingTrend,
            currentCharge: currentCharge,
            updatedAt: existing.updatedAt
        )
        saveVehicleSnapshots(snapshots)
        return true
    }

    public func load() -> WidgetDisplayData? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? decoder.decode(WidgetDisplayData.self, from: data)
    }

    public func load(vehicleIdentifier: String) -> WidgetDisplayData? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return decodedVehicleSnapshots().first(where: { $0.id == vehicleIdentifier })?.data
    }

    public func vehicleSnapshot(vehicleIdentifier: String) -> WidgetVehicleSnapshot? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return decodedVehicleSnapshots().first(where: { $0.id == vehicleIdentifier })
    }

    public func vehicleSnapshots() -> [WidgetVehicleSnapshot] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return decodedVehicleSnapshots()
    }

    public func preferredVehicleSnapshot() -> WidgetVehicleSnapshot? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let identifier = defaults.string(forKey: preferredVehicleIdentifierKey) else { return nil }
        return decodedVehicleSnapshots().first(where: { $0.id == identifier })
    }

    public func remove() {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: vehicleSnapshotsKey)
        defaults.removeObject(forKey: preferredVehicleIdentifierKey)
    }

    private func decodedVehicleSnapshots() -> [WidgetVehicleSnapshot] {
        guard let data = defaults.data(forKey: vehicleSnapshotsKey) else { return [] }
        return (try? decoder.decode([WidgetVehicleSnapshot].self, from: data)) ?? []
    }

    private func saveVehicleSnapshots(_ snapshots: [WidgetVehicleSnapshot]) {
        guard let encoded = try? encoder.encode(snapshots) else { return }
        defaults.set(encoded, forKey: vehicleSnapshotsKey)
    }
}
