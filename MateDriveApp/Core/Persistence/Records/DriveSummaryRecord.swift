import Foundation

public struct DriveSummaryRecord: Equatable, Sendable {
    public let driveId: Int
    public let carId: Int
    public let startDate: String
    public let endDate: String
    public let distance: Double?
    public let durationMin: Int?
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?
    public let energySource: String?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let startAddress: String?
    public let endAddress: String?
    public let speedAvg: Double?
    public let outsideTempAvg: Double?
    public let routeFingerprintJSON: String?
    public let climateOnFraction: Double?
    public let elevationGainM: Double?
    public let elevationLossM: Double?
    public let schemaVersion: Int

    public init(
        driveId: Int,
        carId: Int,
        startDate: String,
        endDate: String,
        distance: Double?,
        durationMin: Int?,
        energyConsumedNet: Double? = nil,
        consumptionNet: Double? = nil,
        energySource: String? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        startAddress: String? = nil,
        endAddress: String? = nil,
        speedAvg: Double? = nil,
        outsideTempAvg: Double? = nil,
        routeFingerprintJSON: String? = nil,
        climateOnFraction: Double? = nil,
        elevationGainM: Double? = nil,
        elevationLossM: Double? = nil,
        schemaVersion: Int = SchemaVersion.current
    ) {
        self.driveId = driveId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.durationMin = durationMin
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
        self.energySource = energySource
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.startRatedRangeKm = startRatedRangeKm
        self.endRatedRangeKm = endRatedRangeKm
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.speedAvg = speedAvg
        self.outsideTempAvg = outsideTempAvg
        self.routeFingerprintJSON = routeFingerprintJSON
        self.climateOnFraction = climateOnFraction
        self.elevationGainM = elevationGainM
        self.elevationLossM = elevationLossM
        self.schemaVersion = schemaVersion
    }
}
