import Charts
import SwiftUI

public struct BatteryView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: BatteryViewModel
    @State private var hasLoaded = false
    @State private var showsShareComposer = false

    private let carId: Int

    public init(carId: Int, viewModel: BatteryViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.stats == nil {
                LoadingStateView(title: t("Loading battery", "正在加载电池"), showsProgress: true)
            } else if let stats = viewModel.state.stats {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(error, language: appLanguage),
                                systemImage: "wifi.exclamationmark"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("battery_refresh_warning")
                        }
                        gauge(stats)
                        historySection
                        metrics(stats)
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            } else {
                LoadingStateView(
                    title: t("Battery unavailable", "电池数据不可用"),
                    message: viewModel.state.errorMessage.map {
                        UserFacingErrorLocalizer.localized($0, language: appLanguage)
                    },
                    systemImage: "battery.0percent",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId) } }
                )
            }
        }
        .navigationTitle(t("Battery", "电池"))
        .accessibilityIdentifier("battery_view")
        .sheet(isPresented: $showsShareComposer) {
            if let stats = viewModel.state.stats {
                BatteryShareComposerView(
                    stats: stats,
                    summary: viewModel.state.historySummary,
                    units: viewModel.state.units.resolved(for: appDisplayUnitSystem)
                )
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private func gauge(_ stats: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(batteryTitle("Battery Health"))
                    .font(.headline)
                Spacer()
                Button {
                    showsShareComposer = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("Share Battery Report", "分享电池报告"))
                .accessibilityIdentifier("battery_share_button")
            }
            if !stats.showsAbsoluteHealth {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(t("Calibration required", "需要校准"))
                        .foregroundStyle(.primary)
                }
                    .font(.title2.bold())
                    .accessibilityIdentifier("battery_calibration_required")
                Text(stats.healthSource == .recordedPeriod ? t(
                    "Battery retention is calculated from data recorded by TeslaMate, not from the vehicle's full lifetime. Enter a verified new-car usable capacity or rated range in Settings to calculate absolute health.",
                    "当前保持率根据 TeslaMate 记录期数据计算，并不代表整车寿命健康度。请在设置中填写已确认的新车可用容量或额定续航后计算绝对健康度。"
                ) : t(
                    "Battery data is insufficient. Enter a verified new-car usable capacity or rated range after TeslaMate has recorded valid samples.",
                    "电池数据不足。请等待 TeslaMate 记录有效样本，并填写已确认的新车可用容量或额定续航。"
                ))
                .font(.footnote)
                .foregroundStyle(.primary)
                .accessibilityIdentifier("battery_calibration_explanation")
                NavigationLink(value: AppRoute.settings) {
                    Label(t("Open Battery Calibration", "打开电池校准"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.0, green: 0.30, blue: 0.68))
                .accessibilityIdentifier("battery_calibration_button")
            } else if let healthPercent = stats.healthPercent {
                ProgressView(value: healthPercent, total: 100)
                    .tint(healthPercent >= 85 ? .green : .orange)
                HStack(alignment: .firstTextBaseline) {
                    Text(BatteryHealthPresentation.percentText(healthPercent))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .accessibilityIdentifier("battery_absolute_health_value")
                    Spacer()
                    Text(stats.lossPercent.map { String(format: "-%.1f%%", $0) } ?? "--")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func metrics(_ stats: BatteryStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: metricColumns, spacing: 12) {
                MetricCard(title: batteryTitle("Capacity Now"), value: stats.currentCapacity.map { String(format: "%.1f kWh", $0) } ?? "--", systemImage: "battery.75percent")
                    .accessibilityIdentifier("battery_current_capacity")
                MetricCard(title: batteryTitle("Range Now"), value: stats.maxRangeNow.map(distanceText) ?? "--", systemImage: "road.lanes")
                    .accessibilityIdentifier("battery_current_range")
                if stats.showsAbsoluteHealth {
                    MetricCard(title: batteryTitle("Capacity New"), value: stats.originalCapacity.map { String(format: "%.1f kWh", $0) } ?? "--", systemImage: "battery.100percent")
                    MetricCard(title: batteryTitle("Capacity Loss"), value: stats.lossKwh.map { String(format: "%.1f kWh", $0) } ?? "--", systemImage: "minus.circle")
                    MetricCard(title: batteryTitle("Range New"), value: stats.maxRangeNew.map(distanceText) ?? "--", systemImage: "speedometer")
                    MetricCard(title: batteryTitle("Range Loss"), value: stats.rangeLoss.map(distanceText) ?? "--", systemImage: "arrow.down.right")
                }
                MetricCard(title: batteryTitle("Usable SOC"), value: stats.usableBatteryLevel.map { "\($0)%" } ?? "--", systemImage: "battery.50percent")
                MetricCard(title: batteryTitle("Rated Range"), value: stats.ratedRange.map(distanceText) ?? "--", systemImage: "gauge")
                MetricCard(title: batteryTitle("At 100%"), value: stats.rangeAt100.map(distanceText) ?? "--", systemImage: "arrow.up.to.line")
                MetricCard(
                    title: batteryTitle("Efficiency"),
                    value: stats.ratedEfficiency.map {
                        MateDriveUnitFormatter.formatEfficiency(
                            $0,
                            units: viewModel.state.units.resolved(for: appDisplayUnitSystem),
                            decimals: 0
                        )
                    } ?? "--",
                    systemImage: "leaf",
                    valueLineLimit: 2
                )
                MetricCard(
                    title: batteryTitle("Health Source"),
                    value: stats.healthSource.title(language: appLanguage),
                    systemImage: "info.circle",
                    valueLineLimit: 2
                )
                    .accessibilityIdentifier("battery_health_source")
                MetricCard(
                    title: batteryTitle("Health Confidence"),
                    value: stats.confidence.title(language: appLanguage),
                    systemImage: "checkmark.seal",
                    valueLineLimit: 2
                )
                    .accessibilityIdentifier("battery_health_confidence")
                if let recordingStartOdometerKm = stats.recordingStartOdometerKm {
                    MetricCard(title: batteryTitle("Recording Start Odometer"), value: distanceText(recordingStartOdometerKm), systemImage: "odometer")
                }
            }
            Text(stats.healthSource.detail(language: appLanguage))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Text(stats.confidence.detail(recordingStartOdometerKm: stats.recordingStartOdometerKm, units: viewModel.state.units.resolved(for: appDisplayUnitSystem), language: appLanguage))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if let history = viewModel.state.history,
           let summary = viewModel.state.historySummary {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("Recording Period", "记录期趋势"))
                    .font(.headline)
                Text(t(
                    "Changes below only cover the TeslaMate recording period and are not lifetime battery health.",
                    "以下变化仅覆盖 TeslaMate 的记录期，不代表车辆从新车至今的绝对电池健康度。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                Text(smoothingDescription(summary))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(t("Data Quality", "数据质量"), systemImage: "checkmark.seal")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(summary.quality.score)/100 · \(summary.quality.level.title(language: appLanguage))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(summary.quality.score), total: 100)
                        .tint(summary.quality.level == .high ? .green : summary.quality.level == .medium ? .orange : .red)
                    Text(t(
                        "This score measures history coverage and estimate stability, not physical cell health.",
                        "该评分衡量历史覆盖度和估算稳定性，不代表电芯物理检测结果。"
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let capacity = history.charts?.capacity, !capacity.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Capacity Trend", "容量趋势")).font(.subheadline.weight(.semibold))
                        Chart {
                            ForEach(capacity) { point in
                                if let date = point.date, let value = point.capacity {
                                    LineMark(x: .value("Date", date), y: .value("kWh", value))
                                        .foregroundStyle(.blue.opacity(0.45))
                                    PointMark(x: .value("Date", date), y: .value("kWh", value))
                                        .foregroundStyle(.blue.opacity(0.45))
                                }
                            }
                            ForEach(history.charts?.capacityMedian ?? []) { point in
                                if let date = point.date, let value = point.capacity {
                                    LineMark(x: .value("Date", date), y: .value("kWh", value))
                                        .foregroundStyle(.orange)
                                        .lineStyle(StrokeStyle(lineWidth: 3))
                                }
                            }
                        }
                        .chartYAxisLabel("kWh")
                        .frame(height: 170)
                    }
                }

                if let ranges = history.charts?.range, !ranges.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("Range Trend", "续航趋势")).font(.subheadline.weight(.semibold))
                        Chart(ranges) { point in
                            if let date = point.date, let value = point.range {
                                LineMark(x: .value("Date", date), y: .value("km", value))
                                    .foregroundStyle(.green)
                                PointMark(x: .value("Date", date), y: .value("km", value))
                                    .foregroundStyle(.green)
                            }
                        }
                        .chartYAxisLabel(viewModel.state.units.resolved(for: appDisplayUnitSystem)?.isImperial == true ? "mi" : "km")
                        .frame(height: 170)
                    }
                }

                LazyVGrid(columns: metricColumns, spacing: 12) {
                    MetricCard(title: t("Capacity at Start", "记录初始容量"), value: energyText(summary.capacityStartKWh), systemImage: "battery.100percent")
                    MetricCard(title: t("Capacity Now", "当前容量"), value: energyText(summary.capacityCurrentKWh), systemImage: "battery.75percent")
                    MetricCard(title: t("Recorded Capacity Change", "记录期容量变化"), value: signedEnergyText(summary.capacityChangeKWh), systemImage: "arrow.up.arrow.down")
                    MetricCard(title: t("Range at Start", "记录初始续航"), value: summary.rangeStartKm.map(distanceText) ?? "--", systemImage: "flag")
                    MetricCard(title: t("Range Now", "当前续航"), value: summary.rangeCurrentKm.map(distanceText) ?? "--", systemImage: "gauge")
                    MetricCard(title: t("Recorded Range Change", "记录期续航变化"), value: signedDistanceText(summary.rangeChangeKm), systemImage: "arrow.up.arrow.down")
                    MetricCard(title: t("Recording Start Odometer", "开始记录时里程表"), value: summary.startOdometerKm.map(distanceText) ?? "--", systemImage: "odometer")
                    MetricCard(title: t("Distance Recorded", "已记录里程"), value: summary.recordedDistanceKm.map(distanceText) ?? "--", systemImage: "road.lanes")
                    MetricCard(title: t("Derived Efficiency", "样本推导效率"), value: summary.efficiencyWhKm.map { MateDriveUnitFormatter.formatEfficiency($0, units: viewModel.state.units.resolved(for: appDisplayUnitSystem), decimals: 0) } ?? "--", systemImage: "leaf")
                    MetricCard(title: t("Qualifying Charges", "合格充电样本"), value: summary.qualifyingChargeCount.map(String.init) ?? "--", systemImage: "checkmark.circle")
                    MetricCard(title: t("Capacity Samples", "容量样本"), value: String(summary.quality.capacitySampleCount), systemImage: "chart.xyaxis.line")
                    MetricCard(title: t("Range Samples", "续航样本"), value: String(summary.quality.rangeSampleCount), systemImage: "point.3.connected.trianglepath.dotted")
                    MetricCard(title: t("History Span", "历史跨度"), value: t("\(summary.quality.recordedDays) days", "\(summary.quality.recordedDays) 天"), systemImage: "calendar")
                    MetricCard(title: t("Recorded Capacity Retention", "记录期容量保持率"), value: percentText(summary.recordedCapacityRetentionPercent), systemImage: "percent")
                    MetricCard(title: t("Recorded Range Retention", "记录期续航保持率"), value: percentText(summary.recordedRangeRetentionPercent), systemImage: "percent")
                }
            }
        }
    }

    private func batteryTitle(_ key: String) -> String {
        DashboardTextFormatter.title(key, language: appLanguage)
    }

    private var metricColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 12)]
        }
        return [GridItem(.adaptive(minimum: 145), spacing: 12)]
    }

    private func distanceText(_ value: Double) -> String {
        MateDriveUnitFormatter.formatDistance(value, units: viewModel.state.units.resolved(for: appDisplayUnitSystem))
    }

    private func energyText(_ value: Double?) -> String {
        value.map { String(format: "%.2f kWh", $0) } ?? "--"
    }

    private func signedEnergyText(_ value: Double?) -> String {
        value.map { String(format: "%+.2f kWh", $0) } ?? "--"
    }

    private func signedDistanceText(_ value: Double?) -> String {
        guard let value else { return "--" }
        let formatted = distanceText(abs(value))
        return value > 0 ? "+\(formatted)" : value < 0 ? "-\(formatted)" : formatted
    }

    private func percentText(_ value: Double?) -> String {
        value.map { String(format: "%.2f%%", $0) } ?? "--"
    }

    private func smoothingDescription(_ summary: BatteryHistorySummary) -> String {
        let capacity = summary.capacityUsesMedian
            ? t("capacity median trend", "容量中位趋势")
            : t("available capacity samples", "现有容量样本")
        return t(
            "Summary uses the \(capacity) and median windows of \(summary.rangeSmoothingSampleCount) range samples at each end.",
            "摘要使用\(capacity)，续航首尾各取 \(summary.rangeSmoothingSampleCount) 个样本的中位数。"
        )
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum BatteryHealthPresentation {
    public static func percentText(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "--"
    }
}
