import Foundation

public struct TripDrive: Equatable, Identifiable, Sendable {
    public let id: Int
    public let startDate: String
    public let endDate: String
    public let distance: Double
    public let durationMin: Int
    public let energyConsumed: Double?
    public let speedMax: Double
    public let startAddress: String?
    public let endAddress: String?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?

    public init(
        id: Int,
        startDate: String,
        endDate: String,
        distance: Double,
        durationMin: Int,
        energyConsumed: Double? = nil,
        speedMax: Double = 0,
        startAddress: String? = nil,
        endAddress: String? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.durationMin = durationMin
        self.energyConsumed = energyConsumed
        self.speedMax = speedMax
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
    }
}

public struct TripCharge: Equatable, Identifiable, Sendable {
    public let id: Int
    public let startDate: String
    public let endDate: String
    public let energyAdded: Double
    public let cost: Double?
    public let durationMin: Int
    public let address: String?

    public init(
        id: Int,
        startDate: String,
        endDate: String,
        energyAdded: Double,
        cost: Double? = nil,
        durationMin: Int? = nil,
        address: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.energyAdded = energyAdded
        self.cost = cost
        self.durationMin = durationMin ?? Self.durationMinutes(startDate: startDate, endDate: endDate)
        self.address = address
    }

    private static func durationMinutes(startDate: String, endDate: String) -> Int {
        guard
            let start = DomainDateParser.date(from: startDate),
            let end = DomainDateParser.date(from: endDate)
        else {
            return 0
        }
        return max(Int(end.timeIntervalSince(start) / 60.0), 0)
    }
}

public struct DetectedTrip: Equatable, Sendable {
    public let drives: [TripDrive]
    public let charges: [TripCharge]
    public let totalDistance: Double
    public let totalDrivingDurationMin: Int
    public let totalDurationMin: Int
    public let totalEnergyConsumed: Double
    public let totalEnergyCharged: Double
    public let totalChargeCost: Double?
    public let pricedChargeCount: Int
    public let missingChargeCostCount: Int
    public let chargeCostIsComplete: Bool
    public let averageEfficiency: Double?
    public let maxSpeed: Double
    public let startAddress: String?
    public let endAddress: String?
    public let startDate: String
    public let endDate: String
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let name: String?
}

public enum TripAggregator {
    public static func buildTrip(
        drives: [TripDrive],
        charges: [TripCharge],
        name: String? = nil
    ) -> DetectedTrip? {
        guard let firstDrive = drives.first, let lastDrive = drives.last else {
            return nil
        }

        let totalDistance = drives.reduce(0) { $0 + $1.distance }
        let totalDrivingMin = drives.reduce(0) { $0 + $1.durationMin }
        let firstStart = DomainDateParser.date(from: firstDrive.startDate)
        let lastEnd = DomainDateParser.date(from: lastDrive.endDate)
        let totalMin: Int
        if let firstStart, let lastEnd {
            totalMin = Int(lastEnd.timeIntervalSince(firstStart) / 60.0)
        } else {
            totalMin = totalDrivingMin
        }

        let totalEnergyConsumed = drives.compactMap(\.energyConsumed).reduce(0, +)
        let totalEnergyCharged = charges.reduce(0) { $0 + $1.energyAdded }
        let costs = charges.compactMap(\.cost)
        let totalCost = costs.isEmpty ? nil : costs.reduce(0, +)
        let missingChargeCostCount = charges.count - costs.count
        let maxSpeed = drives.map(\.speedMax).max() ?? 0
        let averageEfficiency = totalDistance > 0 ? (totalEnergyConsumed * 1000.0) / totalDistance : nil

        return DetectedTrip(
            drives: drives,
            charges: charges,
            totalDistance: totalDistance,
            totalDrivingDurationMin: totalDrivingMin,
            totalDurationMin: totalMin,
            totalEnergyConsumed: totalEnergyConsumed,
            totalEnergyCharged: totalEnergyCharged,
            totalChargeCost: totalCost,
            pricedChargeCount: costs.count,
            missingChargeCostCount: missingChargeCostCount,
            chargeCostIsComplete: missingChargeCostCount == 0,
            averageEfficiency: averageEfficiency,
            maxSpeed: maxSpeed,
            startAddress: firstDrive.startAddress,
            endAddress: lastDrive.endAddress,
            startDate: firstDrive.startDate,
            endDate: lastDrive.endDate,
            startBatteryLevel: firstDrive.startBatteryLevel,
            endBatteryLevel: lastDrive.endBatteryLevel,
            name: name
        )
    }
}
