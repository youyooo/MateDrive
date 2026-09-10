import Foundation

public struct StatsExtremesResponse: Decodable, Equatable, Sendable {
    public let extremes: [StatsExtreme]
    public let units: TeslaMateServerStatsUnits?
}

public struct StatsExtreme: Decodable, Equatable, Identifiable, Sendable {
    public var id: String { "\(type)-\(date ?? "")-\(driveId ?? -1)" }
    public let type: String
    public let value: Double?
    public let unit: String?
    public let date: String?
    public let driveId: Int?
}
