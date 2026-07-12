import SwiftUI

public struct DrivingRecordsView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DrivingRecordsViewModel
    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: DrivingRecordsViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.navigate = navigate
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.records.isEmpty {
                LoadingStateView(title: t("Loading driving records", "正在加载驾驶纪录"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.records.isEmpty {
                LoadingStateView(title: t("Driving records unavailable", "驾驶纪录不可用"), message: error, systemImage: "trophy")
            } else if viewModel.state.records.isEmpty {
                ContentUnavailableView(t("No driving records", "暂无驾驶纪录"), systemImage: "trophy", description: Text(t("TeslaMateApi returned no extreme statistics.", "特斯拉数据接口没有返回极值统计。")))
            } else {
                recordList
            }
        }
        .navigationTitle(t("Driving Records", "驾驶纪录"))
        .task { await viewModel.load(carId: carId) }
    }

    private var recordList: some View {
        List {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            Section {
                Text(t("Values come directly from TeslaMateApi. MateDrive converts display units but does not rewrite unusual server values.", "数值直接来自特斯拉数据接口。MateDrive 只转换显示单位，不会改写服务端返回的异常数值。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(t("Records", "纪录")) {
                ForEach(viewModel.state.records) { record in
                    Button { open(record) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: icon(record.type)).foregroundStyle(.blue).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(record.type)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(recordDate(record.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(value(record)).font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(.primary)
                            if record.driveId != nil {
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }.padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                    .disabled(record.driveId == nil)
                }
            }
        }
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var units: UnitPreferences? {
        UnitPreferences(unitOfLength: viewModel.state.units?.unitOfLength, unitOfTemperature: viewModel.state.units?.unitOfTemperature).resolved(for: appDisplayUnitSystem)
    }
    private func open(_ record: StatsExtreme) {
        guard let driveId = record.driveId else { return }
        navigate(.driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor))
    }
    private func value(_ record: StatsExtreme) -> String {
        guard let value = record.value else { return "--" }
        switch record.type {
        case "longest_distance", "daily_most_distance": return MateDroidUnitFormatter.formatDistance(value, units: units, decimals: 1)
        case "longest_duration": return MateDroidUnitFormatter.formatDuration(minutes: Int(value.rounded()), language: appLanguage)
        case "highest_speed": return MateDroidUnitFormatter.formatSpeed(value, units: units, decimals: 0)
        case "highest_elevation_gain": return MateDroidUnitFormatter.formatElevation(Int(value.rounded()), units: units)
        case "hottest_day", "coldest_day": return MateDroidUnitFormatter.formatTemperature(value, units: units, decimals: 1)
        case "daily_most_drives": return t("\(Int(value.rounded())) drives", "\(Int(value.rounded())) 次行程")
        default:
            let suffix = record.unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return suffix.isEmpty ? String(format: "%.1f", value) : String(format: "%.1f %@", value, suffix)
        }
    }
    private func recordDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return t("Date unavailable", "日期不可用") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    private func title(_ type: String) -> String {
        switch type {
        case "longest_distance": t("Longest Drive", "最长行程")
        case "longest_duration": t("Longest Duration", "最长耗时")
        case "highest_speed": t("Highest Speed", "最高速度")
        case "highest_power": t("Highest Power", "最高功率")
        case "highest_elevation_gain": t("Highest Elevation Gain", "最大累计爬升")
        case "hottest_day": t("Hottest Drive", "最热行程")
        case "coldest_day": t("Coldest Drive", "最冷行程")
        case "most_efficient": t("Most Efficient", "最高效率")
        case "daily_most_distance": t("Most Distance in a Day", "单日最多里程")
        case "daily_most_drives": t("Most Drives in a Day", "单日最多行程")
        default: type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    private func icon(_ type: String) -> String {
        switch type {
        case "longest_distance", "daily_most_distance": "road.lanes"
        case "longest_duration": "clock"
        case "highest_speed": "speedometer"
        case "highest_power": "bolt.fill"
        case "highest_elevation_gain": "mountain.2"
        case "hottest_day": "thermometer.high"
        case "coldest_day": "thermometer.low"
        case "most_efficient": "leaf"
        case "daily_most_drives": "car.2"
        default: "trophy"
        }
    }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}
