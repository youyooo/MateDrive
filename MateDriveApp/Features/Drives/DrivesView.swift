import SwiftUI

public struct DrivesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DrivesViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let detailCacheKey: (Int) -> DriveDetailCacheKey
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        exteriorColor: String?,
        viewModel: DrivesViewModel,
        detailCacheKey: @escaping (Int) -> DriveDetailCacheKey,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.detailCacheKey = detailCacheKey
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading drives", "正在加载行程"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        filters
                        if viewModel.state.isUsingCachedData {
                            Label(
                                t("Showing saved drives. Pull to refresh when the server is available.", "正在显示已保存的行程；服务器恢复后下拉刷新。"),
                                systemImage: "icloud.slash"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                        summary
                        histogram
                        rows
                    }
                    .padding(16)
                }
                .contentMargins(.bottom, 96, for: .scrollContent)
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle(t("Drives", "行程"))
        .accessibilityIdentifier("drives_view")
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker(t("Date", "日期"), selection: Binding(
                get: { viewModel.state.dateFilter },
                set: { viewModel.setDateFilter($0) }
            )) {
                ForEach(DriveDateFilter.allCases, id: \.self) { filter in
                    Text(filter.title(language: appLanguage)).tag(filter)
                }
            }
            .pickerStyle(.menu)

            Spacer()

            Picker(t("Distance", "距离"), selection: Binding(
                get: { viewModel.state.distanceFilter },
                set: { viewModel.setDistanceFilter($0) }
            )) {
                ForEach(DriveDistanceFilter.allCases, id: \.self) { filter in
                    Text(filter.title(language: appLanguage)).tag(filter)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Drives", "行程"), value: "\(viewModel.state.summary.totalDrives)", systemImage: "number")
            MetricCard(title: t("Distance", "距离"), value: DrivesPresentation.distanceText(viewModel.state.summary.totalDistanceKm, isComplete: viewModel.state.summary.distanceIsComplete, units: resolvedUnits), subtitle: coverageText(known: viewModel.state.summary.distanceRecordCount, total: viewModel.state.summary.totalDrives, english: "Distance coverage", chinese: "里程覆盖"), systemImage: "road.lanes")
            MetricCard(title: t("Duration", "时长"), value: DrivesPresentation.durationText(viewModel.state.summary.totalDurationMin, isComplete: viewModel.state.summary.durationIsComplete, language: appLanguage), subtitle: coverageText(known: viewModel.state.summary.durationRecordCount, total: viewModel.state.summary.totalDrives, english: "Duration coverage", chinese: "时长覆盖"), systemImage: "clock")
            MetricCard(
                title: t("Efficiency", "效率"),
                value: DrivesPresentation.efficiencyText(viewModel.state.summary.avgEfficiencyWhKm, units: resolvedUnits),
                subtitle: efficiencySummary,
                systemImage: "gauge"
            )
        }
    }

    private var histogram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Distance", "距离"))
                .font(.headline)
            if viewModel.state.chartData.isEmpty {
                LoadingStateView(title: t("No drive history", "暂无行程记录"), systemImage: "road.lanes")
            } else {
                HStack(spacing: 14) {
                    Label(t("Actual", "实际行驶"), systemImage: "circle.fill")
                        .foregroundStyle(.green)
                    Label(t("Rated range used", "表显消耗"), systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium))

                HStack(alignment: .bottom, spacing: 8) {
                    let maximum = max(
                        viewModel.state.chartData.flatMap { [$0.totalDistance, $0.totalRatedRangeDrop] }.compactMap { $0 }.max() ?? 1,
                        1
                    )
                    ForEach(viewModel.state.chartData) { point in
                        VStack(spacing: 6) {
                            Text(DrivesPresentation.distanceText(point.totalDistance, isComplete: point.distanceIsComplete, units: resolvedUnits))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            ZStack(alignment: .bottom) {
                                if let ratedRangeDrop = point.totalRatedRangeDrop {
                                    HistoryHistogramBar(
                                        color: .orange.opacity(0.82),
                                        height: max(8, CGFloat(ratedRangeDrop / maximum) * 112)
                                    )
                                }
                                HistoryHistogramBar(
                                    color: .green,
                                    height: max(12, CGFloat((point.totalDistance ?? 0) / maximum) * 112),
                                    width: point.totalRatedRangeDrop == nil ? 44 : 22
                                )
                                    .overlay(alignment: .bottom) {
                                        Text("\(point.count)")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .padding(.bottom, 3)
                                    }
                            }
                            .frame(height: 112, alignment: .bottom)
                                .help(chartHelpText(count: point.count, distance: DrivesPresentation.distanceText(point.totalDistance, isComplete: point.distanceIsComplete, units: resolvedUnits)))
                            performanceText(actual: point.totalDistance, ratedRangeDrop: point.totalRatedRangeDrop)
                            Text(point.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 206)
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            ForEach(viewModel.state.rows) { row in
                driveCard(row)
                .contextMenu {
                    Button(t("Compare", "比较")) {
                        navigate(.compareDrives(carId: carId, baseDriveId: row.driveId, exteriorColor: exteriorColor))
                    }
                }
            }
        }
    }

    private func driveCard(_ row: DriveRow) -> some View {
        VStack(spacing: 0) {
            Button {
                viewModel.primeDetailSnapshot(
                    driveId: row.driveId,
                    cacheKey: detailCacheKey(row.driveId)
                )
                navigate(.driveDetail(carId: carId, driveId: row.driveId, exteriorColor: exteriorColor))
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: row.intelligence?.confirmedLabel?.iconName ?? "road.lanes")
                        .foregroundStyle(labelColor(row))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) {
                        if let label = row.intelligence?.confirmedLabel {
                            Text(verbatim: label.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PaletteColor(hex: label.colorHex).color)
                        }
                        routeText(row)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                        Text("\(dateText(row.startDate)) · \(t("Actual", "实际")) \(DrivesPresentation.distanceText(row.distance, isComplete: row.distance != nil, units: resolvedUnits)) · \(DrivesPresentation.durationText(row.durationMin, isComplete: row.durationMin != nil, language: appLanguage))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        HStack(spacing: 8) {
                            if let efficiency = row.efficiency {
                                Label(efficiencyText(efficiency), systemImage: "bolt.fill")
                            }
                            if row.climateOnFraction.map({ $0 > 0.05 }) == true {
                                Image(systemName: "fan.fill")
                                    .accessibilityLabel(t("Climate active", "空调已开启"))
                            }
                            if let temperature = row.outsideTempAvg {
                                Text(MateDriveUnitFormatter.formatTemperature(temperature, units: resolvedUnits))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        benchmarkLine(row)
                        if let ratedRangeDrop = row.ratedRangeDropKm {
                            Text("\(t("Rated used", "表显消耗")) \(DrivesPresentation.distanceText(ratedRangeDrop, isComplete: true, units: resolvedUnits)) · \(performanceLabel(actual: row.distance, ratedRangeDrop: ratedRangeDrop))")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(performanceColor(actual: row.distance, ratedRangeDrop: ratedRangeDrop))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("drive_row_\(row.driveId)")
            .buttonStyle(.plain)

            if let suggestion = row.intelligence?.suggestion {
                Divider().padding(.horizontal, 14)
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.direction == .outbound
                             ? t("Possible commute to work", "疑似上班通勤")
                             : t("Possible commute home", "疑似下班通勤"))
                            .font(.caption.weight(.semibold))
                        Text(t("Matched \(suggestion.matchingDriveCount) similar drives", "已匹配 \(suggestion.matchingDriveCount) 次相似行程"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(t("Confirm", "设为通勤")) {
                        Task { await viewModel.confirmSuggestion(for: row.driveId) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(.green)
                }
                .padding(12)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor(row), lineWidth: borderWidth(row))
        }
        .overlay(alignment: .topTrailing) {
            if row.intelligence?.benchmark.accent == .personalBest {
                Label(t("New personal best", "新的个人最佳"), systemImage: "trophy.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.yellow, in: UnevenRoundedRectangle(bottomLeadingRadius: 6, topTrailingRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func benchmarkLine(_ row: DriveRow) -> some View {
        if let benchmark = row.intelligence?.benchmark {
            if let difference = benchmark.percentageDifference {
                let percent = Int(abs(difference).rounded())
                Text(difference <= 0
                     ? t("\(percent)% better than baseline", "优于标定 \(percent)%")
                     : t("\(percent)% above baseline", "高于标定 \(percent)%"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(difference <= 0 ? .green : .orange)
            } else if row.intelligence?.confirmedLabel != nil, benchmark.samplesNeeded > 0 {
                Text(t(
                    "Complete \(benchmark.samplesNeeded) more similar drives to establish your baseline",
                    "再完成 \(benchmark.samplesNeeded) 次相似行程，即可建立个人标定"
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func labelColor(_ row: DriveRow) -> Color {
        row.intelligence?.confirmedLabel.map { PaletteColor(hex: $0.colorHex).color } ?? .blue
    }

    private func borderColor(_ row: DriveRow) -> Color {
        switch row.intelligence?.benchmark.accent ?? .neutral {
        case .efficient, .personalBest: return .green
        case .aboveBenchmark: return .orange
        case .gold: return .yellow
        case .silver: return Color(uiColor: .systemGray2)
        case .bronze: return Color(red: 0.72, green: 0.43, blue: 0.22)
        case .neutral: return Color(uiColor: .separator).opacity(0.55)
        }
    }

    private func borderWidth(_ row: DriveRow) -> CGFloat {
        switch row.intelligence?.benchmark.accent ?? .neutral {
        case .neutral: return 0.75
        default: return 1.5
        }
    }

    private func routeText(_ row: DriveRow) -> Text {
        let start = cleanedAddress(row.startAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("Start", "开始"))
        let end = cleanedAddress(row.endAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("End", "结束"))
        return start + Text(" → ") + end
    }

    private func cleanedAddress(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var resolvedUnits: UnitPreferences? {
        viewModel.state.units.resolved(for: appDisplayUnitSystem)
    }

    private func efficiencyText(_ value: Double) -> String {
        value > 0 ? MateDriveUnitFormatter.formatEfficiency(value, units: resolvedUnits, decimals: 0) : "--"
    }

    private var efficiencySummary: String? {
        let summary = viewModel.state.summary
        var parts: [String] = []
        if summary.efficiencyRecordCount < summary.totalDrives {
            parts.append(t("Efficiency coverage \(summary.efficiencyRecordCount)/\(summary.totalDrives)", "效率覆盖 \(summary.efficiencyRecordCount)/\(summary.totalDrives)"))
        }
        if summary.reconstructedEfficiencyCount > 0 {
            parts.append(t("Includes \(summary.reconstructedEfficiencyCount) reconstructed drives", "包含 \(summary.reconstructedEfficiencyCount) 条重建数据"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func coverageText(known: Int, total: Int, english: String, chinese: String) -> String? {
        guard known < total else { return nil }
        return t("\(english) \(known)/\(total)", "\(chinese) \(known)/\(total)")
    }

    private func chartHelpText(count: Int, distance: String) -> String {
        if MateDriveUnitFormatter.usesChineseLabels(language: appLanguage) {
            return "\(count) 次行程 · \(distance)"
        }
        return "\(count) drives · \(distance)"
    }

    @ViewBuilder
    private func performanceText(actual: Double?, ratedRangeDrop: Double?) -> some View {
        if let ratedRangeDrop {
            Text(performanceLabel(actual: actual, ratedRangeDrop: ratedRangeDrop))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(performanceColor(actual: actual, ratedRangeDrop: ratedRangeDrop))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        } else {
            Text(t("--", "--"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func performanceLabel(actual: Double?, ratedRangeDrop: Double) -> String {
        guard let actual else { return "--" }
        let delta = actual - ratedRangeDrop
        let magnitude = MateDriveUnitFormatter.formatDistance(abs(delta), units: resolvedUnits, decimals: 1)
        if abs(delta) < 0.05 {
            return t("Matches rated", "与表显持平")
        }
        return delta > 0
            ? t("Ahead +\(magnitude)", "跑赢 +\(magnitude)")
            : t("Behind -\(magnitude)", "少跑 -\(magnitude)")
    }

    private func performanceColor(actual: Double?, ratedRangeDrop: Double) -> Color {
        guard let actual else { return .secondary }
        let delta = actual - ratedRangeDrop
        if abs(delta) < 0.05 { return .secondary }
        return delta > 0 ? .green : .orange
    }

    private func dateText(_ value: String) -> String {
        guard let date = DomainDateParser.date(from: value) else {
            return value
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum DrivesPresentation {
    public static func distanceText(_ value: Double?, isComplete: Bool, units: UnitPreferences?) -> String {
        value.map { (isComplete ? "" : "≥") + MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    public static func durationText(_ value: Int?, isComplete: Bool, language: AppLanguage) -> String {
        value.map { (isComplete ? "" : "≥") + MateDriveUnitFormatter.formatDuration(minutes: $0, language: language) } ?? "--"
    }

    public static func efficiencyText(_ value: Double?, units: UnitPreferences?) -> String {
        guard let value, value > 0 else { return "--" }
        return MateDriveUnitFormatter.formatEfficiency(value, units: units, decimals: 0)
    }
}
