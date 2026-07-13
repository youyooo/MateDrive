import Foundation

public enum UserFacingErrorLocalizer {
    public static func localizedOptional(_ message: String?, language: AppLanguage) -> String? {
        guard let rawMessage = message, !rawMessage.isEmpty else {
            return message
        }
        return localized(rawMessage, language: language)
    }

    public static func localized(_ message: String, language: AppLanguage) -> String {
        guard MateDroidUnitFormatter.usesChineseLabels(language: language) else {
            return message
        }

        if message == "Invalid date" {
            return "日期无效。"
        }
        if message == "No TeslaMate cars were returned." {
            return "TeslaMate 没有返回车辆。"
        }
        if message == "TeslaMate returned an empty response." {
            return "TeslaMate 返回了空响应。"
        }

        let exactMappings: [String: String] = [
            "The operation couldn’t be completed.": "操作未能完成。",
            "The operation could not be completed.": "操作未能完成。",
            "The Internet connection appears to be offline.": "网络连接似乎已离线。",
            "A server with the specified hostname could not be found.": "找不到指定主机名的服务器。",
            "The request timed out.": "请求超时。",
            "The network connection was lost.": "网络连接已中断。",
            "The data couldn’t be read because it isn’t in the correct format.": "数据格式不正确，无法读取。",
            "The data could not be read because it is not in the correct format.": "数据格式不正确，无法读取。",
            "Enter a valid charge cost.": "请输入有效的充电费用。",
            "Charge cost must be zero or greater.": "充电费用必须大于或等于 0。",
            "Charge cost writeback is unavailable.": "当前 TeslaMate API 不支持写回充电费用。",
            "A trip must contain at least one drive.": "一条路程必须至少包含一个驾驶分段。"
        ]
        if let localized = exactMappings[message] {
            return localized
        }

        let prefixMappings: [(String, String)] = [
            ("Configure your TeslaMate server before loading the dashboard.", "请先配置 TeslaMate 服务器，再加载首页。"),
            ("Configure your TeslaMate server before loading charges.", "请先配置 TeslaMate 服务器，再加载充电记录。"),
            ("Configure your TeslaMate server before loading drives.", "请先配置 TeslaMate 服务器，再加载行程记录。"),
            ("Configure your TeslaMate server before loading analytics.", "请先配置 TeslaMate 服务器，再加载统计数据。"),
            ("Invalid TeslaMate URL: ", "TeslaMate 地址无效："),
            ("The TeslaMate server URL is invalid: ", "TeslaMate 服务器地址无效："),
            ("SSL certificate error: ", "SSL 证书错误："),
            ("Network error: ", "网络错误："),
            ("Invalid TeslaMate response: ", "TeslaMate 响应无效："),
            ("TeslaMate returned HTTP ", "TeslaMate 返回 HTTP "),
            ("TeslaMate returned no charge data.", "TeslaMate 没有返回充电数据。"),
            ("TeslaMate returned no drive data.", "TeslaMate 没有返回行程数据。"),
            ("TeslaMate returned no analytics data.", "TeslaMate 没有返回统计数据。")
        ]

        for (english, chinese) in prefixMappings {
            if message == english {
                return chinese
            }
            if message.hasPrefix(english) {
                let suffix = String(message.dropFirst(english.count))
                if english == "TeslaMate returned HTTP " {
                    return "\(chinese)\(suffix)"
                }
                return "\(chinese)\(suffix)"
            }
        }

        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("database is locked") {
            return "本地数据库正忙，请稍后重试。"
        }
        if lowercasedMessage.contains("sqlite returned no rows") {
            return "本地数据库没有找到对应记录。"
        }
        if lowercasedMessage.contains("no such table") {
            return "本地数据库表缺失，请重新同步数据。"
        }
        if lowercasedMessage.contains("constraint failed") {
            return "本地数据保存失败：约束检查未通过。"
        }
        if lowercasedMessage.contains("sqlite open failed") {
            return "本地数据库打开失败。"
        }
        if lowercasedMessage.contains("sqlite prepare failed") {
            return "本地数据库查询准备失败。"
        }
        if lowercasedMessage.contains("sqlite bind failed") {
            return "本地数据库参数绑定失败。"
        }
        if lowercasedMessage.contains("sqlite execution failed") || lowercasedMessage.contains("sqlite") {
            return "本地数据库操作失败。"
        }

        return message
    }
}
