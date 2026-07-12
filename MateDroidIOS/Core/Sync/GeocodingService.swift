import Foundation
import CoreLocation

public struct GeocodeLocation: Codable, Equatable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct GeocodeRouteSample: Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let date: String?

    public init(latitude: Double?, longitude: Double?, date: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
    }
}

public enum GeoCoordinateValidator {
    public static func location(latitude: Double?, longitude: Double?) -> GeocodeLocation? {
        guard let latitude, let longitude,
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              latitude != 0 || longitude != 0
        else { return nil }
        return GeocodeLocation(latitude: latitude, longitude: longitude)
    }

    public static func sanitizedRoute(_ samples: [GeocodeRouteSample], maximumSpeedKPH: Double = 350) -> [GeocodeLocation] {
        var accepted: [(location: GeocodeLocation, date: Date?)] = []
        for sample in samples {
            guard let location = location(latitude: sample.latitude, longitude: sample.longitude) else { continue }
            let date = sample.date.flatMap(DomainDateParser.date(from:))
            if let previous = accepted.last,
               let previousDate = previous.date,
               let date,
               date > previousDate {
                let hours = date.timeIntervalSince(previousDate) / 3600
                let allowedDistance = max(1, maximumSpeedKPH * hours)
                if distanceKilometers(from: previous.location, to: location) > allowedDistance {
                    continue
                }
            }
            accepted.append((location, date))
        }
        return accepted.map(\.location)
    }

