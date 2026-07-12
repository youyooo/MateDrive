import Foundation

public struct ChargeCostOverrideRecord: Equatable, Sendable {
    public let chargeId: Int
    public let carId: Int
    public let cost: Double
    public let updatedAt: String

    public init(chargeId: Int, carId: Int, cost: Double, updatedAt: String) {
        self.chargeId = chargeId
        self.carId = carId
        self.cost = cost
        self.updatedAt = updatedAt
    }
}
