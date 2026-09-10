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
            if viewModel.state.isLoading, !hasContent {
                LoadingStateView(title: t("Loading drive insights", "正在加载行程洞察"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, !hasContent {
                LoadingStateView(
                    title: t("Drive insights unavailable", "行程洞察不可用"),
                    message: error,
                    systemImage: "chart.line.text.clipboard",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId) } }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(error, language: appLanguage),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                        drivingScore
                        filter
                        routes
                        evaluations
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Drive Insights", "行程洞察"))
        .accessibilityIdentifier("drive_insights_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var hasContent: Bool {
        !viewModel.state.routes.isEmpty
            || !viewModel.state.evaluations.isEmpty
            || viewModel.state.drivingScore != nil
    }

    @ViewBuilder
    private var drivingScore: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Recent Driving Score", "近期驾驶评分"))
                .font(.headline)

            if let score = viewModel.state.drivingScore {
                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: Double(score.overall) / 100)
                            .stroke(scoreColor(score.overall), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(score.overall)")
                                .font(.title.bold())
                            Text("/100")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 94, height: 94)

                    VStack(alignment: .leading, spacing: 7) {
                        Label(confidenceTitle(score.confidenceLevel), systemImage: "checkmark.shield")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: Double(score.confidence), total: 100)
                            .tint(confidenceColor(score.confidenceLevel))
                        Text(String(format: t("Confidence %d%% · %d recent drives", "置信度 %d%% · 近期 %d 次行程"), score.confidence, score.totalDriveCount))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 10) {
                    ForEach(score.components, id: \.kind) { component in
                        scoreComponent(component, totalDriveCount: score.totalDriveCount)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text(t("Recommendations", "驾驶建议"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(score.recommendations, id: \.self) { recommendation in
                        Label(recommendationText(recommendation), systemImage: recommendationIcon(recommendation))
                            .font(.subheadline)
                            .foregroundStyle(recommendation == .keepSteady ? .green : .primary)
                    }
                }

                Text(t(
                    "Calculated only from available TeslaMate API samples. Missing metrics are excluded instead of scored as zero; this is not Tesla's Safety Score.",
                    "仅使用服务器已记录的有效样本计算；缺失指标会被排除，不会按 0 分处理。本评分并非特斯拉官方安全评分。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Label(t("No reliable data", "暂无可靠数据"), systemImage: "chart.line.downtrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                Text(t(
                    "Hard-braking frequency or regenerative-utilization samples are required. Missing data is not converted into a score.",
                    "至少需要急刹频率或能量回收利用率样本；缺失数据不会被转换为评分。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func scoreComponent(_ component: DriveInsightScoreComponent, totalDriveCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(componentTitle(component.kind), systemImage: component.kind == .safety ? "shield.checkered" : "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(component.score)/100")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            ProgressView(value: Double(component.score), total: 100)
                .tint(scoreColor(component.score))
            HStack {
                Text(componentValue(component))
                Spacer()
                Text(String(format: t("%d/%d drives recorded", "%d/%d 次行程有记录"), component.observedDriveCount, totalDriveCount))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func componentTitle(_ kind: DriveInsightScoreComponentKind) -> String {
        kind == .safety ? t("Braking Smoothness", "制动平稳度") : t("Regeneration", "能量回收")
    }

    private func componentValue(_ component: DriveInsightScoreComponent) -> String {
        switch component.kind {
        case .safety:
            return String(format: t("%.1f hard brakes/100 km", "每百公里 %.1f 次急刹"), component.averageValue)
        case .regeneration:
            return String(format: t("%.0f%% utilization", "利用率 %.0f%%"), component.averageValue)
        }
    }

    private func confidenceTitle(_ level: DriveInsightConfidenceLevel) -> String {
        switch level {
        case .low: t("Low Confidence", "低置信度")
        case .medium: t("Medium Confidence", "中等置信度")
        case .high: t("High Confidence", "高置信度")
        }
    }

    private func recommendationText(_ recommendation: DriveInsightRecommendation) -> String {
        switch recommendation {
        case .smootherBraking:
            t("Increase following distance and anticipate slowing traffic to reduce hard braking.", "增加跟车距离并提前观察减速车流，减少急刹。")
        case .increaseRegeneration:
            t("Release the accelerator earlier and more smoothly to use more regenerative braking.", "更早、更平顺地松开加速踏板，提高能量回收利用率。")
        case .preconditionBattery:
            t("Precondition the battery before cold-weather drives when regeneration is limited.", "低温且能量回收受限时，建议出发前预热电池。")
        case .checkTirePressure:
            t("Check all four tyres; the recorded pressure difference is larger than 0.25 bar.", "检查四轮胎压，记录到的胎压差已达到 0.25 巴。")
        case .improveCoverage:
            t("Record more complete drives before treating this score as a stable trend.", "继续积累完整行程后，再将该评分视为稳定趋势。")
        case .keepSteady:
            t("Recent recorded metrics are balanced. Keep the same smooth driving pattern.", "近期已记录指标较均衡，保持当前平顺驾驶方式。")
        }
    }

    private func recommendationIcon(_ recommendation: DriveInsightRecommendation) -> String {
        switch recommendation {
        case .smootherBraking: "car.side.rear.and.collision.and.car.side.front"
        case .increaseRegeneration: "leaf"
        case .preconditionBattery: "thermometer.medium"
        case .checkTirePressure: "tirepressure"
        case .improveCoverage: "chart.bar.doc.horizontal"
        case .keepSteady: "checkmark.circle.fill"
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 75 ? .green : score >= 50 ? .orange : .red
    }

    private func confidenceColor(_ level: DriveInsightConfidenceLevel) -> Color {
        switch level {
        case .low: .red
        case .medium: .orange
        case .high: .green
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
                Text(t("These evaluations come directly from TeslaMate API and remain separate from MateDrive's transparent recent-driving score.", "以下评价直接来自 TeslaMate API，并与 MateDrive 的透明近期驾驶评分分开显示。"))
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
    private func distance(_ value: Double?) -> String { value.map { MateDriveUnitFormatter.formatDistance($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem)) } ?? "--" }
    private func duration(_ value: Double?) -> String { value.map { "\(Int($0.rounded())) " + t("min", "分钟") } ?? "--" }
    private func energy(_ value: Double?) -> String { value.map { String(format: "%.1f kWh", abs($0)) } ?? "--" }
    private func efficiency(_ value: Double?) -> String { value.map { MateDriveUnitFormatter.formatEfficiency($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem), decimals: 0) } ?? "--" }
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
