import MapKit
import SwiftUI

public struct ActivitiesView: View {
    private enum DisplayMode: String, CaseIterable {
        case list
        case map
    }

    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: ActivitiesViewModel
    @State private var hasLoaded = false
    @State private var selectedParking: TeslaMateActivity?
    @State private var displayMode: DisplayMode = .list
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var selectedActivityID: String?

    private let carId: Int
    private let exteriorColor: String?
    private let standbyDrainAPI: any ActivityAPIProviding
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: ActivitiesViewModel, standbyDrainAPI: any ActivityAPIProviding, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.standbyDrainAPI = standbyDrainAPI
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading activities", "正在加载活动"), showsProgress: true)
            } else if displayMode == .map {
                activityMap
            } else {
                activityList
            }
        }
        .navigationTitle(t("Activities", "活动"))
        .searchable(
            text: Binding(get: { viewModel.state.locationQuery }, set: { viewModel.setLocationQuery($0) }),
            prompt: t("Search start or destination", "搜索起点或终点")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(t("View", "视图"), selection: $displayMode) {
                    Label(t("List", "列表"), systemImage: "list.bullet").tag(DisplayMode.list)
                    Label(t("Map", "地图"), systemImage: "map").tag(DisplayMode.map)
                }
                .pickerStyle(.segmented)
                .frame(width: 112)
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
        .sheet(item: $selectedParking) { item in
            NavigationStack {
                ParkingActivityDetailView(
                    activity: item,
                    carId: carId,
                    standbyDrainAPI: standbyDrainAPI,
                    units: resolvedUnits
                )
            }
                .environment(\.appLanguage, appLanguage)
        }
        .onChange(of: selectedActivityID) { _, stableID in
            guard let stableID,
                  let item = viewModel.filteredItems.first(where: { $0.stableID == stableID })
            else { return }
            selectedActivityID = nil
            open(item)
        }
    }

    private var activityList: some View {
        List {
            filterControls
            historyCoverage
            periodSummary
            sourceNotice
            ForEach(viewModel.filteredItems, id: \.stableID) { item in
                activityRow(item)
                    .onAppear { Task { await viewModel.loadMoreIfNeeded(currentItem: item) } }
            }
            if viewModel.state.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
            if viewModel.filteredItems.isEmpty {
                ContentUnavailableView(t("No activities", "暂无活动"), systemImage: "clock.arrow.circlepath")
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var activityMap: some View {
        VStack(spacing: 0) {
            filterControls
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            historyCoverage
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            if viewModel.mappableItems.isEmpty {
                ContentUnavailableView(
                    t("No mapped activities", "暂无可显示位置的活动"),
                    systemImage: "map"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Map(position: $mapPosition, selection: $selectedActivityID) {
                    ForEach(viewModel.mappableItems, id: \.stableID) { item in
                        if let coordinate = coordinate(for: item) {
                            Marker(kindTitle(item.kind), systemImage: icon(item.kind), coordinate: coordinate)
                                .tint(color(item.kind))
                                .tag(item.stableID)
                        }
                    }
                }
                .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
                .accessibilityLabel(t("Activity map", "活动地图"))
            }
            if viewModel.state.hasMore {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.state.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label(t("Load more activities", "加载更多活动"), systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.state.isLoadingMore || viewModel.state.isLoadingHistory)
                .padding(12)
            }
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(t("Type", "类型"), selection: Binding(
                get: { viewModel.state.filter },
                set: { viewModel.setFilter($0) }
            )) {
                Text(t("All", "全部")).tag(ActivityFilter.all)
                Text(t("Drives", "行程")).tag(ActivityFilter.drive)
                Text(t("Charges", "充电")).tag(ActivityFilter.charge)
                Text(t("Parked", "停车")).tag(ActivityFilter.park)
            }
            .pickerStyle(.segmented)
            Picker(t("Period", "时间范围"), selection: Binding(
                get: { viewModel.state.dateFilter },
                set: { viewModel.setDateFilter($0) }
            )) {
                Text(t("All time", "全部时间")).tag(ActivityDateFilter.all)
                Text(t("Last 7 days", "最近 7 天")).tag(ActivityDateFilter.sevenDays)
                Text(t("Last 30 days", "最近 30 天")).tag(ActivityDateFilter.thirtyDays)
                Text(t("This year", "今年")).tag(ActivityDateFilter.thisYear)
            }
            .pickerStyle(.menu)
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var historyCoverage: some View {
        if viewModel.state.historyFullyLoaded {
            Label(
                t("Complete history loaded (\(viewModel.state.items.count) records)", "已加载完整历史（\(viewModel.state.items.count) 条）"),
                systemImage: "checkmark.circle.fill"
            )
            .font(.footnote)
            .foregroundStyle(.green)
        } else if viewModel.state.historyLoadCapped {
            Label(t("History limit reached; results remain partial.", "已达到历史加载上限；结果仍不完整。"), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if viewModel.state.hasMore {
            Button {
                Task { await viewModel.loadCompleteHistory() }
            } label: {
                if viewModel.state.isLoadingHistory {
                    HStack { ProgressView(); Text(t("Loading complete history…", "正在加载完整历史…")) }
                } else {
                    Label(t("Load complete history for accurate filters", "加载完整历史以准确筛选"), systemImage: "clock.arrow.2.circlepath")
                }
            }
            .disabled(viewModel.state.isLoadingHistory)
        }
    }

    private var periodSummary: some View {
        let summary = viewModel.periodSummary
        return VStack(alignment: .leading, spacing: 8) {
            Text(t("Period Summary", "周期汇总")).font(.headline)
            LabeledContent(t("Records", "记录"), value: "\(summary.activityCount)")
            LabeledContent(t("Drive / Charge / Park", "行程 / 充电 / 停车"), value: "\(summary.driveCount) / \(summary.chargeCount) / \(summary.parkingCount)")
            LabeledContent(t("Distance", "里程"), value: ActivitySummaryPresentation.distanceText(summary.distanceKm, isComplete: summary.distanceIsComplete, units: resolvedUnits))
            coverageText(known: summary.distanceRecordCount, total: summary.driveCount, english: "Distance coverage", chinese: "里程覆盖")
            LabeledContent(t("Charged Energy", "充入能量"), value: ActivitySummaryPresentation.energyText(summary.chargedEnergyKWh, isComplete: summary.chargedEnergyIsComplete))
            coverageText(known: summary.chargedEnergyRecordCount, total: summary.chargeCount, english: "Charge energy coverage", chinese: "充电电量覆盖")
            LabeledContent(t("Driving Energy", "行驶能量"), value: ActivitySummaryPresentation.energyText(summary.drivingEnergyKWh, isComplete: summary.drivingEnergyIsComplete))
            coverageText(known: summary.drivingEnergyRecordCount, total: summary.driveCount, english: "Driving energy coverage", chinese: "行驶电耗覆盖")
            if summary.chargeCount > 0 {
                LabeledContent(t("Known Charge Cost", "已知充电费用"), value: chargeCostText(summary.knownChargeCost, isComplete: summary.chargeCostIsComplete))
                Text(t("Price coverage: \(summary.pricedChargeCount)/\(summary.chargeCount)", "价格覆盖：\(summary.pricedChargeCount)/\(summary.chargeCount)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(t("Parking Cost", "停车费用"), value: currencySymbol + String(format: "%.2f", summary.parkingCost.totalCost))
            if summary.parkingCost.unmatchedParkingCount > 0 {
                Text(t(
                    "\(summary.parkingCost.unmatchedParkingCount) parking records have no matching fee rule.",
                    "\(summary.parkingCost.unmatchedParkingCount) 条停车记录没有匹配费用规则。"
                ))
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var sourceNotice: some View {
        if viewModel.state.source == .localFallback {
            Label(t("Using drive and charge fallback; parking is unavailable.", "正在使用行程和充电回退数据；停车数据不可用。"), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if viewModel.state.paginationIsDegraded {
            Label(t("Server pagination metadata is inaccurate; loading uses actual page results.", "服务端分页信息不准确；已按实际页面结果加载。"), systemImage: "checkmark.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func activityRow(_ item: TeslaMateActivity) -> some View {
        Button { open(item) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon(item.kind))
                    .font(.title3)
                    .foregroundStyle(color(item.kind))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(kindTitle(item.kind)).font(.body.weight(.semibold))
                        Spacer()
                        Text(dateText(item.startDate)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(locationText(item)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 6) {
                        if let duration = item.durationMin { Label(durationText(duration), systemImage: "clock") }
                        if let distance = item.distanceKm { Label(distanceText(distance), systemImage: "road.lanes") }
                        if let socDiff = item.socDiff { Label(signed(socDiff) + "%", systemImage: "battery.50percent") }
                        if item.kind == .charge {
                            Text(item.cost.map { chargeCostText($0, isComplete: true) } ?? t("Cost --", "费用 --"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    private func open(_ item: TeslaMateActivity) {
        switch item.kind {
        case .drive: navigate(.driveDetail(carId: carId, driveId: item.id, exteriorColor: exteriorColor))
        case .charge: navigate(.chargeDetail(carId: carId, chargeId: item.id, exteriorColor: exteriorColor))
        case .park: selectedParking = item
        case .unknown: break
        }
    }

    private func chargeCostText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + currencySymbol + String(format: "%.2f", $0) } ?? "--"
    }

    @ViewBuilder
    private func coverageText(known: Int, total: Int, english: String, chinese: String) -> some View {
        if known < total {
            Text(t("\(english): \(known)/\(total)", "\(chinese)：\(known)/\(total)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var currencySymbol: String {
        MateDroidCurrencyFormatter.symbol(for: viewModel.state.currencyCode)
    }

    private func kindTitle(_ kind: TeslaMateActivityKind) -> String {
        switch kind {
        case .drive: t("Drive", "行程")
        case .charge: t("Charge", "充电")
        case .park: t("Parked", "停车")
        case .unknown: t("Unknown", "未知")
        }
    }

    private func icon(_ kind: TeslaMateActivityKind) -> String {
        switch kind { case .drive: "road.lanes"; case .charge: "bolt.fill"; case .park: "parkingsign.circle"; case .unknown: "questionmark.circle" }
    }

    private func color(_ kind: TeslaMateActivityKind) -> Color {
        switch kind { case .drive: .blue; case .charge: .green; case .park: .orange; case .unknown: .secondary }
    }

    private func locationText(_ item: TeslaMateActivity) -> String {
        [item.startAddress, item.endAddress].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " → ").nilIfEmpty ?? t("Location unavailable", "位置不可用")
    }

    private func coordinate(for item: TeslaMateActivity) -> CLLocationCoordinate2D? {
        let location = GeoCoordinateValidator.location(latitude: item.startLatitude, longitude: item.startLongitude)
            ?? GeoCoordinateValidator.location(latitude: item.endLatitude, longitude: item.endLongitude)
        return location.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func dateText(_ value: String?) -> String {
        value.flatMap(DomainDateParser.date(from:))?.formatted(date: .abbreviated, time: .shortened) ?? "--"
    }

    private func durationText(_ minutes: Double) -> String { "\(Int(minutes.rounded())) " + t("min", "分钟") }
    private var resolvedUnits: UnitPreferences? { viewModel.state.units.resolved(for: appDisplayUnitSystem) }
    private func distanceText(_ km: Double) -> String { MateDroidUnitFormatter.formatDistance(km, units: resolvedUnits) }
    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}

public enum ActivitySummaryPresentation {
    public static func distanceText(_ value: Double?, isComplete: Bool, units: UnitPreferences?) -> String {
        value.map { (isComplete ? "" : "≥") + MateDroidUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    public static func energyText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + String(format: "%.1f kWh", $0) } ?? "--"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
