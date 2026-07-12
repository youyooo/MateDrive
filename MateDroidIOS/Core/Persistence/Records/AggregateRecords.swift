import Foundation

public struct DriveDetailAggregateRecord: Equatable, Sendable {
    public let driveId: Int
    public let carId: Int
    public let payloadJSON: String
    public let schemaVersion: Int
}

public struct ChargeDetailAggregateRecord: Equatable, Sendable {
    public let chargeId: Int
    public let carId: Int
    public let payloadJSON: String
    public let schemaVersion: Int
}

public struct ChargeDetailPricingAggregate: Equatable, Sendable {
    public let chargeId: Int
    public let isDc: Bool?
    public let energySamples: [ChargePricingEnergySample]
    public let chargerIdentity: ChargePricingChargerIdentity?

    public init(
        chargeId: Int,
        isDc: Bool? = nil,
        energySamples: [ChargePricingEnergySample] = [],
        chargerIdentity: ChargePricingChargerIdentity? = nil
    ) {
        self.chargeId = chargeId
        self.isDc = isDc
        self.energySamples = energySamples
        self.chargerIdentity = chargerIdentity
    }
}
