import Charts
import MapKit
import SwiftUI

public struct CommuteRoutesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CommuteRoutesViewModel
    private let carId: Int

    public init(carId: Int, viewModel: CommuteRoutesViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.routes.isEmpty {
                LoadingStateView(title: t("Loading commute routes", "正在加载通勤路线"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.routes.isEmpty {
                LoadingStateView(title: t("Commute routes unavailable", "通勤路线不可用"), message: error, systemImage: "arrow.triangle.swap")
            } else if viewModel.state.routes.isEmpty {
                ContentUnavailableView(t("No commute routes", "暂无通勤路线"), systemImage: "arrow.triangle.swap", description: Text(t("TeslaMateApi has not identified repeated routes yet.", "特斯拉数据接口尚未识别出重复路线。")))
            } else {
                routeList
            }
        }
        .navigationTitle(t("Commute Routes", "通勤路线"))
        .task { await viewModel.load(carId: carId) }
    }

    private var routeList: some View {
        List {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
            }
            summarySection
            Section(t("Routes", "路线")) {
                ForEach(Array(viewModel.state.routes.enumerated()), id: \.element.id) { index, route in
                    NavigationLink {
                        CommuteRouteDetailView(route: route, units: resolvedUnits, rank: index + 1)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("#\(index + 1)").font(.caption.bold()).foregroundStyle(.blue)
                                Text(routeTitle(route)).font(.body.weight(.semibold)).lineLimit(2)
                                Spacer()
                                Text(t("\(route.tripCount ?? 0) drives", "\(route.tripCount ?? 0) 次"))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            HStack {
                                Label(distance(route.totalDistanceKm), systemImage: "road.lanes")
                                Spacer()
                                Label(duration(route.averageDurationMinutes), systemImage: "clock")
                            }.font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            }
            Section {
                Text(t("Routes are server-side clusters of repeated drives. Blank TeslaMate addresses are shown as generic start and end points.", "路线由服务端对重复行程聚类生成；TeslaMate 地址为空时显示为通用起点和终点。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var summarySection: some View {
        Section(t("Summary", "汇总")) {
            HStack {
                summaryMetric(t("Routes", "路线"), viewModel.state.summary?.totalCommuteRoutes)
                summaryMetric(t("Drives", "行程"), viewModel.state.summary?.totalCommuteDrives)
                summaryMetric(t("Smart", "智能通勤"), viewModel.state.summary?.totalSmartCommutes)
            }
        }
    }

    private func summaryMetric(_ title: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "--").font(.title3.monospacedDigit().bold())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolvedUnits: UnitPreferences? {
        UnitPreferences(unitOfLength: viewModel.state.units?.unitOfLength).resolved(for: appDisplayUnitSystem)
    }
    private func routeTitle(_ route: CommuteRoute) -> String {
        "\(address(route.startAddress, fallback: t("Start", "起点"))) → \(address(route.endAddress, fallback: t("End", "终点")))"
    }
    private func address(_ value: String?, fallback: String) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }
        return value
    }
    private func distance(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDistance($0, units: resolvedUnits, decimals: 1) } ?? "--" }
    private func duration(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDuration(minutes: Int($0.rounded()), language: appLanguage) } ?? "--" }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}

private struct CommuteRouteDetailView: View {
    struct SpeedBand: Identifiable {
        let id: String
        let label: String
        let fraction: Double
    }

    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    let route: CommuteRoute
    let units: UnitPreferences?
    let rank: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(address(route.startAddress, fallback: t("Start", "起点"))) → \(address(route.endAddress, fallback: t("End", "终点")))")
                    .font(.title2.bold())
                routeMap
                Text(t("The API provides clustered start and end points only. The map line is a connector, not the driven road geometry.", "接口仅提供聚类后的起点和终点；地图连线只是位置连接，不代表实际行驶道路。"))
                    .font(.footnote).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    MetricCard(title: t("Drive Count", "行程次数"), value: route.tripCount.map(String.init) ?? "--", systemImage: "car")
                    MetricCard(title: t("Total Distance", "总里程"), value: distance(route.totalDistanceKm), systemImage: "road.lanes")
                    MetricCard(title: t("Average Time", "平均耗时"), value: duration(route.averageDurationMinutes), systemImage: "clock")
                    MetricCard(title: t("Time Range", "耗时范围"), value: durationRange, systemImage: "timer")
                    MetricCard(title: t("Regen Capture", "动能回收率"), value: percent(route.averageRegenCaptureRate), systemImage: "arrow.triangle.2.circlepath")
                    MetricCard(title: t("Hard Braking", "急刹次数"), value: route.totalHardBrakingCount.map(String.init) ?? "--", systemImage: "exclamationmark.triangle")
                    MetricCard(title: t("Hard Braking / 100 km", "每百公里急刹"), value: decimal(route.averageHardBrakingPer100Km), systemImage: "gauge.with.dots.needle.67percent")
                    MetricCard(title: t("Elevation", "累计海拔"), value: elevation, systemImage: "mountain.2")
                }
                speedChart
            }.padding(16)
        }
        .navigationTitle(t("Route #\(rank)", "路线 #\(rank)"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var routeMap: some View {
        if let start, let end {
            Map(initialPosition: .rect(MKMapRect(points: [MKMapPoint(start), MKMapPoint(end)]))) {
                Marker(t("Start", "起点"), coordinate: start).tint(.green)
                Marker(t("End", "终点"), coordinate: end).tint(.red)
                MapPolyline(coordinates: [start, end]).stroke(.blue, lineWidth: 4)
            }
            .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var speedChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Speed Distribution", "速度区间分布")).font(.headline)
            Chart(speedBands) { band in
                BarMark(x: .value(t("Speed", "速度"), band.label), y: .value(t("Share", "占比"), band.fraction * 100))
                    .foregroundStyle(.blue)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Double.self) { Text("\(Int(percent.rounded()))%") }
                    }
                }
            }
            .frame(height: 210)
            Text(t("Average share of sampled driving time in each speed band.", "各速度区间占已采样行驶时间的平均比例。"))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var speedBands: [SpeedBand] {
        [("0–20", route.averagePercentSpeed0To20), ("20–40", route.averagePercentSpeed20To40), ("40–80", route.averagePercentSpeed40To80), ("80–120", route.averagePercentSpeed80To120), ("120+", route.averagePercentSpeed120Plus)]
            .compactMap { label, value in value.map { SpeedBand(id: label, label: label, fraction: $0) } }
    }
    private var start: CLLocationCoordinate2D? { coordinate(route.startLatitude, route.startLongitude) }
    private var end: CLLocationCoordinate2D? { coordinate(route.endLatitude, route.endLongitude) }
    private func coordinate(_ latitude: Double?, _ longitude: Double?) -> CLLocationCoordinate2D? { GeoCoordinateValidator.location(latitude: latitude, longitude: longitude).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } }
    private var durationRange: String { "\(duration(route.minimumDurationMinutes)) – \(duration(route.maximumDurationMinutes))" }
    private var elevation: String {
        guard let gain = route.totalElevationGain, let loss = route.totalElevationLoss else { return "--" }
        return "+\(MateDroidUnitFormatter.formatElevation(Int(gain.rounded()), units: units)) / −\(MateDroidUnitFormatter.formatElevation(Int(loss.rounded()), units: units))"
    }
    private func address(_ value: String?, fallback: String) -> String { guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return fallback }; return value }
    private func distance(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDistance($0, units: units, decimals: 1) } ?? "--" }
    private func duration(_ value: Double?) -> String { value.map { MateDroidUnitFormatter.formatDuration(minutes: Int($0.rounded()), language: appLanguage) } ?? "--" }
    private func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "--" }
    private func decimal(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "--" }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}

private extension MKMapRect {
    init(points: [MKMapPoint]) {
        guard let first = points.first else { self = .world; return }
        self = points.dropFirst().reduce(MKMapRect(x: first.x, y: first.y, width: 0, height: 0)) { $0.union(MKMapRect(x: $1.x, y: $1.y, width: 0, height: 0)) }.insetBy(dx: -4_000, dy: -4_000)
    }
}
