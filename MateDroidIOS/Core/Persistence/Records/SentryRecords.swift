import Foundation

public struct SentryAlertLogRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let detectedAtMillis: Int64
    public let sessionStartedAtMillis: Int64?
    public let latitude: Double?
    public let longitude: Double?
    public let address: String?

    public init(
        id: String,
        carId: Int,
        detectedAtMillis: Int64,
        sessionStartedAtMillis: Int64? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        address: String? = nil
    ) {
        self.id = id
        self.carId = carId
        self.detectedAtMillis = detectedAtMillis
        self.sessionStartedAtMillis = sessionStartedAtMillis
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
    }
}

public struct SentryHourlyCount: Equatable, Sendable {
    public let hourBucket: Int64
    public let count: Int

    public init(hourBucket: Int64, count: Int) {
        self.hourBucket = hourBucket
        self.count = count
    }
}
