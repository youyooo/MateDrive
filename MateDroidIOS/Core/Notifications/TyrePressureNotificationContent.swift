import Foundation

public struct TyrePressureNotificationContent: Equatable, Sendable {
    public let carName: String
    public let tyreName: String
    public let pressure: Double
    public let unit: String
    public let threshold: Double
    public let language: AppLanguage

    public init(
        carName: String,
        tyreName: String,
        pressure: Double,
        unit: String,
        threshold: Double,
        language: AppLanguage = .english
    ) {
        self.carName = carName
        self.tyreName = tyreName
        self.pressure = pressure
        self.unit = unit
        self.threshold = threshold
        self.language = language
    }

    public var title: String {
        "\(carName) - \(AppText.localized("Tyre Pressure", "胎压", language: language))"
    }

    public var body: String {
        let bodyFormat = AppText.localized(
            "%@ is %@ %@, below %@ %@",
            "%@ 当前 %@ %@，低于 %@ %@",
            language: language
        )
        return String(format: bodyFormat, localizedTyreName, format(pressure), unit, format(threshold), unit)
    }

    public var categoryIdentifier: String {
        "tyre_pressure_alert"
    }

    private func format(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(rounded - value) < 0.05 {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", value)
    }

    private var localizedTyreName: String {
        if language == .english {
            return tyreName
        }
        let normalized = tyreName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch normalized {
        case "front left", "left front", "fl":
            return AppText.localized("Front Left", "左前轮", language: language)
        case "front right", "right front", "fr":
            return AppText.localized("Front Right", "右前轮", language: language)
        case "rear left", "left rear", "rl":
            return AppText.localized("Rear Left", "左后轮", language: language)
        case "rear right", "right rear", "rr":
            return AppText.localized("Rear Right", "右后轮", language: language)
        default:
            return tyreName
        }
    }
}
