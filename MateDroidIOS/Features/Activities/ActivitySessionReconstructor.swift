import CryptoKit
import Foundation

public struct ActivitySessionReconstructionConfiguration: Equatable, Sendable {
    public let chargeStartGrace: TimeInterval
    public let departureGrace: TimeInterval
    public let clusterRadiusMeters: Double

    public init(
        chargeStartGrace: TimeInterval = 60 * 60,
        departureGrace: TimeInterval = 90 * 60,
        clusterRadiusMeters: Double = 250
    ) {
        self.chargeStartGrace = chargeStartGrace
        self.departureGrace = departureGrace
        self.clusterRadiusMeters = clusterRadiusMeters
    }
}

public enum ActivitySessionReconstructor {
    public static func reconstruct(
        carId: Int,
        events: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration = .init()
    ) -> [SmartActivitySession] {
        let ordered = deduplicated(events).sorted { eventStart($0) < eventStart($1) }
        return ordered.filter { $0.kind == .park }.compactMap { parking in
            buildSession(
                carId: carId,
                parking: parking,
                events: ordered,
                sleepIntervals: sleepIntervals,
                geofences: geofences,
                configuration: configuration
            )
        }.sorted { $0.startDate > $1.startDate }
    }

    private static func buildSession(
        carId: Int,
        parking: TeslaMateActivity,
        events: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration
    ) -> SmartActivitySession? {
        guard let parkingStart = parking.startDate.flatMap(DomainDateParser.date(from:)) else {
            return nil
        }

        let parkingEnd = parking.endDate.flatMap(DomainDateParser.date(from:))
        let location = location(for: parking, role: .parking)
        let geofence = GeofenceRuleEngine.matchingRule(
            latitude: location?.latitude,
            longitude: location?.longitude,
            carId: carId,
            rules: geofences
        )
        let arrival = arrivalDrive(
            before: parkingStart,
            parking: parking,
            location: location,
            geofence: geofence,
            carId: carId,
            events: events,
            geofences: geofences,
            configuration: configuration
        )
        let charges = chargesDuringStay(
            from: parkingStart,
            to: parkingEnd,
            parking: parking,
            location: location,
            geofence: geofence,
            carId: carId,
            events: events,
            geofences: geofences,
            configuration: configuration
        )
        let departure = parkingEnd.flatMap { end in
            departureDrive(
                after: end,
                parking: parking,
                location: location,
                geofence: geofence,
                carId: carId,
                events: events,
                geofences: geofences,
                configuration: configuration
            )
        }

        let references = ([arrival].compactMap { $0 } + [parking] + charges + [departure].compactMap { $0 })
            .map(SmartActivityEventReference.init(sourceActivity:))
        let sourceFingerprint = fingerprint(references)
        let metrics = ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(
                parking: parking,
                charges: charges,
                sleepIntervals: sleepIntervals,
                previousDrive: arrival,
                nextDrive: departure
            )
        )
        let isOpen = parkingEnd == nil
        let startDate = arrival?.startDate.flatMap(DomainDateParser.date(from:)) ?? parkingStart
        let endDate = departure?.endDate.flatMap(DomainDateParser.date(from:)) ?? parkingEnd

