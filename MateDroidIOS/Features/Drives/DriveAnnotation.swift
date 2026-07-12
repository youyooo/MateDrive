import Foundation

public enum DriveClassification: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case unclassified, commute, personal, business, roadTrip, custom
    public var id: String { rawValue }

    public func title(language: AppLanguage) -> String {
        let key: String
        let chinese: String
        switch self {
        case .unclassified: (key, chinese) = ("Unclassified", "未分类")
        case .commute: (key, chinese) = ("Commute", "通勤")
        case .personal: (key, chinese) = ("Personal", "个人")
        case .business: (key, chinese) = ("Business", "商务")
        case .roadTrip: (key, chinese) = ("Road Trip", "长途")
        case .custom: (key, chinese) = ("Custom", "自定义")
        }
        return AppText.localized(key, chinese, language: language)
    }
}

public struct DriveAnnotation: Codable, Equatable, Sendable {
    public var classification: DriveClassification
    public var customLabel: String
    public var note: String

    public init(classification: DriveClassification = .unclassified, customLabel: String = "", note: String = "") {
        self.classification = classification
        self.customLabel = customLabel
        self.note = note
    }

    public var isEmpty: Bool {
        classification == .unclassified && customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func displayLabel(language: AppLanguage) -> String {
        if classification == .custom {
            let value = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return classification.title(language: language)
    }
}

public enum DriveCSVExporter {
    public static func csv(detail: DriveDetail, stats: DriveDetailStats?, annotation: DriveAnnotation, units: UnitPreferences?) -> String {
        let rows: [(String, String)] = [
            ("drive_id", String(detail.driveId)),
            ("start_date", detail.startDate ?? ""),
            ("end_date", detail.endDate ?? ""),
            ("start_address", detail.startAddress ?? ""),
            ("end_address", detail.endAddress ?? ""),
            ("distance_km", number(stats?.distance ?? detail.distance)),
            ("duration_min", stats?.durationMin.map(String.init) ?? ""),
            ("average_speed_kmh", number(stats?.speedAvg)),
            ("max_speed_kmh", stats?.speedMax.map(String.init) ?? ""),
            ("energy_kwh", number(stats?.energyUsed)),
            ("efficiency_wh_km", number(stats?.efficiency)),
            ("classification", annotation.classification.rawValue),
            ("custom_label", annotation.customLabel),
            ("note", annotation.note),
            ("unit_of_length", units?.unitOfLength ?? "km")
        ]
        return "field,value\n" + rows.map { "\(escape($0.0)),\(escape($0.1))" }.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String { value.map { String(format: "%.6f", $0) } ?? "" }
    private static func escape(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
