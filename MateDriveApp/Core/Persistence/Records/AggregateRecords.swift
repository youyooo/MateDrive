import Foundation

public struct DriveDetailAggregateRecord: Equatable, Sendable {
    public let driveId: Int
    public let carId: Int
    public let payloadJSON: String
    public let schemaVersion: Int
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?
    public let energySource: String?

    public init(
        driveId: Int,
        carId: Int,
        payloadJSON: String,
        schemaVersion: Int,
        energyConsumedNet: Double? = nil,
        consumptionNet: Double? = nil,
        energySource: String? = nil
    ) {
        self.driveId = driveId
        self.carId = carId
        self.payloadJSON = payloadJSON
        self.schemaVersion = schemaVersion
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
        self.energySource = energySource
    }
}

public struct ChargeDetailAggregateRecord: Equatable, Sendable {
    public let chargeId: Int
    public let carId: Int
    public let payloadJSON: String
    public let schemaVersion: Int
    public let chargeEnergyAdded: Double?
    public let chargeEnergyUsed: Double?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let odometerKm: Double?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        chargeId: Int,
        carId: Int,
        payloadJSON: String,
        schemaVersion: Int,
        chargeEnergyAdded: Double? = nil,
        chargeEnergyUsed: Double? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        odometerKm: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.chargeId = chargeId
        self.carId = carId
        self.payloadJSON = payloadJSON
        self.schemaVersion = schemaVersion
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargeEnergyUsed = chargeEnergyUsed
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.startRatedRangeKm = startRatedRangeKm
        self.endRatedRangeKm = endRatedRangeKm
        self.odometerKm = odometerKm
        self.latitude = latitude
        self.longitude = longitude
    }
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
