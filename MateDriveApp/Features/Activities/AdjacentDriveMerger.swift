import Foundation

public struct AdjacentDriveMergeConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var maximumGapMinutes: Int
    public var maximumLocationDistanceMeters: Double

    public init(
        isEnabled: Bool = true,
        maximumGapMinutes: Int = 30,
        maximumLocationDistanceMeters: Double = 750
    ) {
        self.isEnabled = isEnabled
        self.maximumGapMinutes = min(max(maximumGapMinutes, 5), 180)
        self.maximumLocationDistanceMeters = min(max(maximumLocationDistanceMeters, 50), 5_000)
    }
}

public enum AdjacentDriveLocationEvidence: String, Codable, Equatable, Sendable {
    case coordinates
    case address
}

public struct AdjacentDriveConnection: Codable, Equatable, Sendable {
    public let gapMinutes: Double
    public let locationEvidence: AdjacentDriveLocationEvidence
    public let distanceMeters: Double?

    public init(gapMinutes: Double, locationEvidence: AdjacentDriveLocationEvidence, distanceMeters: Double?) {
        self.gapMinutes = gapMinutes
        self.locationEvidence = locationEvidence
        self.distanceMeters = distanceMeters
    }
}

public struct ActivityAggregateMeasurement: Equatable, Sendable {
    public let value: Double?
    public let knownCount: Int
    public let totalCount: Int

    public var isComplete: Bool { knownCount == totalCount }

    public init(values: [Double?]) {
        let known: [Double] = values.compactMap { value -> Double? in
            guard let value, value.isFinite else { return nil }
            return value
        }
        value = known.isEmpty ? nil : known.reduce(0, +)
        knownCount = known.count
        totalCount = values.count
    }
}

public struct AdjacentDriveGroup: Equatable, Identifiable, Sendable {
    public let drives: [TeslaMateActivity]
    public let intermediateParking: [TeslaMateActivity]
    public let connections: [AdjacentDriveConnection]

    public var id: String { "merged-" + drives.map(\.stableID).joined(separator: "-") }
    public var firstDrive: TeslaMateActivity { drives[0] }
    public var lastDrive: TeslaMateActivity { drives[drives.count - 1] }
    public var startDate: String? { firstDrive.startDate }
    public var endDate: String? { lastDrive.endDate }
    public var startAddress: String? { firstDrive.startAddress }
    public var endAddress: String? { lastDrive.endAddress }
    public var distance: ActivityAggregateMeasurement { ActivityAggregateMeasurement(values: drives.map(\.distanceKm)) }
    public var drivingEnergy: ActivityAggregateMeasurement {
        ActivityAggregateMeasurement(values: drives.map { $0.kwhUsed ?? $0.kwh.map(abs) })
    }
    public var drivingDuration: ActivityAggregateMeasurement { ActivityAggregateMeasurement(values: drives.map(\.durationMin)) }
    public var stopDurationMinutes: Double { connections.reduce(0) { $0 + $1.gapMinutes } }
    public var paginationAnchor: TeslaMateActivity { firstDrive }
}

public enum ActivityTimelineEntry: Equatable, Identifiable, Sendable {
    case single(TeslaMateActivity)
    case mergedDrive(AdjacentDriveGroup)

    public var id: String {
        switch self {
        case let .single(activity): activity.stableID
        case let .mergedDrive(group): group.id
        }
    }

    public var paginationAnchor: TeslaMateActivity {
        switch self {
        case let .single(activity): activity
        case let .mergedDrive(group): group.paginationAnchor
        }
    }
}

