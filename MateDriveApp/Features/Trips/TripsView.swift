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
            if viewModel.state.isLoading, !viewModel.state.hasLoadedData {
                LoadingStateView(title: t("Loading trips", "正在加载路程"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, !viewModel.state.hasLoadedData {
                LoadingStateView(
                    title: t("Trips unavailable", "路程不可用"),
                    message: UserFacingErrorLocalizer.localized(error, language: appLanguage),
                    systemImage: "map",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId) } }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        filters
                        summary
                        tripList
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle(t("Trips", "路程"))
        .accessibilityIdentifier("trips_view")
        .toolbar {
            Button {
                navigate(.createTrip(carId: carId, exteriorColor: exteriorColor))
            } label: {
                Label(t("Create Trip", "创建路程"), systemImage: "plus")
            }
            .accessibilityIdentifier("create_trip_button")
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
            MetricCard(title: t("Distance", "距离"), value: MateDriveUnitFormatter.formatDistance(viewModel.state.totalDistance, units: units, decimals: 0), systemImage: "road.lanes")
            MetricCard(title: t("Driving", "驾驶"), value: MateDriveUnitFormatter.formatDuration(minutes: viewModel.state.totalDrivingMin, language: appLanguage), systemImage: "clock")
            MetricCard(
                title: t("Charged", "已充电"),
                value: TripEnergyPresentation.text(
                    viewModel.state.totalEnergyCharged,
                    isComplete: viewModel.state.chargedEnergyIsComplete
                ),
                systemImage: "bolt.fill"
            )
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
                    .accessibilityIdentifier("trips_refresh_warning")
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
                    .accessibilityIdentifier(tripAccessibilityIdentifier(trip))
                }
            }
        }
    }

    private func tripAccessibilityIdentifier(_ trip: DetectedTrip) -> String {
        if let driveID = trip.drives.first?.id {
            return "trip_row_\(driveID)"
        }
        return "trip_row_\(trip.startDate)"
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
                Text(MateDriveUnitFormatter.formatDistance(trip.totalDistance, units: units, decimals: 0))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            TripTimelineView(segments: segments, compact: true, language: language)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 6) {
                Label(MateDriveUnitFormatter.formatDuration(minutes: trip.totalDrivingDurationMin, language: language), systemImage: "clock")
                Label(stopCountText(trip.charges.count), systemImage: "bolt.car")
                Label(
                    TripEnergyPresentation.text(trip.totalEnergyConsumed, isComplete: trip.drivingEnergyIsComplete),
                    systemImage: "leaf"
                )
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
            return MateDriveUnitFormatter.usesChineseLabels(language: language) ? "费用 --" : "Cost --"
        }
        let prefix = trip.chargeCostIsComplete ? "" : "≥"
        return prefix + currencySymbol + String(format: "%.2f", cost)
    }

    private func stopCountText(_ count: Int) -> String {
        if MateDriveUnitFormatter.usesChineseLabels(language: language) {
            return "\(count) 次停靠"
        }
        return "\(count) stops"
    }
}
