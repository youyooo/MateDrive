import Foundation

public enum TeslaMateCapabilityPresentation {
    public static let enhancedFeatureMinimumVersion = TeslaMateAPIVersion(major: 2, minor: 5, patch: 0)
    public static let enhancedFeatureMinimumDisplayVersion = "2.5"

    public static let visibleCapabilities: [TeslaMateCapability] = [
        .serverStats, .costReview, .unifiedActivities, .batteryHealthHistory, .driveInsights, .environmentHistory, .topDrainLocations, .commuteRoutes, .statsExtremes, .drivingCoordinates, .serverPlaces
    ]

    public static func titleLocalizationKey(for capability: TeslaMateCapability) -> String {
        switch capability {
        case .serverStats: "Server Statistics"
        case .costReview: "Vehicle Cost Review"
        case .unifiedActivities: "Unified Activities"
        case .batteryHealthHistory: "Battery History"
        case .driveInsights: "Drive Insights"
        case .environmentHistory: "Environment History"
        case .topDrainLocations: "Standby Hotspots"
        case .commuteRoutes: "Commute Routes"
        case .statsExtremes: "Driving Records"
        case .drivingCoordinates: "Recent Driving Map"
        case .serverPlaces: "Smart Places"
        default: capability.rawValue
        }
    }

    public static func stateLocalizationKey(for state: TeslaMateCapabilityState) -> String {
        switch state {
        case .available: "Available"
        case .degraded: "Limited"
        case .unavailable: "Unavailable"
        case .unknown: "Unknown"
        }
    }

    public static func icon(for state: TeslaMateCapabilityState) -> String {
        switch state {
        case .available: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .unavailable: "minus.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

    public static func meetsEnhancedFeatureMinimum(_ version: TeslaMateVersionInfo) -> Bool? {
        version.resolvedVersion.map { $0 >= enhancedFeatureMinimumVersion }
    }
}
