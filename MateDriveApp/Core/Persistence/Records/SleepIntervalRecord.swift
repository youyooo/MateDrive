import Foundation

public struct SleepIntervalRecord: Equatable, Sendable {
    public let carId: Int
    public let startDate: String
    public let endDate: String

    public init(carId: Int, startDate: String, endDate: String) {
        self.carId = carId
        self.startDate = startDate
        self.endDate = endDate
    }
}
