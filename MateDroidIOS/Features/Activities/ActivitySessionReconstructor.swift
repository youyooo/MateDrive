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
        labelOverrides: [ActivityLabelOverride] = [],
        recurrenceCountsByPlaceKey: [String: Int] = [:],
        chargeIdentitiesByChargeID: [Int: ChargePricingChargerIdentity] = [:],
        confirmedCommuteSessionIDs: Set<String> = [],
        configuration: ActivitySessionReconstructionConfiguration = .init()
    ) -> [SmartActivitySession] {
        let ordered = deduplicated(events).sorted(by: orderedBefore)
        var claimedSourceKeys = Set<String>()
        var sessions: [SmartActivitySession] = []

        for parking in ordered where parking.kind == .park {
            guard let session = buildSession(
                carId: carId,
                parking: parking,
                events: ordered,
                sleepIntervals: sleepIntervals,
                geofences: geofences,
                labelOverrides: labelOverrides,
                recurrenceCountsByPlaceKey: recurrenceCountsByPlaceKey,
                chargeIdentitiesByChargeID: chargeIdentitiesByChargeID,
                confirmedCommuteSessionIDs: confirmedCommuteSessionIDs,
                configuration: configuration,
                claimedSourceKeys: claimedSourceKeys
            ) else {
                continue
            }
            sessions.append(session)
            claimedSourceKeys.formUnion(session.eventReferences.map { sourceKey(for: $0.sourceActivity) })
        }

        sessions += ordered.compactMap { drive in
            guard drive.kind == .drive,
                  !claimedSourceKeys.contains(sourceKey(for: drive))
            else { return nil }
            return fallbackSession(
                carId: carId,
                drive: drive,
                geofences: geofences,
                labelOverrides: labelOverrides,
                recurrenceCountsByPlaceKey: recurrenceCountsByPlaceKey,
                confirmedCommuteSessionIDs: confirmedCommuteSessionIDs
            )
        }

        return sessions.sorted {
            $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate > $1.startDate
        }
    }

    private static func buildSession(
        carId: Int,
        parking: TeslaMateActivity,
        events: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        geofences: [GeofenceRule],
        labelOverrides: [ActivityLabelOverride],
        recurrenceCountsByPlaceKey: [String: Int],
        chargeIdentitiesByChargeID: [Int: ChargePricingChargerIdentity],
        confirmedCommuteSessionIDs: Set<String>,
        configuration: ActivitySessionReconstructionConfiguration,
        claimedSourceKeys: Set<String>
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
            configuration: configuration,
            claimedSourceKeys: claimedSourceKeys
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
            configuration: configuration,
            claimedSourceKeys: claimedSourceKeys
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
                configuration: configuration,
                claimedSourceKeys: claimedSourceKeys
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

        let session = SmartActivitySession(
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
        return classified(
            session,
            geofence: geofence,
            labelOverrides: labelOverrides,
            recurrenceCount: recurrenceCountsByPlaceKey[session.placeKey] ?? 0,
            chargeIdentity: charges.first.flatMap { chargeIdentitiesByChargeID[$0.id] },
            hasCharge: !charges.isEmpty,
            hasPromptDeparture: departure != nil && !charges.isEmpty,
            isConfirmedCommute: confirmedCommuteSessionIDs.contains(session.id)
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
        configuration: ActivitySessionReconstructionConfiguration,
        claimedSourceKeys: Set<String>
    ) -> TeslaMateActivity? {
        events.reversed().first { event in
            guard event.kind == .drive,
                  !claimedSourceKeys.contains(sourceKey(for: event)),
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
        configuration: ActivitySessionReconstructionConfiguration,
        claimedSourceKeys: Set<String>
    ) -> [TeslaMateActivity] {
        let waivesChargeStartGrace = geofence?.kind == .home || geofence?.kind == .work
        return events.filter { event in
            guard event.kind == .charge,
                  !claimedSourceKeys.contains(sourceKey(for: event)),
                  let start = event.startDate.flatMap(DomainDateParser.date(from:)),
                  let end = event.endDate.flatMap(DomainDateParser.date(from:)),
                  let parkingEnd,
                  start >= parkingStart,
                  start <= end,
                  end <= parkingEnd,
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
        configuration: ActivitySessionReconstructionConfiguration,
        claimedSourceKeys: Set<String>
    ) -> TeslaMateActivity? {
        for candidate in events {
            guard candidate.kind == .drive,
                  !claimedSourceKeys.contains(sourceKey(for: candidate)),
                  let start = candidate.startDate.flatMap(DomainDateParser.date(from:)),
                  start >= parkingEnd
            else { continue }

            guard start.timeIntervalSince(parkingEnd) <= configuration.departureGrace else {
                return nil
            }
            if sharesPlace(
                candidate,
                role: .departure,
                parking: parking,
                parkingLocation: location,
                parkingGeofence: geofence,
                carId: carId,
                geofences: geofences,
                configuration: configuration
            ) {
                return candidate
            }
        }
        return nil
    }

    private static func fallbackSession(
        carId: Int,
        drive: TeslaMateActivity,
        geofences: [GeofenceRule],
        labelOverrides: [ActivityLabelOverride],
        recurrenceCountsByPlaceKey: [String: Int],
        confirmedCommuteSessionIDs: Set<String>
    ) -> SmartActivitySession? {
        guard let startDate = drive.startDate.flatMap(DomainDateParser.date(from:)) else {
            return nil
        }

        let location = location(for: drive, role: .arrival)
        let geofence = GeofenceRuleEngine.matchingRule(
            latitude: location?.latitude,
            longitude: location?.longitude,
            carId: carId,
            rules: geofences
        )
        let references = [SmartActivityEventReference(sourceActivity: drive)]
        let sourceFingerprint = fingerprint(references)

        let session = SmartActivitySession(
            id: "\(carId)-\(drive.id)",
            carId: carId,
            startDate: startDate,
            endDate: drive.endDate.flatMap(DomainDateParser.date(from:)),
            placeKey: placeKey(geofence: geofence, location: location, fallbackPrefix: "drive", fallbackID: drive.id),
            latitude: location?.latitude,
            longitude: location?.longitude,
            geofenceID: geofence?.id,
            provisionalKind: .unclassified,
            classification: nil,
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: references,
            isOpen: drive.endDate.flatMap(DomainDateParser.date(from:)) == nil,
            quality: .partial,
            derivationVersion: 1,
            sourceFingerprint: sourceFingerprint,
            derivationFingerprint: sourceFingerprint
        )
        return classified(
            session,
            geofence: geofence,
            labelOverrides: labelOverrides,
            recurrenceCount: recurrenceCountsByPlaceKey[session.placeKey] ?? 0,
            chargeIdentity: nil,
            hasCharge: false,
            hasPromptDeparture: false,
            isConfirmedCommute: confirmedCommuteSessionIDs.contains(session.id)
        )
    }

    private static func classified(
        _ session: SmartActivitySession,
        geofence: GeofenceRule?,
        labelOverrides: [ActivityLabelOverride],
        recurrenceCount: Int,
        chargeIdentity: ChargePricingChargerIdentity?,
        hasCharge: Bool,
        hasPromptDeparture: Bool,
        isConfirmedCommute: Bool
    ) -> SmartActivitySession {
        let classification = ActivityPurposeClassifier.classify(
            ActivityClassificationInput(
                session: session,
                sessionOverride: matchingSessionOverride(for: session, in: labelOverrides),
                placeOverride: matchingPlaceOverride(for: session, in: labelOverrides),
                geofenceKind: geofence?.kind,
                recurrenceCount: recurrenceCount,
                chargeIdentity: chargeIdentity,
                hasCharge: hasCharge,
                hasPromptDeparture: hasPromptDeparture,
                isConfirmedCommute: isConfirmedCommute
            )
        )
        return SmartActivitySession(
            id: session.id,
            carId: session.carId,
            startDate: session.startDate,
            endDate: session.endDate,
            placeKey: session.placeKey,
            latitude: session.latitude,
            longitude: session.longitude,
            geofenceID: session.geofenceID,
            provisionalKind: session.provisionalKind,
            classification: classification,
            parkingMetrics: session.parkingMetrics,
            chargeCost: session.chargeCost,
            eventReferences: session.eventReferences,
            isOpen: session.isOpen,
            quality: session.quality,
            derivationVersion: session.derivationVersion,
            sourceFingerprint: session.sourceFingerprint,
            derivationFingerprint: session.derivationFingerprint
        )
    }

    private static func matchingSessionOverride(
        for session: SmartActivitySession,
        in overrides: [ActivityLabelOverride]
    ) -> ActivityLabelOverride? {
        preferredOverride(overrides.filter {
            $0.carId == session.carId && $0.sessionId == session.id
        })
    }

    private static func matchingPlaceOverride(
        for session: SmartActivitySession,
        in overrides: [ActivityLabelOverride]
    ) -> ActivityLabelOverride? {
        preferredOverride(overrides.filter {
            $0.carId == session.carId
                && $0.scope == .futureAtPlace
                && $0.placeKey == session.placeKey
                && matchesTimeWindow($0, date: session.startDate)
        })
    }

    private static func preferredOverride(_ overrides: [ActivityLabelOverride]) -> ActivityLabelOverride? {
        overrides.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt
        }.first
    }

    private static func matchesTimeWindow(_ override: ActivityLabelOverride, date: Date) -> Bool {
        guard let start = override.startMinute, let end = override.endMinute else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if start <= end { return (start...end).contains(minute) }
        return minute >= start || minute <= end
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

    private static func placeKey(
        geofence: GeofenceRule?,
        location: Coordinate?,
        fallbackPrefix: String = "parking",
        fallbackID: Int
    ) -> String {
        if let geofence { return "geofence:\(geofence.id)" }
        if let location { return "coordinate:\(location.latitude),\(location.longitude)" }
        return "\(fallbackPrefix):\(fallbackID)"
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

    private static func orderedBefore(_ lhs: TeslaMateActivity, _ rhs: TeslaMateActivity) -> Bool {
        let lhsStart = eventStart(lhs)
        let rhsStart = eventStart(rhs)
        if lhsStart != rhsStart { return lhsStart < rhsStart }
        return sourceKey(for: lhs) < sourceKey(for: rhs)
    }

    private static func sourceKey(for event: TeslaMateActivity) -> String {
        "\(event.kind.rawValue)-\(event.id)"
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
