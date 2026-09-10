import Foundation

public struct TripDrive: Equatable, Identifiable, Sendable {
    public let id: Int
    public let startDate: String
    public let endDate: String
    public let distance: Double
    public let durationMin: Int
    public let energyConsumed: Double?
    public let speedMax: Double?
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
        speedMax: Double? = nil,
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
    public let energyAdded: Double?
    public let cost: Double?
    public let durationMin: Int
    public let address: String?

    public init(
        id: Int,
        startDate: String,
        endDate: String,
        energyAdded: Double?,
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
    public let totalEnergyConsumed: Double?
    public let drivingEnergyKnownCount: Int
    public let missingDrivingEnergyCount: Int
    public let drivingEnergyIsComplete: Bool
    public let totalEnergyCharged: Double?
    public let chargedEnergyKnownCount: Int
    public let missingChargedEnergyCount: Int
    public let chargedEnergyIsComplete: Bool
    public let totalChargeCost: Double?
    public let pricedChargeCount: Int
    public let missingChargeCostCount: Int
    public let chargeCostIsComplete: Bool
    public let averageEfficiency: Double?
    public let maxSpeed: Double?
    public let startAddress: String?
    public let endAddress: String?
    public let startDate: String
    public let endDate: String
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let name: String?
}

public enum JourneySummaryBuilder {
    public static func makeSummary(
        drives: [TripDrive],
        charges: [TripCharge],
        name: String? = nil
    ) -> DetectedTrip? {
        let orderedDrives = drives.sorted { lhs, rhs in
            let left = DomainDateParser.date(from: lhs.startDate) ?? .distantFuture
            let right = DomainDateParser.date(from: rhs.startDate) ?? .distantFuture
            return left < right
        }
        guard let firstDrive = orderedDrives.first, let lastDrive = orderedDrives.last else {
            return nil
        }

        let driveTotals = orderedDrives.reduce(into: DriveTotals()) { result, drive in
            result.include(drive)
        }
        let chargeTotals = charges.reduce(into: ChargeTotals()) { result, charge in
            result.include(charge)
        }
        let elapsedMinutes = elapsedMinutes(
            start: firstDrive.startDate,
            end: lastDrive.endDate,
            fallback: driveTotals.minutes
        )
        let averageEfficiency = driveTotals.completeEnergy.flatMap { energy in
            driveTotals.distance > 0 ? energy * 1_000 / driveTotals.distance : nil
        }

        return DetectedTrip(
            drives: orderedDrives,
            charges: charges,
            totalDistance: driveTotals.distance,
            totalDrivingDurationMin: driveTotals.minutes,
            totalDurationMin: elapsedMinutes,
            totalEnergyConsumed: driveTotals.energy.value,
            drivingEnergyKnownCount: driveTotals.energy.known,
            missingDrivingEnergyCount: driveTotals.energy.missing,
            drivingEnergyIsComplete: driveTotals.energy.isComplete,
            totalEnergyCharged: chargeTotals.energy.value,
            chargedEnergyKnownCount: chargeTotals.energy.known,
            missingChargedEnergyCount: chargeTotals.energy.missing,
            chargedEnergyIsComplete: chargeTotals.energy.isComplete,
            totalChargeCost: chargeTotals.cost.value,
            pricedChargeCount: chargeTotals.cost.known,
            missingChargeCostCount: chargeTotals.cost.missing,
            chargeCostIsComplete: chargeTotals.cost.isComplete,
            averageEfficiency: averageEfficiency,
            maxSpeed: driveTotals.maximumSpeed,
            startAddress: firstDrive.startAddress,
            endAddress: lastDrive.endAddress,
            startDate: firstDrive.startDate,
            endDate: lastDrive.endDate,
            startBatteryLevel: firstDrive.startBatteryLevel,
            endBatteryLevel: lastDrive.endBatteryLevel,
            name: name
        )
    }

    private static func elapsedMinutes(start: String, end: String, fallback: Int) -> Int {
        guard
            let startDate = DomainDateParser.date(from: start),
            let endDate = DomainDateParser.date(from: end),
            endDate >= startDate
        else {
            return fallback
        }
        return Int(endDate.timeIntervalSince(startDate) / 60)
    }

    private struct OptionalTotal {
        private(set) var sum = 0.0
        private(set) var known = 0
        private(set) var missing = 0

        mutating func include(_ value: Double?) {
            guard let value, value.isFinite else {
                missing += 1
                return
            }
            known += 1
            sum += value
        }

        var value: Double? { known == 0 ? nil : sum }
        var isComplete: Bool { missing == 0 }
    }

    private struct DriveTotals {
        var distance = 0.0
        var minutes = 0
        var energy = OptionalTotal()
        var maximumSpeed: Double?

        mutating func include(_ drive: TripDrive) {
            distance += max(drive.distance, 0)
            minutes += max(drive.durationMin, 0)
            energy.include(drive.energyConsumed)
            if let speed = drive.speedMax, speed.isFinite {
                maximumSpeed = max(maximumSpeed ?? speed, speed)
            }
        }

        var completeEnergy: Double? { energy.isComplete ? energy.value : nil }
    }

    private struct ChargeTotals {
        var energy = OptionalTotal()
        var cost = OptionalTotal()

        mutating func include(_ charge: TripCharge) {
            energy.include(charge.energyAdded)
            cost.include(charge.cost)
        }
    }
}
