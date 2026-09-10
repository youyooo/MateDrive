import SwiftUI

public struct ChargesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var viewModel: ChargesViewModel
    @State private var hasLoaded = false
    @State private var showsPricingBatch = false

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: ChargesViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading charges", "正在加载充电记录"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        filters
                        energyBalanceLink
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
        .navigationTitle(t("Charges", "充电记录"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsPricingBatch = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .disabled(!viewModel.hasPricingRules)
                .accessibilityLabel(Text(t("Pricing Preview", "费用预览")))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigate(.currentCharge(carId: carId, exteriorColor: exteriorColor))
                } label: {
                    Image(systemName: "bolt.car")
                }
                .accessibilityLabel(Text(t("Current Charge", "当前充电")))
            }
        }
        .sheet(isPresented: $showsPricingBatch) {
            NavigationStack {
                ChargePricingBatchView(viewModel: viewModel)
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .chargeCostOverrideDidChange)) { _ in
            Task {
                await viewModel.reloadCostOverrides()
            }
        }
        .accessibilityIdentifier("charges_view")
    }

    private var filters: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker(t("Date", "日期"), selection: Binding(
                    get: { viewModel.state.dateFilter },
                    set: { viewModel.setDateFilter($0) }
                )) {
                    ForEach(ChargeDateFilter.allCases, id: \.self) { filter in
                        Text(filter.title(language: appLanguage)).tag(filter)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Picker(t("Cost", "费用"), selection: Binding(
                    get: { viewModel.state.costFilter },
                    set: { viewModel.setCostFilter($0) }
                )) {
                    ForEach(ChargeCostFilter.allCases, id: \.self) { filter in
                        Text(filter.title(language: appLanguage)).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            Picker(t("Type", "类型"), selection: Binding(
                get: { viewModel.state.typeFilter },
                set: { viewModel.setTypeFilter($0) }
            )) {
                ForEach(ChargeTypeFilter.allCases, id: \.self) { filter in
                    Text(filter.title(language: appLanguage)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Charges", "充电记录"), value: "\(viewModel.state.summary.totalCharges)", systemImage: "number")
            MetricCard(title: t("Energy", "能量"), value: ChargesPresentation.energyText(viewModel.state.summary.totalEnergyAdded, isComplete: viewModel.state.summary.energyIsComplete), subtitle: energyCoverageText, systemImage: "bolt.fill")
            MetricCard(
                title: t("Cost Total", "费用合计"),
                value: formatCost(viewModel.state.summary.totalCost),
                subtitle: ChargeCostCoveragePresentation.summary(viewModel.state.summary, language: appLanguage),
                systemImage: "creditcard"
            )
            MetricCard(title: t("Average", "平均"), value: ChargesPresentation.averageEnergyText(viewModel.state.summary.averageEnergyPerCharge), subtitle: energyCoverageText, systemImage: "chart.bar")
        }
    }

    private var energyBalanceLink: some View {
        Button {
            navigate(.energyCycles(carId: carId, exteriorColor: exteriorColor))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Energy Balance", "能量收支"))
                        .font(.body.weight(.semibold))
                    Text(t("Charge, discharge and range trends", "充放电、日周月对比与续航趋势"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var histogram: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Energy", "能量"))
                .font(.headline)
            if viewModel.state.chartData.isEmpty {
                LoadingStateView(title: t("No charge history", "暂无充电记录"), systemImage: "bolt.slash")
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    let maxEnergy = max(viewModel.state.chartData.compactMap(\.totalEnergy).max() ?? 1, 1)
                    ForEach(viewModel.state.chartData) { point in
                        VStack(spacing: 6) {
                            Text(ChargesPresentation.energyText(point.totalEnergy, isComplete: point.energyIsComplete))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            HistoryHistogramBar(
                                color: .accentColor,
                                height: max(12, CGFloat((point.totalEnergy ?? 0) / maxEnergy) * 120)
                            )
                                .overlay(alignment: .bottom) {
                                    Text("\(point.count)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.bottom, 3)
                                }
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
                    navigate(.chargeDetail(carId: carId, chargeId: row.chargeId, exteriorColor: exteriorColor))
                } label: {
                    chargeRowContent(row)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("charge_row_\(row.chargeId)")
                .contextMenu {
                    Button(t("Compare", "比较")) {
                        navigate(.compareCharges(carId: carId, baseChargeId: row.chargeId, exteriorColor: exteriorColor))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chargeRowContent(_ row: ChargeRow) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    chargeTypeIcon(row)
                    Text(row.address ?? dateText(row.startDate))
                        .font(.body.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    rowChevron
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(rowSubtitle(row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    chargeCost(row)
                }
            }
        } else {
            HStack(spacing: 12) {
                chargeTypeIcon(row)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.address ?? dateText(row.startDate))
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                    Text(rowSubtitle(row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 8)
                chargeCost(row)
                rowChevron
            }
        }
    }

    private func chargeTypeIcon(_ row: ChargeRow) -> some View {
        Image(systemName: row.isDc ? "bolt.car.fill" : "powerplug.fill")
            .foregroundStyle(row.isDc ? .orange : .green)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    private func chargeCost(_ row: ChargeRow) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(row.cost.map(formatCost) ?? "--")
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Text(ChargeCostPresentation.status(
                row.costSource,
                isHistoricalReference: row.isHistoricalReference,
                language: appLanguage
            ))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(costStatusColor(row.costSource))
                .accessibilityIdentifier("charge_cost_status_\(row.chargeId)")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var rowChevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func formatCost(_ value: Double) -> String {
        "\(viewModel.state.currencySymbol)\(String(format: "%.2f", value))"
    }

    private func rowSubtitle(_ row: ChargeRow) -> String {
        "\(dateText(row.startDate)) · \(ChargesPresentation.energyText(row.energyAdded, isComplete: row.energyAdded != nil))"
    }

    private func costStatusColor(_ source: ChargeCostSource) -> Color {
        switch source {
        case .manual:
            return .green
        case .api:
            return .secondary
        case .pricingRule:
            return .orange
        case .none:
            return .secondary
        }
    }

    private var energyCoverageText: String? {
        let summary = viewModel.state.summary
        guard summary.energyRecordCount < summary.totalCharges else { return nil }
        return t("Energy coverage \(summary.energyRecordCount)/\(summary.totalCharges)", "电量覆盖 \(summary.energyRecordCount)/\(summary.totalCharges)")
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

public enum ChargesPresentation {
    public static func energyText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + String(format: "%.1f kWh", $0) } ?? "--"
    }

    public static func averageEnergyText(_ value: Double?) -> String {
        value.map { String(format: "%.1f kWh", $0) } ?? "--"
    }
}

public enum ChargeCostPresentation {
    public static func status(
        _ source: ChargeCostSource,
        isHistoricalReference: Bool = false,
        language: AppLanguage
    ) -> String {
        switch source {
        case .manual:
            return AppText.localized("Confirmed", "已确认", language: language)
        case .api:
            return AppText.localized("Recorded", "已记录", language: language)
        case .pricingRule:
            return isHistoricalReference
                ? AppText.localized("Historical reference", "历史参考", language: language)
                : AppText.localized("Estimated", "估算", language: language)
        case .none:
            return AppText.localized("Add cost", "待补充", language: language)
        }
    }
}

public enum ChargeCostCoveragePresentation {
    public static func summary(_ summary: ChargesSummary, language: AppLanguage) -> String? {
        guard summary.totalCharges > 0 else { return nil }
        if MateDriveUnitFormatter.usesChineseLabels(language: language) {
            let missing = summary.missingCostCount > 0 ? " · 缺 \(summary.missingCostCount) 条" : ""
            return "覆盖 \(summary.pricedChargeCount)/\(summary.totalCharges) 条\(missing)\n记录 \(summary.apiCostCount) · 估算 \(summary.pricingRuleCostCount) · 修正 \(summary.manualCostCount)"
        }
        let missing = summary.missingCostCount > 0 ? " · \(summary.missingCostCount) missing" : ""
        return "Coverage \(summary.pricedChargeCount)/\(summary.totalCharges)\(missing)\nRecorded \(summary.apiCostCount) · estimated \(summary.pricingRuleCostCount) · corrected \(summary.manualCostCount)"
    }
}
