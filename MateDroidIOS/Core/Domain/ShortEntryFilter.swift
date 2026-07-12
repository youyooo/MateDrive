import Foundation

public enum ShortEntryFilter {
    public static let minimumDriveDurationMinutes = 1
    public static let minimumDriveDistanceKilometers = 1.0
    public static let minimumChargeEnergyKilowattHours = 0.1

    public static func isSignificantDrive(distanceKilometers: Double, durationMinutes: Int) -> Bool {
        durationMinutes >= minimumDriveDurationMinutes &&
            distanceKilometers >= minimumDriveDistanceKilometers
    }

    public static func isSignificantCharge(energyKilowattHours: Double) -> Bool {
        energyKilowattHours > minimumChargeEnergyKilowattHours
    }
}