    private static func distanceKilometers(from lhs: GeocodeLocation, to rhs: GeocodeLocation) -> Double {
        let earthRadius = 6_371.0
        let latitudeDelta = (rhs.latitude - lhs.latitude) * .pi / 180
        let longitudeDelta = (rhs.longitude - lhs.longitude) * .pi / 180
        let lhsLatitude = lhs.latitude * .pi / 180
        let rhsLatitude = rhs.latitude * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(lhsLatitude) * cos(rhsLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

public struct GeocodedLocation: Codable, Equatable, Sendable {
    public let address: String?
    public let countryCode: String?
    public let countryName: String?
    public let regionName: String?
    public let city: String?

    public init(address: String? = nil, countryCode: String? = nil, countryName: String? = nil, regionName: String? = nil, city: String? = nil) {
        self.address = address
        self.countryCode = countryCode
        self.countryName = countryName
        self.regionName = regionName
        self.city = city
    }
}

public struct GeocodeQueueItem: Codable, Equatable, Sendable {
    public let gridLatitude: Int
    public let gridLongitude: Int
    public let carId: Int
    public let latitude: Double
    public let longitude: Double
    public let addedAtMilliseconds: Int64

    public init(gridLatitude: Int, gridLongitude: Int, carId: Int, latitude: Double, longitude: Double, addedAtMilliseconds: Int64) {
        self.gridLatitude = gridLatitude
        self.gridLongitude = gridLongitude
        self.carId = carId
        self.latitude = latitude
        self.longitude = longitude
        self.addedAtMilliseconds = addedAtMilliseconds
    }
}

public enum GeocodeGrid {
    public static let precision = 100

    public static func gridCoord(_ coord: Double) -> Int {
        Int(coord * Double(precision))
    }
}

public protocol GeocodeQueueStoring: Sendable {
    func cachedLocation(gridLatitude: Int, gridLongitude: Int) async throws -> GeocodedLocation?
    func enqueue(_ items: [GeocodeQueueItem]) async throws
    func save(location: GeocodedLocation, latitude: Double, longitude: Double) async throws
    func pending(limit: Int) async throws -> [GeocodeQueueItem]
    func removePending(gridLatitude: Int, gridLongitude: Int) async throws
}

public struct GeocodeQueueProcessingReport: Equatable, Sendable {
    public let attemptedCount: Int
    public let completedCount: Int
    public let failedCount: Int
}

public protocol GeocodeQueueProcessing: Sendable {
    func processPending(limit: Int) async -> GeocodeQueueProcessingReport
}

public struct EmptyGeocodeQueueProcessor: GeocodeQueueProcessing {
    public init() {}
    public func processPending(limit _: Int) async -> GeocodeQueueProcessingReport {
        GeocodeQueueProcessingReport(attemptedCount: 0, completedCount: 0, failedCount: 0)
    }
}

public protocol ReverseGeocodingAPI: Sendable {
    func reverseGeocode(latitude: Double, longitude: Double) async -> APIResult<GeocodedLocation>
}

public actor GeocodingService: SyncGeocodingServicing, GeocodeQueueProcessing {
    private let queueStore: any GeocodeQueueStoring
    private let reverseGeocoder: (any ReverseGeocodingAPI)?

    public init(queueStore: any GeocodeQueueStoring, reverseGeocoder: (any ReverseGeocodingAPI)? = nil) {
        self.queueStore = queueStore
        self.reverseGeocoder = reverseGeocoder
    }

    @discardableResult
    public func enqueueLocations(carId: Int, locations: [GeocodeLocation]) async throws -> Int {
        let validLocations = locations.compactMap { GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) }
        let unique = Dictionary(grouping: validLocations) { location in
            GridKey(latitude: GeocodeGrid.gridCoord(location.latitude), longitude: GeocodeGrid.gridCoord(location.longitude))
        }.compactMap { _, values in values.first }

        var uncached: [GeocodeQueueItem] = []
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        for location in unique {
            let gridLatitude = GeocodeGrid.gridCoord(location.latitude)
            let gridLongitude = GeocodeGrid.gridCoord(location.longitude)
            if try await queueStore.cachedLocation(gridLatitude: gridLatitude, gridLongitude: gridLongitude) == nil {
                uncached.append(
                    GeocodeQueueItem(
                        gridLatitude: gridLatitude,
                        gridLongitude: gridLongitude,
                        carId: carId,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        addedAtMilliseconds: now
                    )
                )
            }
        }

        if !uncached.isEmpty {
            try await queueStore.enqueue(uncached)
        }

        return uncached.count
    }

    public func reverseGeocode(latitude: Double, longitude: Double) async -> APIResult<GeocodedLocation> {
        guard GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil else {
            return .failure(.invalidResponse("Invalid geocoding coordinates"))
        }
        let gridLatitude = GeocodeGrid.gridCoord(latitude)
        let gridLongitude = GeocodeGrid.gridCoord(longitude)
        do {
            if let cached = try await queueStore.cachedLocation(gridLatitude: gridLatitude, gridLongitude: gridLongitude) {
                return .success(cached)
            }
        } catch {
            return .failure(.invalidResponse(error.localizedDescription))
        }
        guard let reverseGeocoder else {
            return .failure(.invalidResponse("Reverse geocoder is not configured"))
        }
        let result = await reverseGeocoder.reverseGeocode(latitude: latitude, longitude: longitude)
        if case let .success(location) = result {
            do {
                try await queueStore.save(location: location, latitude: latitude, longitude: longitude)
            } catch {
                return .failure(.invalidResponse(error.localizedDescription))
            }
        }
        return result
    }

    public func cachedLocation(latitude: Double, longitude: Double) async -> GeocodedLocation? {
        try? await queueStore.cachedLocation(
            gridLatitude: GeocodeGrid.gridCoord(latitude),
            gridLongitude: GeocodeGrid.gridCoord(longitude)
        )
    }

    public func processPending(limit: Int = 6) async -> GeocodeQueueProcessingReport {
        guard limit > 0 else { return GeocodeQueueProcessingReport(attemptedCount: 0, completedCount: 0, failedCount: 0) }
        let items: [GeocodeQueueItem]
        do {
            items = try await queueStore.pending(limit: limit)
        } catch {
            return GeocodeQueueProcessingReport(attemptedCount: 0, completedCount: 0, failedCount: 1)
        }
        var completed = 0
        var failed = 0
        for item in items {
            switch await reverseGeocode(latitude: item.latitude, longitude: item.longitude) {
            case .success:
                do {
                    try await queueStore.removePending(gridLatitude: item.gridLatitude, gridLongitude: item.gridLongitude)
                    completed += 1
                } catch {
                    failed += 1
                }
            case .failure:
                failed += 1
            }
        }
        return GeocodeQueueProcessingReport(attemptedCount: items.count, completedCount: completed, failedCount: failed)
    }
}

private struct GridKey: Hashable {
    let latitude: Int
    let longitude: Int
}

public actor AppleReverseGeocodingAPI: ReverseGeocodingAPI {
    private let geocoder = CLGeocoder()

    public init() {}

    public func reverseGeocode(latitude: Double, longitude: Double) async -> APIResult<GeocodedLocation> {
        guard GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil else {
            return .failure(.invalidResponse("Invalid geocoding coordinates"))
        }
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: latitude, longitude: longitude),
                preferredLocale: Locale(identifier: "zh_Hans")
            )
            guard let placemark = placemarks.first else {
                return .failure(.emptyBody)
            }
            return .success(GeocodedLocation(
                address: [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", "),
                countryCode: placemark.isoCountryCode,
                countryName: placemark.country,
                regionName: placemark.administrativeArea ?? placemark.subAdministrativeArea,
                city: placemark.locality ?? placemark.subLocality
            ))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
