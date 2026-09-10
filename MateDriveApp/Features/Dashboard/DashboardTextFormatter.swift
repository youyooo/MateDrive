import Foundation

public enum DashboardTextFormatter {
    public static func title(_ key: String, language: AppLanguage) -> String {
        guard MateDriveUnitFormatter.usesChineseLabels(language: language) else {
            return key
        }

        switch key {
        case "Charging":
            return "充电状态"
        case "Lock":
            return "门锁"
        case "Sentry":
            return "哨兵模式"
        case "Outside":
            return "车外"
        case "Inside":
            return "车内"
        case "History":
            return "历史"
        case "Location":
            return "位置"
        case "Odometer":
            return "里程表"
        case "Software":
            return "软件版本"
        case "Current Charge":
            return "当前充电"
        case "Charges":
            return "充电记录"
        case "Drives":
            return "行程"
        case "Recent Driving Map":
            return "近期行驶地图"
        case "Activities":
            return "活动"
        case "Place Insights":
            return "地点洞察"
        case "Achievements":
            return "成就"
        case "Drive":
            return "行程"
        case "Distance":
            return "距离"
        case "Energy":
            return "能量"
        case "Energy Added":
            return "补能"
        case "Charge Cost":
            return "充电费用"
        case "Cost":
            return "费用"
        case "Average":
            return "平均"
        case "Records":
            return "记录"
        case "Longest Drive":
            return "最长行程"
        case "Most Efficient":
            return "最高效"
        case "AC / DC":
            return "交流 / 直流"
        case "Capacity Now":
            return "当前容量"
        case "Capacity New":
            return "新车容量"
        case "Capacity Loss":
            return "容量损耗"
        case "Range Now":
            return "当前续航"
        case "Range New":
            return "新车续航"
        case "Range Loss":
            return "续航损耗"
        case "Current SOC":
            return "当前电量"
        case "Usable SOC":
            return "可用电量"
        case "Rated Range":
            return "额定续航"
        case "At 100%":
            return "满电续航"
        case "Efficiency":
            return "效率"
        case "Trips":
            return "旅程"
        case "Stats":
            return "统计"
        case "Drive Insights":
            return "行程洞察"
        case "Battery":
            return "电池"
        case "Battery Health":
            return "电池健康"
        case "Health Source":
            return "健康来源"
        case "Health Confidence":
            return "健康可信度"
        case "Recording Start Odometer":
            return "开始记录时里程表"
        case "Mileage":
            return "里程"
        case "Updates":
            return "软件更新"
        case "Settings":
            return "设置"
        case "Palette":
            return "车漆"
        case "Environment History":
            return "环境与胎压"
        case "Standby Hotspots":
            return "待机耗电热点"
        case "Commute Routes":
            return "通勤路线"
        default:
            return key
        }
    }

    public static func statusLine(isCharging: Bool, sentryModeActive: Bool, language: AppLanguage) -> String {
        if isCharging {
            return localized("Charging", "正在充电", language: language)
        }
        if sentryModeActive {
            return localized("Sentry active", "哨兵模式已开启", language: language)
        }
        return localized("Ready", "就绪", language: language)
    }

    public static func chargingValue(isCharging: Bool, language: AppLanguage) -> String {
        isCharging ? localized("Active", "正在充电", language: language) : localized("Idle", "空闲", language: language)
    }

    public static func currentChargeSubtitle(isCharging: Bool, language: AppLanguage) -> String? {
        isCharging ? localized("Current session in progress", "当前充电中", language: language) : nil
    }

    public static func sentryValue(isActive: Bool, language: AppLanguage) -> String {
        localized(isActive ? "On" : "Off", isActive ? "开启" : "关闭", language: language)
    }

    public static func sessionValue(isActive: Bool, language: AppLanguage) -> String {
        localized(isActive ? "Active" : "Inactive", isActive ? "开启" : "关闭", language: language)
    }

    public static func lockText(_ isLocked: Bool?, language: AppLanguage) -> String {
        guard let isLocked else {
            return localized("Unknown", "未知", language: language)
        }
        return localized(isLocked ? "Locked" : "Unlocked", isLocked ? "已锁定" : "已解锁", language: language)
    }

    public static func historyText(charges: Int?, drives: Int?, language: AppLanguage) -> String {
        let labels = dynamicCountLabels(language: language)
        switch (charges, drives) {
        case let (charges?, drives?):
            return "\(charges) \(labels.charge) / \(drives) \(labels.drive)"
        case let (charges?, nil):
            return "\(charges) \(labels.charge)"
        case let (nil, drives?):
            return "\(drives) \(labels.drive)"
        default:
            return "--"
        }
    }

    public static func updatesText(_ updates: Int?, language: AppLanguage) -> String? {
        guard let updates else { return nil }
        switch resolvedDynamicLanguage(language) {
        case .chinese:
            return "\(updates) 次软件更新"
        case .traditionalChinese:
            return "\(updates) 次軟體更新"
        case .english, .system:
            return updates == 1 ? "1 software update" : "\(updates) software updates"
        }
    }

    private static func dynamicCountLabels(language: AppLanguage) -> (charge: String, drive: String) {
        switch resolvedDynamicLanguage(language) {
        case .chinese:
            return ("次充电", "次行程")
        case .traditionalChinese:
            return ("次充電", "次行程")
        case .english, .system:
            return ("charges", "drives")
        }
    }

    private static func resolvedDynamicLanguage(_ language: AppLanguage) -> AppLanguage {
        guard language == .system else { return language }
        let preferred = Locale.preferredLanguages.first?.replacingOccurrences(of: "_", with: "-") ?? ""
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") || preferred.hasPrefix("zh-MO") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") { return .chinese }
        return .english
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}
