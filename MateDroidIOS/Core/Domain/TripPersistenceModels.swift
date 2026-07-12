import CryptoKit
import Foundation

public enum TripLegReference: Hashable, Codable, Identifiable, Sendable {
    case drive(Int)
    case charge(Int)

    private enum CodingKeys: String, CodingKey {
        case type
        case id
    }

    public var id: String {
        "\(type.rawValue)-\(legId)"
    }

    public var type: TripLegType {
        switch self {
        case .drive:
            return .drive
        case .charge:
            return .charge
        }
    }

    public var legId: Int {
        switch self {
        case let .drive(id), let .charge(id):
            return id
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TripLegType.self, forKey: .type)
        let id = try container.decode(Int.self, forKey: .id)
        switch type {
        case .drive:
            self = .drive(id)
        case .charge:
            self = .charge(id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(legId, forKey: .id)
    }
}

public enum TripLegType: String, Codable, Sendable {
    case drive = "DRIVE"
    case charge = "CHARGE"
}

public struct SavedTripSnapshot: Equatable, Identifiable, Sendable {
    public var id: String { tripId }

    public let tripId: String
    public let carId: Int
    public let name: String?
    public let startDate: String
    public let endDate: String
    public let legs: [TripLegReference]
    public let consumedFingerprints: Set<String>

    public init(
        tripId: String,
        carId: Int,
        name: String?,
        startDate: String,
        endDate: String,
        legs: [TripLegReference],
        consumedFingerprints: Set<String> = []
    ) {
        self.tripId = tripId
        self.carId = carId
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.legs = legs
        self.consumedFingerprints = consumedFingerprints
    }
}

public struct TripSourceData: Equatable, Sendable {
    public let drives: [TripDrive]
    public let charges: [TripCharge]
    public let dcChargeIds: Set<Int>
    public let units: UnitPreferences?

    public init(drives: [TripDrive], charges: [TripCharge], dcChargeIds: Set<Int> = [], units: UnitPreferences? = nil) {
        self.drives = drives
        self.charges = charges
        self.dcChargeIds = dcChargeIds
        self.units = units
    }
}

public enum TripFingerprint {
    public static func fingerprint(driveIds: [Int]) -> String {
        let ids = driveIds.sorted().map(String.init).joined(separator: ",")
        let digest = SHA256.hash(data: Data(ids.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func fingerprint(_ trip: DetectedTrip) -> String {
        fingerprint(driveIds: trip.drives.map(\.id))
    }
}

public enum TripTimelineSegmentKind: String, Sendable {
    case drive = "Drive"
    case dcCharge = "DC Charge"
    case acCharge = "AC Charge"
    case parking = "Parked"
}

public struct TripTimelineSegment: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: TripTimelineSegmentKind
    public let durationMin: Int
    public let label: String
    public let driveId: Int?
    public let chargeId: Int?
    public let distanceKm: Double?
    public let energyKwh: Double?

    public init(
        id: String,
        kind: TripTimelineSegmentKind,
        durationMin: Int,
        label: String,
        driveId: Int? = nil,
        chargeId: Int? = nil,
        distanceKm: Double? = nil,
        energyKwh: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.durationMin = durationMin
        self.label = label
        self.driveId = driveId
        self.chargeId = chargeId
        self.distanceKm = distanceKm
        self.energyKwh = energyKwh
    }
}

public enum TripTimelineBuilder {
    private static let minimumParkingGapMin = 5

    public static func build(trip: DetectedTrip, dcChargeIds: Set<Int>, showShort: Bool) -> [TripTimelineSegment] {
        enum Event {
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
        }

        let drives = showShort ? trip.drives : trip.drives.filter {
            ShortEntryFilter.isSignificantDrive(distanceKilometers: $0.distance, durationMinutes: $0.durationMin)
        }
        let charges = showShort ? trip.charges : trip.charges.filter {
            ShortEntryFilter.isSignificantCharge(energyKilowattHours: $0.energyAdded)
        }

        var events = drives.map(Event.drive) + charges.map(Event.charge)
        events.sort { lhs, rhs in lhs.startDate < rhs.startDate }

        var segments: [TripTimelineSegment] = []
        var previousEnd: Date?
        var driveIndex = 0
        var chargeIndex = 0

        for event in events {
            if
                let previousEnd,
                let start = DomainDateParser.date(from: event.startDate) {
                let gap = Int(start.timeIntervalSince(previousEnd) / 60.0)
                if gap >= minimumParkingGapMin {
                    segments.append(
                        TripTimelineSegment(
                            id: "parking-\(segments.count)",
                            kind: .parking,
                            durationMin: gap,
                            label: "Parked"
                        )
                    )
                }
            }

            switch event {
            case let .drive(drive):
                driveIndex += 1
                segments.append(
                    TripTimelineSegment(
                        id: "drive-\(drive.id)",
                        kind: .drive,
                        durationMin: drive.durationMin,
                        label: "Drive \(driveIndex)",
                        driveId: drive.id,
                        distanceKm: drive.distance
                    )
                )
            case let .charge(charge):
                chargeIndex += 1
                let isDc = dcChargeIds.contains(charge.id)
                segments.append(
                    TripTimelineSegment(
                        id: "charge-\(charge.id)",
                        kind: isDc ? .dcCharge : .acCharge,
                        durationMin: charge.durationMin,
                        label: "Charge \(chargeIndex)",
                        chargeId: charge.id,
                        energyKwh: charge.energyAdded
                    )
                )
            }

            previousEnd = DomainDateParser.date(from: event.endDate)
        }

        return segments
    }
}

public extension DetectedTrip {
    var displayName: String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let start = startAddress?.split(separator: ",").first.map(String.init) ?? "Start"
        let end = endAddress?.split(separator: ",").first.map(String.init) ?? "End"
        return "\(start) -> \(end)"
    }

    func displayName(language: AppLanguage) -> String {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let usesChinese = MateDroidUnitFormatter.usesChineseLabels(language: language)
        let start = startAddress?.split(separator: ",").first.map(String.init) ?? (usesChinese ? "开始" : "Start")
        let end = endAddress?.split(separator: ",").first.map(String.init) ?? (usesChinese ? "结束" : "End")
        return "\(start) -> \(end)"
    }
}

public extension TripTimelineSegment {
    func displayLabel(language: AppLanguage) -> String {
        if label == "Parked" {
            return AppText.localized("Parked", "停放", language: language)
        }
        if label.hasPrefix("Drive ") {
            return "\(AppText.localized("Drive", "行程", language: language)) \(label.dropFirst("Drive ".count))"
        }
        if label.hasPrefix("Charge ") {
            return "\(AppText.localized("Charge", "充电", language: language)) \(label.dropFirst("Charge ".count))"
        }
        return label
    }

    func destination(carId: Int, exteriorColor: String?) -> AppRoute? {
        if let driveId {
            return .driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor)
        }
        if let chargeId {
            return .chargeDetail(carId: carId, chargeId: chargeId, exteriorColor: exteriorColor)
        }
        return nil
    }
}
