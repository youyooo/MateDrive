import Foundation

public struct ChargeLiveActivityPresentation: Equatable, Sendable {
    public let carName: String
    public let statusText: String
    public let batteryLabelText: String
    public let batteryText: String
    public let limitText: String?
    public let powerText: String?
    public let energyText: String?
    public let remainingText: String?
    public let updatedText: String
    public let progress: WidgetChargeProgress?
    public let isStale: Bool
    public let accessibilityText: String

    public static func make(
        attributes: ChargeLiveActivityAttributes,
        state: ChargeLiveActivityAttributes.ContentState,
        isStale: Bool
    ) -> Self {
        let language = state.displayLanguage
        let statusText = localizedStatus(
            isCharging: state.isCharging,
            isDC: state.isDC,
            quality: state.quality,
            isStale: isStale,
            language: language
        )
        let batteryLabelText = language.value(
            english: "Battery",
            chinese: "电量",
            traditionalChinese: "電量"
        )
        let batteryText = state.batteryLevel.map { "\($0)%" } ?? "--"
        let limitText = state.chargeLimitSoc.map { value in
            language.value(
                english: "Limit \(value)%",
                chinese: "目标 \(value)%",
                traditionalChinese: "目標 \(value)%"
            )
        }
        let powerText = state.chargerPowerKW.map { "\($0) kW" }
        let energyText = state.energyAddedKWh.map { String(format: "%.1f kWh", $0) }
        let remainingText = state.timeToFullMinutes.map { minutes in
            let duration = localizedDuration(minutes, language: language)
            return language.value(
                english: "\(duration) remaining",
                chinese: "剩余 \(duration)",
                traditionalChinese: "剩餘 \(duration)"
            )
        }
        let updatedText = language.value(
            english: "Updated \(localizedTime(state.updatedAt, language: language))",
            chinese: "更新于 \(localizedTime(state.updatedAt, language: language))",
            traditionalChinese: "更新於 \(localizedTime(state.updatedAt, language: language))"
        )
        let progress: WidgetChargeProgress?
        if state.isCharging,
           let batteryLevel = state.batteryLevel,
           let chargeLimitSoc = state.chargeLimitSoc,
           chargeLimitSoc > 0 {
            let total = min(chargeLimitSoc, 100)
            progress = WidgetChargeProgress(
                current: min(max(batteryLevel, 0), total),
                total: total
            )
        } else {
            progress = nil
        }
        let accessibilityText = [
            attributes.carName,
            statusText,
            batteryLabelText,
            batteryText,
            limitText,
            powerText,
            energyText,
            remainingText,
            updatedText
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return Self(
            carName: attributes.carName,
            statusText: statusText,
            batteryLabelText: batteryLabelText,
            batteryText: batteryText,
            limitText: limitText,
            powerText: powerText,
            energyText: energyText,
            remainingText: remainingText,
            updatedText: updatedText,
            progress: progress,
            isStale: isStale,
            accessibilityText: accessibilityText
        )
    }

    private static func localizedStatus(
        isCharging: Bool,
        isDC: Bool,
        quality: WidgetChargeDataQuality,
        isStale: Bool,
        language: WidgetDisplayLanguage
    ) -> String {
        if quality == .offline {
            return language.value(
                english: "Offline",
                chinese: "离线",
                traditionalChinese: "離線"
            )
        }
        if isStale {
            return language.value(
                english: "Update pending",
                chinese: "等待更新",
                traditionalChinese: "等待更新"
            )
        }
        if quality == .partial {
            return language.value(
                english: "Partial data",
                chinese: "部分数据待更新",
                traditionalChinese: "部分資料待更新"
            )
        }
        guard isCharging else {
            return language.value(
                english: "Not charging",
                chinese: "未充电",
                traditionalChinese: "未充電"
            )
        }
        if isDC {
            return language.value(
                english: "DC charging",
                chinese: "直流充电",
                traditionalChinese: "直流充電"
            )
        }
        return language.value(
            english: "AC charging",
            chinese: "交流充电",
            traditionalChinese: "交流充電"
        )
    }

    private static func localizedDuration(
        _ totalMinutes: Int,
        language: WidgetDisplayLanguage
    ) -> String {
        let minutes = max(totalMinutes, 0)
        guard minutes >= 60 else {
            return language.value(
                english: "\(minutes)m",
                chinese: "\(minutes)分钟",
                traditionalChinese: "\(minutes)分鐘"
            )
        }

        let hours = minutes / 60
        let remainingMinutes = String(format: "%02d", minutes % 60)
        return language.value(
            english: "\(hours)h \(remainingMinutes)m",
            chinese: "\(hours)小时\(remainingMinutes)分钟",
            traditionalChinese: "\(hours)小時\(remainingMinutes)分鐘"
        )
    }

    private static func localizedTime(
        _ date: Date,
        language: WidgetDisplayLanguage
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.value(
            english: "en_US",
            chinese: "zh_Hans_CN",
            traditionalChinese: "zh_Hant_TW"
        ))
        formatter.setLocalizedDateFormatFromTemplate("Hm")
        return formatter.string(from: date)
    }
}
