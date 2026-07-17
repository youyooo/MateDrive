import Foundation

public struct VehicleStateHistoryResponse: Decodable, Equatable, Sendable {
    public let intervals: [VehicleStateInterval]

    private enum CodingKeys: String, CodingKey {
        case data
    }

    public init(from decoder: Decoder) throws {
        if let intervals = try? [VehicleStateInterval](from: decoder) {
            self.intervals = intervals
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        intervals = try container.decode(VehicleStateHistoryEnvelope.self, forKey: .data).states
    }
}

public struct VehicleStateInterval: Decodable, Equatable, Sendable {
    public let state: String
    public let startDate: String
    public let endDate: String?

    public func sleepInterval(now: Date) -> SleepInterval? {
        guard state.lowercased() == "asleep",
              let start = DomainDateParser.date(from: startDate)
        else {
            return nil
        }

        let end = endDate.flatMap(DomainDateParser.date(from:)) ?? now
        return start < end ? SleepInterval(start: start, end: end) : nil
    }
}

private struct VehicleStateHistoryEnvelope: Decodable {
    let states: [VehicleStateInterval]
}
