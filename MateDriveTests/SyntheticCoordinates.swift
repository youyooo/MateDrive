import Foundation

struct SyntheticCoordinate: Equatable {
    let northing: Double
    let easting: Double

    var latitude: Double { northing }
    var longitude: Double { easting }
}

enum SyntheticCoordinates {
    static let zero = SyntheticCoordinate(northing: 0, easting: 0)
    static let invalidLatitude = 90.0 + 1.0
    static let invalidLongitude = 180.0 + 1.0
    static let positiveFractionalGridSample = 48.0 + 0.8566
    static let negativeFractionalGridSample = -(122.0 + 0.4194)

    static func point(latitudeOffset: Double = 0, longitudeOffset: Double = 0) -> SyntheticCoordinate {
        SyntheticCoordinate(northing: 12.0 + latitudeOffset, easting: 34.0 + longitudeOffset)
    }
}
