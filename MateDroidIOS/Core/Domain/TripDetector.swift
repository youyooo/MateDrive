import Foundation

public enum TripDetector {
    private static let microDriveThresholdKm = 1.0
    private static let minimumTripDistanceKm = 300.0
    private static let maxDriveToChargeGapMin = 15
    private static let maxChargeToDriveGapMin = 180
    private static let maxDriveToDriveGapMin = 30

    private enum Event {
        case drive(TripDrive)
        case charge(TripCharge)

        var startDate: String {
            switch self {
            case let .drive(drive): drive.startDate
            case let .charge(charge): charge.startDate
            }
        }

        var endDate: String {
            switch self {
            case let .drive(drive): drive.endDate
            case let .charge(charge): charge.endDate
            }
        }

        var isDrive: Bool {
            if case .drive = self { return true }
            return false
        }
    }

    public static func detectTrips(drives: [TripDrive], dcCharges: [TripCharge]) -> [DetectedTrip] {
        let realDrives = drives.filter { $0.distance >= microDriveThresholdKm }
        var events = realDrives.map(Event.drive) + dcCharges.map(Event.charge)
        events.sort { lhs, rhs in
            (DomainDateParser.date(from: lhs.startDate) ?? .distantPast) <
                (DomainDateParser.date(from: rhs.startDate) ?? .distantPast)
        }

        var trips: [DetectedTrip] = []
        var currentDrives: [TripDrive] = []
        var currentCharges: [TripCharge] = []
        var lastEventEnd: Date?
        var lastWasDrive = false

        for event in events {
            guard let eventStart = DomainDateParser.date(from: event.startDate) else {
                continue
            }

            guard let previousEnd = lastEventEnd else {
                if case let .drive(drive) = event {
                    currentDrives.append(drive)
                    lastEventEnd = DomainDateParser.date(from: event.endDate)
                    lastWasDrive = true
                }
                continue
            }

            let gapMin = Int(eventStart.timeIntervalSince(previousEnd) / 60.0)

            switch (lastWasDrive, event) {
            case (true, let .charge(charge)) where gapMin <= maxDriveToChargeGapMin:
                currentCharges.append(charge)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = false

            case (false, let .drive(drive)) where gapMin <= maxChargeToDriveGapMin:
                currentDrives.append(drive)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = true

            case (true, let .drive(drive)) where gapMin <= maxDriveToDriveGapMin:
                currentDrives.append(drive)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = true

            case (false, let .charge(charge)) where gapMin <= maxChargeToDriveGapMin:
                currentCharges.append(charge)
                lastEventEnd = DomainDateParser.date(from: event.endDate)
                lastWasDrive = false

            default:
                emitTrip(drives: currentDrives, charges: currentCharges, into: &trips)
                currentDrives = []
                currentCharges = []
                lastEventEnd = nil
                lastWasDrive = false

                if case let .drive(drive) = event {
                    currentDrives.append(drive)
                    lastEventEnd = DomainDateParser.date(from: event.endDate)
                    lastWasDrive = true
                }
            }
        }

        emitTrip(drives: currentDrives, charges: currentCharges, into: &trips)
        return trips
    }

    private static func emitTrip(drives: [TripDrive], charges: [TripCharge], into trips: inout [DetectedTrip]) {
        guard drives.count >= 2, !charges.isEmpty else {
            return
        }
        let totalDistance = drives.reduce(0) { $0 + $1.distance }
        guard totalDistance >= minimumTripDistanceKm else {
            return
        }
        if let trip = TripAggregator.buildTrip(drives: drives, charges: charges) {
            trips.append(trip)
        }
    }
}
