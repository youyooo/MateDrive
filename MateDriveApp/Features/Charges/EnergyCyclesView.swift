import Charts
import SwiftUI

public struct EnergyCyclesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: EnergyCyclesViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        exteriorColor: String?,
        viewModel: EnergyCyclesViewModel,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.analysis == nil {
                LoadingStateView(title: t("Loading energy balance", "正在加载能量收支"), showsProgress: true)
            } else if let analysis = viewModel.state.analysis {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        periodPicker
                        if let errorMessage = viewModel.state.errorMessage {
                            Label(UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage), systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        periodSummary(analysis)
                        dataScopeNotes
                        rangeTrend(analysis.rangeTrend)
                        recentCycles(analysis.recentCycles)
                    }
                    .padding(16)
                }
                .refreshable { await viewModel.refresh() }
            } else {
                LoadingStateView(
                    title: t("Energy balance unavailable", "能量收支不可用"),
                    message: viewModel.state.errorMessage,
                    systemImage: "bolt.slash"
                )
            }
        }
        .navigationTitle(t("Energy Balance", "能量收支"))
        .accessibilityIdentifier("energy_cycles_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var periodPicker: some View {
        Picker(t("Period", "周期"), selection: Binding(
            get: { viewModel.state.selectedPeriod },
            set: { viewModel.selectPeriod($0) }
        )) {
            ForEach(EnergyCyclePeriod.allCases, id: \.self) { period in
                Text(period.title(language: appLanguage)).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private func periodSummary(_ analysis: EnergyCycleAnalysis) -> some View {
        let summary = analysis.current
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(analysis.selectedPeriod.title(language: appLanguage))
                    .font(.title2.weight(.semibold))
                Spacer()
                Text(t("\(summary.chargeCount) charges · \(summary.driveCount) drives", "\(summary.chargeCount) 次充电 · \(summary.driveCount) 次行驶"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if summary.isEmpty {
                LoadingStateView(title: t("No records in this period", "该周期暂无记录"), systemImage: "calendar.badge.exclamationmark")
                    .frame(minHeight: 110)
            } else {
                energyChart(summary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: t("Charger Input", "桩侧输入"),
                        value: energyText(summary.chargerInputKWh, complete: summary.chargerInputIsComplete),
                        subtitle: metricSubtitle(
                            current: summary.chargerInputKWh,
                            previous: analysis.previous.chargerInputKWh,
                            coverage: coverage(summary.chargerInputRecordCount, summary.chargeCount),
                            period: analysis.selectedPeriod,
                            unit: "kWh"
                        ),
                        systemImage: "powerplug.fill",
                        tint: .orange
                    )
                    MetricCard(
                        title: t("Added to Battery", "充入电池"),
                        value: energyText(summary.batteryAddedKWh, complete: summary.batteryAddedIsComplete),
                        subtitle: metricSubtitle(
                            current: summary.batteryAddedKWh,
                            previous: analysis.previous.batteryAddedKWh,
                            coverage: coverage(summary.batteryAddedRecordCount, summary.chargeCount),
                            period: analysis.selectedPeriod,
                            unit: "kWh"
                        ),
                        systemImage: "battery.75percent",
                        tint: .green
                    )
                    MetricCard(
                        title: t("Driving Net Use", "行驶净耗"),
                        value: energyText(summary.drivingEnergyKWh, complete: summary.drivingEnergyIsComplete),
                        subtitle: metricSubtitle(
                            current: summary.drivingEnergyKWh,
                            previous: analysis.previous.drivingEnergyKWh,
                            coverage: coverage(summary.drivingEnergyRecordCount, summary.driveCount),
                            period: analysis.selectedPeriod,
                            unit: "kWh"
                        ),
                        systemImage: "car.fill",
                        tint: .blue
                    )
                    MetricCard(
                        title: t("Distance", "行驶里程"),
                        value: distanceText(summary.distanceKm, complete: summary.distanceIsComplete),
                        subtitle: metricSubtitle(
                            current: displayDistance(summary.distanceKm),
                            previous: displayDistance(analysis.previous.distanceKm),
                            coverage: coverage(summary.distanceRecordCount, summary.driveCount),
                            period: analysis.selectedPeriod,
                            unit: MateDriveUnitFormatter.distanceUnit(units: displayUnits)
                        ),
                        systemImage: "road.lanes"
                    )
                    MetricCard(
                        title: t("Charge SOC", "充电电量变化"),
                        value: summary.chargeSOCAdded.map { "+\($0)%" } ?? "--",
                        subtitle: summary.chargingEfficiency.map { t(String(format: "Input efficiency %.0f%%", $0), String(format: "输入效率 %.0f%%", $0)) },
                        systemImage: "arrow.up.circle",
                        tint: .green
                    )
                    MetricCard(
                        title: t("Driving SOC", "行驶电量变化"),
                        value: summary.driveSOCUsed.map { "-\($0)%" } ?? "--",
                        subtitle: t("Drive records only", "仅统计行驶记录"),
                        systemImage: "arrow.down.circle",
                        tint: .blue
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func energyChart(_ summary: EnergyPeriodSummary) -> some View {
        let items = flowItems(summary)
        if !items.isEmpty {
            Chart(items) { item in
                BarMark(
                    x: .value(t("Energy Type", "能量类型"), item.title),
                    y: .value("kWh", item.value)
                )
                .foregroundStyle(item.color)
                .cornerRadius(4)
                .annotation(position: .top) {
                    Text(String(format: "%.1f", item.value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxisLabel("kWh")
            .frame(height: 170)
        }
    }

    private var dataScopeNotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                t("Charger input is the vehicle-side estimate reported by TeslaMate, not a certified station meter reading.", "桩侧输入为 TeslaMate 根据车辆数据记录的估算值，不等同于充电运营商的结算电表。"),
                systemImage: "info.circle"
            )
            Label(
                t("Driving net use excludes parked climate, Sentry Mode and other standby drain; SOC change helps reveal the remaining gap.", "行驶净耗不包含驻车空调、哨兵和其他待机耗电；SOC 变化可用于观察这部分差额。"),
                systemImage: "moon.zzz"
            )
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func rangeTrend(_ points: [EnergyRangeTrendPoint]) -> some View {
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(t("Recorded Range Trend", "记录期续航趋势"))
                        .font(.headline)
                    Spacer()
                    Button {
                        navigate(.battery(carId: carId, efficiency: nil, exteriorColor: exteriorColor))
                    } label: {
                        Label(t("Battery", "电池"), systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                }
                Chart(Array(points.suffix(120))) { point in
                    LineMark(
                        x: .value(t("Date", "日期"), point.date),
                        y: .value(t("Range at 100%", "满电续航"), distanceValue(point.rangeAt100Km))
                    )
                    .foregroundStyle(.green)
                    PointMark(
                        x: .value(t("Date", "日期"), point.date),
                        y: .value(t("Range at 100%", "满电续航"), distanceValue(point.rangeAt100Km))
                    )
                    .foregroundStyle(.green.opacity(0.55))
                }
                .chartYAxisLabel(MateDriveUnitFormatter.distanceUnit(units: displayUnits))
                .frame(height: 180)
                Text(t(
                    "Normalized from rated range at charge end. Use the Battery page for smoothed recording-period trends and calibration.",
                    "根据充电结束时的额定续航和 SOC 归一到 100%。平滑后的记录期趋势和校准请查看“电池”页面。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func recentCycles(_ cycles: [EnergyCycle]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Charge and Discharge Cycles", "充放电周期"))
                .font(.headline)
            if cycles.isEmpty {
                LoadingStateView(title: t("No completed charge cycles", "暂无完整充放电周期"), systemImage: "arrow.triangle.2.circlepath")
                    .frame(minHeight: 120)
            } else {
                ForEach(Array(cycles.prefix(40))) { cycle in
                    Button {
                        navigate(.chargeDetail(carId: carId, chargeId: cycle.chargeId, exteriorColor: exteriorColor))
                    } label: {
                        EnergyCycleCard(cycle: cycle, units: displayUnits)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var displayUnits: UnitPreferences {
        appDisplayUnitSystem == .imperial ? .imperial : .metric
    }

    private func flowItems(_ summary: EnergyPeriodSummary) -> [EnergyFlowChartItem] {
        [
            summary.chargerInputKWh.map { EnergyFlowChartItem(id: "input", title: t("Charger", "桩侧"), value: $0, color: .orange) },
            summary.batteryAddedKWh.map { EnergyFlowChartItem(id: "battery", title: t("Battery", "电池"), value: $0, color: .green) },
            summary.drivingEnergyKWh.map { EnergyFlowChartItem(id: "drive", title: t("Driving", "行驶"), value: $0, color: .blue) }
        ].compactMap { $0 }
    }

    private func metricSubtitle(
        current: Double?,
        previous: Double?,
        coverage: String?,
        period: EnergyCyclePeriod,
        unit: String
    ) -> String? {
        var parts: [String] = []
        if let current, let previous {
            parts.append("\(period.comparisonTitle(language: appLanguage)) \(String(format: "%+.1f", current - previous)) \(unit)")
        }
        if let coverage {
            parts.append(coverage)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func coverage(_ known: Int, _ total: Int) -> String? {
        guard total > 0, known < total else { return nil }
        return t("Coverage \(known)/\(total)", "覆盖 \(known)/\(total)")
    }

    private func energyText(_ value: Double?, complete: Bool) -> String {
        guard let value else { return "--" }
        return (complete ? "" : "≥") + String(format: "%.1f kWh", value)
    }

    private func distanceText(_ value: Double?, complete: Bool) -> String {
        guard let value else { return "--" }
        return (complete ? "" : "≥") + MateDriveUnitFormatter.formatDistance(value, units: displayUnits)
    }

    private func displayDistance(_ value: Double?) -> Double? {
        value.map { distanceValue($0) }
    }

    private func distanceValue(_ value: Double) -> Double {
        MateDriveUnitFormatter.distanceValue(value, units: displayUnits)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct EnergyFlowChartItem: Identifiable {
    let id: String
    let title: String
    let value: Double
    let color: Color
}

private struct EnergyCycleCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let cycle: EnergyCycle
    let units: UnitPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(cycle.chargeEnd.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(stateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
            }

            flowRow(
                icon: "arrow.up.circle.fill",
                color: .green,
                title: t("Charge", "充电"),
                soc: socText(start: cycle.chargeStartSOC, end: cycle.chargeEndSOC),
                energy: t("Battery \(energy(cycle.batteryAddedKWh)) · Charger \(energy(cycle.chargerInputKWh))", "电池 \(energy(cycle.batteryAddedKWh)) · 桩侧 \(energy(cycle.chargerInputKWh))")
            )
            flowRow(
                icon: "arrow.down.circle.fill",
                color: .blue,
                title: t("Driving", "放电行驶"),
                soc: socText(start: cycle.chargeEndSOC, end: cycle.dischargeEndSOC),
                energy: t("Net \(energy(cycle.drivingEnergyKWh)) · \(distance(cycle.distanceKm))", "净耗 \(energy(cycle.drivingEnergyKWh)) · \(distance(cycle.distanceKm))")
            )

            HStack(spacing: 12) {
                if let efficiency = cycle.chargingEfficiency {
                    Label(String(format: "%.0f%%", efficiency), systemImage: "gauge")
                }
                if let loss = cycle.chargingLossKWh {
                    Label(lossText(loss), systemImage: loss >= 0 ? "waveform.path.ecg" : "exclamationmark.triangle")
                }
                Spacer()
                Text(t("\(cycle.driveCount) drives", "\(cycle.driveCount) 次行驶"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !cycle.drivingEnergyIsComplete || !cycle.distanceIsComplete {
                Text(t(
                    "Drive detail coverage \(cycle.drivingEnergyRecordCount)/\(cycle.driveCount)",
                    "行驶能量覆盖 \(cycle.drivingEnergyRecordCount)/\(cycle.driveCount)"
                ))
                .font(.caption2)
                .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var title: String {
        let cleaned = cycle.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cleaned, !cleaned.isEmpty {
            return cleaned
        }
        return t("Charge #\(cycle.chargeId)", "充电 #\(cycle.chargeId)")
    }

    private var stateTitle: String {
        cycle.state.title(language: appLanguage)
    }

    private var stateColor: Color {
        switch cycle.state {
        case .complete: return .green
        case .open: return .blue
        case .consecutiveCharge: return .orange
        }
    }

    private func flowRow(icon: String, color: Color, title: String, soc: String, energy: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(soc).font(.subheadline.weight(.semibold).monospacedDigit())
                }
                Text(energy)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func socText(start: Int?, end: Int?) -> String {
        guard let start, let end else { return "--" }
        return "\(start)% → \(end)%"
    }

    private func energy(_ value: Double?) -> String {
        value.map { String(format: "%.1f kWh", $0) } ?? "--"
    }

    private func distance(_ value: Double?) -> String {
        value.map { MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    private func lossText(_ value: Double) -> String {
        if value >= 0 {
            return t(String(format: "Loss %.1f kWh", value), String(format: "损耗 %.1f kWh", value))
        }
        return t(String(format: "Meter gap %.1f kWh", abs(value)), String(format: "计量差 %.1f kWh", abs(value)))
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
