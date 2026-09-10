@preconcurrency import BackgroundTasks
import Foundation

public protocol BackgroundSyncScheduling: Sendable {
    func register(launchHandler: @escaping @Sendable (BGAppRefreshTask) -> Void) -> Bool
    func registerFullSync(launchHandler: @escaping @Sendable (BGProcessingTask) -> Void) -> Bool
    func scheduleAppRefresh(earliestBeginDate: Date?) throws
    func scheduleFullSync(earliestBeginDate: Date?) throws
}

public struct BackgroundSyncScheduler: BackgroundSyncScheduling, @unchecked Sendable {
    public static let syncTaskIdentifier = "com.matedrive.ios.sync"
    public static let fullSyncTaskIdentifier = "com.matedrive.ios.full-sync"

    private let scheduler: BGTaskScheduler
    private let taskIdentifier: String
    private let fullSyncTaskIdentifier: String

    public init(
        scheduler: BGTaskScheduler = .shared,
        taskIdentifier: String = Self.syncTaskIdentifier,
        fullSyncTaskIdentifier: String = Self.fullSyncTaskIdentifier
    ) {
        self.scheduler = scheduler
        self.taskIdentifier = taskIdentifier
        self.fullSyncTaskIdentifier = fullSyncTaskIdentifier
    }

    public func registerFullSync(launchHandler: @escaping @Sendable (BGProcessingTask) -> Void) -> Bool {
        scheduler.register(forTaskWithIdentifier: fullSyncTaskIdentifier, using: nil) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            launchHandler(processingTask)
        }
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
        // Background refresh timing is system-managed. Register and reschedule the
        // work, then let iOS choose the actual execution window.
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        try scheduler.submit(request)
    }

    public func scheduleFullSync(earliestBeginDate: Date? = nil) throws {
        let request = BGProcessingTaskRequest(identifier: fullSyncTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try scheduler.submit(request)
    }
}
