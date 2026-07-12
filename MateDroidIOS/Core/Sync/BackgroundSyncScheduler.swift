@preconcurrency import BackgroundTasks
import Foundation

public protocol BackgroundSyncScheduling: Sendable {
    func register(launchHandler: @escaping @Sendable (BGAppRefreshTask) -> Void) -> Bool
    func scheduleAppRefresh(earliestBeginDate: Date?) throws
}

public struct BackgroundSyncScheduler: BackgroundSyncScheduling, @unchecked Sendable {
    public static let syncTaskIdentifier = "com.matedrive.ios.sync"

    private let scheduler: BGTaskScheduler
    private let taskIdentifier: String

    public init(scheduler: BGTaskScheduler = .shared, taskIdentifier: String = Self.syncTaskIdentifier) {
        self.scheduler = scheduler
        self.taskIdentifier = taskIdentifier
    }

    public func register(launchHandler: @escaping @Sendable (BGAppRefreshTask) -> Void) -> Bool {
        scheduler.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            launchHandler(refreshTask)
        }
    }

    public func scheduleAppRefresh(earliestBeginDate: Date? = nil) throws {
        // iOS background refresh is best-effort and cannot mirror Android foreground
        // services' cadence. We register and reschedule work, then let the system
        // decide actual execution windows.
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        try scheduler.submit(request)
    }
}
