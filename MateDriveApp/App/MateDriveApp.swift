@preconcurrency import BackgroundTasks
import SwiftUI

@main
struct MateDriveApp: App {
    @StateObject private var purchaseManager: StoreKitPurchaseManager
    private let environment: AppEnvironment
    private let backgroundScheduler: BackgroundSyncScheduler
    private let dataSyncCoordinator: AppDataSyncCoordinator
    private let liveActivityCoordinator: ChargeLiveActivityCoordinator
    private let cloudBackupCoordinator: CloudBackupCoordinator
    private let smartActivityIndexer: SmartActivityIndexer

    init() {
        AppLaunchPerformanceMonitor.shared.beginIfNeeded()
        _purchaseManager = StateObject(wrappedValue: StoreKitPurchaseManager())
        let environment = AppEnvironment.live
        let scheduler = BackgroundSyncScheduler()
        let liveActivityCoordinator = ChargeLiveActivityCoordinator(
            manager: SystemChargeLiveActivityManager.shared
        )
        self.liveActivityCoordinator = liveActivityCoordinator
        let dataPreloader = AppDataPreloader(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            liveActivityCoordinator: liveActivityCoordinator,
            activitiesCache: ActivitiesStateCache.shared,
            databaseProvider: environment.databaseProvider
        )
        self.environment = environment
        self.backgroundScheduler = scheduler
        let smartActivityIndexer = SmartActivityIndexer(
            source: CachedSmartActivitySourceLoader(
                activitiesCache: ActivitiesStateCache.shared,
                sleepIntervalStore: DatabaseBackedSleepIntervalStore(databaseProvider: environment.databaseProvider),
                settingsStore: environment.settingsStore,
                chargeCostOverrideStore: DatabaseBackedChargeCostOverrideStore(
                    databaseProvider: environment.databaseProvider
                ),
                chargePricingAggregateStore: DatabaseBackedChargePricingAggregateStore(
                    databaseProvider: environment.databaseProvider
                )
            ),
            sessionStore: DatabaseBackedSmartActivityStore(databaseProvider: environment.databaseProvider),
            labelStore: DatabaseBackedActivityLabelOverrideStore(databaseProvider: environment.databaseProvider)
        )
        self.smartActivityIndexer = smartActivityIndexer

        let refreshRunner = BackgroundRefreshWorkRunner(
            historySyncRunner: HistorySyncRunner(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore,
                databaseProvider: environment.databaseProvider
            ),
            refreshVehicleStatus: {
                guard !Task.isCancelled else { return false }
                let viewModel = await MainActor.run {
                    DashboardViewModel(
                        api: SettingsBackedDashboardAPI(
                            settingsStore: environment.settingsStore,
                            secretStore: environment.secretStore
                        ),
                        settingsStore: environment.settingsStore,
                        notificationService: environment.notificationService,
                        sentryAlertStore: DatabaseBackedSentryAlertLogStore(databaseProvider: environment.databaseProvider),
                        locationResolver: CachedDashboardLocationResolver(
                            queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider),
                            reverseGeocoder: AppleReverseGeocodingAPI()
                        )
                    )
                }
                await viewModel.load()
                let statusRefreshed = await MainActor.run {
                    viewModel.state.selectedCarId != nil && viewModel.state.errorMessage == nil
                }
                guard statusRefreshed, !Task.isCancelled else { return false }
                let preloadReport = await dataPreloader.preload()
                return !Task.isCancelled && preloadReport.canIndexSmartActivities
            },
            rebuildSmartActivities: { carIds in
                let report = await smartActivityIndexer.rebuild(carIds: carIds)
                return report.failedCarIds.isEmpty
                    && report.completedCarIds.count + report.unchangedCarIds.count == report.attemptedCarIds.count
            }
        )
        let dataSyncCoordinator = AppDataSyncCoordinator(workRunner: refreshRunner)
        self.dataSyncCoordinator = dataSyncCoordinator
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
#if MATEDRIVE_DISABLE_CLOUDKIT
        let cloudBackupService: any CloudBackupServicing = UnavailableCloudBackupService()
#else
        let cloudBackupService: any CloudBackupServicing = CloudKitBackupService()
#endif
        let cloudBackupCoordinator = CloudBackupCoordinator(
            service: cloudBackupService,
            databaseProvider: DatabaseBackupProvider(
                databaseProvider: environment.databaseProvider,
                settingsStore: environment.settingsStore
            ),
            preferencesStore: UserDefaultsCloudBackupPreferencesStore(),
            syncController: dataSyncCoordinator,
            cacheInvalidator: LiveBackupCacheInvalidator(),
            appVersion: { appVersion },
            didRestore: {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .mateDriveCloudRestoreCompleted,
                        object: nil
                    )
                }
            }
        )
        self.cloudBackupCoordinator = cloudBackupCoordinator

        _ = scheduler.register { task in
            let completion = BackgroundRefreshTaskCompletion(task: task)
            let work = Task {
                _ = await dataSyncCoordinator.start()
                let report = await dataSyncCoordinator.waitUntilIdle()
                if let report {
                    _ = await cloudBackupCoordinator.createAutomaticBackup(after: report)
                }
                try? scheduler.scheduleAppRefresh(earliestBeginDate: Date().addingTimeInterval(30 * 60))
                completion.finish(success: report?.isSuccessful == true)
            }
            task.expirationHandler = {
                work.cancel()
                Task {
                    await dataSyncCoordinator.cancel()
                }
                completion.finish(success: false)
            }
        }
        _ = scheduler.registerFullSync { task in
            let completion = BackgroundProcessingTaskCompletion(task: task)
            let work = Task {
                _ = await dataSyncCoordinator.start()
                let report = await dataSyncCoordinator.waitUntilIdle()
                if let report {
                    _ = await cloudBackupCoordinator.createAutomaticBackup(after: report)
                }
                try? scheduler.scheduleFullSync(earliestBeginDate: Date().addingTimeInterval(30 * 60))
                completion.finish(success: report?.isSuccessful == true)
            }
            task.expirationHandler = {
                work.cancel()
                Task {
                    await dataSyncCoordinator.cancel()
                }
                completion.finish(success: false)
            }
        }
        try? scheduler.scheduleAppRefresh(earliestBeginDate: Date().addingTimeInterval(30 * 60))
        try? scheduler.scheduleFullSync(earliestBeginDate: Date().addingTimeInterval(15 * 60))
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                environment: environment,
                dataSyncCoordinator: dataSyncCoordinator,
                liveActivityCoordinator: liveActivityCoordinator,
                cloudBackupCoordinator: cloudBackupCoordinator,
                smartActivityIndexer: smartActivityIndexer
            )
            .environmentObject(purchaseManager)
        }
    }
}

private final class BackgroundProcessingTaskCompletion: @unchecked Sendable {
    private let task: BGProcessingTask
    private let lock = NSLock()
    private var didFinish = false

    init(task: BGProcessingTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}

private final class BackgroundRefreshTaskCompletion: @unchecked Sendable {
    private let task: BGAppRefreshTask
    private let lock = NSLock()
    private var didFinish = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        lock.unlock()
        task.setTaskCompleted(success: success)
    }
}
