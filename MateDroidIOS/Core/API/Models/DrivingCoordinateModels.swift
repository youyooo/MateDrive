import Foundation

public struct DrivingCoordinatesResponse: Decodable, Equatable, Sendable {
    public let data: DrivingCoordinatesData
}

public struct DrivingCoordinatesData: Decodable, Equatable, Sendable {
    public let carId: Int?
    public let coordinates: [DrivingCoordinate]
    public let originalPoints: Int?
    public let simplifiedPoints: Int?
    public let units: DrivingCoordinateUnits?
}

public struct DrivingCoordinate: Decodable, Equatable, Sendable {
    public let driveId: Int?
    public let latitude: Double?
    public let longitude: Double?
    public let speed: Double?
    public let elevation: Double?
    public let outsideTemp: Double?
    public let date: String?
    public let type: String?
}

public struct DrivingCoordinateUnits: Decodable, Equatable, Sendable {
    public let length: String?
    public let temperature: String?
}
