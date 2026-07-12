import MapKit
import SwiftUI

public struct RecentDrivingMapView: View {
    private enum Mode: String, CaseIterable { case map, list }
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: RecentDrivingMapViewModel
    @State private var mode: Mode = .map
    @State private var mapPosition: MapCameraPosition = .automatic
    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: RecentDrivingMapViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.navigate = navigate
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.routes.isEmpty {
                LoadingStateView(title: t("Loading recent driving map", "正在加载近期行驶地图"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.routes.isEmpty {
                LoadingStateView(title: t("Driving map unavailable", "行驶地图不可用"), message: error, systemImage: "map")
            } else if viewModel.state.routes.isEmpty {
                ContentUnavailableView(t("No driving coordinates", "暂无行驶坐标"), systemImage: "map", description: Text(t("TeslaMateApi returned no valid recent route points.", "特斯拉数据接口没有返回有效的近期路线坐标。")))
            } else if mode == .map {
                routeMap
            } else {
                routeList
            }
        }
        .navigationTitle(t("Recent Driving Map", "近期行驶地图"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(t("View", "视图"), selection: $mode) {
                    Label(t("Map", "地图"), systemImage: "map").tag(Mode.map)
                    Label(t("List", "列表"), systemImage: "list.bullet").tag(Mode.list)
                }.pickerStyle(.segmented).frame(width: 112)
            }
        }
        .task { await viewModel.load(carId: carId) }
    }

    private var routeMap: some View {
        Map(position: $mapPosition) {
            ForEach(Array(viewModel.state.routes.enumerated()), id: \.element.id) { index, route in
                let coordinates = route.points.compactMap(coordinate)
                if coordinates.count > 1 {
                    MapPolyline(coordinates: coordinates)
                        .stroke(routeColor(index), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
                if let first = coordinates.first {
                    Annotation(t("Drive \(route.id)", "行程 \(route.id)"), coordinate: first) {
                        Button { open(route) } label: {
                            Image(systemName: "car.fill").font(.caption).foregroundStyle(.white)
                                .frame(width: 30, height: 30).background(routeColor(index), in: Circle())
                        }.accessibilityLabel(t("Open drive \(route.id)", "打开行程 \(route.id)"))
                    }
                }
            }
        }
        .mapControls { MapCompass(); MapScaleView() }
        .safeAreaInset(edge: .bottom) { mapSummary }
    }

    private var mapSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(t("\(viewModel.state.routes.count) recent drives · \(displayedPointCount) displayed points", "近期 \(viewModel.state.routes.count) 次行程 · 显示 \(displayedPointCount) 个坐标点"))
                .font(.subheadline.weight(.semibold))
            Text(coverageText).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(.regularMaterial)
    }

    private var routeList: some View {
        List {
            Section {
                Text(t("This is the recent coordinate window returned by TeslaMateApi, not guaranteed complete driving history.", "这里展示特斯拉数据接口返回的近期坐标窗口，不保证覆盖全部行驶历史。"))
                    .font(.footnote).foregroundStyle(.secondary)
                Text(coverageText).font(.footnote).foregroundStyle(.secondary)
            }
            Section(t("Recent Drives", "近期行程")) {
                ForEach(Array(viewModel.state.routes.enumerated()), id: \.element.id) { index, route in
                    Button { open(route) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(routeColor(index)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t("Drive \(route.id)", "行程 \(route.id)")).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(routeDate(route)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(t("\(route.points.count) points", "\(route.points.count) 个点")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(route.maximumSpeed.map { MateDroidUnitFormatter.formatSpeed($0, units: units) } ?? "--").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }.padding(.vertical, 4)
                    }.buttonStyle(.plain)
                }
            }
        }.refreshable { await viewModel.load(carId: carId) }
    }

    private var displayedPointCount: Int { viewModel.state.routes.reduce(0) { $0 + $1.points.count } }
    private var coverageText: String {
        let original = viewModel.state.originalPointCount.map(String.init) ?? "--"
        let simplified = viewModel.state.simplifiedPointCount.map(String.init) ?? "--"
        let invalid = viewModel.state.invalidPointCount
        return t("API points: \(original) original / \(simplified) simplified · \(invalid) invalid omitted", "接口坐标：原始 \(original) / 简化 \(simplified) · 已省略 \(invalid) 个无效点")
    }
    private var units: UnitPreferences? { UnitPreferences(unitOfLength: viewModel.state.units?.length, unitOfTemperature: viewModel.state.units?.temperature).resolved(for: appDisplayUnitSystem) }
    private func open(_ route: RecentDrivingRoute) { navigate(.driveDetail(carId: carId, driveId: route.id, exteriorColor: exteriorColor)) }
    private func coordinate(_ point: DrivingCoordinate) -> CLLocationCoordinate2D? { GeoCoordinateValidator.location(latitude: point.latitude, longitude: point.longitude).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    private func routeDate(_ route: RecentDrivingRoute) -> String { route.startedAt?.formatted(date: .abbreviated, time: .shortened) ?? t("Date unavailable", "日期不可用") }
    private func routeColor(_ index: Int) -> Color { [.blue, .green, .orange, .purple, .pink, .cyan][index % 6] }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}