        return SmartActivitySession(
            id: "\(carId)-\(parking.id)",
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            placeKey: placeKey(geofence: geofence, location: location, fallbackID: parking.id),
            latitude: location?.latitude,
            longitude: location?.longitude,
            geofenceID: geofence?.id,
            provisionalKind: provisionalPurpose(geofence: geofence, hasCharge: !charges.isEmpty),
            classification: nil,
            parkingMetrics: metrics,
            chargeCost: nil,
            eventReferences: references,
            isOpen: isOpen,
            quality: metrics?.quality ?? .unavailable,
            derivationVersion: 1,
            sourceFingerprint: sourceFingerprint,
            derivationFingerprint: sourceFingerprint
        )
    }

    private static func arrivalDrive(
        before parkingStart: Date,
        parking: TeslaMateActivity,
        location: Coordinate?,
        geofence: GeofenceRule?,
        carId: Int,
        events: [TeslaMateActivity],
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration
    ) -> TeslaMateActivity? {
        events.reversed().first { event in
            guard event.kind == .drive,
                  let end = event.endDate.flatMap(DomainDateParser.date(from:)),
                  end <= parkingStart
            else { return false }
            return sharesPlace(
                event,
                role: .arrival,
                parking: parking,
                parkingLocation: location,
                parkingGeofence: geofence,
                carId: carId,
                geofences: geofences,
                configuration: configuration
            )
        }
    }

    private static func chargesDuringStay(
        from parkingStart: Date,
        to parkingEnd: Date?,
        parking: TeslaMateActivity,
        location: Coordinate?,
        geofence: GeofenceRule?,
        carId: Int,
        events: [TeslaMateActivity],
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration
    ) -> [TeslaMateActivity] {
        let waivesChargeStartGrace = geofence?.kind == .home || geofence?.kind == .work
        return events.filter { event in
            guard event.kind == .charge,
                  let start = event.startDate.flatMap(DomainDateParser.date(from:)),
                  start >= parkingStart,
                  parkingEnd.map({ start <= $0 }) ?? true,
                  waivesChargeStartGrace || start.timeIntervalSince(parkingStart) <= configuration.chargeStartGrace
            else { return false }
            return sharesPlace(
                event,
                role: .charge,
                parking: parking,
                parkingLocation: location,
                parkingGeofence: geofence,
                carId: carId,
                geofences: geofences,
                configuration: configuration
            )
        }
    }

    private static func departureDrive(
        after parkingEnd: Date,
        parking: TeslaMateActivity,
        location: Coordinate?,
        geofence: GeofenceRule?,
        carId: Int,
        events: [TeslaMateActivity],
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration
    ) -> TeslaMateActivity? {
        guard let candidate = events.first(where: { event in
            guard event.kind == .drive,
                  let start = event.startDate.flatMap(DomainDateParser.date(from:))
            else { return false }
            return start >= parkingEnd
        }),
        let start = candidate.startDate.flatMap(DomainDateParser.date(from:)),
        start.timeIntervalSince(parkingEnd) <= configuration.departureGrace
        else { return nil }

        return sharesPlace(
            candidate,
            role: .departure,
            parking: parking,
            parkingLocation: location,
            parkingGeofence: geofence,
            carId: carId,
            geofences: geofences,
            configuration: configuration
        ) ? candidate : nil
    }

    private static func sharesPlace(
        _ event: TeslaMateActivity,
        role: EventRole,
        parking: TeslaMateActivity,
        parkingLocation: Coordinate?,
        parkingGeofence: GeofenceRule?,
        carId: Int,
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration
    ) -> Bool {
        guard event.id != parking.id else { return false }
        let eventLocation = location(for: event, role: role)
        let eventGeofence = GeofenceRuleEngine.matchingRule(
            latitude: eventLocation?.latitude,
            longitude: eventLocation?.longitude,
            carId: carId,
            rules: geofences
        )
        if let parkingGeofence, parkingGeofence.id == eventGeofence?.id {
            return true
        }
        guard let parkingLocation, let eventLocation else { return false }
        return distanceMeters(from: parkingLocation, to: eventLocation) <= configuration.clusterRadiusMeters
    }

    private static func provisionalPurpose(geofence: GeofenceRule?, hasCharge: Bool) -> SmartActivityPurpose {
        guard hasCharge else { return .parking }
        switch geofence?.kind {
        case .home: return .homeCharging
        case .work: return .workCharging
        default: return .replenishment
        }
    }

    private static func placeKey(geofence: GeofenceRule?, location: Coordinate?, fallbackID: Int) -> String {
        if let geofence { return "geofence:\(geofence.id)" }
        if let location { return "coordinate:\(location.latitude),\(location.longitude)" }
        return "parking:\(fallbackID)"
    }

    private static func fingerprint(_ references: [SmartActivityEventReference]) -> String {
        let source = references.map {
            "\($0.kind.rawValue)-\($0.sourceID)-\($0.startDate ?? "")-\($0.endDate ?? "")"
        }.sorted().joined(separator: "|")
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func deduplicated(_ events: [TeslaMateActivity]) -> [TeslaMateActivity] {
        var seen = Set<String>()
        return events.filter { seen.insert("\($0.kind.rawValue)-\($0.id)").inserted }
    }

    private static func eventStart(_ event: TeslaMateActivity) -> Date {
        event.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
    }

    private static func location(for event: TeslaMateActivity, role: EventRole) -> Coordinate? {
        let coordinates: [(Double?, Double?)]
        switch role {
        case .arrival:
            coordinates = [(event.endLatitude, event.endLongitude), (event.startLatitude, event.startLongitude)]
        case .departure:
            coordinates = [(event.startLatitude, event.startLongitude), (event.endLatitude, event.endLongitude)]
        case .parking:
            coordinates = [(event.endLatitude, event.endLongitude), (event.startLatitude, event.startLongitude)]
        case .charge:
            coordinates = [(event.startLatitude, event.startLongitude), (event.endLatitude, event.endLongitude)]
        }
        for (latitude, longitude) in coordinates {
            if let latitude, let longitude,
               GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil {
                return Coordinate(latitude: latitude, longitude: longitude)
            }
        }
        return nil
    }

    private static func distanceMeters(from lhs: Coordinate, to rhs: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private struct Coordinate: Sendable {
        let latitude: Double
        let longitude: Double
    }

    private enum EventRole {
        case arrival, departure, parking, charge
    }
}
