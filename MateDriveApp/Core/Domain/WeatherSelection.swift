import Foundation

public struct WeatherRoutePosition: Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let date: String?

    public init(latitude: Double?, longitude: Double?, date: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
    }
}

public struct WeatherPositionWithDistance: Equatable, Sendable {
    public let position: WeatherRoutePosition
    public let cumulativeDistanceKm: Double

    public init(position: WeatherRoutePosition, cumulativeDistanceKm: Double) {
        self.position = position
        self.cumulativeDistanceKm = cumulativeDistanceKm
    }
}

public struct TripRoutePoint: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct TripRouteSegment: Equatable, Sendable {
    public let points: [TripRoutePoint]

    public init(points: [TripRoutePoint]) {
        self.points = points
    }
}

public struct TimedWeatherSample: Equatable, Sendable {
    public let epochMilliseconds: Int64
    public let latitude: Double
    public let longitude: Double

    public init(epochMilliseconds: Int64, latitude: Double, longitude: Double) {
        self.epochMilliseconds = epochMilliseconds
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum WeatherSelection {
    private static let thresholdSinglePointKm = 10.0
    private static let thresholdTwoPointsKm = 30.0
    private static let thresholdMediumDriveKm = 150.0
    private static let intervalMediumKm = 25.0
    private static let intervalLongKm = 35.0

    public static func driveEnvironmentPosition(
        positions: [WeatherRoutePosition]
    ) -> WeatherRoutePosition? {
        let valid = positions.compactMap { position -> (position: WeatherRoutePosition, date: Date)? in
            guard GeoCoordinateValidator.location(
                latitude: position.latitude,
                longitude: position.longitude
            ) != nil,
                let rawDate = position.date,
                let date = DomainDateParser.date(from: rawDate)
            else {
                return nil
            }
            return (position, date)
        }
        guard let firstDate = valid.map(\.date).min(),
              let lastDate = valid.map(\.date).max()
        else {
            return nil
        }

        let midpoint = firstDate.addingTimeInterval(lastDate.timeIntervalSince(firstDate) / 2)
        return valid.min {
            abs($0.date.timeIntervalSince(midpoint)) < abs($1.date.timeIntervalSince(midpoint))
        }?.position
    }

    public static func calculateCumulativeDistances(
        positions: [WeatherRoutePosition]
    ) -> [WeatherPositionWithDistance] {
        let validPositions = positions.compactMap {
            position -> (position: WeatherRoutePosition, location: GeocodeLocation)? in
            guard position.date != nil,
                  let location = GeoCoordinateValidator.location(
                      latitude: position.latitude,
                      longitude: position.longitude
                  )
            else {
                return nil
            }
            return (position, location)
        }
        guard !validPositions.isEmpty else {
            return []
        }

        var cumulativeDistance = 0.0
        var result: [WeatherPositionWithDistance] = []

        for (index, position) in validPositions.enumerated() {
            if index > 0 {
                let previous = validPositions[index - 1]
                cumulativeDistance += haversineDistance(
                    latitude1: previous.location.latitude,
                    longitude1: previous.location.longitude,
                    latitude2: position.location.latitude,
                    longitude2: position.location.longitude
                )
            }
            result.append(WeatherPositionWithDistance(
                position: position.position,
                cumulativeDistanceKm: cumulativeDistance
            ))
        }

        return result
    }

    public static func selectWeatherPositions(
        positions: [WeatherRoutePosition],
        totalDistanceKm: Double
    ) -> [WeatherPositionWithDistance] {
        selectWeatherPositions(
            positionsWithDistance: calculateCumulativeDistances(positions: positions),
            totalDistanceKm: totalDistanceKm
        )
    }

    public static func selectWeatherPositions(
        positionsWithDistance: [WeatherPositionWithDistance],
        totalDistanceKm: Double
    ) -> [WeatherPositionWithDistance] {
        guard let first = positionsWithDistance.first, let last = positionsWithDistance.last else {
            return []
        }

        if totalDistanceKm < thresholdSinglePointKm {
            return [last]
        }

        if totalDistanceKm < thresholdTwoPointsKm {
            return [first, last]
        }

        let interval = totalDistanceKm <= thresholdMediumDriveKm ? intervalMediumKm : intervalLongKm
        return selectAtIntervals(positionsWithDistance: positionsWithDistance, intervalKm: interval, totalDistanceKm: totalDistanceKm)
    }

    public static func selectTripSamples(
        drives: [TripDrive],
        routeSegments: [TripRouteSegment]
    ) -> [TimedWeatherSample] {
        guard !drives.isEmpty, !routeSegments.isEmpty else {
            return []
        }

        var allPoints: [TimedWeatherSample] = []

        for (driveIndex, drive) in drives.enumerated() {
            guard driveIndex < routeSegments.count else {
                continue
            }
            let points = routeSegments[driveIndex].points
            guard !points.isEmpty,
                  let startDate = DomainDateParser.date(from: drive.startDate),
                  let endDate = DomainDateParser.date(from: drive.endDate)
            else {
                continue
            }

            let durationMilliseconds = max(Int64(endDate.timeIntervalSince(startDate) * 1000), 1)
            let count = points.count
            let startMilliseconds = Int64(startDate.timeIntervalSince1970 * 1000)

            for (index, point) in points.enumerated() {
                let offset = count > 1 ? Int64(Double(durationMilliseconds) * Double(index) / Double(count - 1)) : 0
                allPoints.append(
                    TimedWeatherSample(
                        epochMilliseconds: startMilliseconds + offset,
                        latitude: point.latitude,
                        longitude: point.longitude
                    )
                )
            }
        }

        guard !allPoints.isEmpty else {
            return []
        }

        let totalDriveMin = drives.reduce(0) { $0 + $1.durationMin }
        let sampleCount = min(max(Int(Double(totalDriveMin) / 60.0), 3), 12)

        return (0..<sampleCount).map { index in
            let denominator = max(sampleCount - 1, 1)
            let pointIndex = min(max(Int((Double(index) / Double(denominator)) * Double(allPoints.count - 1)), 0), allPoints.count - 1)
            return allPoints[pointIndex]
        }
    }

    private static func selectAtIntervals(
        positionsWithDistance: [WeatherPositionWithDistance],
        intervalKm: Double,
        totalDistanceKm: Double
    ) -> [WeatherPositionWithDistance] {
        guard let first = positionsWithDistance.first, let last = positionsWithDistance.last else {
            return []
        }

        var selected = [first]
        var nextTarget = intervalKm

        while nextTarget < totalDistanceKm - intervalKm / 2 {
            if let closest = positionsWithDistance.min(by: {
                abs($0.cumulativeDistanceKm - nextTarget) < abs($1.cumulativeDistanceKm - nextTarget)
            }), closest != selected.last {
                selected.append(closest)
            }
            nextTarget += intervalKm
        }

        if selected.last != last {
            selected.append(last)
        }

        return selected
    }

    private static func haversineDistance(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let earthRadiusKm = 6371.0
        let dLat = degreesToRadians(latitude2 - latitude1)
        let dLon = degreesToRadians(longitude2 - longitude1)
        let lat1 = degreesToRadians(latitude1)
        let lat2 = degreesToRadians(latitude2)

        let a = sin(dLat / 2) * sin(dLat / 2) +
            sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusKm * c
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
