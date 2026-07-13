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
        self.schemaVersion = schemaVersion
    }
}