public enum AdjacentDriveMerger {
    public static func entries(
        from activities: [TeslaMateActivity],
        configuration: AdjacentDriveMergeConfiguration,
        calendar: Calendar = .current
    ) -> [ActivityTimelineEntry] {
        let descending = activities.sorted { activityDate($0) > activityDate($1) }
        guard configuration.isEnabled else { return descending.map(ActivityTimelineEntry.single) }
        let chronological = descending.reversed()
        var result: [ActivityTimelineEntry] = []
        var index = 0
        let values = Array(chronological)

        while index < values.count {
            guard values[index].kind == .drive else {
                result.append(.single(values[index]))
                index += 1
                continue
            }

            var drives = [values[index]]
            var parking: [TeslaMateActivity] = []
            var connections: [AdjacentDriveConnection] = []
            var cursor = index

            while let candidate = nextDrive(after: cursor, in: values),
                  let connection = connection(
                      from: drives[drives.count - 1],
                      to: candidate.drive,
                      configuration: configuration,
                      calendar: calendar
                  ) {
                drives.append(candidate.drive)
                if let stop = candidate.parking { parking.append(stop) }
                connections.append(connection)
                cursor = candidate.index
            }

            if drives.count > 1 {
                result.append(.mergedDrive(AdjacentDriveGroup(
                    drives: drives,
                    intermediateParking: parking,
                    connections: connections
                )))
                index = cursor + 1
            } else {
                result.append(.single(values[index]))
                index += 1
            }
        }

        return result.reversed()
    }

    private static func nextDrive(
        after index: Int,
        in activities: [TeslaMateActivity]
    ) -> (drive: TeslaMateActivity, parking: TeslaMateActivity?, index: Int)? {
        let next = index + 1
        guard next < activities.count else { return nil }
        if activities[next].kind == .drive {
            return (activities[next], nil, next)
        }
        guard activities[next].kind == .park,
              next + 1 < activities.count,
              activities[next + 1].kind == .drive
        else { return nil }
        return (activities[next + 1], activities[next], next + 1)
    }

    private static func connection(
        from previous: TeslaMateActivity,
        to next: TeslaMateActivity,
        configuration: AdjacentDriveMergeConfiguration,
        calendar: Calendar
    ) -> AdjacentDriveConnection? {
        guard let previousEnd = previous.endDate.flatMap(DomainDateParser.date(from:)),
              let nextStart = next.startDate.flatMap(DomainDateParser.date(from:)),
              nextStart >= previousEnd,
              calendar.isDate(previousEnd, inSameDayAs: nextStart)
        else { return nil }
        let gapMinutes = nextStart.timeIntervalSince(previousEnd) / 60
        guard gapMinutes <= Double(configuration.maximumGapMinutes) else { return nil }

        if let previousLocation = GeoCoordinateValidator.location(
            latitude: previous.endLatitude,
            longitude: previous.endLongitude
        ), let nextLocation = GeoCoordinateValidator.location(
            latitude: next.startLatitude,
            longitude: next.startLongitude
        ) {
            let distance = distanceMeters(
                from: (previousLocation.latitude, previousLocation.longitude),
                to: (nextLocation.latitude, nextLocation.longitude)
            )
            guard distance <= configuration.maximumLocationDistanceMeters else { return nil }
            return AdjacentDriveConnection(
                gapMinutes: gapMinutes,
                locationEvidence: .coordinates,
                distanceMeters: distance
            )
        }

        let previousAddress = normalizedAddress(previous.endAddress)
        let nextAddress = normalizedAddress(next.startAddress)
        guard !previousAddress.isEmpty, previousAddress == nextAddress else { return nil }
        return AdjacentDriveConnection(gapMinutes: gapMinutes, locationEvidence: .address, distanceMeters: nil)
    }

    private static func activityDate(_ activity: TeslaMateActivity) -> Date {
        activity.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
    }

    private static func normalizedAddress(_ address: String?) -> String {
        address?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ") ?? ""
    }

    private static func distanceMeters(
        from lhs: (latitude: Double, longitude: Double),
        to rhs: (latitude: Double, longitude: Double)
    ) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = lhs.latitude * .pi / 180
        let lat2 = rhs.latitude * .pi / 180
        let deltaLat = (rhs.latitude - lhs.latitude) * .pi / 180
        let deltaLon = (rhs.longitude - lhs.longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
