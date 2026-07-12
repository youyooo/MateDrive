import Foundation

public struct ChargingNotificationContent: Equatable, Sendable {
    public let carName: String
    public let chargerPowerKW: Double
    public let isDC: Bool
    public let batteryLevel: Int?
    public let chargeLimit: Int?
    public let language: AppLanguage

    public init(
        carName: String,
        chargerPowerKW: Double,
        isDC: Bool,
        batteryLevel: Int? = nil,
        chargeLimit: Int? = nil,
        language: AppLanguage = .english
    ) {
        self.carName = carName
        self.chargerPowerKW = chargerPowerKW
        self.isDC = isDC
        self.batteryLevel = batteryLevel
        self.chargeLimit = chargeLimit
        self.language = language
    }

    public var title: String {
        let chargeType = (isDC ? ChargePricingChargeType.dc : .ac).displayText(language: language)
        return "\(carName) - \(formattedPower) \(chargeType)"
    }

    public var body: String {
        let battery = batteryLevel.map { "\($0)%" } ?? "--"
        let limit = chargeLimit.map { "\($0)%" } ?? "--"
        let format = AppText.localized("Battery %@, limit %@", "电量 %@，上限 %@", language: language)
        return String(format: format, battery, limit)
    }

    public var categoryIdentifier: String {
        "charging_status"
    }

    private var formattedPower: String {
        let rounded = chargerPowerKW.rounded()
        if abs(rounded - chargerPowerKW) < 0.05 {
            return "\(Int(rounded)) kW"
        }
        return String(format: "%.1f kW", chargerPowerKW)
    }
}
