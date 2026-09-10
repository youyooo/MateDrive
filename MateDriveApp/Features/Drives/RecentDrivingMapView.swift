import MapKit
import SwiftUI

public struct RecentDrivingMapView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: RecentDrivingMapViewModel
    @State private var mode: ListMapViewMode = .map
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isChoosingHistoricalMoment = false
    @State private var historicalMoment = Date()
    @State private var pendingHistoricalMoment: Date?
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
                LoadingStateView(
                    title: t("Driving map unavailable", "行驶地图不可用"),
                    message: error,
                    systemImage: "map",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId) } }
                )
            } else if viewModel.state.routes.isEmpty {
                ContentUnavailableView(t("No driving coordinates", "暂无行驶坐标"), systemImage: "map", description: Text(t("TeslaMateApi returned no valid recent route points.", "特斯拉数据接口没有返回有效的近期路线坐标。")))
            } else if mode == .map {
                routeMap
            } else {
                routeList
            }
        }
        .navigationTitle(t("Recent Driving Map", "近期行驶地图"))
        .accessibilityIdentifier("recent_driving_map_view")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                actionsMenu
            }
        }
        .sheet(isPresented: $isChoosingHistoricalMoment, onDismiss: openPendingHistoricalMoment) {
            historicalMomentPicker
        }
        .task { await viewModel.load(carId: carId) }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                mode = mode.toggleDestination
            } label: {
                Label(
                    mode == .map ? t("Show list", "显示列表") : t("Show map", "显示地图"),
                    systemImage: mode.toolbarSystemImage
                )
            }

            Button {
                historicalMoment = suggestedHistoricalMoment
                pendingHistoricalMoment = nil
                isChoosingHistoricalMoment = true
            } label: {
                Label(t("Where Was I", "当时在哪"), systemImage: "clock.arrow.circlepath")
            }
            .accessibilityIdentifier("recent_map_where_was_i")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(t("Map actions", "地图操作"))
        .accessibilityIdentifier("recent_map_actions")
    }

    private var historicalMomentPicker: some View {
        NavigationStack {
            Form {
                DatePicker(
                    t("Date and time", "日期与时间"),
                    selection: $historicalMoment,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)

                Text(t(
                    "Choose a moment from your recorded TeslaMate history.",
                    "选择特斯拉数据记录范围内的一个时间。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(t("Where Was I", "当时在哪"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) {
                        pendingHistoricalMoment = nil
                        isChoosingHistoricalMoment = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("View", "查看")) {
                        pendingHistoricalMoment = historicalMoment
                        isChoosingHistoricalMoment = false
                    }
                    .accessibilityIdentifier("where_was_i_confirm")
                }
            }
            .accessibilityIdentifier("where_was_i_picker")
        }
        .presentationDetents([.medium, .large])
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

    private var suggestedHistoricalMoment: Date {
        viewModel.state.routes.compactMap(\.startedAt).max() ?? Date()
    }

    private func openPendingHistoricalMoment() {
        guard let pendingHistoricalMoment else { return }
        self.pendingHistoricalMoment = nil
        navigate(.whereWasI(
            carId: carId,
            timestamp: ISO8601DateFormatter().string(from: pendingHistoricalMoment),
            exteriorColor: exteriorColor
        ))
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
                                Text(route.maximumSpeed.map { MateDriveUnitFormatter.formatSpeed($0, units: units) } ?? "--").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
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
