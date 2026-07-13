import SwiftUI

public struct DrivesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DrivesViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: DrivesViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
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
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle(t("Drives", "行程"))
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
                HStack(alignment: .bottom, spacing: 8) {
                    let maxDistance = max(viewModel.state.chartData.compactMap(\.totalDistance).max() ?? 1, 1)
                    ForEach(viewModel.state.chartData) { point in
                        VStack(spacing: 6) {
                            Text(DrivesPresentation.distanceText(point.totalDistance, isComplete: point.distanceIsComplete, units: resolvedUnits))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(.tint)
                                .frame(height: max(12, CGFloat((point.totalDistance ?? 0) / maxDistance) * 120))
                                .overlay(alignment: .bottom) {
                                    Text("\(point.count)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.bottom, 3)
                                }
                                .help(chartHelpText(count: point.count, distance: DrivesPresentation.distanceText(point.totalDistance, isComplete: point.distanceIsComplete, units: resolvedUnits)))
                            Text(point.label)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 170)
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
                Button {
                    navigate(.driveDetail(carId: carId, driveId: row.driveId, exteriorColor: exteriorColor))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "road.lanes")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 4) {
                            routeText(row)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                            Text("\(dateText(row.startDate)) · \(DrivesPresentation.distanceText(row.distance, isComplete: row.distance != nil, units: resolvedUnits)) · \(DrivesPresentation.durationText(row.durationMin, isComplete: row.durationMin != nil, language: appLanguage))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if let efficiency = row.efficiency {
                                Text(verbatim: "\(efficiencyText(efficiency)) · \(DriveEnergySourcePresentation.subtitle(for: row.efficiencySource, language: appLanguage))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(t("Compare", "比较")) {
                        navigate(.compareDrives(carId: carId, baseDriveId: row.driveId, exteriorColor: exteriorColor))
                    }
                }
            }
        }
    }

    private func routeText(_ row: DriveRow) -> Text {
        let start = cleanedAddress(row.startAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("Start", "开始"))
        let end = cleanedAddress(row.endAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("End", "结束"))
        return start + Text(" -> ") + end
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
        value > 0 ? MateDroidUnitFormatter.formatEfficiency(value, units: resolvedUnits, decimals: 0) : "--"
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
        if MateDroidUnitFormatter.usesChineseLabels(language: appLanguage) {
            return "\(count) 次行程 · \(distance)"
        }
        return "\(count) drives · \(distance)"
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
        value.map { (isComplete ? "" : "≥") + MateDroidUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    public static func durationText(_ value: Int?, isComplete: Bool, language: AppLanguage) -> String {
        value.map { (isComplete ? "" : "≥") + MateDroidUnitFormatter.formatDuration(minutes: $0, language: language) } ?? "--"
    }

    public static func efficiencyText(_ value: Double?, units: UnitPreferences?) -> String {
        guard let value, value > 0 else { return "--" }
        return MateDroidUnitFormatter.formatEfficiency(value, units: units, decimals: 0)
    }
}
