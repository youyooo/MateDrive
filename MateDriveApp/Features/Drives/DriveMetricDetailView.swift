import SwiftUI

public struct DriveMetricDetailState: Equatable, Sendable {
    public var isLoading: Bool
    public var driveDetail: DriveDetail?
    public var stats: DriveDetailStats?
    public var units: UnitPreferences?
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        driveDetail: DriveDetail? = nil,
        stats: DriveDetailStats? = nil,
        units: UnitPreferences? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.driveDetail = driveDetail
        self.stats = stats
        self.units = units
        self.errorMessage = errorMessage
    }
}

@MainActor
public final class DriveMetricDetailViewModel: ObservableObject {
    @Published public private(set) var state: DriveMetricDetailState

    private let api: any DriveAPIProviding

    public init(api: any DriveAPIProviding, initialState: DriveMetricDetailState = DriveMetricDetailState()) {
        self.api = api
        self.state = initialState
    }

    public func load(carId: Int, driveId: Int) async {
        state.isLoading = state.driveDetail == nil
        state.errorMessage = nil

        async let detailResult = api.driveDetail(carId: carId, driveId: driveId)
        async let statusResult = api.carStatus(carId: carId)

        switch await detailResult {
        case let .success(detail):
            state.driveDetail = detail
            state.stats = DriveStatsCalculator.calculateStats(detail)
            state.isLoading = false
        case let .failure(error):
            state.errorMessage = error.driveMessage
            state.isLoading = false
        }

        if case let .success(payload) = await statusResult {
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
        }
    }
}

