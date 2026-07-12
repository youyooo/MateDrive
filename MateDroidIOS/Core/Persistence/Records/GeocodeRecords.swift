import Foundation

public struct GeocodeCacheRecord: Equatable, Sendable {
    public let cacheKey: String
    public let latitude: Double
    public let longitude: Double
    public let payloadJSON: String
    public let updatedAt: String
}

public struct GeocodeQueueRecord: Equatable, Sendable {
    public let cacheKey: String
    public let latitude: Double
    public let longitude: Double
    public let createdAt: String
}

public struct GeocodeProgressRecord: Equatable, Sendable {
    public let carId: Int
    public let lastProcessedAt: String?
}
