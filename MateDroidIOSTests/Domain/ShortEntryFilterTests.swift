import XCTest
@testable import MateDroidIOS

final class ShortEntryFilterTests: XCTestCase {
    func testDriveMustMeetAndroidDurationAndDistanceThresholds() {
        XCTAssertFalse(ShortEntryFilter.isSignificantDrive(distanceKilometers: 0.99, durationMinutes: 10))
        XCTAssertFalse(ShortEntryFilter.isSignificantDrive(distanceKilometers: 10, durationMinutes: 0))
        XCTAssertTrue(ShortEntryFilter.isSignificantDrive(distanceKilometers: 1.0, durationMinutes: 1))
    }

    func testChargeMustBeStrictlyGreaterThanAndroidEnergyThreshold() {
        XCTAssertFalse(ShortEntryFilter.isSignificantCharge(energyKilowattHours: 0.1))
        XCTAssertTrue(ShortEntryFilter.isSignificantCharge(energyKilowattHours: 0.11))
    }
}