public struct DriveMetricDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DriveMetricDetailViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let driveId: Int
    private let metric: DriveMetricKind

    public init(carId: Int, driveId: Int, metric: DriveMetricKind, viewModel: DriveMetricDetailViewModel) {
        self.carId = carId
        self.driveId = driveId
        self.metric = metric
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading drive", "正在加载行程"), showsProgress: true)
            } else if let detail = viewModel.state.driveDetail,
                      let stats = viewModel.state.stats
            {
                let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let errorMessage = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage),
                                systemImage: "wifi.slash"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                        DriveMetricDetailContent(
                            metric: metric,
                            detail: detail,
                            stats: stats,
                            units: units,
                            language: appLanguage
                        )
                    }
                    .padding(16)
                }
            } else {
                LoadingStateView(
                    title: t("Drive unavailable", "行程不可用"),
                    message: viewModel.state.errorMessage,
                    systemImage: "exclamationmark.triangle",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId, driveId: driveId) } }
                )
            }
        }
        .navigationTitle(metric.title(language: appLanguage))
        .accessibilityIdentifier("drive_metric_detail_view")
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId, driveId: driveId)
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveMetricDetailContent: View {
    let metric: DriveMetricKind
    let detail: DriveDetail
    let stats: DriveDetailStats
    let units: UnitPreferences?
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            MetricCard(
                title: metric.title(language: language),
                value: valueText(for: metric),
                subtitle: sourceText(for: metric),
                systemImage: metric.systemImage
            )

            if let missingMessage {
                Text(verbatim: missingMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: localized("Details", "详细数据"))
                    .font(.headline)

                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        DriveMetricDetailRowView(row: row)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
            }
        }
    }

    private var rows: [DriveMetricDetailRow] {
        switch metric {
        case .averageSpeed:
            return [
                row("Displayed value", "显示值", valueText(for: .averageSpeed)),
                row("Position samples", "位置采样", "\(speeds.count)"),
                row("Position average", "采样平均速度", formatSpeed(stats.speedAvg)),
                row("Distance / duration", "里程 / 时长", "\(formatDistance(stats.distance)) / \(durationText(stats.durationMin))"),
                row("Summary fallback", "汇总备用字段", detail.speedAvg.map { MateDriveUnitFormatter.formatSpeed($0, units: units) } ?? "--")
            ]
        case .maxSpeed:
            return [
                row("Displayed value", "显示值", valueText(for: .maxSpeed)),
                row("Minimum moving speed", "最低行驶速度", formatSpeed(stats.speedMin.map(Double.init))),
                row("Position samples", "位置采样", "\(speeds.count)"),
                row("Summary speedMax", "汇总最高速度", detail.speedMax.map { MateDriveUnitFormatter.formatSpeed(Double($0), units: units) } ?? "--")
            ]
        case .efficiency:
            return [
                row("Displayed value", "显示值", valueText(for: .efficiency)),
                row("Source", "来源", efficiencySource),
                row("Formula", "公式", efficiencyFormula),
                row("Net energy consumed", "净耗电量", formatEnergy(detail.usableEnergyConsumedNet)),
                row("Integrated traction energy", "积分牵引能量", formatEnergy(stats.tractionEnergyKWh)),
                row("Integrated regenerated energy", "积分回收能量", formatEnergy(stats.regeneratedEnergyKWh)),
                row("Power sample coverage", "功率采样覆盖率", coverageText),
                row("API efficiency fallback", "接口效率备用值", detail.usableConsumptionNet.map { MateDriveUnitFormatter.formatEfficiency($0, units: units, decimals: 0) } ?? "--"),
                row("Distance", "里程", formatDistance(stats.distance))
            ]
        case .energy:
            return [
                row("Displayed value", "显示值", valueText(for: .energy)),
                row("Source field", "来源字段", localized("energyConsumedNet", "净耗电量")),
                row("Net energy consumed", "净耗电量", formatEnergy(detail.usableEnergyConsumedNet)),
                row("Integrated traction energy", "积分牵引能量", formatEnergy(stats.tractionEnergyKWh)),
                row("Integrated regenerated energy", "积分回收能量", formatEnergy(stats.regeneratedEnergyKWh)),
                row("Power sample coverage", "功率采样覆盖率", coverageText),
                row("Battery delta", "电量变化", batteryDeltaText),
                row("Distance", "里程", formatDistance(stats.distance)),
                row("Duration", "时长", durationText(stats.durationMin))
            ]
        case .elevation:
            return [
                row("Displayed value", "显示值", valueText(for: .elevation)),
                row("Gain", "上升", formatElevation(stats.elevationGain)),
                row("Loss", "下降", formatElevation(stats.elevationLoss)),
                row("Highest", "最高海拔", formatElevation(stats.elevationMax)),
                row("Lowest", "最低海拔", formatElevation(stats.elevationMin)),
                row("Position samples", "位置采样", "\(elevations.count)")
            ]
        case .duration:
            return [
                row("Displayed value", "显示值", valueText(for: .duration)),
                row("Start", "开始", dateText(detail.startDate)),
                row("End", "结束", dateText(detail.endDate)),
                row("Distance", "里程", formatDistance(stats.distance)),
                row("Average from distance", "按里程计算均速", formatSpeed(stats.avgSpeedFromDistance))
            ]
        }
    }

    private var missingMessage: String? {
        if (metric == .energy || metric == .efficiency), stats.energySource == .powerSamples {
            return localized(
                "TeslaMate did not return drive energy fields. This value is reconstructed by integrating timestamped power samples and subtracting regenerated energy.",
                "TeslaMate 未返回行程电耗字段。当前值由带时间戳的功率采样积分，并扣除动能回收后重建。"
            )
        }
        if (metric == .energy || metric == .efficiency),
           stats.energySource == .unavailable,
           stats.energySampleCoverage != nil
        {
            return localized(
                "Power samples cover less than 80% of the recorded interval, so no potentially understated energy value is shown.",
                "功率采样覆盖不足记录时段的 80%，为避免低估电耗，不显示推算结果。"
            )
        }
        switch metric {
        case .energy where stats.energyUsed == nil:
            return localized(
                "TeslaMate did not return energyConsumedNet for this drive, so the card shows -- instead of a fake 0.0 kWh.",
                "TeslaMate 没有返回净耗电量，所以卡片会显示 --，不会再误显示 0.0 kWh。"
            )
        case .efficiency where stats.efficiency == nil:
            return localized(
                "TeslaMate did not return energyConsumedNet or consumptionNet for this drive, so efficiency is unavailable.",
                "TeslaMate 没有返回净耗电量或接口效率备用值，所以效率暂无数据。"
            )
        case .efficiency where detail.usableEnergyConsumedNet == nil && detail.usableConsumptionNet != nil:
            return localized(
                "energyConsumedNet is missing; this value uses the API consumptionNet fallback.",
                "净耗电量缺失，当前效率使用接口返回的效率备用值。"
            )
        default:
            return nil
        }
    }

    private var efficiencySource: String {
        if detail.usableEnergyConsumedNet != nil, (stats.distance ?? 0) > 0 {
            return localized("Calculated from energyConsumedNet and distance", "由净耗电量和里程计算")
        }
        if stats.energySource == .powerSamples {
            return localized("Integrated power samples", "功率采样积分")
        }
        if detail.usableConsumptionNet != nil {
            return localized("API consumptionNet fallback", "接口效率备用值")
        }
        return localized("No source field returned", "接口未返回来源字段")
    }

    private var efficiencyFormula: String {
        if detail.usableEnergyConsumedNet != nil, (stats.distance ?? 0) > 0 {
            return localized("energyConsumedNet * 1000 / distance", "净耗电量 × 1000 / 里程")
        }
        if stats.energySource == .powerSamples {
            return localized("(traction - regeneration) * 1000 / distance", "（牵引能量 - 回收能量）× 1000 / 里程")
        }
        if detail.usableConsumptionNet != nil {
            return localized("consumptionNet", "接口效率备用值")
        }
        return "--"
    }

    private var speeds: [Int] {
        (detail.positions ?? []).compactMap(\.speed)
    }

    private var elevations: [Int] {
        (detail.positions ?? []).compactMap(\.elevation)
    }

    private func valueText(for metric: DriveMetricKind) -> String {
        switch metric {
        case .averageSpeed:
            return formatSpeed(stats.speedAvg)
        case .maxSpeed:
            return formatSpeed(stats.speedMax.map(Double.init))
        case .efficiency:
            return stats.efficiency.map { MateDriveUnitFormatter.formatEfficiency($0, units: units, decimals: 0) } ?? "--"
        case .energy:
            return formatEnergy(stats.energyUsed)
        case .elevation:
            return DriveDetailPresentation.elevationText(gain: stats.elevationGain, loss: stats.elevationLoss, units: units)
        case .duration:
            return durationText(stats.durationMin)
        }
    }

    private func sourceText(for metric: DriveMetricKind) -> String {
        switch metric {
        case .averageSpeed, .maxSpeed:
            return localized("Calculated from drive position samples", "由行程位置采样计算")
        case .efficiency:
            return efficiencySource
        case .energy:
            switch stats.energySource {
            case .api:
                return detail.usableEnergyConsumedNet != nil
                    ? localized("Direct TeslaMate field: energyConsumedNet", "TeslaMate 原始字段：净耗电量")
                    : localized("No reliable energy source", "没有可靠电耗来源")
            case .powerSamples:
                return localized("Integrated TeslaMate power samples", "TeslaMate 功率采样积分")
            case .unavailable:
                return localized("No reliable energy source", "没有可靠电耗来源")
            }
        case .elevation:
            return localized("Calculated from elevation samples", "由海拔采样计算")
        case .duration:
            return localized("Direct TeslaMate duration field", "TeslaMate 原始时长字段")
        }
    }

    private func row(_ englishLabel: String, _ chineseLabel: String, _ value: String) -> DriveMetricDetailRow {
        DriveMetricDetailRow(label: localized(englishLabel, chineseLabel), value: value)
    }

    private func formatEnergy(_ value: Double?) -> String {
        value.map { String(format: "%.1f kWh", $0) } ?? "--"
    }

    private var coverageText: String {
        stats.energySampleCoverage.map { String(format: "%.1f%%", $0 * 100) } ?? "--"
    }

    private func durationText(_ value: Int?) -> String {
        DriveDetailPresentation.durationText(value, language: language)
    }

    private func formatDistance(_ value: Double?) -> String {
        DriveDetailPresentation.distanceText(value, units: units)
    }

    private func formatSpeed(_ value: Double?) -> String {
        DriveDetailPresentation.speedText(value, units: units)
    }

    private func formatElevation(_ value: Int?) -> String {
        value.map { MateDriveUnitFormatter.formatElevation($0, units: units) } ?? "--"
    }

    private var batteryDeltaText: String {
        guard let start = stats.batteryStart, let end = stats.batteryEnd, let used = stats.batteryUsed else { return "--" }
        return "\(start)% → \(end)% (\(used)%)"
    }

    private func dateText(_ value: String?) -> String {
        guard let value, let date = DomainDateParser.date(from: value) else {
            return value ?? "--"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

private struct DriveMetricDetailRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

private struct DriveMetricDetailRowView: View {
    let row: DriveMetricDetailRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: row.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(verbatim: row.value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
