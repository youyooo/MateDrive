import MapKit
import SwiftUI

public struct PlaceInsightsView: View {
    private enum Mode: String, CaseIterable { case list, map }

    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: PlaceInsightsViewModel
    @State private var hasLoaded = false
    @State private var mode: Mode = .list
    @State private var selectedPlace: PlaceInsight?
    @State private var mapPosition: MapCameraPosition = .automatic

    private let carId: Int
    private let standbyDrainAPI: any ActivityAPIProviding

    public init(carId: Int, viewModel: PlaceInsightsViewModel, standbyDrainAPI: any ActivityAPIProviding) {
        self.carId = carId
        self.standbyDrainAPI = standbyDrainAPI
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading places", "正在加载地点"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.places.isEmpty {
                LoadingStateView(title: t("Places unavailable", "地点数据不可用"), message: error, systemImage: "mappin.slash")
            } else if mode == .map {
                placeMap
            } else {
                placeList
            }
        }
        .navigationTitle(t("Place Insights", "地点洞察"))
        .searchable(text: Binding(get: { viewModel.state.query }, set: { viewModel.setQuery($0) }), prompt: t("Search places", "搜索地点"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(t("View", "视图"), selection: $mode) {
                    Label(t("List", "列表"), systemImage: "list.bullet").tag(Mode.list)
                    Label(t("Map", "地图"), systemImage: "map").tag(Mode.map)
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
        .sheet(item: $selectedPlace) { place in
            NavigationStack { detail(place) }
                .environment(\.appLanguage, appLanguage)
        }
    }

    private var placeList: some View {
        List {
            coverage
            ForEach(viewModel.filteredPlaces) { place in
                Button { selectedPlace = place } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(.blue).frame(width: 26)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(place.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            if let role = place.role {
                                Text(roleTitle(role, confidence: place.roleConfidence)).font(.caption2.weight(.semibold)).foregroundStyle(.blue)
                            }
                            Text(t("\(place.totalEvents) records · \(place.chargeCount) charges · \(place.parkingCount) parks", "\(place.totalEvents) 条记录 · \(place.chargeCount) 次充电 · \(place.parkingCount) 次停车"))
                                .font(.caption).foregroundStyle(.secondary)
                            if let date = place.lastVisitedAt {
                                Text(t("Last visited \(date.formatted(date: .abbreviated, time: .shortened))", "最近访问 \(date.formatted(date: .abbreviated, time: .shortened))"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
            if viewModel.filteredPlaces.isEmpty {
                ContentUnavailableView(t("No places", "暂无地点"), systemImage: "mappin.slash")
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var placeMap: some View {
        VStack(spacing: 0) {
            coverage.padding(12)
            Map(position: $mapPosition) {
                ForEach(viewModel.filteredPlaces) { place in
                    if let location = GeoCoordinateValidator.location(latitude: place.latitude, longitude: place.longitude) {
                        Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                            Button { selectedPlace = place } label: {
                                Image(systemName: place.chargeCount > 0 ? "bolt.circle.fill" : "mappin.circle.fill")
                                    .font(.title).foregroundStyle(place.chargeCount > 0 ? .green : .blue)
                            }
                            .accessibilityLabel(place.name)
                        }
                    }
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
        }
    }

    @ViewBuilder private var coverage: some View {
        if viewModel.state.usesServerPlaces {
            Label(t("\(viewModel.state.places.count) smart places from complete server pagination", "已完整分页加载 \(viewModel.state.places.count) 个智能地点"), systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        } else if viewModel.state.historyFullyLoaded {
            Label(t("\(viewModel.state.places.count) places from \(viewModel.state.activityCount) complete activity records", "从 \(viewModel.state.activityCount) 条完整活动记录识别出 \(viewModel.state.places.count) 个地点"), systemImage: "checkmark.circle.fill")
                .font(.footnote).foregroundStyle(.green)
        } else {
            Label(t("Place results are partial because the history limit was reached.", "历史记录达到加载上限，地点结果不完整。"), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
        }
    }

    private func detail(_ place: PlaceInsight) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(place.name).font(.title2.bold())
                if let location = GeoCoordinateValidator.location(latitude: place.latitude, longitude: place.longitude) {
                    let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))) {
                        Marker(place.name, coordinate: coordinate)
                    }
                    .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8))
                    NavigationLink {
                        StandbyDrainView(carId: carId, latitude: location.latitude, longitude: location.longitude, placeName: place.name, viewModel: StandbyDrainViewModel(api: standbyDrainAPI))
                    } label: {
                        Label(t("View Standby Drain", "查看待机损耗"), systemImage: "moon.zzz").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    if let visits = place.visitCount { MetricCard(title: t("Visits", "到访次数"), value: "\(visits)", systemImage: "figure.walk") }
                    if let activeDays = place.activeDays { MetricCard(title: t("Active Days", "活跃天数"), value: "\(activeDays)", systemImage: "calendar") }
                    MetricCard(title: t("Departures", "出发"), value: "\(place.departureCount)", systemImage: "arrow.up.right")
                    MetricCard(title: t("Arrivals", "到达"), value: "\(place.arrivalCount)", systemImage: "arrow.down.left")
                    MetricCard(title: t("Charges", "充电"), value: "\(place.chargeCount)", systemImage: "bolt.fill")
                    MetricCard(title: t("Parking", "停车"), value: "\(place.parkingCount)", systemImage: "parkingsign.circle")
                    if place.chargedEnergyAvailable { MetricCard(title: t("Charged Energy", "充入能量"), value: String(format: "%.1f kWh", place.chargedEnergyKWh), systemImage: "battery.100percent") }
                    if place.parkingMinutesAvailable { MetricCard(title: t("Parking Time", "停车时长"), value: duration(place.parkingMinutes), systemImage: "clock") }
                    if place.parkingCostAvailable {
                        MetricCard(title: t("Parking Cost", "停车费用"), value: currencySymbol + String(format: "%.2f", place.parkingCost), systemImage: "creditcard")
                    }
                    if let distance = place.driveDistanceKm { MetricCard(title: t("Drive Distance", "行驶里程"), value: MateDroidUnitFormatter.formatDistance(distance, units: resolvedUnits), systemImage: "road.lanes") }
                    if place.chargeCost != nil || place.missingChargeCostCount != nil {
                        MetricCard(
                            title: t("Known Charge Cost", "已知充电费用"),
                            value: chargeCostText(place),
                            subtitle: chargeCostCoverageText(place),
                            systemImage: "creditcard"
                        )
                    }
                    if let loss = place.parkingRangeLossKm { MetricCard(title: t("Parking Range Loss", "停车续航损耗"), value: MateDroidUnitFormatter.formatDistance(loss, units: resolvedUnits), systemImage: "battery.25percent") }
                    if let longest = place.longestParkingMinutes { MetricCard(title: t("Longest Parking", "最长停车"), value: duration(longest), systemImage: "clock.badge") }
                }
                if let first = place.firstVisitedAt {
                    Text(t("First seen \(first.formatted(date: .abbreviated, time: .shortened))", "首次记录 \(first.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .navigationTitle(t("Place Detail", "地点详情"))
    }

    private func duration(_ minutes: Double) -> String {
        MateDroidUnitFormatter.formatDuration(minutes: Int(minutes.rounded()), language: appLanguage)
    }

    private func chargeCostText(_ place: PlaceInsight) -> String {
        guard let cost = place.chargeCost else { return "--" }
        let prefix = place.chargeCostIsComplete == false ? "≥" : ""
        return prefix + currencySymbol + String(format: "%.2f", cost)
    }

    private func chargeCostCoverageText(_ place: PlaceInsight) -> String? {
        guard let priced = place.pricedChargeCount else {
            return t("Price coverage unavailable", "价格覆盖未知")
        }
        return t("Price coverage: \(priced)/\(place.chargeCount)", "价格覆盖：\(priced)/\(place.chargeCount)")
    }

    private var resolvedUnits: UnitPreferences? {
        UnitPreferences(unitOfLength: viewModel.state.serverUnits?.unitOfLength, unitOfTemperature: viewModel.state.serverUnits?.unitOfTemperature).resolved(for: appDisplayUnitSystem)
    }

    private var currencySymbol: String {
        MateDroidCurrencyFormatter.symbol(for: viewModel.state.currencyCode)
    }

    private func roleTitle(_ role: String, confidence: String?) -> String {
        let title: String
        switch role {
        case "frequentPlace": title = t("Frequent place", "常去地点")
        case "chargingHub": title = t("Charging hub", "充电地点")
        case "home": title = t("Home", "家庭")
        case "work": title = t("Work", "工作地点")
        default: title = role
        }
        guard let confidence else { return title }
        let confidenceTitle = confidence == "high" ? t("high confidence", "高置信度") : confidence == "medium" ? t("medium confidence", "中置信度") : t("low confidence", "低置信度")
        return "\(title) · \(confidenceTitle)"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
