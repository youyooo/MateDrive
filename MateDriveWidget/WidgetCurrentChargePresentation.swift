import Foundation

public enum WidgetChargeVisualState: Equatable, Sendable {
    case charging
    case starting
    case idle
    case offline
    case stale
    case unavailable
}

public struct WidgetChargeProgress: Equatable, Sendable {
    public let current: Int
    public let total: Int

    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }
}

public struct WidgetCurrentChargePresentation: Equatable, Sendable {
    public let state: WidgetChargeVisualState
    public let carName: String
    public let statusText: String
    public let batteryText: String
    public let limitText: String?
    public let powerText: String?
    public let energyText: String?
    public let remainingText: String?
    public let updatedText: String?
    public let trustText: String?
    public let progress: WidgetChargeProgress?
    public let chargeTypeText: String?
    public let accessibilityText: String

    public static func make(
        snapshot: WidgetVehicleSnapshot?,
        configuredVehicleName: String?,
        now: Date
    ) -> Self {
        let language = snapshot?.data.displayLanguage ?? .system
        let carName = resolvedCarName(
            snapshotName: snapshot?.data.carName,
            configuredVehicleName: configuredVehicleName
        )

        guard let charge = snapshot?.currentCharge else {
            let recovery = language.value(
                english: "Open MateDrive to sync",
                chinese: "打开 MateDrive 同步",
                traditionalChinese: "開啟 MateDrive 同步"
            )
            return Self(
                state: .unavailable,
                carName: carName,
                statusText: recovery,
                batteryText: "--",
                limitText: nil,
                powerText: nil,
                energyText: nil,
                remainingText: nil,
                updatedText: nil,
                trustText: nil,
                progress: nil,
                chargeTypeText: nil,
                accessibilityText: "\(carName), \(recovery)"
            )
        }

        let state = visualState(for: charge, now: now)
        let status = localizedStatus(state, language: language)
        let battery = charge.batteryLevel.map { "\($0)%" } ?? "--"
        let limit = charge.chargeLimitSoc.map { value in
            language.value(
                english: "Limit \(value)%",
                chinese: "目标 \(value)%",
                traditionalChinese: "目標 \(value)%"
            )
        }
        let power = charge.chargerPowerKW.map { "\($0) kW" }
        let energy = charge.energyAddedKWh.map { String(format: "%.1f kWh", $0) }
        let remaining = charge.timeToFullMinutes.map { minutes in
            let duration = localizedDuration(minutes, language: language)
            return language.value(
                english: "\(duration) remaining",
                chinese: "剩余 \(duration)",
                traditionalChinese: "剩餘 \(duration)"
            )
        }
        let ageSeconds = max(0, Int(now.timeIntervalSince(charge.updatedAt).rounded(.down)))
        let updatedDuration = localizedDuration(ageSeconds / 60, language: language)
        let updated = language.value(
            english: "Updated \(updatedDuration)",
            chinese: "更新于 \(updatedDuration)",
            traditionalChinese: "更新於 \(updatedDuration)"
        )
        let trust = charge.quality == .partial
            ? language.value(
                english: "Partial data",
                chinese: "部分数据待更新",
                traditionalChinese: "部分資料待更新"
            )
            : nil

        let suppressChargeMetrics = charge.phase == .idle
        let visibleLimit = suppressChargeMetrics ? nil : limit
        let visiblePower = suppressChargeMetrics ? nil : power
        let visibleEnergy = suppressChargeMetrics ? nil : energy
        let visibleRemaining = suppressChargeMetrics ? nil : remaining
        let progress: WidgetChargeProgress?
        if !suppressChargeMetrics,
           let current = charge.batteryLevel,
           let total = charge.chargeLimitSoc,
           total > 0 {
            progress = WidgetChargeProgress(current: current, total: total)
        } else {
            progress = nil
        }
        let chargeType = suppressChargeMetrics
            ? nil
            : charge.isDC.map { $0 ? "DC" : "AC" }
        let accessibility = [
            carName,
            status,
            trust,
            battery,
            visibleLimit,
            chargeType,
            visiblePower,
            visibleEnergy,
            visibleRemaining,
            updated
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return Self(
            state: state,
            carName: carName,
            statusText: status,
            batteryText: battery,
            limitText: visibleLimit,
            powerText: visiblePower,
            energyText: visibleEnergy,
            remainingText: visibleRemaining,
            updatedText: updated,
            trustText: trust,
            progress: progress,
            chargeTypeText: chargeType,
            accessibilityText: accessibility
        )
    }

    private static func resolvedCarName(
        snapshotName: String?,
        configuredVehicleName: String?
    ) -> String {
        if let snapshotName {
            let trimmed = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let configuredVehicleName {
            let trimmed = configuredVehicleName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "MateDrive"
    }

    private static func visualState(
        for charge: WidgetCurrentChargeData,
        now: Date
    ) -> WidgetChargeVisualState {
        if charge.quality == .offline {
            return .offline
        }
        if charge.isStale(at: now) {
            return .stale
        }
        switch charge.phase {
        case .charging:
            return .charging
        case .starting:
            return .starting
        case .idle:
            return .idle
        }
    }

    private static func localizedStatus(
        _ state: WidgetChargeVisualState,
        language: WidgetDisplayLanguage
    ) -> String {
        switch state {
        case .charging:
            return language.value(
                english: "Charging",
                chinese: "正在充电",
                traditionalChinese: "正在充電"
            )
        case .starting:
            return language.value(
                english: "Starting charge",
                chinese: "准备充电",
                traditionalChinese: "準備充電"
            )
        case .idle:
            return language.value(
                english: "Not charging",
                chinese: "未充电",
                traditionalChinese: "未充電"
            )
        case .offline:
            return language.value(
                english: "Offline",
                chinese: "离线",
                traditionalChinese: "離線"
            )
        case .stale:
            return language.value(
                english: "Data may be out of date",
                chinese: "数据可能已过期",
                traditionalChinese: "資料可能已過期"
            )
        case .unavailable:
            return language.value(
                english: "Open MateDrive to sync",
                chinese: "打开 MateDrive 同步",
                traditionalChinese: "開啟 MateDrive 同步"
            )
        }
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
        let remainingMinutes = minutes % 60
        let paddedMinutes = String(format: "%02d", remainingMinutes)
        return language.value(
            english: "\(hours)h \(paddedMinutes)m",
            chinese: "\(hours)小时\(paddedMinutes)分钟",
            traditionalChinese: "\(hours)小時\(paddedMinutes)分鐘"
        )
    }
}
