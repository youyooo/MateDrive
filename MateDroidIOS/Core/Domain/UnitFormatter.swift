import Foundation

public enum DisplayUnitSystem: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case teslamate
    case metric
    case imperial

    public var id: String { rawValue }
}

public struct UnitPreferences: Equatable, Sendable {
    public let unitOfLength: String?
    public let unitOfTemperature: String?
    public let unitOfPressure: String?

    public var isImperial: Bool {
        unitOfLength == "mi"
    }

    public init(unitOfLength: String? = nil, unitOfTemperature: String? = nil, unitOfPressure: String? = nil) {
        self.unitOfLength = unitOfLength
        self.unitOfTemperature = unitOfTemperature
        self.unitOfPressure = unitOfPressure
    }

    public static let metric = UnitPreferences(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    public static let imperial = UnitPreferences(unitOfLength: "mi", unitOfTemperature: "F", unitOfPressure: "psi")

    public func resolved(for displayUnitSystem: DisplayUnitSystem) -> UnitPreferences {
        UnitPreferences.resolved(self, for: displayUnitSystem) ?? self
    }

    public func resolved(for _: AppLanguage) -> UnitPreferences {
        self
    }

    public static func resolved(_ units: UnitPreferences?, for displayUnitSystem: DisplayUnitSystem) -> UnitPreferences? {
        switch displayUnitSystem {
        case .teslamate:
            return units
        case .metric:
            return .metric
        case .imperial:
            return .imperial
        }
    }

    public static func resolved(_ units: UnitPreferences?, for _: AppLanguage) -> UnitPreferences? {
        units
    }
}

public extension Optional where Wrapped == UnitPreferences {
    func resolved(for displayUnitSystem: DisplayUnitSystem) -> UnitPreferences? {
        UnitPreferences.resolved(self, for: displayUnitSystem)
    }

    func resolved(for _: AppLanguage) -> UnitPreferences? {
        self
    }
}

public enum MateDroidUnitFormatter {
    private static let formatterLocale = Locale(identifier: "en_US_POSIX")
    private static let milesPerKilometer = 0.621371
    private static let feetPerMeter = 3.28084
    private static let psiPerBar = 14.5038

    public static func formatElevation(_ value: Int?, units: UnitPreferences?) -> String {
        let meters = value ?? 0
        if units?.isImperial == true {
            return "\(formatInteger(Int(Double(meters) * feetPerMeter))) ft"
        }
        return "\(formatInteger(meters)) m"
    }

    public static func elevationValue(_ value: Float, units: UnitPreferences?) -> Float {
        units?.isImperial == true ? value * Float(feetPerMeter) : value
    }

    public static func elevationUnit(units: UnitPreferences?) -> String {
        units?.isImperial == true ? "ft" : "m"
    }

    public static func formatDistance(_ value: Double, units: UnitPreferences?, decimals: Int = 1) -> String {
        "\(formatDecimal(distanceValue(value, units: units), decimals: decimals, grouping: true)) \(distanceUnit(units: units))"
    }

    public static func distanceValue(_ value: Double, units: UnitPreferences?, decimals _: Int = 1) -> Double {
        units?.isImperial == true ? value * milesPerKilometer : value
    }

    public static func distanceUnit(units: UnitPreferences?) -> String {
        units?.isImperial == true ? "mi" : "km"
    }

    public static func formatTemperature(_ value: Double, units: UnitPreferences?, decimals: Int = 0) -> String {
        "\(formatDecimal(temperatureValue(value, units: units), decimals: decimals, grouping: false))\(temperatureUnit(units: units))"
    }

    public static func temperatureValue(_ value: Double, units: UnitPreferences?) -> Double {
        units?.unitOfTemperature == "F" ? value * 9 / 5 + 32 : value
    }

    public static func temperatureUnit(units: UnitPreferences?) -> String {
        units?.unitOfTemperature == "F" ? "°F" : "°C"
    }

    public static func formatPressure(_ value: Double, units: UnitPreferences?, decimals: Int = 1) -> String {
        "\(formatDecimal(pressureValue(value, units: units), decimals: decimals, grouping: false)) \(pressureUnit(units: units))"
    }

    public static func pressureUnit(units: UnitPreferences?) -> String {
        units?.unitOfPressure == "psi" ? "psi" : "bar"
    }

    public static func pressureValue(_ value: Double, units: UnitPreferences?) -> Double {
        units?.unitOfPressure == "psi" ? value * psiPerBar : value
    }

    public static func formatEfficiency(_ value: Double, units: UnitPreferences?, decimals: Int = 1) -> String {
        "\(formatDecimal(efficiencyValue(value, units: units), decimals: decimals, grouping: false)) \(efficiencyUnit(units: units))"
    }

    public static func efficiencyUnit(units: UnitPreferences?) -> String {
        units?.isImperial == true ? "Wh/mi" : "Wh/km"
    }

    public static func efficiencyValue(_ value: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? value / milesPerKilometer : value
    }

    public static func formatSpeed(_ value: Double, units: UnitPreferences?, decimals: Int = 0) -> String {
        "\(formatDecimal(speedValue(value, units: units), decimals: decimals, grouping: false)) \(speedUnit(units: units))"
    }

    public static func speedUnit(units: UnitPreferences?) -> String {
        units?.isImperial == true ? "mph" : "km/h"
    }

    public static func speedValue(_ value: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? value * milesPerKilometer : value
    }

    public static func formatDuration(minutes value: Int, language: AppLanguage) -> String {
        let hours = value / 60
        let minutes = value % 60

        if usesChineseLabels(language: language) {
            let traditional = AppText.usesTraditionalChinese(language: language)
            let hourLabel = traditional ? "小時" : "小时"
            let minuteLabel = traditional ? "分鐘" : "分钟"
            if hours > 0, minutes > 0 {
                return "\(hours)\(hourLabel) \(minutes)\(minuteLabel)"
            }
            if hours > 0 {
                return "\(hours)\(hourLabel)"
            }
            return "\(value)\(minuteLabel)"
        }

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(value)m"
    }

    private static func formatDecimal(_ value: Double, decimals: Int, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = formatterLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }

    private static func formatInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = formatterLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func usesChineseLabels(language: AppLanguage) -> Bool {
        switch language {
        case .chinese, .traditionalChinese:
            return true
        case .english, .german, .spanish, .italian, .catalan:
            return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("zh") == true
        }
    }
}
