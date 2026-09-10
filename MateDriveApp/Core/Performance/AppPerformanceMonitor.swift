import Foundation
import os

struct NavigationPerformanceResult: Equatable, Sendable {
    let routeName: String
    let duration: TimeInterval
    let exceededBudget: Bool
}

@MainActor
final class NavigationPerformanceTracker {
    static let defaultBudget: TimeInterval = 0.5

    private struct PendingInterval {
        let signpostID: OSSignpostID?
        let startedAt: TimeInterval
        let routeName: String
    }

    private let log: OSLog
    private let logger: Logger
    private let now: @MainActor () -> TimeInterval
    private let budget: TimeInterval
    private let emitsSignposts: Bool
    private let onCompleted: @MainActor (NavigationPerformanceResult) -> Void
    private var pending: [AppRoute: PendingInterval] = [:]

    init(
        budget: TimeInterval = NavigationPerformanceTracker.defaultBudget,
        emitsSignposts: Bool = true,
        now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        onCompleted: @escaping @MainActor (NavigationPerformanceResult) -> Void = { _ in }
    ) {
        self.log = OSLog(subsystem: AppPerformanceMonitor.subsystem, category: "Navigation")
        self.logger = Logger(subsystem: AppPerformanceMonitor.subsystem, category: "Navigation")
        self.now = now
        self.budget = budget
        self.emitsSignposts = emitsSignposts
        self.onCompleted = onCompleted
    }

    func begin(_ route: AppRoute) {
        guard pending[route] == nil else { return }
        let routeName = route.performanceName
        let signpostID = emitsSignposts ? OSSignpostID(log: log) : nil
        if let signpostID {
            os_signpost(
                .begin,
                log: log,
                name: "CachedNavigation",
                signpostID: signpostID,
                "route=%{public}s",
                routeName
            )
        }
        pending[route] = PendingInterval(
            signpostID: signpostID,
            startedAt: now(),
            routeName: routeName
        )
    }

    func destinationAppeared(_ route: AppRoute) {
        guard let interval = pending.removeValue(forKey: route) else { return }
        let duration = max(now() - interval.startedAt, 0)
        if let signpostID = interval.signpostID {
            os_signpost(
                .end,
                log: log,
                name: "CachedNavigation",
                signpostID: signpostID,
                "route=%{public}s duration_ms=%{public}.1f",
                interval.routeName,
                duration * 1_000
            )
        }
        let result = NavigationPerformanceResult(
            routeName: interval.routeName,
            duration: duration,
            exceededBudget: duration > budget
        )
        if result.exceededBudget {
            logger.warning(
                "Cached navigation exceeded budget: route=\(interval.routeName, privacy: .public) duration_ms=\(duration * 1_000, privacy: .public)"
            )
        }
        onCompleted(result)
    }
}

final class AppLaunchPerformanceMonitor: @unchecked Sendable {
    static let shared = AppLaunchPerformanceMonitor()

    private let log = OSLog(subsystem: AppPerformanceMonitor.subsystem, category: "Launch")
    private let lock = NSLock()
    private var signpostID: OSSignpostID?
    private var didFinish = false

    private init() {}

    func beginIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard signpostID == nil, !didFinish else { return }
        let id = OSSignpostID(log: log)
        signpostID = id
        os_signpost(.begin, log: log, name: "LaunchToCachedContent", signpostID: id)
    }

    func cachedContentPresented() {
        lock.lock()
        guard !didFinish, let id = signpostID else {
            lock.unlock()
            return
        }
        didFinish = true
        signpostID = nil
        lock.unlock()
        os_signpost(.end, log: log, name: "LaunchToCachedContent", signpostID: id)
    }
}

enum AppPerformanceMonitor {
    static let subsystem = "com.matedrive.ios.performance"
}

extension AppRoute {
    var performanceName: String {
        switch self {
        case .settings: return "Settings"
        case .dashboard: return "Dashboard"
        case .palettePreview: return "Palette"
        case .charges: return "Charges"
        case .energyCycles: return "EnergyCycles"
        case .chargeDetail: return "ChargeDetail"
        case .compareCharges: return "CompareCharges"
        case .currentCharge: return "CurrentCharge"
        case .activities: return "Activities"
        case .activitySession: return "ActivitySession"
        case .places: return "Places"
        case .achievements: return "Achievements"
        case .drives: return "Drives"
        case .recentDrivingMap: return "RecentDrivingMap"
        case .driveDetail: return "DriveDetail"
        case let .driveMetricDetail(_, _, metric, _): return "DriveMetric.\(metric.rawValue)"
        case .compareDrives: return "CompareDrives"
        case .battery: return "Battery"
        case .mileage: return "Mileage"
        case .updates: return "Updates"
        case .stats: return "Stats"
        case .costReview: return "CostReview"
        case .drivingRecords: return "DrivingRecords"
        case .driveInsights: return "DriveInsights"
        case .environmentHistory: return "EnvironmentHistory"
        case .topDrainLocations: return "TopDrainLocations"
        case .commuteRoutes: return "CommuteRoutes"
        case .countriesVisited: return "CountriesVisited"
        case .regionsVisited: return "RegionsVisited"
        case .whereWasI: return "WhereWasI"
        case .trips: return "Trips"
        case .createTrip: return "CreateTrip"
        case .tripDetail: return "TripDetail"
        case .sentryHistory: return "SentryHistory"
        }
    }
}
