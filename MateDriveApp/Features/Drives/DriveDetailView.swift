import Charts
import MapKit
import SwiftUI
import UniformTypeIdentifiers

public struct DriveDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DriveDetailViewModel
    @State private var hasLoaded = false
    @State private var confirmsTripRemoval = false
    @State private var editsAnnotation = false
    @State private var exportDocument: DriveCSVDocument?
    @State private var exportsCSV = false
    @State private var exportError: String?
    @State private var sharesCard = false
    @State private var routeLabelDraft: DriveRouteLabelRule?
    @State private var presentsExpandedDetail = false

    private let carId: Int
    private let driveId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, driveId: Int, exteriorColor: String?, viewModel: DriveDetailViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.driveId = driveId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.driveDetail == nil {
                LoadingStateView(title: t("Loading drive", "正在加载行程"), showsProgress: true)
            } else if let detail = viewModel.state.driveDetail {
                let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        DriveHeroView(detail: detail, stats: viewModel.state.stats, units: units)
                        DriveGeofenceSummaryCard(
                            startGeofence: viewModel.state.startGeofence,
                            endGeofence: viewModel.state.endGeofence
                        )
                        detailLoadStatus
                        if viewModel.state.isShowingSummary || !presentsExpandedDetail {
                            DriveStatsGrid(stats: viewModel.state.stats, units: units) { metric in
                                navigate(.driveMetricDetail(
                                    carId: carId,
                                    driveId: driveId,
                                    metric: metric,
                                    exteriorColor: exteriorColor
                                ))
                            }
                        } else {
                            DriveRouteReplayView(detail: detail, units: units)
                            DriveDistanceComparisonCard(detail: detail, units: units)
                            DriveIntelligencePerformanceCard(
                                detail: detail,
                                stats: viewModel.state.stats,
                                intelligence: viewModel.state.intelligence,
                                units: units,
                                onConfirmSuggestion: {
                                    Task { await viewModel.confirmSuggestion(carId: carId, driveId: driveId) }
                                },
                                onEditLabel: {
                                    routeLabelDraft = viewModel.state.intelligence?.confirmedLabel
                                        ?? draftRouteLabel(detail: detail)
                                }
                            )
                            DriveStatsGrid(stats: viewModel.state.stats, units: units) { metric in
                                navigate(.driveMetricDetail(carId: carId, driveId: driveId, metric: metric, exteriorColor: exteriorColor))
                            }
                            DriveCabinTelemetryCard(detail: detail, units: units)
                            annotationSection
                            tripMembershipSection
                            if supportsRouteWeather(detail) {
                                if !viewModel.state.allowsThirdPartyRouteWeather {
                                    RouteWeatherConsentCard(
                                        isEnabling: viewModel.state.isEnablingRouteWeather,
                                        showsError: viewModel.state.routeWeatherPermissionFailed
                                    ) {
                                        Task { await viewModel.enableRouteWeather() }
                                    }
                                } else if viewModel.state.isLoadingWeather || !viewModel.state.weatherPoints.isEmpty {
                                    WeatherAlongTheWayView(
                                        points: viewModel.state.weatherPoints,
                                        units: units,
                                        isLoading: viewModel.state.isLoadingWeather
                                    )
                                }
                            }
                            DrivePositionCharts(detail: detail, units: units)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.load(carId: carId, driveId: driveId)
                }
            } else {
                LoadingStateView(
                    title: t("Drive unavailable", "行程不可用"),
                    message: localizedErrorMessage,
                    systemImage: "exclamationmark.triangle",
                    retryTitle: t("Retry", "重试")
                ) {
                    Task {
                        await viewModel.load(carId: carId, driveId: driveId)
                    }
                }
            }
        }
        .navigationTitle(t("Drive Detail", "行程详情"))
        .accessibilityIdentifier("drive_detail_view")
        .confirmationDialog(t("Remove from trip?", "从路程中移除？"), isPresented: $confirmsTripRemoval, titleVisibility: .visible) {
            Button(t("Remove", "移除"), role: .destructive) { Task { await viewModel.removeFromTrip(carId: carId, driveId: driveId) } }
            Button(t("Cancel", "取消"), role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editsAnnotation = true } label: { Label(t("Edit Classification", "编辑分类"), systemImage: "tag") }
                    Button {
                        navigate(.compareDrives(carId: carId, baseDriveId: driveId, exteriorColor: exteriorColor))
                    } label: {
                        Label(t("Compare", "比较"), systemImage: "arrow.left.arrow.right")
                    }
                    .accessibilityIdentifier("drive_compare_button")
                    if !viewModel.state.isShowingSummary {
                        Button { sharesCard = true } label: { Label(t("Share Card", "分享卡片"), systemImage: "photo.on.rectangle.angled") }
                        Button { prepareExport() } label: { Label(t("Export CSV", "导出表格"), systemImage: "square.and.arrow.up") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(t("Drive Actions", "行程操作"))
                .accessibilityIdentifier("drive_actions_button")
            }
        }
        .sheet(isPresented: $editsAnnotation) {
            NavigationStack {
                DriveAnnotationEditor(annotation: viewModel.state.annotation) { annotation in
                    Task { await viewModel.saveAnnotation(carId: carId, driveId: driveId, annotation: annotation) }
                    editsAnnotation = false
                }
            }
            .environment(\.appLanguage, appLanguage)
        }
        .sheet(isPresented: $sharesCard) {
            if let detail = viewModel.state.driveDetail {
                DriveShareComposerView(
                    detail: detail,
                    stats: viewModel.state.stats,
                    annotation: viewModel.state.annotation,
                    units: viewModel.state.units.resolved(for: appDisplayUnitSystem)
                )
                .environment(\.appLanguage, appLanguage)
                .presentationDetents([.large])
            }
        }
        .sheet(item: $routeLabelDraft) { rule in
            NavigationStack {
                DriveRouteLabelEditor(rule: rule) { updated in
                    Task { await viewModel.updateRouteLabelRule(carId: carId, rule: updated) }
                    routeLabelDraft = nil
                }
            }
            .environment(\.appLanguage, appLanguage)
        }
        .fileExporter(
            isPresented: $exportsCSV,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "MateDrive-drive-\(driveId)"
        ) { result in
            if case let .failure(error) = result { exportError = error.localizedDescription }
            exportDocument = nil
        }
        .alert(t("Export Failed", "导出失败"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(t("OK", "确定"), role: .cancel) {}
        } message: {
            Text(UserFacingErrorLocalizer.localizedOptional(exportError, language: appLanguage) ?? "")
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId, driveId: driveId)
        }
        .task(id: driveId) {
            presentsExpandedDetail = false
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            presentsExpandedDetail = true
        }
    }

    private func supportsRouteWeather(_ detail: DriveDetail) -> Bool {
        guard let distance = detail.distance, distance > 0 else { return false }
        return (detail.positions ?? []).contains { position in
            guard position.date != nil,
                  let latitude = position.latitude,
                  let longitude = position.longitude
            else { return false }
            return GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil
        }
    }

    @ViewBuilder
    private var detailLoadStatus: some View {
        if let message = localizedErrorMessage, !isStoreScreenshotMode {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(t("Retry", "重试")) {
                    Task { await viewModel.load(carId: carId, driveId: driveId) }
                }
                .font(.footnote.weight(.semibold))
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        } else if viewModel.state.isRefreshing {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(viewModel.state.isShowingSummary
                     ? t("Showing saved data while detailed telemetry loads", "已显示本地记录，详细轨迹正在后台加载")
                     : t("Updating drive data", "正在后台更新行程数据"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var localizedErrorMessage: String? {
        UserFacingErrorLocalizer.localizedOptional(viewModel.state.errorMessage, language: appLanguage)
    }

    private var isStoreScreenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MATEDRIVE_STORE_SCREENSHOT_MODE"] == "1"
        #else
        false
        #endif
    }

    private func draftRouteLabel(detail: DriveDetail) -> DriveRouteLabelRule? {
        let fingerprint = DriveRouteFingerprint(positions: detail.positions ?? [])
        guard fingerprint.isComplete, let distance = detail.distance, distance > 0 else { return nil }
        return DriveRouteLabelRule(
            carId: carId,
            name: t("My route", "自定义路线"),
            iconName: "tag.fill",
            colorHex: "3478F6",
            typicalDistanceKm: distance,
            fingerprint: fingerprint
        )
    }

    private var annotationSection: some View {
        Button { editsAnnotation = true } label: {
            HStack {
                Image(systemName: "tag").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Classification & Notes", "分类与备注")).font(.headline).foregroundStyle(.primary)
                    Text(viewModel.state.annotation.displayLabel(language: appLanguage)).foregroundStyle(.secondary)
                    if !viewModel.state.annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(viewModel.state.annotation.note).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func prepareExport() {
        guard let detail = viewModel.state.driveDetail else { return }
        let csv = DriveCSVExporter.csv(detail: detail, stats: viewModel.state.stats, annotation: viewModel.state.annotation, units: viewModel.state.units.resolved(for: appDisplayUnitSystem))
        exportDocument = DriveCSVDocument(csv: csv)
        exportsCSV = true
    }

    @ViewBuilder
    private var tripMembershipSection: some View {
        if let membership = viewModel.state.tripMembership {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Saved Trip", "所属路程")).font(.headline)
                Button {
                    navigate(.tripDetail(carId: carId, tripStartDate: membership.snapshot.startDate, exteriorColor: exteriorColor))
                } label: {
                    HStack {
                        Label(membership.trip.displayName(language: appLanguage), systemImage: "map")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }.buttonStyle(.bordered)
                Button(t("Remove from Trip", "从路程中移除"), role: .destructive) { confirmsTripRemoval = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct RouteWeatherConsentCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let isEnabling: Bool
    let showsError: Bool
    let onEnable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(t("Route Weather", "路线天气"), systemImage: "cloud.sun.fill")
                .font(.headline)
            Text(t(
                "To load weather for this drive, MateDrive sends one representative precise route coordinate and the drive time to Open-Meteo. Open-Meteo may retain request logs for up to 90 days. You can turn this off and clear saved weather in Privacy & Local Data.",
                "如需加载本次行程天气，MateDrive 会向 Open-Meteo 发送一个代表性的精确路线坐标和行程时间。Open-Meteo 可能将请求日志保留最长 90 天。你可以随时在“隐私与本地数据”中关闭并清除已保存天气。"
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)

            if showsError {
                Label(
                    t("Could not save this permission. Try again.", "无法保存此授权，请重试。"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }

            Button(action: onEnable) {
                Label(
                    isEnabling ? t("Enabling Route Weather", "正在启用路线天气") : t("Enable Route Weather", "启用路线天气"),
                    systemImage: "checkmark.shield.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isEnabling)
            .accessibilityIdentifier("route_weather_enable_button")
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("route_weather_consent_card")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveIntelligencePerformanceCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let detail: DriveDetail
    let stats: DriveDetailStats?
    let intelligence: DriveIntelligenceResult?
    let units: UnitPreferences?
    let onConfirmSuggestion: () -> Void
    let onEditLabel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(t("Performance", "表现"), systemImage: "gauge.with.dots.needle.67percent")
                    .font(.headline)
                Spacer()
                if let label = intelligence?.confirmedLabel {
                    Button(action: onEditLabel) {
                        Label(label.name, systemImage: label.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PaletteColor(hex: label.colorHex).color)
                    }
                    .buttonStyle(.plain)
                } else if intelligence?.suggestion == nil {
                    Button(action: onEditLabel) {
                        Label(t("Create label", "创建标签"), systemImage: "tag")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }

            if let suggestion = intelligence?.suggestion {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.direction == .outbound
                             ? t("Possible commute to work", "疑似上班通勤")
                             : t("Possible commute home", "疑似下班通勤"))
                            .font(.subheadline.weight(.semibold))
                        Text(t("Based on \(suggestion.matchingDriveCount) similar weekday drives", "根据 \(suggestion.matchingDriveCount) 次工作日相似行程判断"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("Confirm", "确认"), action: onConfirmSuggestion)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                }
                .padding(12)
                .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 0) {
                performanceMetric(t("This drive", "本次能耗"), efficiencyText(benchmark.currentEfficiency))
                Divider().frame(height: 42)
                performanceMetric(t("Personal baseline", "个人标定"), efficiencyText(benchmark.benchmarkEfficiency))
                Divider().frame(height: 42)
                performanceMetric(t("Difference", "差距"), differenceText)
            }

            if benchmark.recentEfficiencies.count >= 2 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("Last 8 drives on this route", "最近 8 次同路线"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Chart(Array(benchmark.recentEfficiencies.enumerated()), id: \.offset) { index, value in
                        LineMark(x: .value("Index", index), y: .value("Efficiency", value))
                            .foregroundStyle(.green)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Index", index), y: .value("Efficiency", value))
                            .foregroundStyle(index == benchmark.currentTrendIndex ? .orange : .green)
                            .symbolSize(index == benchmark.currentTrendIndex ? 70 : 28)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 118)
                }
            }

            if let achievementText = achievementMessage {
                Label(achievementText, systemImage: achievementIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(achievementColor)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(achievementColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            } else if intelligence?.confirmedLabel != nil, benchmark.samplesNeeded > 0 {
                Label(
                    t(
                        "Complete \(benchmark.samplesNeeded) more similar drives to establish your baseline",
                        "再完成 \(benchmark.samplesNeeded) 次相似行程，即可建立个人标定"
                    ),
                    systemImage: "chart.line.uptrend.xyaxis"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            factorGrid
            rangeComparison
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.75), lineWidth: benchmark.accent == .neutral ? 0.75 : 1.5)
        }
    }

    private var benchmark: DriveBenchmarkResult {
        intelligence?.benchmark ?? DriveBenchmarkResult(
            currentEfficiency: stats?.efficiency,
            benchmarkEfficiency: nil,
            percentageDifference: nil,
            recentEfficiencies: [],
            currentTrendIndex: nil,
            rank: nil,
            previousBestEfficiency: nil,
            sampleCount: 0,
            samplesNeeded: DriveIntelligenceEngine.minimumBenchmarkSamples,
            accent: .neutral,
            isThreeDriveStreak: false,
            fiveDriveImprovementPercent: nil
        )
    }

    private func performanceMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var factorGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            factor("thermometer.medium", t("Temperature", "温度"), detail.outsideTempAvg.map { MateDriveUnitFormatter.formatTemperature($0, units: units) } ?? "--")
            factor("fan.fill", t("Climate", "空调"), climateText)
            factor("speedometer", t("Average speed", "平均速度"), stats?.speedAvg.map { MateDriveUnitFormatter.formatSpeed($0, units: units) } ?? "--")
            factor("mountain.2.fill", t("Elevation", "海拔变化"), elevationText)
        }
    }

    private func factor(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(verbatim: value).font(.caption.weight(.medium)).lineLimit(1)
            }
        }
    }

    private var rangeComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("Rated display vs actual distance", "表显消耗与实际行驶"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Label(MateDriveUnitFormatter.formatDistance(detail.distance ?? 0, units: units), systemImage: "road.lanes")
                Spacer()
                Label(detail.rangeRated?.usedDistance.map { MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--", systemImage: "gauge.with.dots.needle.50percent")
                Spacer()
                Text(rangeOutcome)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rangeOutcomeColor)
            }
            .font(.caption)
        }
        .padding(.top, 2)
    }

    private var differenceText: String {
        guard let difference = benchmark.percentageDifference else { return "--" }
        let percent = Int(abs(difference).rounded())
        return difference <= 0 ? t("Better \(percent)%", "优于 \(percent)%") : t("Above \(percent)%", "高于 \(percent)%")
    }

    private var achievementMessage: String? {
        if benchmark.accent == .personalBest, let previous = benchmark.previousBestEfficiency,
           let current = benchmark.currentEfficiency {
            let saved = Int(max(previous - current, 0).rounded())
            return t("New personal best, saving \(saved) Wh/km versus the old record", "新的个人最佳，较原纪录节省 \(saved) 瓦时/公里")
        }
        if benchmark.isThreeDriveStreak {
            return t("Three drives in a row better than your baseline", "连续 3 次优于个人标定")
        }
        if let improvement = benchmark.fiveDriveImprovementPercent, improvement >= 1 {
            let percent = Int(improvement.rounded())
            return t("Average efficiency improved \(percent)% over the last 5 commutes", "近 5 次通勤平均能耗下降 \(percent)%")
        }
        if benchmark.rank == 1, intelligence?.confirmedLabel != nil {
            return t("Today's commute is the most efficient drive on this route", "今天的通勤，是这条路线最省电的一次")
        }
        return nil
    }

    private var achievementIcon: String { benchmark.accent == .personalBest ? "trophy.fill" : "sparkles" }
    private var achievementColor: Color { benchmark.accent == .personalBest ? .green : .blue }

    private var accentColor: Color {
        switch benchmark.accent {
        case .efficient, .personalBest: return .green
        case .aboveBenchmark: return .orange
        case .gold: return .yellow
        case .silver: return Color(uiColor: .systemGray2)
        case .bronze: return Color(red: 0.72, green: 0.43, blue: 0.22)
        case .neutral: return Color(uiColor: .separator)
        }
    }

    private var climateText: String {
        let samples = detail.positions ?? []
        let active = samples.filter(\.isClimateOn)
        guard !active.isEmpty else { return t("Off", "未开启") }
        let fan = active.compactMap { $0.climateInfo?.fanStatus }.max()
        let setting = active.compactMap { $0.climateInfo?.driverTempSetting }.last
        var values: [String] = []
        if let setting { values.append(MateDriveUnitFormatter.formatTemperature(setting, units: units)) }
        if let fan { values.append(t("Fan \(fan)", "\(fan) 档")) }
        return values.isEmpty ? t("On", "已开启") : values.joined(separator: " · ")
    }

    private var elevationText: String {
        let elevations = (detail.positions ?? []).compactMap(\.elevation).map(Double.init)
        guard elevations.count > 1 else { return "--" }
        let changes = zip(elevations, elevations.dropFirst()).map { $1 - $0 }
        let gain = Int(changes.filter { $0 > 0 }.reduce(0, +).rounded())
        let loss = Int(abs(changes.filter { $0 < 0 }.reduce(0, +)).rounded())
        return "+\(gain)m / -\(loss)m"
    }

    private var rangeOutcome: String {
        guard let actual = detail.distance, let rated = detail.rangeRated?.usedDistance else { return "--" }
        let delta = actual - rated
        let value = MateDriveUnitFormatter.formatDistance(abs(delta), units: units, decimals: 1)
        return delta >= 0 ? t("Ahead \(value)", "跑赢 \(value)") : t("Gap \(value)", "差距 \(value)")
    }

    private var rangeOutcomeColor: Color {
        guard let actual = detail.distance, let rated = detail.rangeRated?.usedDistance else { return .secondary }
        return actual >= rated ? .green : .orange
    }

    private func efficiencyText(_ value: Double?) -> String {
        value.map { MateDriveUnitFormatter.formatEfficiency($0, units: units, decimals: 0) } ?? "--"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveRouteLabelEditor: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var rule: DriveRouteLabelRule
    let onSave: (DriveRouteLabelRule) -> Void

    private let icons = ["briefcase.fill", "house.fill", "figure.2.and.child.holdinghands", "dumbbell.fill", "airplane", "tag.fill"]
    private let colors = ["22A65A", "3478F6", "FF9500", "AF52DE", "E5484D", "8E8E93"]

    init(rule: DriveRouteLabelRule, onSave: @escaping (DriveRouteLabelRule) -> Void) {
        _rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section(t("Label", "标签")) {
                TextField(t("Name", "名称"), text: $rule.name)
                Picker(t("Icon", "图标"), selection: $rule.iconName) {
                    ForEach(icons, id: \.self) { icon in
                        Image(systemName: icon).tag(icon)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section(t("Color", "颜色")) {
                HStack(spacing: 18) {
                    ForEach(colors, id: \.self) { hex in
                        Button {
                            rule.colorHex = hex
                        } label: {
                            Circle()
                                .fill(PaletteColor(hex: hex).color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if rule.colorHex == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(t("Route Label", "路线标签"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t("Cancel", "取消")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Save", "保存")) { onSave(rule) }
                    .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveAnnotationEditor: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @Environment(\.dismiss) private var dismiss
    @State private var classification: DriveClassification
    @State private var customLabel: String
    @State private var note: String
    let onSave: (DriveAnnotation) -> Void

    init(annotation: DriveAnnotation, onSave: @escaping (DriveAnnotation) -> Void) {
        _classification = State(initialValue: annotation.classification)
        _customLabel = State(initialValue: annotation.customLabel)
        _note = State(initialValue: annotation.note)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Picker(t("Classification", "分类"), selection: $classification) {
                ForEach(DriveClassification.allCases) { value in Text(value.title(language: appLanguage)).tag(value) }
            }
            if classification == .custom {
                TextField(t("Custom Label", "自定义标签"), text: $customLabel)
            }
            Section(t("Note", "备注")) {
                TextEditor(text: $note).frame(minHeight: 140)
            }
        }
        .navigationTitle(t("Drive Classification", "行程分类"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("Cancel", "取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Save", "保存")) { onSave(DriveAnnotation(classification: classification, customLabel: customLabel, note: note)) }
                    .disabled(classification == .custom && customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private func t(_ en: String, _ zh: String) -> String { AppText.localized(en, zh, language: appLanguage) }
}

private struct DriveCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let csv: String
    init(csv: String) { self.csv = csv }
    init(configuration: ReadConfiguration) throws { csv = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(csv.utf8)) }
}

public struct DriveRouteReplayView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @State private var selectedIndex = 0
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?

    let detail: DriveDetail
    let units: UnitPreferences?
    private let samples: [DriveReplaySample]
    private let coordinates: [CLLocationCoordinate2D]
    private let mapRegion: MKCoordinateRegion

    public init(detail: DriveDetail, units: UnitPreferences?) {
        self.detail = detail
        self.units = units
        let samples = DriveReplayBuilder.samples(from: detail.positions ?? [])
        self.samples = samples
        let coordinates = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        self.coordinates = coordinates
        self.mapRegion = Self.region(for: coordinates)
    }

    public var body: some View {
        if samples.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                replayMap(samples: samples)
                replayControls(samples: samples)
                replayMetrics(sample: samples[min(selectedIndex, samples.count - 1)])
            }
            .onDisappear { stopPlayback() }
        } else {
            LoadingStateView(title: t("No route coordinates", "暂无路线坐标"), systemImage: "map")
                .frame(minHeight: 120)
        }
    }

    private func replayMap(samples: [DriveReplaySample]) -> some View {
        let index = min(selectedIndex, samples.count - 1)
        return MapGestureGate { isMapInteractionEnabled in
            IncrementalDriveReplayMap(
                coordinates: coordinates,
                region: mapRegion,
                selectedIndex: index,
                isPlaying: isPlaying,
                isMapInteractionEnabled: isMapInteractionEnabled,
                startTitle: t("Start", "开始"),
                endTitle: t("End", "结束"),
                currentTitle: t("Current", "当前位置")
            )
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func replayControls(samples: [DriveReplaySample]) -> some View {
        HStack(spacing: 12) {
            Button {
                isPlaying ? stopPlayback() : startPlayback(sampleCount: samples.count)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(isPlaying ? t("Pause replay", "暂停回放") : t("Play route", "播放路线"))

            Slider(
                value: Binding(
                    get: { Double(min(selectedIndex, samples.count - 1)) },
                    set: { selectedIndex = min(max(Int($0.rounded()), 0), samples.count - 1) }
                ),
                in: 0...Double(samples.count - 1),
                step: 1,
                onEditingChanged: { editing in if editing { stopPlayback() } }
            )
            .accessibilityLabel(t("Route progress", "路线进度"))

            Text("\(min(selectedIndex, samples.count - 1) + 1)/\(samples.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    private func replayMetrics(sample: DriveReplaySample) -> some View {
        let position = sample.position
        return HStack(spacing: 0) {
            replayMetric(t("Time", "时间"), value: formattedTime(position.date))
            replayMetric(t("Speed", "速度"), value: position.speed.map { MateDriveUnitFormatter.formatSpeed(Double($0), units: units) } ?? "--")
            replayMetric(t("Power", "功率"), value: position.power.map { "\($0) kW" } ?? "--")
            replayMetric(t("Battery", "电量"), value: position.batteryLevel.map { "\($0)%" } ?? "--")
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func replayMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func startPlayback(sampleCount: Int) {
        stopPlayback()
        if selectedIndex >= sampleCount - 1 { selectedIndex = 0 }
        isPlaying = true
        playbackTask = Task { @MainActor in
            while !Task.isCancelled, selectedIndex < sampleCount - 1 {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { break }
                selectedIndex += 1
            }
            if !Task.isCancelled { isPlaying = false }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func formattedTime(_ value: String?) -> String {
        guard let value, let date = DomainDateParser.date(from: value) else { return "--" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2,
            longitude: ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(((latitudes.max() ?? 0) - (latitudes.min() ?? 0)) * 1.4, 0.01),
                longitudeDelta: max(((longitudes.max() ?? 0) - (longitudes.min() ?? 0)) * 1.4, 0.01)
            )
        )
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct IncrementalDriveReplayMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    let region: MKCoordinateRegion
    let selectedIndex: Int
    let isPlaying: Bool
    let isMapInteractionEnabled: Bool
    let startTitle: String
    let endTitle: String
    let currentTitle: String

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinates: coordinates)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.isPitchEnabled = false
        mapView.isRotateEnabled = false
        mapView.isScrollEnabled = true
        mapView.isZoomEnabled = true
        mapView.isUserInteractionEnabled = isMapInteractionEnabled
        mapView.showsCompass = false
        context.coordinator.install(
            on: mapView,
            region: region,
            startTitle: startTitle,
            endTitle: endTitle,
            currentTitle: currentTitle
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.isUserInteractionEnabled = isMapInteractionEnabled
        context.coordinator.update(
            selectedIndex: selectedIndex,
            isPlaying: isPlaying,
            startTitle: startTitle,
            endTitle: endTitle,
            currentTitle: currentTitle,
            on: mapView
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let coordinates: [CLLocationCoordinate2D]
        private let startAnnotation = ReplayAnnotation(kind: .start)
        private let endAnnotation = ReplayAnnotation(kind: .end)
        private let currentAnnotation = ReplayAnnotation(kind: .current)
        private var routePolyline: MKPolyline?
        private var traveledPolyline: MKPolyline?
        private var lastTrailIndex: Int?

        init(coordinates: [CLLocationCoordinate2D]) {
            self.coordinates = coordinates
        }

        func install(
            on mapView: MKMapView,
            region: MKCoordinateRegion,
            startTitle: String,
            endTitle: String,
            currentTitle: String
        ) {
            guard let first = coordinates.first, let last = coordinates.last else { return }

            var routeCoordinates = coordinates
            let routePolyline = MKPolyline(coordinates: &routeCoordinates, count: routeCoordinates.count)
            self.routePolyline = routePolyline
            mapView.addOverlay(routePolyline, level: .aboveRoads)

            startAnnotation.coordinate = first
            endAnnotation.coordinate = last
            currentAnnotation.coordinate = first
            startAnnotation.title = startTitle
            endAnnotation.title = endTitle
            currentAnnotation.title = currentTitle
            mapView.addAnnotations([startAnnotation, endAnnotation, currentAnnotation])
            mapView.setRegion(region, animated: false)
        }

        func update(
            selectedIndex: Int,
            isPlaying: Bool,
            startTitle: String,
            endTitle: String,
            currentTitle: String,
            on mapView: MKMapView
        ) {
            guard !coordinates.isEmpty else { return }
            let index = min(max(selectedIndex, 0), coordinates.count - 1)
            currentAnnotation.coordinate = coordinates[index]
            updateTitle(startTitle, for: startAnnotation)
            updateTitle(endTitle, for: endAnnotation)
            updateTitle(currentTitle, for: currentAnnotation)

            let refreshesTrail = !isPlaying || DriveReplayRenderPolicy.shouldRefreshTrail(
                lastRenderedIndex: lastTrailIndex,
                currentIndex: index,
                sampleCount: coordinates.count
            )
            guard refreshesTrail else { return }

            if let traveledPolyline {
                mapView.removeOverlay(traveledPolyline)
            }
            traveledPolyline = nil
            if index >= 1 {
                var traveledCoordinates = Array(coordinates.prefix(index + 1))
                let polyline = MKPolyline(coordinates: &traveledCoordinates, count: traveledCoordinates.count)
                traveledPolyline = polyline
                mapView.addOverlay(polyline, level: .aboveRoads)
            }
            lastTrailIndex = index
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            if polyline === routePolyline {
                renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.45)
                renderer.lineWidth = 4
            } else {
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 5
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let replayAnnotation = annotation as? ReplayAnnotation else { return nil }
            let reuseIdentifier = "drive-replay-\(replayAnnotation.kind.rawValue)"
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: replayAnnotation, reuseIdentifier: reuseIdentifier)
            marker.annotation = replayAnnotation
            marker.canShowCallout = false
            marker.displayPriority = .required
            marker.titleVisibility = replayAnnotation.kind == .current ? .visible : .adaptive
            switch replayAnnotation.kind {
            case .start:
                marker.markerTintColor = .systemBlue
                marker.glyphImage = UIImage(systemName: "flag.fill")
            case .end:
                marker.markerTintColor = .systemPink
                marker.glyphImage = UIImage(systemName: "flag.checkered")
            case .current:
                marker.markerTintColor = .systemGreen
                marker.glyphImage = UIImage(systemName: "car.fill")
            }
            return marker
        }

        private func updateTitle(_ title: String, for annotation: ReplayAnnotation) {
            guard annotation.title != title else { return }
            annotation.title = title
        }
    }

    private final class ReplayAnnotation: MKPointAnnotation {
        enum Kind: String {
            case start
            case end
            case current
        }

        let kind: Kind

        init(kind: Kind) {
            self.kind = kind
            super.init()
        }
    }
}

public struct DriveHeroView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let detail: DriveDetail
    let stats: DriveDetailStats?
    let units: UnitPreferences?

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            routeText
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Text(dateText(detail.startDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(DriveDetailPresentation.distanceText(stats?.distance ?? detail.distance, units: units))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Spacer()
                Text(DriveDetailPresentation.batteryText(start: stats?.batteryStart, end: stats?.batteryEnd))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var routeText: Text {
        let start = cleanedAddress(detail.startAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("Start", "开始"))
        let end = cleanedAddress(detail.endAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("End", "结束"))
        return start + Text(" → ") + end
    }

    private func cleanedAddress(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func dateText(_ value: String?) -> String {
        guard let value, let date = DomainDateParser.date(from: value) else {
            return value ?? ""
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum DriveDetailPresentation {
    public static func distanceText(_ value: Double?, units: UnitPreferences?) -> String {
        value.map { MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    public static func speedText(_ value: Double?, units: UnitPreferences?) -> String {
        value.map { MateDriveUnitFormatter.formatSpeed($0, units: units) } ?? "--"
    }

    public static func batteryText(start: Int?, end: Int?) -> String {
        guard let start, let end else { return "--" }
        return "\(start)% → \(end)%"
    }

    public static func elevationText(gain: Int?, loss: Int?, units: UnitPreferences?) -> String {
        guard let gain, let loss else { return "--" }
        return "+\(MateDriveUnitFormatter.formatElevation(gain, units: units)) / -\(MateDriveUnitFormatter.formatElevation(loss, units: units))"
    }

    public static func durationText(_ value: Int?, language: AppLanguage) -> String {
        value.map { MateDriveUnitFormatter.formatDuration(minutes: $0, language: language) } ?? "--"
    }
}

public struct DriveStatsGrid: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let stats: DriveDetailStats?
    let units: UnitPreferences?
    let onSelectMetric: ((DriveMetricKind) -> Void)?

    public init(stats: DriveDetailStats?, units: UnitPreferences?, onSelectMetric: ((DriveMetricKind) -> Void)? = nil) {
        self.stats = stats
        self.units = units
        self.onSelectMetric = onSelectMetric
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            metricCard(.averageSpeed, value: DriveDetailPresentation.speedText(stats?.speedAvg, units: units))
            metricCard(.maxSpeed, value: DriveDetailPresentation.speedText(stats?.speedMax.map(Double.init), units: units))
            metricCard(
                .efficiency,
                value: stats?.efficiency.map { MateDriveUnitFormatter.formatEfficiency($0, units: units, decimals: 0) } ?? "--"
            )
            metricCard(
                .energy,
                value: stats?.energyUsed.map { String(format: "%.1f kWh", $0) } ?? "--"
            )
            metricCard(.elevation, value: DriveDetailPresentation.elevationText(gain: stats?.elevationGain, loss: stats?.elevationLoss, units: units))
            metricCard(.duration, value: DriveDetailPresentation.durationText(stats?.durationMin, language: appLanguage))
        }
    }

    @ViewBuilder
    private func metricCard(_ metric: DriveMetricKind, value: String, subtitle: String? = nil) -> some View {
        if let onSelectMetric {
            Button {
                onSelectMetric(metric)
            } label: {
                MetricCard(title: metric.title(language: appLanguage), value: value, subtitle: subtitle, systemImage: metric.systemImage)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("drive_metric_\(metric.rawValue)_button")
            .accessibilityHint(AppText.localized("Open details", "打开详细数据", language: appLanguage))
        } else {
            MetricCard(title: metric.title(language: appLanguage), value: value, subtitle: subtitle, systemImage: metric.systemImage)
        }
    }

}

private struct DriveGeofenceSummaryCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let startGeofence: GeofenceRule?
    let endGeofence: GeofenceRule?

    var body: some View {
        if startGeofence != nil || endGeofence != nil {
            HStack(spacing: 10) {
                fenceLabel(startGeofence, fallback: t("Start", "起点"))
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                fenceLabel(endGeofence, fallback: t("End", "终点"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func fenceLabel(_ fence: GeofenceRule?, fallback: String) -> some View {
        Label {
            Text(fence?.name ?? fallback)
                .lineLimit(1)
        } icon: {
            Image(systemName: fence?.kind.systemImage ?? "mappin.circle")
                .foregroundStyle(fence == nil ? Color.secondary : Color.green)
        }
        .font(.subheadline.weight(.medium))
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveDistanceComparisonCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let detail: DriveDetail
    let units: UnitPreferences?

    private var actualDistance: Double? { detail.distance }
    private var ratedRangeDrop: Double? { detail.rangeRated?.usedDistance }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("Distance Comparison", "距离对比"), systemImage: "arrow.left.arrow.right")
                .font(.headline)

            HStack(alignment: .top, spacing: 0) {
                metric(title: t("Actual Distance", "实际行驶"), value: distanceText(actualDistance), tint: .green)
                Divider()
                    .frame(height: 42)
                    .padding(.horizontal, 14)
                metric(title: t("Rated Range Used", "表显消耗"), value: distanceText(ratedRangeDrop), tint: .orange)
            }

            if let comparisonText {
                Label(comparisonText, systemImage: comparisonIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(comparisonTint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func metric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var comparisonText: String? {
        guard let actualDistance, let ratedRangeDrop else { return nil }
        let delta = actualDistance - ratedRangeDrop
        let magnitude = distanceText(abs(delta))
        if abs(delta) < 0.05 { return t("Matches rated range", "与表显持平") }
        return delta > 0 ? t("Ahead of rated by \(magnitude)", "跑赢表显 \(magnitude)") : t("Below rated by \(magnitude)", "少于表显 \(magnitude)")
    }

    private var comparisonIcon: String {
        guard let actualDistance, let ratedRangeDrop else { return "minus.circle" }
        return actualDistance >= ratedRangeDrop ? "arrow.up.right" : "arrow.down.right"
    }

    private var comparisonTint: Color {
        guard let actualDistance, let ratedRangeDrop else { return .secondary }
        if abs(actualDistance - ratedRangeDrop) < 0.05 { return .secondary }
        return actualDistance > ratedRangeDrop ? .green : .orange
    }

    private func distanceText(_ value: Double?) -> String {
        DriveDetailPresentation.distanceText(value, units: units)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveCabinTelemetryCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let detail: DriveDetail
    let units: UnitPreferences?

    private var telemetry: DriveCabinTelemetry { DriveCabinTelemetry(positions: detail.positions ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("Cabin & Media", "座舱与媒体"), systemImage: "car.side.air.circulate")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: telemetry.wasClimateOn ? "fanblades.fill" : "fanblades")
                    .foregroundStyle(telemetry.wasClimateOn ? .blue : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Climate", "空调"))
                        .font(.subheadline.weight(.semibold))
                    Text(climateStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let driverSetting = telemetry.driverTemperatureSetting {
                    Text(temperatureText(driverSetting))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.blue)
                }
            }

            if telemetry.hasClimateTelemetry {
                Divider()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], alignment: .leading, spacing: 14) {
                    telemetryValue(icon: "fanblades", title: t("Fan", "风量"), value: telemetry.fanStatus.map { t("Level \($0)", "\($0) 档") } ?? "--")
                    telemetryValue(icon: "thermometer.medium", title: t("Driver", "主驾设定"), value: telemetry.driverTemperatureSetting.map(temperatureText) ?? "--")
                    telemetryValue(icon: "thermometer.medium", title: t("Passenger", "副驾设定"), value: telemetry.passengerTemperatureSetting.map(temperatureText) ?? "--")
                    telemetryValue(icon: "waveform.path.ecg", title: t("Climate samples", "空调采样"), value: "\(telemetry.climateOnSampleCount)/\(telemetry.climateSampleCount)")
                }
            }

            Divider()
            HStack(spacing: 10) {
                Image(systemName: "speaker.slash")
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Audio", "音响"))
                        .font(.subheadline.weight(.semibold))
                    Text(t("TeslaMate does not record playback or volume for drives.", "TeslaMate 未记录行程中的播放状态或音量。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var climateStatusText: String {
        guard telemetry.hasClimateTelemetry else { return t("No climate telemetry", "未记录空调遥测") }
        return telemetry.wasClimateOn
            ? t("On in \(telemetry.climateOnSampleCount) sampled positions", "采样中开启 \(telemetry.climateOnSampleCount) 次")
            : t("No on-state in samples", "采样中未见开启状态")
    }

    private func telemetryValue(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func temperatureText(_ value: Double) -> String {
        MateDriveUnitFormatter.formatTemperature(value, units: units, decimals: 1)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

struct DriveCabinTelemetry: Equatable, Sendable {
    let climateSampleCount: Int
    let climateOnSampleCount: Int
    let fanStatus: Int?
    let driverTemperatureSetting: Double?
    let passengerTemperatureSetting: Double?

    init(positions: [DrivePosition]) {
        let climateSamples = positions.compactMap(\.climateInfo)
        climateSampleCount = climateSamples.count
        climateOnSampleCount = climateSamples.filter { $0.isClimateOn == true }.count
        fanStatus = Self.mostFrequent(climateSamples.compactMap(\.fanStatus).filter { $0 > 0 })
        driverTemperatureSetting = Self.mostFrequent(climateSamples.compactMap(\.driverTempSetting))
        passengerTemperatureSetting = Self.mostFrequent(climateSamples.compactMap(\.passengerTempSetting))
    }

    var hasClimateTelemetry: Bool { climateSampleCount > 0 }
    var wasClimateOn: Bool { climateOnSampleCount > 0 }

    private static func mostFrequent<T: Hashable>(_ values: [T]) -> T? {
        guard !values.isEmpty else { return nil }
        let counts = values.reduce(into: [T: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { lhs, rhs in
            lhs.value == rhs.value ? String(describing: lhs.key) > String(describing: rhs.key) : lhs.value < rhs.value
        }?.key
    }
}

public enum DriveEnergySourcePresentation {
    public static func subtitle(for source: DriveEnergySource, language: AppLanguage) -> String {
        switch source {
        case .api:
            return AppText.localized("Direct TeslaMate data", "TeslaMate 原始数据", language: language)
        case .powerSamples:
            return AppText.localized("Reconstructed from power samples", "由功率采样重建", language: language)
        case .unavailable:
            return AppText.localized("No reliable data", "暂无可靠数据", language: language)
        }
    }

    public static func efficiencySubtitle(
        energySource: DriveEnergySource,
        hasEfficiency: Bool,
        language: AppLanguage
    ) -> String {
        if energySource == .unavailable, hasEfficiency {
            return subtitle(for: .api, language: language)
        }
        return subtitle(for: energySource, language: language)
    }
}

public struct DrivePositionCharts: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let detail: DriveDetail
    let units: UnitPreferences?

    public var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Text(t("Analysis", "分析"))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 16)

            chart(t("Speed", "速度"), kind: .speed)
            Divider()
            chart(t("Power", "功率"), kind: .power)
            Divider()
            chart(t("Battery & Heating", "电量和电池加热"), kind: .battery)
            Divider()
            chart(t("Elevation", "海拔"), kind: .elevation)
            Divider()
            chart(t("Temperature", "温度"), kind: .temperature)
            Divider()
            chart(t("Tire Pressure", "胎压"), kind: .tirePressure)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var positions: [DrivePosition] { detail.positions ?? [] }

    private func chart(_ title: String, kind: DriveChartKind) -> some View {
        DriveTimeSeriesChart(
            title: title,
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: kind == .tirePressure ? detail.sourceUnits?.unitOfPressure : nil
        )
        .padding(.vertical, 16)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum DriveChartKind: Sendable {
    case speed, power, battery, elevation, temperature, tirePressure
}

public struct DriveChartSample: Equatable, Sendable, Identifiable {
    public let date: Date
    public let value: Double
    public let series: String
    public let isHighlighted: Bool

    public var id: String { "\(date.timeIntervalSince1970)-\(series)" }
}

public enum DriveChartSampleBuilder {
    public static let maximumSamplesPerSeries = 240

    public static func samples(
        kind: DriveChartKind,
        positions: [DrivePosition],
        units: UnitPreferences?,
        sourcePressureUnit: String? = nil
    ) -> [DriveChartSample] {
        let rawSamples = positions.flatMap { position -> [DriveChartSample] in
            guard let date = position.date.flatMap(DomainDateParser.date(from:)) else { return [] }
            switch kind {
            case .speed:
                guard let value = position.speed.map(Double.init) else { return [] }
                return [sample(date, convertedSpeed(value, units: units), "speed")]
            case .power:
                guard let value = position.power.map(Double.init) else { return [] }
                return [sample(date, value, value < 0 ? "regeneration" : "traction", highlighted: value < 0)]
            case .battery:
                guard let value = position.batteryLevel.map(Double.init) else { return [] }
                return [sample(date, value, "battery", highlighted: position.isBatteryHeaterOn)]
            case .elevation:
                guard let value = position.elevation.map(Double.init) else { return [] }
                return [sample(date, units?.isImperial == true ? value * 3.28084 : value, "elevation")]
            case .temperature:
                var values: [DriveChartSample] = []
                if let outside = position.outsideTemp { values.append(sample(date, convertedTemperature(outside, units: units), "outside")) }
                if let inside = position.insideTemp { values.append(sample(date, convertedTemperature(inside, units: units), "inside")) }
                return values
            case .tirePressure:
                return [
                    pressureSample(position.tpmsPressureFl, date: date, series: "frontLeft", sourceUnit: sourcePressureUnit, units: units),
                    pressureSample(position.tpmsPressureFr, date: date, series: "frontRight", sourceUnit: sourcePressureUnit, units: units),
                    pressureSample(position.tpmsPressureRl, date: date, series: "rearLeft", sourceUnit: sourcePressureUnit, units: units),
                    pressureSample(position.tpmsPressureRr, date: date, series: "rearRight", sourceUnit: sourcePressureUnit, units: units)
                ].compactMap { $0 }
            }
        }
        .enumerated()
        .sorted {
            if $0.element.date == $1.element.date {
                return $0.offset < $1.offset
            }
            return $0.element.date < $1.element.date
        }
        .map(\.element)
        return limited(rawSamples, maximumPerSeries: maximumSamplesPerSeries)
    }

    private static func limited(_ samples: [DriveChartSample], maximumPerSeries: Int) -> [DriveChartSample] {
        guard maximumPerSeries >= 2 else { return Array(samples.prefix(maximumPerSeries)) }
        let groupedIndexes = Dictionary(grouping: samples.indices, by: { samples[$0].series })
        var retainedIndexes: Set<Int> = []

        for indexes in groupedIndexes.values {
            guard indexes.count > maximumPerSeries else {
                retainedIndexes.formUnion(indexes)
                continue
            }

            var selected: Set<Int> = []
            func retain(_ index: Int?) {
                guard let index, selected.count < maximumPerSeries else { return }
                selected.insert(index)
            }

            retain(indexes.first)
            retain(indexes.last)
            retain(indexes.min { samples[$0].value < samples[$1].value })
            retain(indexes.max { samples[$0].value < samples[$1].value })

            let highlighted = indexes.filter { samples[$0].isHighlighted }
            retain(highlighted.first)
            retain(highlighted.last)

            for slot in 1..<(maximumPerSeries - 1) where selected.count < maximumPerSeries {
                let progress = Double(slot) / Double(maximumPerSeries - 1)
                let offset = Int((Double(indexes.count - 1) * progress).rounded())
                retain(indexes[offset])
            }
            retainedIndexes.formUnion(selected)
        }

        return samples.indices.compactMap { retainedIndexes.contains($0) ? samples[$0] : nil }
    }

    private static func sample(_ date: Date, _ value: Double, _ series: String, highlighted: Bool = false) -> DriveChartSample {
        DriveChartSample(date: date, value: value, series: series, isHighlighted: highlighted)
    }

    private static func convertedSpeed(_ value: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? value * 0.621371 : value
    }

    private static func convertedTemperature(_ value: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? value * 9 / 5 + 32 : value
    }

    private static func pressureSample(
        _ value: Double?,
        date: Date,
        series: String,
        sourceUnit: String?,
        units: UnitPreferences?
    ) -> DriveChartSample? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let bar = sourceUnit?.lowercased() == "psi" ? value / 14.5038 : value
        return sample(date, MateDriveUnitFormatter.pressureValue(bar, units: units), series)
    }
}

public enum DriveChartSelection {
    public static func nearestDate(to date: Date, in samples: [DriveChartSample]) -> Date? {
        samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date
    }

    public static func samples(at date: Date, in samples: [DriveChartSample]) -> [DriveChartSample] {
        guard let nearestDate = nearestDate(to: date, in: samples) else { return [] }
        return samples.filter { $0.date == nearestDate }
    }
}

public struct DriveTimeSeriesChart: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @State private var selectedDate: Date?

    let title: String
    let kind: DriveChartKind
    let positions: [DrivePosition]
    let units: UnitPreferences?
    let sourcePressureUnit: String?
    private let chartSamples: [DriveChartSample]

    public init(
        title: String,
        kind: DriveChartKind,
        positions: [DrivePosition],
        units: UnitPreferences?,
        sourcePressureUnit: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.positions = positions
        self.units = units
        self.sourcePressureUnit = sourcePressureUnit
        self.chartSamples = DriveChartSampleBuilder.samples(
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: sourcePressureUnit
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let headerValue {
                    Text(verbatim: headerValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if samples.isEmpty {
                LoadingStateView(title: t("No data", "暂无数据"), systemImage: "chart.xyaxis.line")
            } else {
                Chart {
                    ForEach(samples) { sample in
                        if kind == .elevation {
                            AreaMark(
                                x: .value("Time", sample.date),
                                yStart: .value("Baseline", yDomain.lowerBound),
                                yEnd: .value("Value", sample.value)
                            )
                                .foregroundStyle(.brown.opacity(0.28))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                                .foregroundStyle(.brown)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)
                        } else {
                            if kind == .temperature || kind == .tirePressure {
                                LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value), series: .value("Series", sample.series))
                                    .foregroundStyle(color(for: sample))
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .interpolationMethod(.linear)
                            } else {
                                LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                                    .foregroundStyle(color(for: sample))
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .interpolationMethod(kind == .speed ? .catmullRom : .linear)
                            }
                            if sample.isHighlighted {
                                PointMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                                    .foregroundStyle(kind == .power ? .green : .red)
                                    .symbolSize(26)
                            }
                        }
                    }
                    if let selectedSample = selectedSamples.first {
                        RuleMark(x: .value("Selected time", selectedSample.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ForEach(selectedSamples) { sample in
                            PointMark(x: .value("Selected time", sample.date), y: .value("Selected value", sample.value))
                                .foregroundStyle(color(for: sample))
                                .symbolSize(48)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartYScale(domain: yDomain)
                .chartXSelection(value: $selectedDate)
                .frame(height: 190)
                selectionDetail
                legend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var samples: [DriveChartSample] {
        chartSamples
    }

    private var selectedSamples: [DriveChartSample] {
        guard let selectedDate else { return [] }
        return DriveChartSelection.samples(at: selectedDate, in: samples)
    }

    private var headerValue: String? {
        DriveChartHeaderPresentation.valueText(
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: sourcePressureUnit
        )
    }

    private var yDomain: ClosedRange<Double> {
        DriveChartScale.domain(kind: kind, samples: samples) ?? 0...1
    }

    private var xAxisDates: [Date] {
        DriveChartAxisPresentation.interiorDates(samples: samples)
    }

    @ViewBuilder
    private var selectionDetail: some View {
        if let sample = selectedSamples.first {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    selectionTime(sample.date)
                    selectionValues
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 5) {
                    selectionTime(sample.date)
                    selectionValues
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 34, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func selectionTime(_ date: Date) -> some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit().weight(.semibold))
            .fixedSize()
    }

    private var selectionValues: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(selectedSamples) { selectedSample in
                    selectionItem(selectedSample)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 5) {
                ForEach(selectedSamples) { selectedSample in
                    selectionItem(selectedSample)
                }
            }
        }
    }

    private func selectionItem(_ sample: DriveChartSample) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color(for: sample)).frame(width: 7, height: 7)
            Text(selectionValue(sample))
                .font(.caption.monospacedDigit())
                .fixedSize()
        }
    }

    private func selectionValue(_ sample: DriveChartSample) -> String {
        let value = sample.value.formatted(.number.precision(.fractionLength(kind == .elevation ? 0 : 1)))
        switch kind {
        case .speed: return "\(value) \(units?.isImperial == true ? "mph" : "km/h")"
        case .power: return "\(value) kW"
        case .battery: return "\(value)%"
        case .elevation: return "\(value) \(units?.isImperial == true ? "ft" : "m")"
        case .temperature:
            let label = sample.series == "inside" ? t("Inside", "车内") : t("Outside", "车外")
            return "\(label) \(value)°\(units?.isImperial == true ? "F" : "C")"
        case .tirePressure:
            return "\(wheelTitle(sample.series)) \(value) \(MateDriveUnitFormatter.pressureUnit(units: units))"
        }
    }

    @ViewBuilder
    private var legend: some View {
        switch kind {
        case .power:
            HStack { legendItem(t("Traction", "驱动"), .orange); legendItem(t("Regeneration", "能量回收"), .green) }
        case .battery:
            HStack { legendItem(t("Battery", "电量"), .green); legendItem(t("Battery heating", "电池加热"), .red) }
        case .temperature:
            HStack { legendItem(t("Outside", "车外"), .blue); legendItem(t("Inside", "车内"), .green) }
        case .tirePressure:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 6) {
                legendItem(t("Front Left", "左前"), .blue)
                legendItem(t("Front Right", "右前"), .green)
                legendItem(t("Rear Left", "左后"), .orange)
                legendItem(t("Rear Right", "右后"), .purple)
            }
        default:
            EmptyView()
        }
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        Label { Text(text).font(.caption).foregroundStyle(.secondary) } icon: { Circle().fill(color).frame(width: 8, height: 8) }
    }

    private func color(for sample: DriveChartSample) -> Color {
        switch kind {
        case .speed: return .blue
        case .power: return .orange
        case .battery: return .green
        case .elevation: return .brown
        case .temperature: return sample.series == "inside" ? .green : .blue
        case .tirePressure:
            switch sample.series {
            case "frontLeft": return .blue
            case "frontRight": return .green
            case "rearLeft": return .orange
            default: return .purple
            }
        }
    }

    private func wheelTitle(_ series: String) -> String {
        switch series {
        case "frontLeft": return t("Front Left", "左前")
        case "frontRight": return t("Front Right", "右前")
        case "rearLeft": return t("Rear Left", "左后")
        default: return t("Rear Right", "右后")
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
