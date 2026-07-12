import Charts
import SwiftUI

public struct CostReviewView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CostReviewViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let currencySymbol: String
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        exteriorColor: String?,
        currencySymbol: String,
        viewModel: CostReviewViewModel,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.currencySymbol = currencySymbol
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.response == nil {
                LoadingStateView(title: t("Loading cost review", "正在加载成本回顾"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.response == nil {
                LoadingStateView(
                    title: t("Cost review unavailable", "成本回顾不可用"),
                    message: error,
                    systemImage: "chart.line.uptrend.xyaxis"
                )
            } else {
                content
            }
        }
        .navigationTitle(t("Vehicle Cost Review", "用车成本回顾"))
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                rangePicker
                if let response = viewModel.state.response {
                    if let error = viewModel.state.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    completenessBanner(response)
                    overview(response)
                    trend(response)
                    composition(response)
                    comparison(response)
                    dataQuality(response)
                    placeRankings(response)
                    records(response)
                }
            }
            .padding(16)
        }
    }

    private var rangePicker: some View {
        Picker(t("Range", "范围"), selection: Binding(
            get: { viewModel.state.range },
            set: { range in Task { await viewModel.select(range, carId: carId) } }
        )) {
            ForEach(CostReviewRange.allCases) { range in
                Text(CostReviewPresentation.rangeTitle(range, language: appLanguage)).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.state.isLoading)
    }

    @ViewBuilder
    private func completenessBanner(_ response: CostReviewResponse) -> some View {
        let quality = response.data.dataQuality
        if viewModel.missingCostCount > 0 {
            Label(
                t(
                    "\(viewModel.missingCostCount) cost records are missing. Recorded spend is a partial total; missing values are not counted as zero.",
                    "有 \(viewModel.missingCostCount) 条费用缺失。已记录支出只是部分合计，缺失值不会按 0 计算。"
                ),
                systemImage: "exclamationmark.circle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else if quality.hasAnyActivity == true {
            Label(t("All cost records in this period are complete.", "此周期内的费用记录完整。"), systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }

    private func overview(_ response: CostReviewResponse) -> some View {
        let summary = response.data.summary
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(t("Overview", "概览"), trailing: dateRangeText(response.data.range))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryMetric(
                    t("Recorded Spend", "已记录支出"),
                    CostReviewPresentation.money(summary.recordedSpend, currencySymbol: currencySymbol),
                    "creditcard",
                    viewModel.hasCompleteRecordedSpend ? nil : t("Partial", "不完整")
                )
                summaryMetric(
                    t("Estimated Use Cost", "估算用车成本"),
                    CostReviewPresentation.money(summary.estimatedUseCost, currencySymbol: currencySymbol),
                    "car.side",
                    t("Energy estimate", "能耗估算")
                )
                summaryMetric(t("Distance", "行驶里程"), distanceText(summary.totalDistanceKm, response: response), "road.lanes", nil)
                summaryMetric(t("Drives / Charges", "行程 / 充电"), "\(summary.driveCount ?? 0) / \(summary.chargeCount ?? 0)", "arrow.triangle.swap", nil)
            }
        }
    }

    private func trend(_ response: CostReviewResponse) -> some View {
        let buckets = response.data.buckets.filter { $0.date != nil }
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(t("Cost Trend", "成本趋势"), trailing: currencySymbol)
            if buckets.isEmpty {
                emptyRow(t("No cost activity in this period", "此周期内没有成本活动"), icon: "chart.line.downtrend.xyaxis")
            } else {
                Chart {
                    ForEach(buckets) { bucket in
                        if let date = bucket.date, let value = bucket.estimatedUseCost {
                            LineMark(x: .value("Date", date), y: .value("Cost", value), series: .value("Series", "estimated"))
                                .foregroundStyle(.blue)
                                .interpolationMethod(.catmullRom)
                        }
                        if let date = bucket.date, let value = bucket.recordedSpend {
                            LineMark(x: .value("Date", date), y: .value("Cost", value), series: .value("Series", "recorded"))
                                .foregroundStyle(.orange)
                            PointMark(x: .value("Date", date), y: .value("Cost", value))
                                .foregroundStyle(.orange)
                                .symbolSize(28)
                        }
                    }
                }
                .frame(height: 220)
                .chartYAxis { AxisMarks(position: .leading) }
                chartLegend
            }
        }
    }

    private var chartLegend: some View {
        HStack(spacing: 18) {
            legendItem(t("Estimated use cost", "估算用车成本"), color: .blue)
            legendItem(t("Recorded spend", "已记录支出"), color: .orange)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func composition(_ response: CostReviewResponse) -> some View {
        let items = costComponents(response.data.summary)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(t("Cost Composition", "成本构成"), trailing: currencySymbol)
            if items.isEmpty {
                emptyRow(t("No cost composition is available", "暂无成本构成数据"), icon: "chart.bar.xaxis")
            } else {
                Chart(items) { item in
                    BarMark(x: .value("Cost", item.value), y: .value("Type", item.title))
                        .foregroundStyle(item.color)
                        .annotation(position: .trailing) {
                            Text(CostReviewPresentation.money(item.value, currencySymbol: currencySymbol))
                                .font(.caption.monospacedDigit())
                        }
                }
                .frame(height: CGFloat(max(items.count, 1)) * 46)
                .chartXAxis(.hidden)
            }
        }
    }

    @ViewBuilder
    private func comparison(_ response: CostReviewResponse) -> some View {
        if let comparison = response.data.comparison {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader(t("Previous Period", "上一周期对比"), trailing: dateRangeText(comparison.previousRange))
                comparisonRow(t("Estimated Use Cost", "估算用车成本"), comparison.estimatedUseCost, money: true)
                comparisonRow(t("Recorded Spend", "已记录支出"), comparison.recordedSpend, money: true)
                comparisonRow(t("Charging Spend", "充电支出"), comparison.chargingSpend, money: true)
                comparisonRow(t("Cost per Distance", "单位里程成本"), comparison.costPerDistance, money: false)
            }
        }
    }

    private func comparisonRow(_ title: String, _ metric: CostReviewMetricComparison?, money: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(comparisonReason(metric, money: money))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(metricValue(metric?.currentValue, money: money))
                    .font(.body.monospacedDigit().weight(.semibold))
                if metric?.isEligible == true, let delta = metric?.delta {
                    Text(deltaText(delta, money: money))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(delta <= 0 ? .green : .orange)
                } else {
                    Text(t("Not comparable", "不可比较"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func dataQuality(_ response: CostReviewResponse) -> some View {
        let quality = response.data.dataQuality
        return VStack(alignment: .leading, spacing: 12) {
            Text(t("Data Quality", "数据完整性")).font(.headline)
            coverageRow(t("Charging Cost", "充电费用"), quality: quality.chargingCost)
            coverageRow(t("Parking Cost", "停车费用"), quality: quality.parkingCost)
        }
    }

    private func coverageRow(_ title: String, quality: CostReviewCostQuality) -> some View {
        let total = quality.eventCount ?? 0
        let recorded = quality.costRecordedCount ?? 0
        let progress = total > 0 ? Double(recorded) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(CostReviewPresentation.coverage(recorded: recorded, total: total, language: appLanguage))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
            if let zero = quality.zeroCostCount, zero > 0 {
                Text(t("\(zero) confirmed free records", "\(zero) 条已确认免费记录"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func placeRankings(_ response: CostReviewResponse) -> some View {
        let rankings = Array(response.data.placeRankings.charging.prefix(4))
        if !rankings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Charging by Location", "充电地点成本")).font(.headline)
                ForEach(rankings) { place in
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(place.displayName ?? t("Unknown location", "未知地点"))
                                .font(.subheadline.weight(.semibold))
                            Text(CostReviewPresentation.coverage(
                                recorded: place.costRecordedCount ?? 0,
                                total: place.chargeCount ?? 0,
                                language: appLanguage
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CostReviewPresentation.money(place.totalCost, currencySymbol: currencySymbol))
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    @ViewBuilder
    private func records(_ response: CostReviewResponse) -> some View {
        let records = response.data.records
        if !records.topCharges.isEmpty || !records.missingChargeCosts.isEmpty || !records.missingParkingCosts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Cost Records", "费用记录")).font(.headline)
                ForEach(records.topCharges.prefix(4)) { record in
                    chargeRecordRow(record, status: .known)
                }
                ForEach(records.missingChargeCosts.prefix(6)) { record in
                    chargeRecordRow(record, status: .missing)
                }
                ForEach(records.missingParkingCosts.prefix(4)) { record in
                    parkingRecordRow(record)
                }
            }
        }
    }

    private func chargeRecordRow(_ record: CostReviewRecord, status: RecordCostStatus) -> some View {
        Button {
            navigate(.chargeDetail(carId: carId, chargeId: record.id, exteriorColor: exteriorColor))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: status == .known ? "bolt.fill" : "exclamationmark.circle")
                    .foregroundStyle(status == .known ? .green : .orange)
                recordIdentity(record)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(status == .known ? CostReviewPresentation.money(record.cost, currencySymbol: currencySymbol) : t("Missing", "缺失"))
                        .font(.body.monospacedDigit().weight(.semibold))
                    if let energy = record.energyKwh {
                        Text(String(format: "%.1f kWh", energy)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func parkingRecordRow(_ record: CostReviewRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "parkingsign.circle").foregroundStyle(.orange)
            recordIdentity(record)
            Spacer()
            Text(t("Cost missing", "费用缺失"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func recordIdentity(_ record: CostReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.title ?? record.address ?? t("Unknown location", "未知地点"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(record.startDate.flatMap(DomainDateParser.date(from:))?.formatted(date: .abbreviated, time: .shortened) ?? "--")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryMetric(_ title: String, _ value: String, _ icon: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.72)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func emptyRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let trailing, !trailing.isEmpty {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private func costComponents(_ summary: CostReviewSummary) -> [CostComponent] {
        [
            summary.estimatedDrivingEnergyCost.map { CostComponent(id: "drive", title: t("Driving energy", "行驶能耗"), value: $0, color: .blue) },
            summary.estimatedStandbyEnergyCost.map { CostComponent(id: "standby", title: t("Standby energy", "待机能耗"), value: $0, color: .purple) },
            summary.chargingCost.map { CostComponent(id: "charge", title: t("Recorded charging", "已记录充电"), value: $0, color: .green) },
            summary.parkingCost.map { CostComponent(id: "parking", title: t("Recorded parking", "已记录停车"), value: $0, color: .orange) }
        ].compactMap { $0 }
    }

    private func metricValue(_ value: Double?, money: Bool) -> String {
        money
            ? CostReviewPresentation.money(value, currencySymbol: currencySymbol)
            : value.map { String(format: "%@%.3f", currencySymbol, $0) } ?? "--"
    }

    private func comparisonReason(_ metric: CostReviewMetricComparison?, money: Bool) -> String {
        guard let metric else { return t("No comparison data", "暂无对比数据") }
        if metric.isEligible == true {
            return t("Previous: ", "上一周期：") + metricValue(metric.previousValue, money: money)
        }
        let codes = Set(metric.reasonCodes)
        if codes.contains(where: { $0.contains("missing_parking_cost") || $0.contains("missing_charging_cost") }) {
            return t("Comparison withheld because costs are incomplete", "费用不完整，暂不计算涨跌")
        }
        if codes.contains(where: { $0.contains("no_activity") }) {
            return t("No activity in one of the periods", "其中一个周期没有活动")
        }
        return t("Insufficient comparable data", "可比数据不足")
    }

    private func deltaText(_ value: Double, money: Bool) -> String {
        if money {
            return CostReviewPresentation.moneyDelta(value, currencySymbol: currencySymbol)
        }
        return String(format: "%+.3f", value)
    }

    private func dateRangeText(_ range: CostReviewDateRange?) -> String? {
        guard let range,
              let start = range.startDate.flatMap(DomainDateParser.date(from:)),
              let end = range.endDate.flatMap(DomainDateParser.date(from:)) else { return nil }
        return start.formatted(date: .numeric, time: .omitted) + " – " + end.formatted(date: .numeric, time: .omitted)
    }

    private func distanceText(_ value: Double?, response: CostReviewResponse) -> String {
        guard let value else { return "--" }
        let units = UnitPreferences(
            unitOfLength: response.units?.unitOfLength,
            unitOfTemperature: response.units?.unitOfTemperature,
            unitOfPressure: response.units?.unitOfPressure
        ).resolved(for: appDisplayUnitSystem)
        return MateDroidUnitFormatter.formatDistance(value, units: units)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct CostComponent: Identifiable {
    let id: String
    let title: String
    let value: Double
    let color: Color
}

private enum RecordCostStatus {
    case known
    case missing
}
