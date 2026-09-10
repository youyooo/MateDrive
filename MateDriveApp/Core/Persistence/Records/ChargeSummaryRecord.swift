import Foundation

public struct ChargeSummaryRecord: Equatable, Sendable {
    public let chargeId: Int
    public let carId: Int
    public let startDate: String
    public let endDate: String?
    public let chargeEnergyAdded: Double?
    public let cost: Double?
    public let durationMin: Int?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let chargeEnergyUsed: Double?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let odometerKm: Double?
    public let schemaVersion: Int

    public init(
        chargeId: Int,
        carId: Int,
        startDate: String,
        endDate: String?,
        chargeEnergyAdded: Double?,
        cost: Double?,
        durationMin: Int? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        chargeEnergyUsed: Double? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        odometerKm: Double? = nil,
        schemaVersion: Int = SchemaVersion.current
    ) {
        self.chargeId = chargeId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.chargeEnergyAdded = chargeEnergyAdded
        self.cost = cost
        self.durationMin = durationMin
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.chargeEnergyUsed = chargeEnergyUsed
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.startRatedRangeKm = startRatedRangeKm
        self.endRatedRangeKm = endRatedRangeKm
        self.odometerKm = odometerKm
        self.schemaVersion = schemaVersion
    }
}
