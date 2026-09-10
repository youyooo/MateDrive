import MapKit
import SwiftUI

struct ParkingActivityDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @Environment(\.dismiss) private var dismiss
    let activity: TeslaMateActivity
    let carId: Int
    let standbyDrainAPI: any ActivityAPIProviding
    let units: UnitPreferences?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let location = GeoCoordinateValidator.location(latitude: activity.startLatitude, longitude: activity.startLongitude) {
                    let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))) {
                        Marker(activity.startAddress ?? t("Parked", "停车"), coordinate: coordinate)
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(activity.startAddress ?? t("Location unavailable", "位置不可用")).font(.title3.weight(.semibold))
                if let location = GeoCoordinateValidator.location(latitude: activity.startLatitude, longitude: activity.startLongitude) {
                    NavigationLink {
                        StandbyDrainView(
                            carId: carId,
                            latitude: location.latitude,
                            longitude: location.longitude,
                            placeName: activity.startAddress,
                            preferredUnits: units,
                            viewModel: StandbyDrainViewModel(api: standbyDrainAPI)
                        )
                    } label: {
                        Label(t("View Standby Drain", "查看待机损耗"), systemImage: "moon.zzz")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                    MetricCard(title: t("Duration", "时长"), value: activity.durationMin.map { "\(Int($0.rounded())) " + t("min", "分钟") } ?? "--", systemImage: "clock")
                    MetricCard(title: "SOC", value: activity.soc.map { "\($0)%" } ?? "--", systemImage: "battery.50percent")
                    MetricCard(title: t("SOC Change", "电量变化"), value: activity.socDiff.map { ($0 > 0 ? "+" : "") + "\($0)%" } ?? "--", systemImage: "arrow.up.arrow.down")
                    MetricCard(title: t("Range Change", "续航变化"), value: activity.rangeDiffKm.map(signedDistance) ?? "--", systemImage: "gauge.with.dots.needle.33percent")
                    MetricCard(title: t("Energy Change", "能量变化"), value: activity.kwh.map { String(format: "%+.2f kWh", $0) } ?? "--", systemImage: "bolt")
                    MetricCard(title: t("Odometer", "里程表"), value: activity.odometerKm.map { MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0) } ?? "--", systemImage: "car")
                }
            }
            .padding(16)
        }
        .navigationTitle(t("Parking Detail", "停车详情"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("Done", "完成")) { dismiss() } } }
    }

    private func signedDistance(_ value: Double) -> String {
        let converted = MateDriveUnitFormatter.distanceValue(value, units: units)
        return String(format: "%+.1f %@", converted, MateDriveUnitFormatter.distanceUnit(units: units))
    }

    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}
