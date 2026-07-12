import Foundation

public enum RouteCoverage {
    public static let allAndroidRoutes: [AppRoute] = [
        .settings,
        .dashboard,
        .palettePreview,
        .charges(carId: 1, exteriorColor: "PPSW"),
        .chargeDetail(carId: 1, chargeId: 2, exteriorColor: "PPSW"),
        .compareCharges(carId: 1, baseChargeId: 2, exteriorColor: "PPSW"),
        .currentCharge(carId: 1, exteriorColor: "PPSW"),
        .activities(carId: 1, exteriorColor: "PPSW"),
        .places(carId: 1),
        .achievements(carId: 1, exteriorColor: "PPSW"),
        .drives(carId: 1, exteriorColor: "PPSW"),
        .recentDrivingMap(carId: 1, exteriorColor: "PPSW"),
        .driveDetail(carId: 1, driveId: 3, exteriorColor: "PPSW"),
        .compareDrives(carId: 1, baseDriveId: 3, exteriorColor: "PPSW"),
        .battery(carId: 1, efficiency: 140.5, exteriorColor: "PPSW"),
        .mileage(carId: 1, exteriorColor: "PPSW", targetDay: "2026-07-01"),
        .updates(carId: 1, exteriorColor: "PPSW"),
        .stats(carId: 1, exteriorColor: "PPSW"),
        .drivingRecords(carId: 1, exteriorColor: "PPSW"),
        .driveInsights(carId: 1, exteriorColor: "PPSW"),
        .environmentHistory(carId: 1),
        .topDrainLocations(carId: 1),
        .commuteRoutes(carId: 1),
        .countriesVisited(carId: 1, exteriorColor: "PPSW", year: 2026),
        .regionsVisited(carId: 1, countryCode: "IT", countryName: "Italy", exteriorColor: "PPSW", year: 2026),
        .whereWasI(carId: 1, timestamp: "2026-07-01T12:00:00Z", exteriorColor: "PPSW"),
        .trips(carId: 1, exteriorColor: "PPSW"),
        .createTrip(carId: 1, exteriorColor: "PPSW"),
        .tripDetail(carId: 1, tripStartDate: "2026-07-01T12:00:00Z", exteriorColor: "PPSW"),
        .sentryHistory(carId: 1, exteriorColor: "PPSW")
    ]

    public static func hasImplementedDestination(_ route: AppRoute) -> Bool {
        switch route {
        case .settings,
             .dashboard,
             .palettePreview,
             .charges,
             .chargeDetail,
             .compareCharges,
             .currentCharge,
             .activities,
             .places,
             .achievements,
             .drives,
             .recentDrivingMap,
             .driveDetail,
             .driveMetricDetail,
             .compareDrives,
             .battery,
             .mileage,
             .updates,
             .stats,
             .costReview,
             .drivingRecords,
             .driveInsights,
             .environmentHistory,
             .topDrainLocations,
             .commuteRoutes,
             .countriesVisited,
             .regionsVisited,
             .whereWasI,
             .trips,
             .createTrip,
             .tripDetail,
             .sentryHistory:
            return true
        }
    }
}
