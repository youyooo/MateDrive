import MapKit
import SwiftUI

public struct TopDrainLocationsView: View {
    private enum Mode: String, CaseIterable { case list, map }
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: TopDrainLocationsViewModel
    @State private var mode: Mode = .list
    @State private var selectedLocation: TopDrainLocation?
    @State private var mapPosition: MapCameraPosition = .automatic
    private let carId: Int
    private let standbyDrainAPI: any ActivityAPIProviding

    public init(carId: Int, viewModel: TopDrainLocationsViewModel, standbyDrainAPI: any ActivityAPIProviding) {
        self.carId = carId
        self.standbyDrainAPI = standbyDrainAPI
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.locations.isEmpty {
                LoadingStateView(title: t("Loading standby hotspots", "正在加载待机耗电热点"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.locations.isEmpty {
                LoadingStateView(title: t("Standby hotspots unavailable", "待机耗电热点不可用"), message: error, systemImage: "moon.zzz")
            } else if viewModel.state.locations.isEmpty {
                ContentUnavailableView(t("No standby hotspots", "暂无待机耗电热点"), systemImage: "moon.zzz", description: Text(t("TeslaMateApi returned no aggregated parking drain locations.", "特斯拉数据接口没有返回聚合停车耗电地点。")))
            } else if mode == .map {
                locationMap
            } else {
                locationList
            }
        }
        .navigationTitle(t("Standby Hotspots", "待机耗电热点"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker(t("View", "视图"), selection: $mode) {
                    Label(t("List", "列表"), systemImage: "list.bullet").tag(Mode.list)
                    Label(t("Map", "地图"), systemImage: "map").tag(Mode.map)
                }
                .pickerStyle(.segmented).frame(width: 112)
            }
        }
        .task { await viewModel.load(carId: carId) }
        .sheet(item: $selectedLocation) { location in
            NavigationStack { detail(location) }.environment(\.appLanguage, appLanguage)
        }
    }

    private var locationList: some View {
        List {
            refreshWarning
            explanation
            ForEach(Array(viewModel.state.locations.enumerated()), id: \.element.id) { index, location in
                Button { selectedLocation = location } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white).frame(width: 28, height: 28).background(.orange, in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(locationName(location, index: index)).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                            Text(t("\(location.parkingCount ?? 0) parks · \(duration(location.totalDurationMin))", "\(location.parkingCount ?? 0) 次停车 · \(duration(location.totalDurationMin))"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(distance(location.totalRangeLossKm)).font(.body.monospacedDigit().weight(.semibold))
                            Text(percent(location.averageDrainPercent24H)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var locationMap: some View {
        VStack(spacing: 0) {
            refreshWarning.padding(.horizontal, 12).padding(.top, 8)
            explanation.padding(12)
            Map(position: $mapPosition) {
                ForEach(Array(viewModel.state.locations.enumerated()), id: \.element.id) { index, location in
                    if let coordinate = coordinate(location) {
                        Annotation(locationName(location, index: index), coordinate: coordinate) {
                            Button { selectedLocation = location } label: {
                                ZStack {
                                    Circle().fill(.orange).frame(width: 38, height: 38)
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }.accessibilityLabel(locationName(location, index: index))
                        }
                    }
                }
            }.mapControls { MapCompass(); MapScaleView() }
        }
    }

    private var explanation: some View {
        Label(t("Aggregated from TeslaMate parking records. Range loss is not battery degradation.", "根据 TeslaMate 停车记录聚合；续航损耗不代表电池衰减。"), systemImage: "info.circle")
            .font(.footnote).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var refreshWarning: some View {
        if let error = viewModel.state.errorMessage {
            Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    private func detail(_ location: TopDrainLocation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(locationName(location, index: nil)).font(.title2.bold())
                if let coordinate = coordinate(location) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))) { Marker(locationName(location, index: nil), coordinate: coordinate) }
                        .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 8))
                    NavigationLink {
                        StandbyDrainView(carId: carId, latitude: coordinate.latitude, longitude: coordinate.longitude, placeName: locationName(location, index: nil), preferredUnits: effectiveUnits, viewModel: StandbyDrainViewModel(api: standbyDrainAPI))
                    } label: { Label(t("Analyze This Location", "分析此地点"), systemImage: "chart.xyaxis.line").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    MetricCard(title: t("Range Loss", "续航损耗"), value: distance(location.totalRangeLossKm), systemImage: "battery.25percent")
                    MetricCard(title: t("24h Battery Change", "24 小时电量变化"), value: percent(location.averageDrainPercent24H), systemImage: "percent")
                    MetricCard(title: t("Drain Rate", "损耗速率"), value: rate(location.averageDrainRateKmH), systemImage: "gauge.with.dots.needle.33percent")
                    MetricCard(title: t("Parking Events", "停车次数"), value: location.parkingCount.map(String.init) ?? "--", systemImage: "parkingsign.circle")
                    MetricCard(title: t("Parking Time", "停车时长"), value: duration(location.totalDurationMin), systemImage: "clock")
                }
            }.padding(16)
        }.navigationTitle(t("Hotspot Detail", "热点详情"))
    }

    private var effectiveUnits: UnitPreferences? { UnitPreferences(unitOfLength: viewModel.state.units?.unitOfLength, unitOfTemperature: viewModel.state.units?.unitOfTemperature, unitOfPressure: viewModel.state.units?.unitOfPressure).resolved(for: appDisplayUnitSystem) }
    private func coordinate(_ value: TopDrainLocation) -> CLLocationCoordinate2D? { GeoCoordinateValidator.location(latitude: value.latitude, longitude: value.longitude).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    private func locationName(_ value: TopDrainLocation, index: Int?) -> String { if let address = value.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty { return address }; if let index { return t("Hotspot \(index + 1)", "热点 \(index + 1)") }; return t("Standby Hotspot", "待机耗电热点") }
    private func distance(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDistance($0, units: effectiveUnits, decimals: 1) } ?? "--" }
    private func rate(_ value: Double?) -> String { guard let value else { return "--" }; return String(format: "%.2f %@/h", MateDroidUnitFormatter.distanceValue(value, units: effectiveUnits), MateDroidUnitFormatter.distanceUnit(units: effectiveUnits)) }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%+.1f%%/24h", $0) } ?? "--" }
    private func duration(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDuration(minutes: Int($0.rounded()), language: appLanguage) } ?? "--" }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}
