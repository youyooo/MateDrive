import Charts
import SwiftUI

public struct CompareChargesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @StateObject private var viewModel: CompareChargesViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let baseChargeId: Int

    public init(carId: Int, baseChargeId: Int, viewModel: CompareChargesViewModel) {
        self.carId = carId
        self.baseChargeId = baseChargeId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading comparison", "正在加载比较"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = viewModel.state.errorMessage {
                            Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        if let base = viewModel.state.baseRow {
                            baseSummary(base)
                            sortPicker
                            comparisons
                            curves
                        } else if viewModel.state.errorMessage == nil {
                            LoadingStateView(title: t("No charge data", "暂无充电数据"), systemImage: "bolt.slash")
                                .frame(minHeight: 180)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Compare Charges", "比较充电"))
        .accessibilityIdentifier("compare_charges_view")
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId, baseChargeId: baseChargeId)
        }
    }

    private var sortPicker: some View {
        Picker(t("Sort", "排序"), selection: Binding(
            get: { viewModel.state.sort },
            set: { viewModel.setSort($0) }
        )) {
            ForEach(CompareChargeSort.allCases, id: \.self) { sort in
                Text(verbatim: sort.title(language: appLanguage)).tag(sort)
            }
        }
        .pickerStyle(.segmented)
    }

    private func baseSummary(_ row: ComparableChargeRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Base Charge", "基准充电"))
                        .font(.headline)
                    rowTitleText(row)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                chargeTypeBadge(row)
            }
            metricGrid(row)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var comparisons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Similar Charges", "相似充电"))
                .font(.headline)
            if viewModel.state.comparisonRows.isEmpty {
                LoadingStateView(title: t("No comparable charges", "暂无可比较的充电记录"), systemImage: "bolt.slash")
                    .frame(minHeight: 120)
            } else {
                ForEach(viewModel.state.comparisonRows) { row in
                    comparisonRow(row)
                }
            }
        }
    }

    private func comparisonRow(_ row: ComparableChargeRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(row.isDc ? Color.orange : Color.green)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    rowTitleText(row)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(dateText(row.startDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(costPerKwhText(row.costPerKwh))
                    .font(.body.weight(.semibold).monospacedDigit())
            }
            metricGrid(row)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func metricGrid(_ row: ComparableChargeRow) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
            compactMetric(title: t("Peak", "峰值"), value: ChargeComparisonPresentation.powerText(row.peakKW))
            compactMetric(title: t("Duration", "时长"), value: ChargeComparisonPresentation.durationText(row.durationMin, language: appLanguage))
            compactMetric(title: t("Charge Energy", "充电能量"), value: ChargeComparisonPresentation.energyText(row.energyAdded))
            compactMetric(title: t("Total Cost", "总费用"), value: costText(row.totalCost))
            compactMetric(title: t("Price per kWh", "每度电价格"), value: costPerKwhText(row.costPerKwh))
            compactMetric(title: "SOC", value: ChargeComparisonPresentation.batteryText(start: row.batteryStart, end: row.batteryEnd))
        }
    }

    private var curves: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Charge Curves", "充电曲线"))
                .font(.headline)
            if viewModel.state.curves.isEmpty {
                LoadingStateView(title: t("No curve data", "暂无曲线数据"), systemImage: "chart.xyaxis.line")
                    .frame(minHeight: 120)
            } else {
                ForEach(viewModel.state.curves) { curve in
                    curveCard(curve)
                }
            }
        }
    }

    private func curveCard(_ curve: SessionCurve) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if curve.isBase {
                    Text(t("Base Charge", "基准充电"))
                        .font(.caption.weight(.semibold))
                } else {
                    Text(verbatim: "#\(curve.chargeId)")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                Text("\(curve.points.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ChargeComparisonCurveChart(points: curve.points, isBase: curve.isBase)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chargeTypeBadge(_ row: ComparableChargeRow) -> some View {
        Text((row.isDc ? ChargePricingChargeType.dc : .ac).displayText(language: appLanguage))
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(row.isDc ? Color.orange.opacity(0.18) : Color.green.opacity(0.18)))
            .foregroundStyle(row.isDc ? .orange : .green)
    }

    private func costText(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return viewModel.state.currencySymbol + String(format: "%.2f", value)
    }

    private func costPerKwhText(_ value: Double?) -> String {
        "\(costText(value))/kWh"
    }

    @ViewBuilder
    private func rowTitleText(_ row: ComparableChargeRow) -> some View {
        if let address = row.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
            Text(verbatim: address)
        } else if row.isBase {
            Text(t("Base Charge", "基准充电"))
        } else {
            Text(verbatim: "#\(row.chargeId)")
        }
    }

    private func dateText(_ value: String?) -> String {
        guard let value, let date = DomainDateParser.date(from: value) else {
            return value ?? "--"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum ChargeComparisonPresentation {
    public static func powerText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) kW"
    }

    public static func durationText(_ value: Int?, language: AppLanguage) -> String {
        guard let value else { return "--" }
        return MateDriveUnitFormatter.formatDuration(minutes: value, language: language)
    }

    public static func energyText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f kWh", value)
    }

    public static func batteryText(start: Int?, end: Int?) -> String {
        guard let start, let end else { return "--" }
        return "\(start)% → \(end)%"
    }
}

public struct ChargeComparisonCurveChart: View {
    @Environment(\.appLanguage) private var appLanguage
    @State private var selectedSOC: Double?

    let points: [SessionCurvePoint]
    let isBase: Bool

    public init(points: [SessionCurvePoint], isBase: Bool) {
        self.points = points
        self.isBase = isBase
    }

    public var body: some View {
        Chart {
            ForEach(Array(sampledPoints.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("SOC", point.soc), y: .value(t("Power", "功率"), point.power))
                    .foregroundStyle(color.opacity(0.12))
                LineMark(x: .value("SOC", point.soc), y: .value(t("Power", "功率"), point.power))
                    .foregroundStyle(color)
                    .interpolationMethod(.monotone)
                    .accessibilityLabel("\(Int(point.soc))%, \(Int(point.power)) kW")
            }
            if let selectedPoint {
                RuleMark(x: .value(t("Selected SOC", "已选择电量"), selectedPoint.soc))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("SOC", selectedPoint.soc),
                    y: .value(t("Power", "功率"), selectedPoint.power)
                )
                .foregroundStyle(color)
                .symbolSize(55)
            }
        }
        .chartXAxisLabel("SOC (%)")
        .chartYAxisLabel(t("Power (kW)", "功率 (kW)"))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXSelection(value: $selectedSOC)
        .frame(height: 170)
        .accessibilityLabel(t("Charge power by battery level", "按电量显示充电功率"))
        .overlay(alignment: .topTrailing) {
            if let selectedPoint {
                Text("\(selectedPoint.soc.formatted(.number.precision(.fractionLength(0))))% · \(selectedPoint.power.formatted(.number.precision(.fractionLength(1)))) kW")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(6)
            }
        }
    }

    private var sampledPoints: [SessionCurvePoint] {
        guard points.count > 80 else { return points }
        let stride = Double(points.count - 1) / 79.0
        return (0..<80).map { points[Int((Double($0) * stride).rounded())] }
    }

    private var color: Color { isBase ? .accentColor : .secondary }

    private var selectedPoint: SessionCurvePoint? {
        selectedSOC.flatMap { ChargeCurveSelection.nearest(to: $0, in: sampledPoints) }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum ChargeCurveSelection {
    public static func nearest(to soc: Double, in points: [SessionCurvePoint]) -> SessionCurvePoint? {
        points.min { abs($0.soc - soc) < abs($1.soc - soc) }
    }
}
