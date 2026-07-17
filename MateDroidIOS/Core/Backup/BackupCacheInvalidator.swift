import Foundation
import WidgetKit

public protocol BackupCacheInvalidating: Sendable {
    func invalidateAfterRestore() async throws
}

public struct NoopBackupCacheInvalidator: BackupCacheInvalidating {
    public init() {}
    public func invalidateAfterRestore() async throws {}
}

public struct NoopAppDataSyncSuspender: AppDataSyncSuspending {
    public init() {}
    public func suspendAndWait() async {}
    public func resume() async {}
}

public struct LiveBackupCacheInvalidator: BackupCacheInvalidating {
    private let responseCache: HTTPResponseCache
    private let dashboardStore: DashboardSnapshotStore
    private let activitiesCache: ActivitiesStateCache
    private let widgetSnapshotStore: WidgetSnapshotStore

    public init(
        responseCache: HTTPResponseCache = .shared,
        dashboardStore: DashboardSnapshotStore = .shared,
        activitiesCache: ActivitiesStateCache = .shared,
        widgetSnapshotStore: WidgetSnapshotStore = .shared
    ) {
        self.responseCache = responseCache
        self.dashboardStore = dashboardStore
        self.activitiesCache = activitiesCache
        self.widgetSnapshotStore = widgetSnapshotStore
    }

    public func invalidateAfterRestore() async throws {
        async let responseCleanup: Void = responseCache.removeAll()
        async let dashboardCleanup: Void = dashboardStore.clearAll()
        async let activitiesCleanup: Void = activitiesCache.removeAll()
        _ = await (responseCleanup, dashboardCleanup, activitiesCleanup)
        DriveDetailStateCache.shared.removeAll()
        ChargeDetailStateCache.shared.removeAll()
        widgetSnapshotStore.remove()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

public extension Notification.Name {
    static let mateDriveCloudRestoreCompleted = Notification.Name(
        "MateDriveCloudRestoreCompleted"
    )
}
