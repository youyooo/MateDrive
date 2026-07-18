import Foundation

public enum ActivityMetricQuality: String, Codable, Equatable, Sendable {
    case complete, partial, estimated, unavailable
}

public struct ParkingIntervalInput: Equatable, Sendable {
    public let parking: TeslaMateActivity
    public let charges: [TeslaMateActivity]
    public let sleepIntervals: [SleepInterval]
    public let previousDrive: TeslaMateActivity?
    public let nextDrive: TeslaMateActivity?

    public init(
        parking: TeslaMateActivity,
        charges: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        previousDrive: TeslaMateActivity? = nil,
        nextDrive: TeslaMateActivity? = nil
    ) {
        self.parking = parking
        self.charges = charges
        self.sleepIntervals = sleepIntervals
        self.previousDrive = previousDrive
        self.nextDrive = nextDrive
    }
}

public struct ParkingIntervalMetrics: Codable, Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let startBatteryPercent: Int?
    public let endBatteryPercent: Int?
    public let netBatteryChangePercent: Int?
    public let chargeGainPercent: Int?
    public let standbyBatteryChangePercent: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let ratedRangeChangeKm: Double?
    public let vehicleReportedChargeEnergyKWh: Double?
    public let sleepDuration: TimeInterval
    public let awakeDuration: TimeInterval
    public let wakeCount: Int
    public let quality: ActivityMetricQuality
    public let missingReasonCodes: [String]
}
