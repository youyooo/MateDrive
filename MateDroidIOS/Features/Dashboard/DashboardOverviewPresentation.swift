import Foundation

struct DashboardOverviewItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    let route: AppRoute?
}

struct DashboardOverviewPresentation: Equatable, Sendable {
    let items: [DashboardOverviewItem]

    init(state: DashboardState, units: UnitPreferences?, language: AppLanguage) {
        let carId = state.selectedCarId
        items = [
            DashboardOverviewItem(
                id: "odometer",
                title: AppText.localized("Odometer", "里程表", language: language),
                value: state.odometer.map {
                    MateDroidUnitFormatter.formatDistance($0, units: units, decimals: 0)
                } ?? "--",
                systemImage: "gauge.with.dots.needle.50percent",
                route: carId.map {
                    .mileage(carId: $0, exteriorColor: state.exteriorColor, targetDay: nil)
                }
            ),
            DashboardOverviewItem(
                id: "drives",
                title: AppText.localized("Drives", "行程", language: language),
                value: state.totalDrives.map(String.init) ?? "--",
                systemImage: "road.lanes",
                route: carId.map {
                    .activities(carId: $0, exteriorColor: state.exteriorColor)
                }
            ),
            DashboardOverviewItem(
                id: "charges",
                title: AppText.localized("Charges", "充电", language: language),
                value: state.totalCharges.map(String.init) ?? "--",
                systemImage: "bolt.fill",
                route: carId.map {
                    .charges(carId: $0, exteriorColor: state.exteriorColor)
                }
            )
        ]
    }
}
