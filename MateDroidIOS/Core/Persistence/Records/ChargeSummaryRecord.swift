import Foundation

public struct ChargeSummaryRecord: Equatable, Sendable {
    public let chargeId: Int
    public let carId: Int
    public let startDate: String
    public let endDate: String?
    public let chargeEnergyAdded: Double?
    public let cost: Double?
    public let schemaVersion: Int

    public init(chargeId: Int, carId: Int, startDate: String, endDate: String?, chargeEnergyAdded: Double?, cost: Double?, schemaVersion: Int = SchemaVersion.current) {
        self.chargeId = chargeId
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
        self.chargeEnergyAdded = chargeEnergyAdded
        self.cost = cost
        self.schemaVersion = schemaVersion
    }
}
