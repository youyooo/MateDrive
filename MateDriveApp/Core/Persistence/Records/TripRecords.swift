import Foundation

public struct TripRouteCacheRecord: Equatable, Sendable {
    public let cacheKey: String
    public let payloadJSON: String
    public let updatedAt: String
}

public struct TripCountryCacheRecord: Equatable, Sendable {
    public let cacheKey: String
    public let payloadJSON: String
    public let updatedAt: String
}

public struct SavedTripRecord: Equatable, Sendable {
    public let tripId: String
    public let carId: Int
    public let name: String
    public let startDate: String
    public let endDate: String
}

public struct SavedTripLegRecord: Equatable, Sendable {
    public let legId: String
    public let tripId: String
    public let sequence: Int
    public let payloadJSON: String
}

public struct SavedTripConsumedFingerprintRecord: Equatable, Sendable {
    public let tripId: String
    public let fingerprint: String
}
