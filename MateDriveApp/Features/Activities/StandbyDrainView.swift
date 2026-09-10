import SwiftUI

public struct StandbyDrainView: View {
    @Environment(\.appLanguage) private var appLanguage
    @StateObject private var viewModel: StandbyDrainViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let latitude: Double
    private let longitude: Double
    private let placeName: String?
    private let preferredUnits: UnitPreferences?

    public init(carId: Int, latitude: Double, longitude: Double, placeName: String?, preferredUnits: UnitPreferences? = nil, viewModel: StandbyDrainViewModel) {
        self.carId = carId
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.preferredUnits = preferredUnits
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, !viewModel.state.hasLoadedData {
                LoadingStateView(title: t("Loading standby drain", "正在加载待机损耗"), showsProgress: true)
            } else if let data = viewModel.state.data {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = viewModel.state.errorMessage {
                            refreshWarning(error)
                        }
                        if let placeName, !placeName.isEmpty {
                            Text(verbatim: placeName).font(.title3.weight(.semibold))
                        }
                        scopeNotice(data)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                            MetricCard(title: t("Range Loss", "续航损耗"), value: distance(data.totalRangeLossKm), systemImage: "battery.25percent")
                            MetricCard(title: t("24h Battery Change", "24 小时电量变化"), value: percent(data.averageDrainPercent24H), systemImage: "percent")
                            MetricCard(title: t("Average Drain Rate", "平均损耗速率"), value: rate(data.averageDrainRateKmH), systemImage: "gauge.with.dots.needle.33percent")
                            MetricCard(title: t("Maximum Drain Rate", "最高损耗速率"), value: rate(data.maximumDrainRateKmH), systemImage: "arrow.up")
                            MetricCard(title: t("Minimum Drain Rate", "最低损耗速率"), value: rate(data.minimumDrainRateKmH), systemImage: "arrow.down")
                            MetricCard(title: t("Parking Events", "停车次数"), value: count(data.totalParkingEvents), systemImage: "parkingsign.circle")
                            MetricCard(title: t("Parking Days", "停车天数"), value: days(data.totalParkingDays), systemImage: "calendar")
                        }
                        Text(t(
                            "Standby drain is calculated by TeslaMateApi from parking records near this location. It does not measure battery cell degradation.",
                            "待机损耗由特斯拉数据接口根据该地点附近的停车记录计算，不代表电芯健康度或电池衰减。"
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .refreshable { await load() }
            } else {
                LoadingStateView(
                    title: t("Standby drain unavailable", "待机损耗不可用"),
                    message: unavailableMessage,
                    systemImage: "moon.zzz"
                )
            }
        }
        .navigationTitle(t("Standby Drain", "待机损耗"))
        .accessibilityIdentifier("standby_drain_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await load()
        }
    }

    private func scopeNotice(_ data: StandbyDrainData) -> some View {
        let period = data.periodDays.map { t("Last \($0) days", "最近 \($0) 天") } ?? t("Server period", "服务端统计周期")
        let radius = data.radiusMeters.map { MateDriveUnitFormatter.formatDistance($0 / 1_000, units: effectiveUnits, decimals: 1) } ?? "--"
        return Label("\(period) · " + t("within \(radius)", "\(radius) 范围内"), systemImage: "mappin.and.ellipse")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func load() async {
        await viewModel.load(carId: carId, latitude: latitude, longitude: longitude)
    }

    private func refreshWarning(_ error: String) -> some View {
        Label(
            UserFacingErrorLocalizer.localized(error, language: appLanguage),
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .accessibilityIdentifier("standby_drain_refresh_warning")
    }

    private var unavailableMessage: String {
        guard let error = viewModel.state.errorMessage else {
            return t("No standby drain data was returned for this location.", "该地点没有返回待机损耗数据。")
        }
        return UserFacingErrorLocalizer.localized(error, language: appLanguage)
    }

    private func distance(_ value: Double?) -> String {
        guard let value else { return "--" }
        return MateDriveUnitFormatter.formatDistance(value, units: effectiveUnits, decimals: 1)
    }

    private func rate(_ value: Double?) -> String {
        guard let value else { return "--" }
        let converted = MateDriveUnitFormatter.distanceValue(value, units: effectiveUnits)
        return String(format: "%.2f %@/h", converted, MateDriveUnitFormatter.distanceUnit(units: effectiveUnits))
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%+.1f%%", value)
    }

    private func count(_ value: Int?) -> String {
        value.map(String.init) ?? "--"
    }

    private func days(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }

    private var effectiveUnits: UnitPreferences? {
        let serverUnits = viewModel.state.units.map { UnitPreferences(unitOfLength: $0.length) }
        return UnitPreferences.resolved(preferredUnits ?? serverUnits, for: appLanguage)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
