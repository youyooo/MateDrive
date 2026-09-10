import Foundation

public struct SentryNotificationContent: Equatable, Sendable {
    public let carName: String
    public let alertCount: Int
    public let locationText: String?
    public let language: AppLanguage

    public init(carName: String, alertCount: Int, locationText: String? = nil, language: AppLanguage = .english) {
        self.carName = carName
        self.alertCount = alertCount
        self.locationText = locationText
        self.language = language
    }

    public var title: String {
        "\(carName) - \(AppText.localized("Sentry Alert", "哨兵警报", language: language)) #\(alertCount)"
    }

    public var body: String {
        if let locationText {
            let format = AppText.localized("Detected at %@", "检测位置：%@", language: language)
            return String(format: format, locationText)
        }
        return AppText.localized("Sentry mode detected activity", "哨兵模式检测到活动", language: language)
    }

    public var categoryIdentifier: String {
        "sentry_alert"
    }
}
