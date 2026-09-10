import MapKit
import SwiftUI

public struct ActivitiesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: ActivitiesViewModel
    @State private var hasLoaded = false
    @State private var selectedParking: TeslaMateActivity?
    @State private var selectedDriveGroup: AdjacentDriveGroup?
    @State private var showsPeriodShareComposer = false
    @State private var displayMode: ListMapViewMode = .list
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
            if viewModel.state.isLoading, viewModel.state.items.isEmpty {
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
                ListMapToolbarButton(
                    mode: $displayMode,
                    showListLabel: t("Show list", "显示列表"),
                    showMapLabel: t("Show map", "显示地图")
                )
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
        .sheet(item: $selectedDriveGroup) { group in
            NavigationStack {
                AdjacentDriveGroupDetailView(group: group, units: resolvedUnits) { drive in
                    selectedDriveGroup = nil
                    open(drive)
                }
            }
            .environment(\.appLanguage, appLanguage)
            .environment(\.appDisplayUnitSystem, appDisplayUnitSystem)
        }
        .sheet(isPresented: $showsPeriodShareComposer) {
            ActivityPeriodShareComposerView(
                summary: viewModel.periodSummary,
                dateFilter: viewModel.state.dateFilter,
                activityFilter: viewModel.state.filter,
                dateRange: viewModel.periodDateRange,
                historyIsComplete: viewModel.state.historyFullyLoaded,
                locationFilterIsActive: !viewModel.state.locationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                currencyCode: viewModel.state.currencyCode,
                units: resolvedUnits
            )
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
            sleepSummary
            historyCoverage
            periodSummary
            sourceNotice
            ForEach(viewModel.timelineEntries) { entry in
                timelineRow(entry)
                    .onAppear { Task { await viewModel.loadMoreIfNeeded(currentItem: entry.paginationAnchor) } }
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

    private var sleepSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(t("Sleep Duration", "休眠时长"), systemImage: "moon.zzz.fill")
                .font(.headline)
                .foregroundStyle(.indigo)

            Picker(t("Sleep Period", "休眠周期"), selection: Binding(
                get: { viewModel.selectedSleepPeriod },
                set: { viewModel.setSleepPeriod($0) }
            )) {
                Text(t("Charge", "充电后")).tag(SleepDurationPeriod.sinceCharge)
                Text(t("Today", "今天")).tag(SleepDurationPeriod.today)
                Text(t("Week", "本周")).tag(SleepDurationPeriod.week)
                Text(t("Month", "本月")).tag(SleepDurationPeriod.month)
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline) {
                Text(sleepPeriodTitle(viewModel.selectedSleepPeriod))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(sleepSummaryText(viewModel.selectedSleepSummary))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
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
            Toggle(
                t("Merge adjacent drives", "合并相邻行程"),
                isOn: Binding(
                    get: { viewModel.mergeConfiguration.isEnabled },
                    set: { value in Task { await viewModel.setAdjacentDriveMergingEnabled(value) } }
                )
            )
            if viewModel.mergeConfiguration.isEnabled {
                Picker(
                    t("Maximum stop", "最长停留"),
                    selection: Binding(
                        get: { viewModel.mergeConfiguration.maximumGapMinutes },
                        set: { value in Task { await viewModel.setAdjacentDriveMergeMaximumGapMinutes(value) } }
                    )
                ) {
                    ForEach([15, 30, 60, 120], id: \.self) { minutes in
                        Text("\(minutes) " + t("min", "分钟")).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
            }
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
            HStack {
                Text(t("Period Summary", "周期汇总")).font(.headline)
                Spacer()
                Button {
                    showsPeriodShareComposer = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help(t("Share Period Recap", "分享周期回顾"))
                .accessibilityLabel(t("Share Period Recap", "分享周期回顾"))
                .disabled(summary.activityCount == 0)
            }
            LabeledContent(t("Records", "记录"), value: "\(summary.activityCount)")
            LabeledContent(t("Drive / Charge / Park", "行程 / 充电 / 停车"), value: "\(summary.driveCount) / \(summary.chargeCount) / \(summary.parkingCount)")
            if viewModel.mergedDriveGroupCount > 0 {
                Label(
                    formatted(
                        "%d adjacent-drive groups; original record counts are retained.",
                        "已合并 %d 组相邻行程；原始记录数量保持不变。",
                        viewModel.mergedDriveGroupCount
                    ),
                    systemImage: "arrow.triangle.branch"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
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
            LabeledContent(
                t("Parking Cost", "停车费用"),
                value: ActivitySummaryPresentation.parkingCostText(
                    summary.parkingCost,
                    parkingCount: summary.parkingCount,
                    historyIsComplete: viewModel.state.historyFullyLoaded,
                    currencyCode: viewModel.state.currencyCode
                )
            )
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

    @ViewBuilder
    private func timelineRow(_ entry: ActivityTimelineEntry) -> some View {
        switch entry {
        case let .single(activity):
            activityRow(activity)
        case let .mergedDrive(group):
            mergedDriveRow(group)
        }
    }

    private func mergedDriveRow(_ group: AdjacentDriveGroup) -> some View {
        Button { selectedDriveGroup = group } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(t("Merged Drive", "合并行程")).font(.body.weight(.semibold))
                        Spacer()
                        Text(dateText(group.startDate)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(mergedLocationText(group)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 6) {
                        Label(
                            formatted("%d segments", "%d 段行程", group.drives.count),
                            systemImage: "point.3.connected.trianglepath.dotted"
                        )
                        if let distance = group.distance.value {
                            Label(
                                ActivitySummaryPresentation.distanceText(
                                    distance,
                                    isComplete: group.distance.isComplete,
                                    units: resolvedUnits
                                ),
                                systemImage: "road.lanes"
                            )
                        }
                        Label(
                            formatted(
                                "%d min stops",
                                "停留 %d 分钟",
                                Int(group.stopDurationMinutes.rounded())
                            ),
                            systemImage: "pause.circle"
                        )
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

    private func mergedLocationText(_ group: AdjacentDriveGroup) -> String {
        [group.startAddress, group.endAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
            .nilIfEmpty ?? t("Location unavailable", "位置不可用")
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
        MateDriveCurrencyFormatter.symbol(for: viewModel.state.currencyCode)
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
    private func distanceText(_ km: Double) -> String { MateDriveUnitFormatter.formatDistance(km, units: resolvedUnits) }
    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
    private func sleepPeriodTitle(_ period: SleepDurationPeriod) -> String {
        switch period {
        case .sinceCharge: t("Since Charge", "充电以来")
        case .today: t("Today", "今天")
        case .week: t("This Week", "本周")
        case .month: t("This Month", "本月")
        }
    }
    private func sleepSummaryText(_ summary: SleepDurationSummary?) -> String {
        guard let summary, summary.isAvailable else {
            return t("Unavailable", "服务端未提供")
        }
        guard let duration = summary.duration, duration > 0 else {
            return t("No sleep recorded", "暂无休眠记录")
        }
        return MateDriveUnitFormatter.formatDuration(
            minutes: max(Int(duration / 60), 1),
            language: appLanguage
        )
    }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
    private func formatted(_ english: String, _ chinese: String, _ arguments: CVarArg...) -> String {
        String(format: t(english, chinese), arguments: arguments)
    }
}

public enum ActivitySummaryPresentation {
    public static func distanceText(_ value: Double?, isComplete: Bool, units: UnitPreferences?) -> String {
        value.map { (isComplete ? "" : "≥") + MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    public static func energyText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + String(format: "%.1f kWh", $0) } ?? "--"
    }

    public static func currencyText(_ value: Double?, isComplete: Bool, currencyCode: String) -> String {
        value.map {
            (isComplete ? "" : "≥")
                + MateDriveCurrencyFormatter.symbol(for: currencyCode)
                + String(format: "%.2f", $0)
        } ?? "--"
    }

    public static func parkingCostText(
        _ summary: ParkingCostSummary,
        parkingCount: Int,
        historyIsComplete: Bool,
        currencyCode: String
    ) -> String {
        if parkingCount == 0 {
            return historyIsComplete
                ? currencyText(0, isComplete: true, currencyCode: currencyCode)
                : "--"
        }
        guard summary.matchedParkingCount > 0 else { return "--" }
        return currencyText(
            summary.totalCost,
            isComplete: summary.unmatchedParkingCount == 0 && historyIsComplete,
            currencyCode: currencyCode
        )
    }
}

private struct AdjacentDriveGroupDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss

    let group: AdjacentDriveGroup
    let units: UnitPreferences?
    let onOpenDrive: (TeslaMateActivity) -> Void

    var body: some View {
        List {
            Section(t("Combined Summary", "合并汇总")) {
                LabeledContent(t("Segments", "行程段数"), value: "\(group.drives.count)")
                LabeledContent(
                    t("Distance", "里程"),
                    value: ActivitySummaryPresentation.distanceText(
                        group.distance.value,
                        isComplete: group.distance.isComplete,
                        units: units
                    )
                )
                LabeledContent(
                    t("Driving Time", "驾驶时长"),
                    value: measurementMinutes(group.drivingDuration)
                )
                LabeledContent(
                    t("Intermediate Stops", "中途停留"),
                    value: formatted("%d min", "%d 分钟", Int(group.stopDurationMinutes.rounded()))
                )
                LabeledContent(
                    t("Driving Energy", "行驶能量"),
                    value: ActivitySummaryPresentation.energyText(
                        group.drivingEnergy.value,
                        isComplete: group.drivingEnergy.isComplete
                    )
                )
            }

            Section(t("Why These Drives Were Merged", "合并依据")) {
                Text(t(
                    "MateDrive groups the display only. TeslaMate records remain unchanged, and every original segment stays available below.",
                    "MateDrive 只合并显示，不会修改 TeslaMate 记录；下方仍可查看每一段原始行程。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
                ForEach(Array(group.connections.enumerated()), id: \.offset) { index, connection in
                    Label(connectionText(index: index, connection: connection), systemImage: evidenceIcon(connection))
                        .font(.subheadline)
                }
            }

            Section(t("Original Drive Segments", "原始行程分段")) {
                ForEach(group.drives, id: \.stableID) { drive in
                    Button {
                        dismiss()
                        onOpenDrive(drive)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "road.lanes").foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(segmentLocation(drive)).font(.body.weight(.medium))
                                HStack(spacing: 10) {
                                    Text(dateText(drive.startDate))
                                    if let distance = drive.distanceKm {
                                        Text(MateDriveUnitFormatter.formatDistance(distance, units: units))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(t("Merged Drive", "合并行程"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Done", "完成")) { dismiss() }
            }
        }
    }

    private func measurementMinutes(_ measurement: ActivityAggregateMeasurement) -> String {
        guard let value = measurement.value else { return "--" }
        return (measurement.isComplete ? "" : "≥") + formatted("%d min", "%d 分钟", Int(value.rounded()))
    }

    private func connectionText(index: Int, connection: AdjacentDriveConnection) -> String {
        let number = index + 1
        let gap = Int(connection.gapMinutes.rounded())
        if let distance = connection.distanceMeters {
            return formatted(
                "Segments %d-%d: %d min stop, endpoints %d m apart",
                "第 %d-%d 段：停留 %d 分钟，衔接点相距 %d 米",
                number,
                number + 1,
                gap,
                Int(distance.rounded())
            )
        }
        return formatted(
            "Segments %d-%d: %d min stop, matching endpoint address",
            "第 %d-%d 段：停留 %d 分钟，衔接点地址一致",
            number,
            number + 1,
            gap
        )
    }

    private func evidenceIcon(_ connection: AdjacentDriveConnection) -> String {
        connection.locationEvidence == .coordinates ? "location.fill" : "mappin.and.ellipse"
    }

    private func segmentLocation(_ activity: TeslaMateActivity) -> String {
        [activity.startAddress, activity.endAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " → ")
            .nilIfEmpty ?? t("Location unavailable", "位置不可用")
    }

    private func dateText(_ value: String?) -> String {
        value.flatMap(DomainDateParser.date(from:))?.formatted(date: .abbreviated, time: .shortened) ?? "--"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private func formatted(_ english: String, _ chinese: String, _ arguments: CVarArg...) -> String {
        String(format: t(english, chinese), arguments: arguments)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
