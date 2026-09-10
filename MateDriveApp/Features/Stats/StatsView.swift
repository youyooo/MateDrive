import SwiftUI

public struct StatsView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: StatsViewModel
    @State private var hasLoaded = false
    @State private var heatmapMetric: StatsHeatmapMetric = .distance

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: StatsViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, !hasVisibleContent {
                LoadingStateView(title: t("Loading stats", "正在加载统计"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let errorMessage = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                        filters
                        summary
                        activityHeatmap
                        serverInsights
                        records
                        navigationRows
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Stats", "统计"))
        .accessibilityIdentifier("stats_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var hasVisibleContent: Bool {
        viewModel.state.serverStats != nil
            || !viewModel.state.availableYears.isEmpty
            || viewModel.state.summary != .empty
            || !viewModel.state.dailyActivity.isEmpty
    }

    private var filters: some View {
        Picker(t("Year", "年份"), selection: Binding(
            get: { viewModel.state.selectedFilter },
            set: { viewModel.setFilter($0) }
        )) {
            Text(t("All Time", "全部")).tag(StatsYearFilter.allTime)
            ForEach(viewModel.state.availableYears, id: \.self) { year in
                Text("\(year)").tag(StatsYearFilter.year(year))
            }
        }
        .pickerStyle(.menu)
    }

    private var summary: some View {
        let summary = viewModel.state.summary
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: localizedTitle("Drives"), value: "\(summary.totalDrives)", systemImage: "road.lanes")
            MetricCard(
                title: localizedTitle("Distance"),
                value: StatsCoveragePresentation.valuePrefix(missingCount: viewModel.displayedDistanceMissingCount) + distanceText(viewModel.displayedTotalDistance),
                subtitle: distanceCoverageText,
                systemImage: "speedometer"
            )
            MetricCard(title: localizedTitle("Charges"), value: "\(summary.totalCharges)", systemImage: "bolt.fill")
            MetricCard(
                title: localizedTitle("Energy Added"),
                value: StatsCoveragePresentation.valuePrefix(missingCount: summary.missingChargeEnergyCount) + String(format: "%.1f kWh", summary.totalChargeEnergy),
                subtitle: chargeEnergyCoverageText,
                systemImage: "battery.100percent"
            )
            MetricCard(
                title: t("Known Charge Cost", "已知充电费用"),
                value: "\(viewModel.state.currencySymbol)\(String(format: "%.2f", viewModel.displayedTotalChargeCost))",
                subtitle: chargeCostCoverageText,
                systemImage: "creditcard"
            )
            MetricCard(title: t("Parking Cost", "停车费用"), value: parkingCostText, systemImage: "parkingsign.circle")
            MetricCard(title: t("Vehicle Cost", "车辆总成本"), value: totalVehicleCostText, systemImage: "car.side")
            MetricCard(title: localizedTitle("AC / DC"), value: "\(summary.acCharges) / \(summary.dcCharges)", systemImage: "powerplug")
            Text(summarySourceText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .gridCellColumns(2)
        }
    }

    private var parkingCostText: String {
        guard viewModel.state.parkingCostAvailable else { return t("Unavailable", "不可用") }
        return "\(viewModel.state.currencySymbol)\(String(format: "%.2f", viewModel.state.parkingCost.totalCost))"
    }

    private var totalVehicleCostText: String {
        guard let total = viewModel.displayedTotalVehicleCost else { return t("Incomplete", "不完整") }
        return "\(viewModel.state.currencySymbol)\(String(format: "%.2f", total))"
    }

    private var chargeCostCoverageText: String {
        if viewModel.usesServerAllTimeSummary, !viewModel.usesLocalChargeCostTotal {
            return t("TeslaMate API aggregate", "TeslaMate API 汇总")
        }
        let summary = viewModel.state.summary
        if MateDriveUnitFormatter.usesChineseLabels(language: appLanguage) {
            return "覆盖 \(summary.pricedChargeCount)/\(summary.totalCharges) 条\n接口 \(summary.apiChargeCostCount) · 规则 \(summary.pricingRuleChargeCostCount) · 手动 \(summary.manualChargeCostCount)"
        }
        return "Coverage \(summary.pricedChargeCount)/\(summary.totalCharges)\nAPI \(summary.apiChargeCostCount) · rules \(summary.pricingRuleChargeCostCount) · manual \(summary.manualChargeCostCount)"
    }

    private var summarySourceText: String {
        if viewModel.state.parkingCostAvailable, viewModel.state.parkingCost.unmatchedParkingCount > 0 {
            return t(
                "Vehicle cost excludes \(viewModel.state.parkingCost.unmatchedParkingCount) unmatched parking records.",
                "车辆总成本未包含 \(viewModel.state.parkingCost.unmatchedParkingCount) 条未匹配停车记录。"
            )
        }
        if viewModel.state.parkingCostAvailable, !viewModel.state.parkingHistoryComplete {
            return t("Parking history is partial; vehicle cost is incomplete.", "停车历史不完整，车辆总成本并非完整值。")
        }
        if viewModel.usesServerAllTimeSummary, viewModel.usesLocalChargeCostTotal {
            return t("Distance: TeslaMate API · Cost: per-record local pricing", "距离：TeslaMate API · 费用：逐笔本地价格")
        }
        if viewModel.usesServerAllTimeSummary {
            return t("Distance and cost: TeslaMate API", "距离和费用：TeslaMate API")
        }
        return t("Calculated locally from loaded records", "根据已加载记录在本地计算")
    }

    @ViewBuilder
    private var activityHeatmap: some View {
        if let year = viewModel.state.heatmapYear, !viewModel.state.dailyActivity.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("Year Activity", "全年活动"))
                        .font(.headline)
                    Spacer()
                    Text(verbatim: "\(year)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Picker(t("Metric", "指标"), selection: $heatmapMetric) {
                    Text(t("Driving", "驾驶")).tag(StatsHeatmapMetric.distance)
                    Text(t("Charging", "充电")).tag(StatsHeatmapMetric.chargingEnergy)
                }
                .pickerStyle(.segmented)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(12), spacing: 3), count: 7), spacing: 3) {
                        ForEach(Array(heatmapCells.enumerated()), id: \.offset) { _, activity in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(heatmapColor(for: activity))
                                .frame(width: 12, height: 12)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 102)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heatmapAccessibilityLabel(year: year))
                .accessibilityValue(heatmapAccessibilityValue)
                .accessibilityIdentifier("stats_heatmap_summary")

                HStack(spacing: 6) {
                    Text(t("Less", "较少"))
                    ForEach(1...5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(heatmapTint.opacity(0.12 + Double(level) * 0.16))
                            .frame(width: 12, height: 12)
                    }
                    Text(t("More", "较多"))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var serverInsights: some View {
        if let stats = viewModel.state.serverStats {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("Server Insights", "服务端洞察"))
                        .font(.headline)
                    Spacer()
                    Text("TeslaMate API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    MetricCard(title: t("Net Consumption", "净能耗"), value: efficiencyText(stats.avgConsumptionNet), systemImage: "leaf")
                    MetricCard(title: t("Gross Consumption", "总能耗"), value: efficiencyText(stats.avgConsumptionGross), systemImage: "bolt")
                    MetricCard(title: t("Regen Capture", "能量回收捕获率"), value: percentText(stats.avgRegenCaptureRate, fraction: true), systemImage: "arrow.triangle.2.circlepath")
                    MetricCard(title: t("Hard Braking", "急刹车"), value: integerText(stats.totalHardBrakingCount), systemImage: "exclamationmark.octagon")
                    MetricCard(title: hardBrakingRateTitle, value: hardBrakingRateText(stats.avgHardBrakingPer100km), systemImage: "chart.bar")
                    MetricCard(title: t("Standby Range Loss", "待机续航损耗"), value: stats.totalStandbyRangeLossKm.map(distanceText) ?? noDataText, systemImage: "moon.zzz")
                    MetricCard(title: t("Standby Drain Rate", "待机损耗速率"), value: stats.avgDrainRateKmH.map { StatsUnitPresentation.drainRate($0, units: resolvedUnits) } ?? noDataText, systemImage: "gauge.with.dots.needle.33percent")
                    MetricCard(title: t("Parking Events", "停车事件"), value: integerText(stats.parkingEventCount), systemImage: "parkingsign.circle")
                    MetricCard(title: t("New Places", "新地点"), value: integerText(stats.newPlaceDriveCount), systemImage: "mappin.and.ellipse")
                    MetricCard(title: t("Commute Routes", "通勤路线"), value: integerText(stats.commuteRouteCount), systemImage: "arrow.triangle.swap")
                }
                if let checkedAt = viewModel.state.serverStatsCheckedAt {
                    Text(t("Updated", "更新时间") + " " + checkedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Records", "纪录"))
                .font(.headline)
            if let longest = viewModel.state.summary.longestDrive {
                recordButton(title: localizedTitle("Longest Drive"), value: longest.distance.map(distanceText) ?? "--", drive: longest)
            }
            if let efficient = viewModel.state.summary.mostEfficientDrive {
                recordButton(title: localizedTitle("Most Efficient"), value: efficient.efficiencyWhKm.map { MateDriveUnitFormatter.formatEfficiency($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem), decimals: 0) } ?? "--", drive: efficient)
            }
        }
    }

    private var navigationRows: some View {
        VStack(spacing: 10) {
            Button {
                navigate(.costReview(carId: carId, exteriorColor: exteriorColor))
            } label: {
                HStack {
                    Label(t("Vehicle Cost Review", "用车成本回顾"), systemImage: "chart.line.uptrend.xyaxis")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats_cost_review_button")
            Button {
                navigate(.drivingRecords(carId: carId, exteriorColor: exteriorColor))
            } label: {
                Label(t("All Driving Records", "全部驾驶纪录"), systemImage: "trophy")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats_driving_records_button")
            Button {
                let year: Int?
                if case let .year(value) = viewModel.state.selectedFilter {
                    year = value
                } else {
                    year = nil
                }
                navigate(.countriesVisited(carId: carId, exteriorColor: exteriorColor, year: year))
            } label: {
                Label(t("Countries Visited", "到访国家"), systemImage: "globe.europe.africa")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stats_countries_button")
        }
    }

    private func recordButton(title: String, value: String, drive: DriveData) -> some View {
        Button {
            if let driveId = drive.driveId {
                navigate(.driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor))
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: title)
                        .font(.body.weight(.semibold))
                    Text(drive.startDate.flatMap { DomainDateParser.date(from: $0)?.formatted(date: .abbreviated, time: .omitted) } ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(value)
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private func distanceText(_ value: Double) -> String {
        MateDriveUnitFormatter.formatDistance(value, units: resolvedUnits)
    }

    private var distanceCoverageText: String? {
        let summary = viewModel.state.summary
        let missing = viewModel.displayedDistanceMissingCount
        guard missing > 0 else { return nil }
        return StatsCoveragePresentation.coverageText(
            known: summary.totalDrives - missing,
            total: summary.totalDrives,
            nounKey: "drives",
            language: appLanguage
        )
    }

    private var chargeEnergyCoverageText: String? {
        let summary = viewModel.state.summary
        guard summary.missingChargeEnergyCount > 0 else { return nil }
        return StatsCoveragePresentation.coverageText(
            known: summary.totalCharges - summary.missingChargeEnergyCount,
            total: summary.totalCharges,
            nounKey: "Charges",
            language: appLanguage
        )
    }

    private var resolvedUnits: UnitPreferences? { viewModel.state.units.resolved(for: appDisplayUnitSystem) }

    private var hardBrakingRateTitle: String {
        resolvedUnits?.isImperial == true ? t("Hard Braking per 100 mi", "每百英里急刹车") : t("Hard Braking per 100 km", "每百公里急刹车")
    }

    private func hardBrakingRateText(_ value: Double?) -> String {
        value.map { String(format: "%.1f", StatsUnitPresentation.hardBrakingPer100($0, units: resolvedUnits)) } ?? noDataText
    }

    private var noDataText: String { t("No data", "暂无数据") }

    private func efficiencyText(_ value: Double?) -> String {
        value.map { MateDriveUnitFormatter.formatEfficiency($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem), decimals: 0) } ?? noDataText
    }

    private func percentText(_ value: Double?, fraction: Bool) -> String {
        guard let value else { return noDataText }
        return String(format: "%.1f%%", fraction ? value * 100 : value)
    }

    private func integerText(_ value: Int?) -> String {
        value.map(String.init) ?? noDataText
    }

    private func decimalText(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? noDataText
    }

    private var heatmapCells: [StatsDailyActivity?] {
        guard let first = viewModel.state.dailyActivity.first else { return [] }
        let calendar = Calendar.current
        let leading = (calendar.component(.weekday, from: first.date) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + viewModel.state.dailyActivity.map(Optional.some)
    }

    private var heatmapMaximum: Double {
        max(viewModel.state.dailyActivity.map(heatmapValue).max() ?? 0, 0)
    }

    private var heatmapTint: Color {
        heatmapMetric == .distance ? .green : .blue
    }

    private func heatmapValue(_ activity: StatsDailyActivity) -> Double {
        switch heatmapMetric {
        case .distance:
            return activity.distanceKm
        case .chargingEnergy:
            return activity.chargeEnergyKWh
        }
    }

    private func heatmapColor(for activity: StatsDailyActivity?) -> Color {
        guard let activity else { return .clear }
        let value = heatmapValue(activity)
        guard value > 0, heatmapMaximum > 0 else {
            return Color(uiColor: .tertiarySystemFill)
        }
        return heatmapTint.opacity(0.18 + 0.82 * min(value / heatmapMaximum, 1))
    }

    private func heatmapAccessibilityLabel(year: Int) -> String {
        switch heatmapMetric {
        case .distance:
            return t("\(year) driving activity", "\(year) 年驾驶活动")
        case .chargingEnergy:
            return t("\(year) charging activity", "\(year) 年充电活动")
        }
    }

    private var heatmapAccessibilityValue: String {
        let activeDays = viewModel.state.dailyActivity.filter { heatmapValue($0) > 0 }.count
        switch heatmapMetric {
        case .distance:
            let totalDistance = viewModel.state.dailyActivity.reduce(0) { $0 + $1.distanceKm }
            let driveCount = viewModel.state.dailyActivity.reduce(0) { $0 + $1.driveCount }
            return t(
                "\(activeDays) active days, \(distanceText(totalDistance)), \(driveCount) drives",
                "\(activeDays) 个活跃日，共 \(distanceText(totalDistance))，\(driveCount) 次行程"
            )
        case .chargingEnergy:
            let totalEnergy = viewModel.state.dailyActivity.reduce(0) { $0 + $1.chargeEnergyKWh }
            let chargeCount = viewModel.state.dailyActivity.reduce(0) { $0 + $1.chargeCount }
            return t(
                "\(activeDays) active days, \(String(format: "%.1f kWh", totalEnergy)), \(chargeCount) charges",
                "\(activeDays) 个活跃日，共 \(String(format: "%.1f kWh", totalEnergy))，\(chargeCount) 次充电"
            )
        }
    }

    private func localizedTitle(_ key: String) -> String {
        DashboardTextFormatter.title(key, language: appLanguage)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum StatsCoveragePresentation {
    public static func valuePrefix(missingCount: Int) -> String {
        missingCount > 0 ? "≥" : ""
    }

    public static func coverageText(known: Int, total: Int, nounKey: String, language: AppLanguage) -> String {
        let label = AppText.localized("Data coverage", "数据覆盖", language: language)
        let noun = AppText.localized(nounKey, nounKey == "drives" ? "次行程" : "充电记录", language: language)
        let separator = AppText.usesTraditionalChinese(language: language) || language == .chinese ? "：" : ": "
        return "\(label)\(separator)\(known)/\(total) \(noun)"
    }
}

public enum StatsUnitPresentation {
    public static func hardBrakingPer100(_ valuePer100Km: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? valuePer100Km * 1.609344 : valuePer100Km
    }

    public static func drainRate(_ kilometersPerHour: Double, units: UnitPreferences?) -> String {
        let value = MateDriveUnitFormatter.distanceValue(kilometersPerHour, units: units)
        return String(format: "%.2f %@/h", value, MateDriveUnitFormatter.distanceUnit(units: units))
    }
}

private enum StatsHeatmapMetric: Hashable {
    case distance
    case chargingEnergy
}
