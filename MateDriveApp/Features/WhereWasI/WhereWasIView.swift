import MapKit
import SwiftUI

public struct WhereWasIView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: WhereWasIViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let timestamp: String
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, timestamp: String, exteriorColor: String?, viewModel: WhereWasIViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.timestamp = timestamp
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, !hasVisibleContent {
                LoadingStateView(title: t("Finding location", "正在定位"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, !hasVisibleContent {
                LoadingStateView(
                    title: t("Unable to find location", "无法查询位置"),
                    message: UserFacingErrorLocalizer.localized(error, language: appLanguage),
                    systemImage: "exclamationmark.triangle",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId, timestamp: timestamp) } }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(error, language: appLanguage),
                                systemImage: "wifi.exclamationmark"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("where_was_i_refresh_warning")
                        }
                        hero
                        map
                        metrics
                        links
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.load(carId: carId, timestamp: timestamp)
                }
            }
        }
        .navigationTitle(t("Where Was I", "当时在哪"))
        .accessibilityIdentifier("where_was_i_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId, timestamp: timestamp)
        }
    }

    private var hasVisibleContent: Bool {
        viewModel.state.carState != nil
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(carStateTitle(viewModel.state.carState))
                .font(.largeTitle.weight(.bold))
            Text(viewModel.state.targetDateTime ?? timestamp)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let geofence = viewModel.state.geofenceName {
                Text(geofence)
                    .font(.body.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var map: some View {
        if let location = GeoCoordinateValidator.location(latitude: viewModel.state.latitude, longitude: viewModel.state.longitude) {
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            MapGestureGate { isMapInteractionEnabled in
                Map(
                    initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))),
                    interactionModes: isMapInteractionEnabled ? .all : []
                ) {
                    Marker(t("Location", "位置"), coordinate: coordinate)
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var metrics: some View {
        let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            if let distance = viewModel.state.driveDistance {
                MetricCard(title: t("Drive Distance", "行驶距离"), value: MateDriveUnitFormatter.formatDistance(distance, units: units), systemImage: "road.lanes")
            }
            if let speed = viewModel.state.speed {
                MetricCard(title: t("Speed", "速度"), value: MateDriveUnitFormatter.formatSpeed(Double(speed), units: units), systemImage: "speedometer")
            }
            if let battery = viewModel.state.batteryLevel {
                MetricCard(title: t("Battery", "电量"), value: "\(battery)%", systemImage: "battery.75percent")
            }
            if let power = viewModel.state.chargerPower {
                MetricCard(title: t("Power", "功率"), value: "\(power) kW", systemImage: "bolt.fill")
            }
            if let temp = viewModel.state.outsideTemp {
                MetricCard(title: t("Outside", "车外"), value: MateDriveUnitFormatter.formatTemperature(temp, units: units), systemImage: "thermometer.medium")
            }
            if let minutes = viewModel.state.parkedDurationMinutes {
                MetricCard(title: t("Parked", "停放"), value: durationText(minutes), systemImage: "parkingsign.circle")
            }
        }
    }

    private var links: some View {
        VStack(spacing: 10) {
            if let driveId = viewModel.state.driveId ?? viewModel.state.lastActivityDriveId {
                Button {
                    navigate(.driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor))
                } label: {
                    Label(t("View Drive", "查看行程"), systemImage: "road.lanes")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
            if let chargeId = viewModel.state.chargeId ?? viewModel.state.lastActivityChargeId {
                Button {
                    navigate(.chargeDetail(carId: carId, chargeId: chargeId, exteriorColor: exteriorColor))
                } label: {
                    Label(t("View Charge", "查看充电"), systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
                }
                .buttonStyle(.plain)
            }
            Button {
                navigate(.countriesVisited(carId: carId, exteriorColor: exteriorColor, year: nil))
            } label: {
                Label(t("Countries Visited", "到访国家"), systemImage: "globe")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            }
            .buttonStyle(.plain)
        }
    }

    private func durationText(_ value: Int) -> String {
        MateDriveUnitFormatter.formatDuration(minutes: value, language: appLanguage)
    }

    private func carStateTitle(_ state: CarActivityState?) -> String {
        switch state {
        case .driving:
            return t("Driving", "行驶中")
        case .charging:
            return t("Charging", "充电中")
        case .parked:
            return t("Parked", "已停放")
        case nil:
            return t("Unknown", "未知")
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
