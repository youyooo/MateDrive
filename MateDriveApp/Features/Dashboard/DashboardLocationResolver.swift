import Foundation

public protocol DashboardLocationResolving: Sendable {
    func address(carId: Int, latitude: Double, longitude: Double) async -> String?
}

public struct CachedDashboardLocationResolver: DashboardLocationResolving {
    private let service: GeocodingService
    private let allowsNetworkLookup: Bool

    public init(
        queueStore: any GeocodeQueueStoring,
        reverseGeocoder: any ReverseGeocodingAPI,
        allowsNetworkLookup: Bool = true
    ) {
        service = GeocodingService(queueStore: queueStore, reverseGeocoder: reverseGeocoder)
        self.allowsNetworkLookup = allowsNetworkLookup
    }

    public func address(carId: Int, latitude: Double, longitude: Double) async -> String? {
        if let cached = await service.cachedLocation(latitude: latitude, longitude: longitude) {
            return Self.displayAddress(cached)
        }
        do {
            _ = try await service.enqueueLocations(
                carId: carId,
                locations: [GeocodeLocation(latitude: latitude, longitude: longitude)]
            )
        } catch {
            return nil
        }
        guard allowsNetworkLookup else { return nil }
        _ = await service.processPending(limit: 6)
        guard let resolved = await service.cachedLocation(latitude: latitude, longitude: longitude) else {
            return nil
        }
        return Self.displayAddress(resolved)
    }

    private static func displayAddress(_ location: GeocodedLocation) -> String? {
        for candidate in [location.address, location.city, location.regionName, location.countryName] {
            if let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
