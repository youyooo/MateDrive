import MapKit
import Charts
import SwiftUI

public struct ChargeDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: ChargeDetailViewModel
    @State private var hasLoaded = false
    @State private var costInput = ""
    @State private var confirmsTripRemoval = false
    @State private var isShowingPriceConfirmation = false

    private let carId: Int
    private let chargeId: Int
    private let exteriorColor: String?
    private let pricingService: any ChargePricingObservationServicing
    private let currencyCode: String
    private let smartActivityIndexer: any SmartActivityIndexing
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        chargeId: Int,
        exteriorColor: String?,
        viewModel: ChargeDetailViewModel,
        pricingService: any ChargePricingObservationServicing,
        currencyCode: String,
        smartActivityIndexer: any SmartActivityIndexing,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.chargeId = chargeId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.pricingService = pricingService
        self.currencyCode = currencyCode
        self.smartActivityIndexer = smartActivityIndexer
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.chargeDetail == nil {
                LoadingStateView(title: t("Loading charge", "正在加载充电"), showsProgress: true)
            } else if let detail = viewModel.state.chargeDetail {
                let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ChargeHeroView(detail: detail, stats: viewModel.state.stats, units: units, isDc: viewModel.state.isDcCharge)
                        detailLoadStatus
                        ChargeEnergyFlowSection(stats: viewModel.state.stats)
                        map(detail: detail)
                        ChargeStatsGrid(stats: viewModel.state.stats, units: units)
                        tripMembershipSection
                        ChargeCostEditor(
                            apiCost: viewModel.state.apiCost,
                            manualCost: viewModel.state.manualCost,
                            pricingRuleCost: viewModel.state.pricingRuleCost,
                            pricingRuleName: viewModel.state.pricingRuleName,
                            pricingRuleMatchFactors: viewModel.state.pricingRuleMatchFactors,
                            pricingBreakdown: viewModel.state.pricingBreakdown,
                            pricingSessionFee: viewModel.state.pricingSessionFee,
                            hasPricingRules: viewModel.state.hasPricingRules,
                            effectiveCost: viewModel.state.effectiveCost,
                            costSourceType: viewModel.state.costSource,
                            costSyncState: viewModel.state.costSyncState,
                            errorMessage: isStoreScreenshotMode ? nil : viewModel.state.errorMessage,
                            currencySymbol: viewModel.state.currencySymbol,
                            costInput: $costInput,
                            onSave: saveCostOverride,
                            onClear: clearCostOverride
                        )
                        Button {
                            isShowingPriceConfirmation = true
                        } label: {
                            Label(t("Confirm bill and price", "确认账单与电价"), systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.borderedProminent)
                        if !viewModel.state.isShowingSummary {
                            ChargePointChart(points: CurrentChargeViewModel.chronological(detail.chargePoints ?? []), units: units)
                        }
                    }
                    .padding(16)
                }
            } else {
                LoadingStateView(
                    title: t("Charge unavailable", "充电数据不可用"),
                    message: localizedErrorMessage,
                    systemImage: "exclamationmark.triangle",
                    retryTitle: t("Retry", "重试")
                ) {
                    Task {
                        await viewModel.load(carId: carId, chargeId: chargeId)
                        syncCostInput()
                    }
                }
            }
        }
        .navigationTitle(t("Charge Detail", "充电详情"))
        .confirmationDialog(t("Remove from trip?", "从路程中移除？"), isPresented: $confirmsTripRemoval, titleVisibility: .visible) {
            Button(t("Remove", "移除"), role: .destructive) { Task { await viewModel.removeFromTrip(carId: carId, chargeId: chargeId) } }
            Button(t("Cancel", "取消"), role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    navigate(.compareCharges(carId: carId, baseChargeId: chargeId, exteriorColor: exteriorColor))
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .accessibilityLabel(t("Compare", "比较"))
                .accessibilityIdentifier("charge_compare_button")
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId, chargeId: chargeId)
            syncCostInput()
        }
        .onChange(of: viewModel.state.effectiveCost) { _, _ in
            syncCostInput()
        }
        .sheet(isPresented: $isShowingPriceConfirmation) {
            if let detail = viewModel.state.chargeDetail {
                ChargePriceConfirmationView(
                    confirmation: priceConfirmation(detail),
                    stationName: cleaned(detail.address)
                        ?? t("Recorded charging location", "已记录充电地点"),
                    currencySymbol: viewModel.state.currencySymbol,
                    service: pricingService,
                    onSaved: { _ in
                        isShowingPriceConfirmation = false
                        refreshAfterPriceConfirmation()
                    },
                    onCancel: { isShowingPriceConfirmation = false }
                )
            }
        }
        .accessibilityIdentifier("charge_detail_view")
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
                    Task {
                        await viewModel.load(carId: carId, chargeId: chargeId)
                        syncCostInput()
                    }
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
                     ? t("Showing saved data while detailed charging telemetry loads", "已显示本地记录，详细充电数据正在后台加载")
                     : t("Updating charge data", "正在后台更新充电数据"))
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

    @ViewBuilder
    private func map(detail: ChargeDetail) -> some View {
        if let location = GeoCoordinateValidator.location(latitude: detail.latitude, longitude: detail.longitude) {
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            MapGestureGate { isMapInteractionEnabled in
                Map(
                    initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))),
                    interactionModes: isMapInteractionEnabled ? .all : []
                ) {
                    Marker(t("Charge", "充电"), coordinate: coordinate)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func saveCostOverride() {
        Task {
            let didSave = await viewModel.saveCostOverrideInput(carId: carId, chargeId: chargeId, input: costInput)
            if didSave {
                NotificationCenter.default.post(name: .chargeCostOverrideDidChange, object: nil)
            }
        }
    }

    private func clearCostOverride() {
        costInput = ""
        Task {
            let didSave = await viewModel.saveCostOverride(carId: carId, chargeId: chargeId, cost: nil)
            if didSave {
                NotificationCenter.default.post(name: .chargeCostOverrideDidChange, object: nil)
            }
        }
    }

    private func syncCostInput() {
        if let cost = viewModel.state.effectiveCost {
            costInput = String(format: "%.2f", cost)
        } else {
            costInput = ""
        }
    }

    private func priceConfirmation(_ detail: ChargeDetail) -> ChargePricingConfirmation {
        let coordinates = GeoCoordinateValidator.location(
            latitude: detail.latitude,
            longitude: detail.longitude
        ).map { GeocodeLocation(latitude: $0.latitude, longitude: $0.longitude) }
        let measuredIdentity = ChargingSessionAnalyzer.chargerIdentity(detail)
        let chargerIdentity: ChargePricingChargerIdentity = viewModel.state.isDcCharge && measuredIdentity == .ac
            ? .unknownDC
            : measuredIdentity
        return ChargePricingConfirmation(
            carId: carId,
            chargeId: chargeId,
            stationKey: "",
            scope: .sessionOnly,
            finalAmount: viewModel.state.effectiveCost ?? detail.cost ?? 0,
            billedEnergyKWh: nil,
            pricePerKWh: nil,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            currencyCode: currencyCode,
            coordinates: coordinates,
            chargerIdentity: chargerIdentity,
            startMinute: nil,
            endMinute: nil
        )
    }

    private func refreshAfterPriceConfirmation() {
        NotificationCenter.default.post(name: .chargeCostOverrideDidChange, object: nil)
        Task {
            await viewModel.load(carId: carId, chargeId: chargeId)
            _ = await smartActivityIndexer.rebuild(carIds: [carId])
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public struct ChargeHeroView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let detail: ChargeDetail
    let stats: ChargeDetailStats?
    let units: UnitPreferences?
    let isDc: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if let address = cleanedAddress(detail.address) {
                        Text(verbatim: address)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                    } else {
                        Text(t("Charge", "充电"))
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                    }
                    Text(dateText(detail.startDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isDc ? "DC" : "AC")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(isDc ? Color.orange.opacity(0.18) : Color.green.opacity(0.18)))
                    .foregroundStyle(isDc ? .orange : .green)
            }

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Added to Battery", "充入电池"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ChargeDetailPresentation.energyText(
                        detailEnergy: detail.chargeEnergyAdded,
                        calculatedEnergy: stats?.energyAdded
                    ))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SOC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(batteryText(stats))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
    }

    private func batteryText(_ stats: ChargeDetailStats?) -> String {
        ChargeComparisonPresentation.batteryText(start: stats?.batteryStart, end: stats?.batteryEnd)
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

public enum ChargeDetailPresentation {
    public static func energyText(detailEnergy: Double?, calculatedEnergy: Double?) -> String {
        guard let energy = detailEnergy ?? calculatedEnergy else { return "--" }
        return String(format: "%.1f kWh", energy)
    }
}

public struct ChargeEnergyFlowSection: View {
    @Environment(\.appLanguage) private var appLanguage

    let stats: ChargeDetailStats?

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Energy Flow", "能量流向"))
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                MetricCard(
                    title: t("Charger Input", "桩侧输入"),
                    value: energy(stats?.energyUsed),
                    subtitle: t("Vehicle-side estimate", "车端数据估算"),
                    systemImage: "powerplug.fill",
                    tint: .orange
                )
                MetricCard(
                    title: t("Added to Battery", "充入电池"),
                    value: energy(stats?.energyAdded),
                    subtitle: t("Reported by vehicle", "车辆接口上报"),
                    systemImage: "battery.75percent",
                    tint: .green
                )
                MetricCard(
                    title: lossTitle,
                    value: lossText,
                    systemImage: lossIsNegative ? "exclamationmark.triangle" : "waveform.path.ecg",
                    tint: lossIsNegative ? .orange : .blue
                )
                MetricCard(
                    title: t("Charging Efficiency", "充电效率"),
                    value: stats?.efficiency.map { String(format: "%.0f%%", $0) } ?? "--",
                    subtitle: t("Battery added ÷ charger input", "充入电池 ÷ 桩侧输入"),
                    systemImage: "gauge",
                    tint: .green
                )
            }
            if stats?.energyUsed == nil {
                Label(
                    t("This TeslaMate record has no charger-input energy, so loss and efficiency cannot be calculated.", "该条 TeslaMate 记录没有桩侧输入电量，因此无法计算损耗和效率。"),
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var lossIsNegative: Bool {
        (stats?.energyLoss ?? 0) < 0
    }

    private var lossTitle: String {
        lossIsNegative ? t("Meter Difference", "计量差异") : t("Charging Loss", "充电损耗")
    }

    private var lossText: String {
        guard let loss = stats?.energyLoss else { return "--" }
        return String(format: "%.1f kWh", abs(loss))
    }

    private func energy(_ value: Double?) -> String {
        value.map { String(format: "%.1f kWh", $0) } ?? "--"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public struct ChargeStatsGrid: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let stats: ChargeDetailStats?
    let units: UnitPreferences?

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Peak Power", "峰值功率"), value: ChargeComparisonPresentation.powerText(stats?.powerMax), systemImage: "bolt.fill")
            MetricCard(title: t("Average", "平均"), value: stats?.powerAvg.map { String(format: "%.1f kW", $0) } ?? "--", systemImage: "chart.bar")
            MetricCard(title: t("Voltage", "电压"), value: stats?.voltageMax.map { "\($0) V" } ?? "--", systemImage: "waveform.path.ecg")
            MetricCard(title: t("Temperature", "温度"), value: stats?.tempAvg.map { MateDriveUnitFormatter.formatTemperature($0, units: units) } ?? "--", systemImage: "thermometer.medium")
            MetricCard(title: t("Duration", "时长"), value: ChargeComparisonPresentation.durationText(stats?.durationMin, language: appLanguage), systemImage: "clock")
            MetricCard(title: t("Current", "电流"), value: stats?.currentAvg.map { String(format: "%.1f A", $0) } ?? "--", systemImage: "bolt.horizontal")
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ChargeCostEditor: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let apiCost: Double?
    let manualCost: Double?
    let pricingRuleCost: Double?
    let pricingRuleName: String?
    let pricingRuleMatchFactors: [ChargePricingMatchFactor]
    let pricingBreakdown: [ChargePricingCostComponent]
    let pricingSessionFee: Double
    let hasPricingRules: Bool
    let effectiveCost: Double?
    let costSourceType: ChargeCostSource
    let costSyncState: ChargeCostSyncState
    let errorMessage: String?
    let currencySymbol: String
    @Binding var costInput: String
    let onSave: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Charge Cost", "充电费用"))
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                TextField(t("Charge Cost", "充电费用"), text: $costInput)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                HStack(spacing: 10) {
                    Button(t("Save Cost", "保存费用"), action: onSave)
                        .buttonStyle(.borderedProminent)
                    Button(t("Clear Manual Cost", "清除手动费用"), action: onClear)
                        .buttonStyle(.bordered)
                }
                if let errorMessage {
                    Label(UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if costSyncState != .none {
                    Label(costSyncText, systemImage: costSyncState == .server ? "checkmark.icloud" : "iphone")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(costSyncState == .server ? Color.green : Color.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                MetricCard(title: t("Cost", "费用"), value: formatCost(effectiveCost), systemImage: "creditcard")
                MetricCard(title: t("Cost Source", "费用来源"), value: costSourceText, systemImage: "tag")
                MetricCard(title: t("Manual Cost", "手动费用"), value: formatCost(manualCost), systemImage: "pencil")
                MetricCard(title: t("Pricing Rule", "价格规则"), value: pricingRuleText, systemImage: "location.magnifyingglass")
                MetricCard(title: t("API Cost", "API 费用"), value: formatCost(apiCost), systemImage: "server.rack")
            }

            if let explanation = costExplanation {
                explanationSection(explanation)
            }

            if pricingRuleCost == nil {
                Text(hasPricingRules ? t("No pricing rule matched this charge", "没有匹配这次充电的价格规则") : t("Location and time pricing rules are not configured yet", "尚未配置位置和分时价格规则"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if !pricingBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("Pricing Breakdown", "计价明细"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(pricingBreakdown.enumerated()), id: \.offset) { _, component in
                        HStack {
                            Text(componentTime(component))
                            Spacer()
                            Text(String(format: "%.2f kWh × %@%.2f", component.energyKWh, currencySymbol, component.pricePerKWh))
                                .foregroundStyle(.secondary)
                            Text(formatCost(component.cost))
                                .monospacedDigit()
                        }
                        .font(.footnote)
                    }
                    if pricingSessionFee > 0 {
                        HStack {
                            Text(t("Session Fee", "单次服务费"))
                            Spacer()
                            Text(formatCost(pricingSessionFee))
                                .monospacedDigit()
                        }
                        .font(.footnote)
                    }
                }
            }
        }
    }

    private var costExplanation: ChargeCostExplanation? {
        ChargeCostExplanationBuilder.build(
            source: costSourceType,
            ruleName: pricingRuleName,
            matchFactors: pricingRuleMatchFactors,
            components: pricingBreakdown,
            sessionFee: pricingSessionFee,
            language: appLanguage
        )
    }

    private func explanationSection(_ explanation: ChargeCostExplanation) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label(t("How this cost was determined", "费用如何得出"), systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(explanation.status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(costSourceType == .pricingRule ? Color.orange : Color.green)
            }

            Text(explanation.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(explanation.evidence, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if explanation.allowsCorrection {
                Text(t(
                    "If the amount is inaccurate, edit it above. Your correction will be used first.",
                    "如果金额不准确，可在上方修改；你的修正会被优先采用。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("charge_cost_explanation")
    }

    private var costSourceText: String {
        costSourceType.displayText(language: appLanguage)
    }

    private var costSyncText: String {
        switch costSyncState {
        case .none:
            return ""
        case .server:
            return t("Synced to the TeslaMate API cost ledger", "已同步到 TeslaMate API 费用账本")
        case .localOnly:
            return t("Saved on this device only", "仅保存在本机")
        }
    }

    private var pricingRuleText: String {
        guard let pricingRuleCost else {
            return "--"
        }
        if let pricingRuleName, !pricingRuleName.isEmpty {
            return "\(pricingRuleName) · \(formatCost(pricingRuleCost))"
        }
        return formatCost(pricingRuleCost)
    }

    private func formatCost(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(currencySymbol)\(String(format: "%.2f", value))"
    }

    private func componentTime(_ component: ChargePricingCostComponent) -> String {
        guard let start = component.startMinuteOfDay, let end = component.endMinuteOfDay else {
            return t("Default rate", "默认电价")
        }
        return String(format: "%02d:%02d-%02d:%02d", start / 60, start % 60, end / 60, end % 60)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public struct ChargePointChart: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @State private var metric: ChargeChartMetric = .power
    @State private var selectedIndex: Int?

    let points: [ChargePoint]
    let units: UnitPreferences?

    public init(points: [ChargePoint], units: UnitPreferences? = nil) {
        self.points = points
        self.units = units
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Charge Samples", "充电采样")).font(.headline)
                Spacer()
                Text("\(points.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if points.isEmpty {
                LoadingStateView(title: t("No charge point data", "暂无充电采样数据"), systemImage: "chart.bar")
            } else {
                Picker(t("Chart Metric", "曲线指标"), selection: $metric) {
                    Text(t("Power", "功率")).tag(ChargeChartMetric.power)
                    Text(t("Battery", "电量")).tag(ChargeChartMetric.battery)
                }
                .pickerStyle(.segmented)

                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        if let value = metric.value(point) {
                            AreaMark(x: .value(t("Sample", "采样"), index), y: .value(metric.axisTitle(appLanguage), value))
                                .foregroundStyle(.tint.opacity(0.12))
                            LineMark(x: .value(t("Sample", "采样"), index), y: .value(metric.axisTitle(appLanguage), value))
                                .foregroundStyle(.tint)
                                .interpolationMethod(.monotone)
                            if selectedIndex == index {
                                RuleMark(x: .value(t("Selected", "已选择"), index))
                                    .foregroundStyle(.secondary)
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                            }
                        }
                    }
                }
                .chartYAxisLabel(metric.axisTitle(appLanguage))
                .chartXSelection(value: $selectedIndex)
                .frame(height: 210)
                .accessibilityLabel(metric.accessibilityTitle(appLanguage))

                if let selectedIndex, points.indices.contains(selectedIndex) {
                    sampleDetail(points[selectedIndex], index: selectedIndex)
                } else {
                    Text(t("Touch the curve to inspect a sample.", "触摸曲线可查看单个采样点。"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sampleDetail(_ point: ChargePoint, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(sampleTime(point, index: index)).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                sampleValue("bolt.fill", point.chargerPower.map { "\($0) kW" })
                sampleValue("battery.50percent", point.batteryLevel.map { "\($0)%" })
                sampleValue("waveform.path.ecg", point.chargerVoltage.map { "\($0) V" })
                sampleValue("thermometer.medium", point.outsideTemp.map { MateDriveUnitFormatter.formatTemperature($0, units: units, decimals: 1) })
            }
            .font(.caption)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func sampleValue(_ image: String, _ value: String?) -> some View {
        Label(value ?? "--", systemImage: image).lineLimit(1)
    }

    private func sampleTime(_ point: ChargePoint, index: Int) -> String {
        if let date = point.date.flatMap(DomainDateParser.date(from:)) {
            return date.formatted(date: .omitted, time: .standard)
        }
        return t("Sample \(index + 1)", "采样点 \(index + 1)")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private enum ChargeChartMetric: String, CaseIterable {
    case power
    case battery

    func value(_ point: ChargePoint) -> Double? {
        return switch self {
        case .power: point.chargerPower.map(Double.init)
        case .battery: point.batteryLevel.map(Double.init)
        }
    }

    func axisTitle(_ language: AppLanguage) -> String {
        let chinese = MateDriveUnitFormatter.usesChineseLabels(language: language)
        return switch self {
        case .power: chinese ? "功率 (kW)" : "Power (kW)"
        case .battery: chinese ? "电量 (%)" : "Battery (%)"
        }
    }

    func accessibilityTitle(_ language: AppLanguage) -> String {
        let chinese = MateDriveUnitFormatter.usesChineseLabels(language: language)
        return switch self {
        case .power: chinese ? "充电功率曲线" : "Charging power curve"
        case .battery: chinese ? "充电电量曲线" : "Charging battery curve"
        }
    }
}
