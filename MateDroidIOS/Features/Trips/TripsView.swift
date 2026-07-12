import SwiftUI

public struct TripsView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: TripsViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: TripsViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.navigate = navigate
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading trips", "正在加载路程"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        filters
                        summary
                        tripList
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Trips", "路程"))
        .toolbar {
            Button {
                navigate(.createTrip(carId: carId, exteriorColor: exteriorColor))
            } label: {
                Label(t("Create Trip", "创建路程"), systemImage: "plus")
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var filters: some View {
        Picker(t("Year", "年份"), selection: Binding(
            get: { viewModel.state.selectedYear ?? 0 },
            set: { viewModel.setYear($0 == 0 ? nil : $0) }
        )) {
            Text(t("All", "全部")).tag(0)
            ForEach(viewModel.state.availableYears, id: \.self) { year in
                Text(String(year)).tag(year)
            }
        }
        .pickerStyle(.segmented)
    }

    private var summary: some View {
        let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Trips", "路程"), value: "\(viewModel.state.trips.count)", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            MetricCard(title: t("Distance", "距离"), value: MateDroidUnitFormatter.formatDistance(viewModel.state.totalDistance, units: units, decimals: 0), systemImage: "road.lanes")
            MetricCard(title: t("Driving", "驾驶"), value: MateDroidUnitFormatter.formatDuration(minutes: viewModel.state.totalDrivingMin, language: appLanguage), systemImage: "clock")
            MetricCard(title: t("Charged", "已充电"), value: String(format: "%.1f kWh", viewModel.state.totalEnergyCharged), systemImage: "bolt.fill")
            if viewModel.state.totalChargeCount > 0 {
                MetricCard(
                    title: t("Known Charge Cost", "已知充电费用"),
                    value: costText(viewModel.state.totalChargeCost, isComplete: viewModel.state.chargeCostIsComplete),
                    subtitle: t("Price coverage: \(viewModel.state.pricedChargeCount)/\(viewModel.state.totalChargeCount)", "价格覆盖：\(viewModel.state.pricedChargeCount)/\(viewModel.state.totalChargeCount)"),
                    systemImage: "creditcard"
                )
            }
        }
    }

    private var tripList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if viewModel.state.trips.isEmpty {
                LoadingStateView(title: t("No trips found", "暂无路程"), systemImage: "map")
            } else {
                ForEach(viewModel.state.trips, id: \.startDate) { trip in
                    Button {
                        navigate(.tripDetail(carId: carId, tripStartDate: trip.startDate, exteriorColor: exteriorColor))
                    } label: {
                        TripRow(
                            trip: trip,
                            units: viewModel.state.units.resolved(for: appDisplayUnitSystem),
                            language: appLanguage,
                            currencySymbol: viewModel.state.currencySymbol,
                            segments: TripTimelineBuilder.build(
                                trip: trip,
                                dcChargeIds: viewModel.state.dcChargeIds,
                                showShort: viewModel.state.showShortDrivesCharges
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private func costText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + viewModel.state.currencySymbol + String(format: "%.2f", $0) } ?? "--"
    }
}

private struct TripRow: View {
    let trip: DetectedTrip
    let units: UnitPreferences?
    let language: AppLanguage
    let currencySymbol: String
    let segments: [TripTimelineSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.displayName(language: language))
                    .font(.body.weight(.semibold))
                Spacer()
                Text(MateDroidUnitFormatter.formatDistance(trip.totalDistance, units: units, decimals: 0))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            TripTimelineView(segments: segments, compact: true, language: language)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 6) {
                Label(MateDroidUnitFormatter.formatDuration(minutes: trip.totalDrivingDurationMin, language: language), systemImage: "clock")
                Label(stopCountText(trip.charges.count), systemImage: "bolt.car")
                if trip.totalEnergyConsumed > 0 {
                    Text(String(format: "%.1f kWh", trip.totalEnergyConsumed))
                }
                if !trip.charges.isEmpty {
                    Text(chargeCostText)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var chargeCostText: String {
        guard let cost = trip.totalChargeCost else {
            return MateDroidUnitFormatter.usesChineseLabels(language: language) ? "费用 --" : "Cost --"
        }
        let prefix = trip.chargeCostIsComplete ? "" : "≥"
        return prefix + currencySymbol + String(format: "%.2f", cost)
    }

    private func stopCountText(_ count: Int) -> String {
        if MateDroidUnitFormatter.usesChineseLabels(language: language) {
            return "\(count) 次停靠"
        }
        return "\(count) stops"
    }
}
