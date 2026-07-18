@preconcurrency import BackgroundTasks
import SwiftUI

@main
struct MateDroidApp: App {
    private let environment: AppEnvironment
    private let backgroundScheduler: BackgroundSyncScheduler

    init() {
        let environment = AppEnvironment.live
        let scheduler = BackgroundSyncScheduler()
        let dataPreloader = AppDataPreloader(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            activitiesCache: ActivitiesStateCache.shared
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
                )
            ),
            sessionStore: DatabaseBackedSmartActivityStore(databaseProvider: environment.databaseProvider),
            labelStore: DatabaseBackedActivityLabelOverrideStore(databaseProvider: environment.databaseProvider)
        )

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
                _ = await dataPreloader.preload()
                return !Task.isCancelled
            },
            rebuildSmartActivities: { carIds in
                let report = await smartActivityIndexer.rebuild(carIds: carIds)
                return report.failedCarIds.isEmpty
                    && report.completedCarIds.count + report.unchangedCarIds.count == report.attemptedCarIds.count
            }
        )

        _ = scheduler.register { task in
            let completion = BackgroundRefreshTaskCompletion(task: task)
            let work = Task {
                let report = await refreshRunner.run()
                try? scheduler.scheduleAppRefresh(earliestBeginDate: Date().addingTimeInterval(30 * 60))
                completion.finish(success: report.isSuccessful)
            }
            task.expirationHandler = {
                work.cancel()
                completion.finish(success: false)
            }
        }
        try? scheduler.scheduleAppRefresh(earliestBeginDate: Date().addingTimeInterval(30 * 60))
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
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
