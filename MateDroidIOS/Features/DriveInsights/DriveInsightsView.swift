import SwiftUI

public struct DriveInsightsView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DriveInsightsViewModel
    @State private var hasLoaded = false
    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: DriveInsightsViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading drive insights", "正在加载行程洞察"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage {
                LoadingStateView(title: t("Drive insights unavailable", "行程洞察不可用"), message: error, systemImage: "chart.line.text.clipboard")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        filter
                        routes
                        evaluations
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Drive Insights", "行程洞察"))
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var filter: some View {
        Picker(t("Routes", "路线"), selection: Binding(get: { viewModel.state.filter }, set: { viewModel.setFilter($0) })) {
            Text(t("Repeated", "重复路线")).tag(DriveInsightFilter.repeated)
            Text(t("All", "全部")).tag(DriveInsightFilter.all)
        }
        .pickerStyle(.segmented)
    }

    private var routes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Route Groups", "路线分组")).font(.headline)
            ForEach(viewModel.visibleRoutes) { item in
                Button {
                    if let driveId = item.latestDriveId {
                        navigate(.driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(routeText(item.insight)).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                            Spacer()
                            Text("\(item.insight.driveCount ?? 0) " + t("drives", "次"))
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 14) {
                            metric(t("Average Distance", "平均距离"), distance(item.insight.avgDistanceKm))
                            metric(t("Average Duration", "平均时长"), duration(item.insight.avgDurationMin))
                            metric(t("Average Energy", "平均能耗"), energy(item.insight.avgEnergyKwh))
                        }
                        HStack {
                            Text(t("Consumption", "电耗") + ": " + efficiency(item.insight.consumptionWhKm))
                            Spacer()
                            if item.latestDriveId != nil { Image(systemName: "chevron.right") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .disabled(item.latestDriveId == nil)
            }
        }
    }

    @ViewBuilder
    private var evaluations: some View {
        if !viewModel.state.evaluations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Server Evaluations", "服务端驾驶评价")).font(.headline)
                Text(t("These evaluations come from TeslaMate API; MateDrive does not calculate a separate driving score.", "以下评价来自 TeslaMate API；MateDrive 不会自行编造驾驶评分。"))
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(viewModel.state.evaluations) { item in
                    Button { navigate(.driveDetail(carId: carId, driveId: item.driveId, exteriorColor: exteriorColor)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: evaluationIcon(item.evaluation.type)).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(evaluationTitle(item.evaluation.type)).font(.body.weight(.semibold))
                                Text(date(item.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(value).font(.caption.weight(.semibold)) }
    }
    private func routeText(_ item: TeslaMateRouteInsight) -> String { "\(item.startAddress ?? t("Unknown", "未知")) → \(item.endAddress ?? t("Unknown", "未知"))" }
    private func distance(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDistance($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem)) } ?? "--" }
    private func duration(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) " + t("min", "分钟") } ?? "--" }
    private func energy(_ value: Double?) -> String { value.map { String(format: "%.1f kWh", abs($0)) } ?? "--" }
    private func efficiency(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatEfficiency($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem), decimals: 0) } ?? "--" }
    private func date(_ value: String?) -> String { value.flatMap(DomainDateParser.date(from:))?.formatted(date: .abbreviated, time: .shortened) ?? "--" }

    private func evaluationTitle(_ type: String) -> String {
        switch type {
        case "safety_distance": t("Safety Distance", "安全车距")
        case "low_temp_regen": t("Cold-weather Regen", "低温能量回收")
        case "golden_foot": t("Efficient Driving", "高效驾驶")
        case "rush_hour_comfort": t("Rush-hour Comfort", "高峰舒适度")
        case "elevation_insight": t("Elevation Impact", "海拔影响")
        case "short_trip_hvac": t("Short-trip Climate Use", "短途空调使用")
        default: t("Drive Evaluation", "驾驶评价")
        }
    }
    private func evaluationIcon(_ type: String) -> String { type == "golden_foot" ? "leaf.fill" : type == "elevation_insight" ? "mountain.2.fill" : "info.circle.fill" }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}
