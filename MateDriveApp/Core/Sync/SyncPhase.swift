import Foundation

public enum SyncPhase: Equatable, Sendable {
    case idle
    case syncingSummaries
    case syncingDriveDetails
    case syncingChargeDetails
    case geocoding
    case complete
    case error(String)
}
