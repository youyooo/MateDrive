import SwiftUI
import UIKit

@MainActor
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let environment: AppEnvironment
    private let capabilityService: TeslaMateCapabilityService
    private let dataSyncCoordinator: AppDataSyncCoordinator
    private let liveActivityCoordinator: ChargeLiveActivityCoordinator
    private let cloudBackupCoordinator: any CloudBackupCoordinating
    private let smartActivityIndexer: any SmartActivityIndexing
    private let weatherService: WeatherService
    private let launchSnapshot: WidgetVehicleSnapshot?
    private let widgetNavigationVehicleRegistry: WidgetNavigationVehicleRegistry
    private let navigationPerformanceTracker = NavigationPerformanceTracker()
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var syncLifecycleController: AppDataSyncLifecycleController
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var activityTimelineViewModel: ActivityTimelineViewModel
    @State private var navigation = RootNavigationState()
    @State private var serverNavigationGate = ServerConfigurationNavigationGate()
    @State private var isLaunchExperienceVisible = true

    public init(
        environment: AppEnvironment,
        dataSyncCoordinator: AppDataSyncCoordinator,
        liveActivityCoordinator: ChargeLiveActivityCoordinator,
        cloudBackupCoordinator: any CloudBackupCoordinating,
        smartActivityIndexer: any SmartActivityIndexing,
        widgetNavigationVehicleRegistry: WidgetNavigationVehicleRegistry = .shared
    ) {
        self.environment = environment
        self.dataSyncCoordinator = dataSyncCoordinator
        self.liveActivityCoordinator = liveActivityCoordinator
        self.cloudBackupCoordinator = cloudBackupCoordinator
        self.smartActivityIndexer = smartActivityIndexer
        self.widgetNavigationVehicleRegistry = widgetNavigationVehicleRegistry
        self.weatherService = WeatherService(api: OpenMeteoAPI())
        self.launchSnapshot = WidgetSnapshotStore.shared.preferredVehicleSnapshot()
        let profileStore = DatabaseBackedTeslaMateServerProfileStore(databaseProvider: environment.databaseProvider)
        let capabilityService = TeslaMateCapabilityService(profileStore: profileStore)
        self.capabilityService = capabilityService
        let diagnostic = TeslaMateConnectionDiagnostic(capabilityDiscovery: capabilityService)
        let geographyStore = DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider)
        let geographyProcessor = GeocodingService(queueStore: geographyStore, reverseGeocoder: AppleReverseGeocodingAPI())
        let historySyncRunner = HistorySyncRunner(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            databaseProvider: environment.databaseProvider
        )
        _syncLifecycleController = StateObject(
            wrappedValue: AppDataSyncLifecycleController(
                coordinator: dataSyncCoordinator,
                didCompleteSync: { report in
                    _ = await cloudBackupCoordinator.createAutomaticBackup(after: report)
                }
            )
        )
        _settingsViewModel = StateObject(
            wrappedValue: SettingsViewModel(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore,
                connectionDiagnostic: diagnostic,
                serverProfileStore: profileStore,
                geographyHealthProvider: geographyStore,
                geographyQueueProcessor: geographyProcessor,
                historySyncHealthProvider: DatabaseBackedHistorySyncHealthProvider(databaseProvider: environment.databaseProvider),
                historySyncRunner: historySyncRunner,
                notificationService: environment.notificationService,
                syncController: dataSyncCoordinator
            )
        )
        _dashboardViewModel = StateObject(
            wrappedValue: DashboardViewModel(
                api: SettingsBackedDashboardAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ),
                settingsStore: environment.settingsStore,
                liveActivityCoordinator: liveActivityCoordinator,
                liveActivityActivationPolicy: .allowStart,
                notificationService: environment.notificationService,
                sentryAlertStore: DatabaseBackedSentryAlertLogStore(databaseProvider: environment.databaseProvider),
                summaryProvider: DashboardSummaryProvider(
                    databaseProvider: environment.databaseProvider,
                    settingsStore: environment.settingsStore
                ),
                locationResolver: CachedDashboardLocationResolver(
                    queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider),
                    reverseGeocoder: AppleReverseGeocodingAPI(),
                    allowsNetworkLookup: false
                )
            )
        )
        _activityTimelineViewModel = StateObject(
            wrappedValue: ActivityTimelineViewModel(
                sessionStore: DatabaseBackedSmartActivityStore(
                    databaseProvider: environment.databaseProvider
                ),
                settingsStore: environment.settingsStore
            )
        )
    }

    public var body: some View {
        Group {
            if settingsViewModel.settings.isConfigured {
                configuredTabs
            } else {
                NavigationStack(path: $navigation.settingsPath) {
                    SettingsView(
                        viewModel: settingsViewModel,
                        cloudBackupCoordinator: cloudBackupCoordinator,
                        smartActivityIndexer: smartActivityIndexer,
                        activityLabelStore: activityLabelStore(),
                        pricingObservationStore: chargePricingObservationStore(),
                        smartActivityCarIds: smartActivityCarIds,
                        isInitialSetup: true
                    )
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
                                .onAppear { navigationPerformanceTracker.destinationAppeared(route) }
                        }
                }
            }
        }
        .environment(\.locale, appLocale)
        .environment(\.appLanguage, settingsViewModel.settings.appLanguage)
        .environment(\.appDisplayUnitSystem, settingsViewModel.settings.displayUnitSystem)
        .overlay {
            if isLaunchExperienceVisible {
                LaunchExperienceView(snapshot: LaunchExperienceSnapshot(snapshot: launchSnapshot))
                    .transition(.opacity)
                    .zIndex(100)
                    .task {
                        #if DEBUG
                        if ProcessInfo.processInfo.environment["MATEDRIVE_HOLD_LAUNCH_EXPERIENCE"] == "1" {
                            return
                        }
                        if ProcessInfo.processInfo.environment["MATEDRIVE_SKIP_LAUNCH_EXPERIENCE"] == "1" {
                            isLaunchExperienceVisible = false
                            return
                        }
                        #endif
                        do {
                            try await Task.sleep(for: LaunchExperienceTiming.minimumDisplayDuration)
                        } catch {
                            return
                        }
                        if MateDriveMotion.animationsEnabled(reduceMotion: reduceMotion) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                isLaunchExperienceVisible = false
                            }
                        } else {
                            isLaunchExperienceVisible = false
                        }
                    }
            }
        }
        .task {
            #if DEBUG
            await DebugLocalTeslamateSeeder.seedLaunchConfigurationIfNeeded(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore
            )
            #endif
            await settingsViewModel.loadEssentials()
            _ = serverNavigationGate.synchronize(
                serverURL: settingsViewModel.settings.serverURL
            )
            #if DEBUG
            if Self.isUITestMode {
                await DebugLocalTeslamateSeeder.seedDatabaseFixtureIfNeeded(
                    databaseProvider: environment.databaseProvider
                )
            }
            await applyStoreScreenshotRouteIfNeeded()
            if Self.isAutomatedTestMode
                || Self.isReservedTestServer(settingsViewModel.settings.serverURL)
            {
                return
            }
            #endif
            Task(priority: .utility) {
                await syncLifecycleController.appDidBecomeActive()
                await settingsViewModel.refreshOperationalState()
                await openPendingShortcutIfNeeded()
                await processPendingGeography()
                await refreshCapabilityProfileIfNeeded()
                let coordinator = dataSyncCoordinator
                _ = await coordinator.waitUntilIdle()
                await processPendingGeography()
                await settingsViewModel.refreshHistorySyncHealth()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    #if DEBUG
                    guard !Self.isAutomatedTestMode else { return }
                    #endif
                    await syncLifecycleController.appDidBecomeActive()
                    await openPendingShortcutIfNeeded()
                }
            case .background:
                syncLifecycleController.appDidEnterBackground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mateDriveShortcutNavigationRequested)) { _ in
            Task { await openPendingShortcutIfNeeded() }
        }
        .onOpenURL { url in
            Task { await openWidgetURL(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mateDriveCloudRestoreCompleted)) { _ in
            Task {
                await settingsViewModel.load()
                syncLifecycleController.publishRestoredDataRevision()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            releaseRebuildableMemoryCaches()
        }
        .onChange(of: syncLifecycleController.cacheRevision) {
            Task { await dashboardViewModel.load() }
        }
        .onChange(of: settingsViewModel.settings.serverURL) { _, current in
            guard serverNavigationGate.synchronize(serverURL: current) else { return }
            navigation = RootNavigationState()
            dashboardViewModel.resetForServerChange()
            releaseRebuildableMemoryCaches()
            Task {
                await syncLifecycleController.serverConfigurationDidChange()
                await dashboardViewModel.load()
            }
        }
        .onChange(of: settingsViewModel.connectionConfigurationRevision) {
            Task {
                await syncLifecycleController.serverConfigurationDidChange()
                await dashboardViewModel.load()
            }
        }
        .accessibilityIdentifier("root_view")
    }

    private var configuredTabs: some View {
        TabView(
            selection: Binding(
                get: { navigation.selectedTab },
                set: { navigation.selectTab($0) }
            )
        ) {
            NavigationStack(path: $navigation.homePath) {
                DashboardView(
                    viewModel: dashboardViewModel,
                    navigate: navigate(to:)
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .onAppear { navigationPerformanceTracker.destinationAppeared(route) }
                }
            }
            .tabItem {
                Label(t("Home", "首页"), systemImage: "house.fill")
                    .accessibilityIdentifier("root_tab_home")
            }
            .tag(RootTab.home)
            .accessibilityIdentifier("root_home_navigation")

            NavigationStack(path: $navigation.activityPath) {
                Group {
                    if let carId = dashboardViewModel.state.selectedCarId {
                        ActivityTimelineView(
                            carId: carId,
                            cacheRevision: syncLifecycleController.cacheRevision,
                            viewModel: activityTimelineViewModel,
                            navigate: navigate(to:)
                        )
                    } else {
                        ContentUnavailableView(
                            t("No vehicle selected", "尚未选择车辆"),
                            systemImage: "car"
                        )
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .onAppear { navigationPerformanceTracker.destinationAppeared(route) }
                }
            }
            .tabItem {
                Label(t("Activity", "动态"), systemImage: "clock.arrow.circlepath")
                    .accessibilityIdentifier("root_tab_activity")
            }
            .tag(RootTab.activity)
            .accessibilityIdentifier("root_activity_navigation")

            NavigationStack(path: $navigation.featuresPath) {
                FeatureHubView(
                    viewModel: dashboardViewModel,
                    navigate: navigate(to:)
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .onAppear { navigationPerformanceTracker.destinationAppeared(route) }
                }
            }
            .tabItem {
                Label(t("Features", "功能"), systemImage: "square.grid.2x2.fill")
                    .accessibilityIdentifier("root_tab_features")
            }
            .tag(RootTab.features)
            .accessibilityIdentifier("root_features_navigation")

            NavigationStack(path: $navigation.settingsPath) {
                SettingsView(
                    viewModel: settingsViewModel,
                    cloudBackupCoordinator: cloudBackupCoordinator,
                    smartActivityIndexer: smartActivityIndexer,
                    activityLabelStore: activityLabelStore(),
                    pricingObservationStore: chargePricingObservationStore(),
                    smartActivityCarIds: smartActivityCarIds
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                        .onAppear { navigationPerformanceTracker.destinationAppeared(route) }
                }
            }
            .tabItem {
                Label(t("Settings", "设置"), systemImage: "gearshape.fill")
                    .accessibilityIdentifier("root_tab_settings")
            }
            .tag(RootTab.settings)
            .accessibilityIdentifier("root_settings_navigation")
        }
        .tint(Color(red: 0.10, green: 0.68, blue: 0.32))
        .toolbarBackground(Color(uiColor: .systemBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private var appLocale: Locale {
        guard let localeIdentifier = settingsViewModel.settings.appLanguage.localeIdentifier else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: localeIdentifier)
    }

    private func navigate(to route: AppRoute) {
        navigationPerformanceTracker.begin(route)
        navigation.open(route, source: navigation.selectedTab)
    }

    private func releaseRebuildableMemoryCaches() {
        VehiclePageStateCacheRegistry.releaseMemory()
        DriveDetailStateCache.shared.removeAll()
        ChargeDetailStateCache.shared.removeAll()
        TripDetailStateCache.shared.removeAll()
        CompareDrivesStateCache.shared.removeAll()
        CompareChargesStateCache.shared.removeAll()
        Task(priority: .utility) {
            await HTTPResponseCache.shared.releaseMemory()
            await ActivitiesStateCache.shared.releaseMemory()
            await WeatherCache.shared.releaseMemory()
            await SoftwareUpdateSnapshotStore.shared.releaseMemory()
        }
    }

    #if DEBUG
    private static var isUITestMode: Bool {
        ProcessInfo.processInfo.environment["MATEDRIVE_UI_TEST_MODE"] == "1"
    }

    private static var isAutomatedTestMode: Bool {
        isUITestMode
            || ProcessInfo.processInfo.environment["MATEDRIVE_AUTOMATED_TEST_MODE"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    private static func isReservedTestServer(_ value: String) -> Bool {
        guard let host = URL(string: value)?.host?.lowercased() else { return false }
        return host == "invalid" || host.hasSuffix(".invalid")
    }

    private func applyStoreScreenshotRouteIfNeeded() async {
        let processEnvironment = ProcessInfo.processInfo.environment
        guard processEnvironment["MATEDRIVE_STORE_SCREENSHOT_MODE"] == "1",
              let route = processEnvironment["MATEDRIVE_STORE_SCREENSHOT_ROUTE"]
        else { return }

        await DebugLocalTeslamateSeeder.seedDatabaseFixtureIfNeeded(
            databaseProvider: environment.databaseProvider,
            environment: processEnvironment
        )
        await dashboardViewModel.load()

        switch route {
        case "dashboard":
            navigation = RootNavigationState(selectedTab: .home)
        case "activity":
            navigation = RootNavigationState(selectedTab: .activity)
        case "features":
            navigation = RootNavigationState(selectedTab: .features)
        case "drive-detail":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.driveDetail(carId: 1, driveId: 101, exteriorColor: nil)]
            )
        case "charge-detail":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.chargeDetail(carId: 1, chargeId: 201, exteriorColor: nil)]
            )
        case "battery":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.battery(carId: 1, efficiency: 146, exteriorColor: nil)]
            )
        case "stats":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.stats(carId: 1, exteriorColor: nil)]
            )
        case "mileage":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.mileage(carId: 1, exteriorColor: nil, targetDay: nil)]
            )
        case "places":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.places(carId: 1)]
            )
        case "drive-insights":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.driveInsights(carId: 1, exteriorColor: nil)]
            )
        case "environment":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.environmentHistory(carId: 1)]
            )
        case "standby-hotspots":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.topDrainLocations(carId: 1)]
            )
        case "commute-routes":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.commuteRoutes(carId: 1)]
            )
        case "achievements":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.achievements(carId: 1, exteriorColor: nil)]
            )
        case "updates":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.updates(carId: 1, exteriorColor: nil)]
            )
        case "sentry":
            navigation = RootNavigationState(
                selectedTab: .features,
                featuresPath: [.sentryHistory(carId: 1, exteriorColor: nil)]
            )
        default:
            assertionFailure("Unknown App Store screenshot route: \(route)")
        }
    }
    #endif

    private func openPendingShortcutIfNeeded() async {
        guard let destination = PendingShortcutNavigationStore.live.consume() else { return }
        let settings = await environment.settingsStore.load()
        let fallbackCarId = await shortcutFallbackCarId(settings: settings)
        let route = MateDriveShortcutRouter.route(
            destination: destination,
            settings: settings,
            fallbackCarId: fallbackCarId
        )
        if route == .settings, !settings.isConfigured {
            navigation.settingsPath.removeAll()
        } else {
            navigation.openShortcut(route)
        }
    }

    private func openWidgetURL(_ url: URL) async {
        guard let request = MateDriveWidgetNavigation.parse(url) else { return }
        let settings = await environment.settingsStore.load()
        let resolvedCarID = request.vehicleIdentifier.flatMap {
            widgetNavigationVehicleRegistry.resolve(
                serverURL: settings.serverURL,
                vehicleIdentifier: $0
            )
        }
        let route = WidgetNavigationRouter.route(
            request: request,
            settings: settings,
            resolvedCarID: resolvedCarID,
            fallbackCarID: dashboardViewModel.state.selectedCarId
        )
        navigation.openShortcut(route)
    }

    private func shortcutFallbackCarId(settings: AppSettings) async -> Int? {
        guard settings.isConfigured,
              settings.lastSelectedCarId == nil
        else { return nil }
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore
        )
        guard case let .success(api) = await factory.makeAPI(settings: settings),
              case let .success(cars) = await api.cars()
        else { return nil }
        return cars.first?.carId
    }

    private func refreshCapabilityProfileIfNeeded() async {
        let settings = await environment.settingsStore.load()
        guard settings.isConfigured else { return }
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore
        )
        guard case let .success(api) = await factory.makeAPI() else { return }

        let carId: Int
        if let selectedCarId = settings.lastSelectedCarId {
            carId = selectedCarId
        } else {
            guard case let .success(cars) = await api.cars(), let firstCar = cars.first else { return }
            carId = firstCar.carId
        }
        _ = await capabilityService.discover(api: api, carId: carId, force: false)
    }

    private func processPendingGeography() async {
        let service = GeocodingService(
            queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider),
            reverseGeocoder: AppleReverseGeocodingAPI()
        )
        _ = await service.processPending(limit: 6)
        await settingsViewModel.refreshGeographyHealth()
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsView(
                viewModel: settingsViewModel,
                cloudBackupCoordinator: cloudBackupCoordinator
            )
        case .dashboard:
            DashboardView(
                viewModel: dashboardViewModel,
                navigate: navigate(to:)
            )
        case .palettePreview:
            PalettePreviewView()
        case let .charges(carId, exteriorColor):
            ChargesView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: chargesViewModel(),
                navigate: navigate(to:)
            )
        case let .energyCycles(carId, exteriorColor):
            EnergyCyclesView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: EnergyCyclesViewModel(
                    provider: DatabaseBackedEnergyCycleDataProvider(databaseProvider: environment.databaseProvider),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                navigate: navigate(to:)
            )
        case let .chargeDetail(carId, chargeId, exteriorColor):
            let cacheKey = chargeDetailCacheKey(carId: carId, chargeId: chargeId)
            ChargeDetailView(
                carId: carId,
                chargeId: chargeId,
                exteriorColor: exteriorColor,
                viewModel: ChargeDetailViewModel(
                    api: chargeAPI(),
                    settingsStore: environment.settingsStore,
                    summaryCache: DatabaseBackedChargeSummaryCache(databaseProvider: environment.databaseProvider),
                    costOverrideStore: chargeCostOverrideStore(),
                    tripMembershipManager: tripMembershipService(),
                    cacheKey: cacheKey
                ),
                pricingService: chargePricingObservationService(),
                currencyCode: settingsViewModel.settings.resolvedCurrencyCode(),
                smartActivityIndexer: smartActivityIndexer,
                navigate: navigate(to:)
            )
        case let .compareCharges(carId, baseChargeId, _):
            let cacheKey = CompareChargesCacheKey(
                serverURL: settingsViewModel.settings.serverURL,
                carId: carId,
                baseChargeId: baseChargeId
            )
            CompareChargesView(
                carId: carId,
                baseChargeId: baseChargeId,
                viewModel: CompareChargesViewModel(
                    api: chargeAPI(),
                    costOverrideStore: chargeCostOverrideStore(),
                    settingsStore: environment.settingsStore,
                    historyProvider: mileageDataProvider(),
                    cacheKey: cacheKey
                )
            )
        case let .currentCharge(carId, _):
            CurrentChargeView(
                carId: carId,
                viewModel: CurrentChargeViewModel(
                    api: chargeAPI(),
                    liveActivityCoordinator: liveActivityCoordinator,
                    vehicleIdentifier: WidgetVehicleIdentity.identifier(
                        serverURL: settingsViewModel.settings.serverURL,
                        carID: carId
                    ),
                    displayLanguage: WidgetDisplayLanguage(
                        appLanguage: settingsViewModel.settings.appLanguage
                    ),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                )
            )
        case let .activities(carId, exteriorColor):
            ActivitiesView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: ActivitiesViewModel(api: SettingsBackedActivityAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), settingsStore: environment.settingsStore, cache: ActivitiesStateCache.shared,
                sleepSummaryProvider: DashboardSummaryProvider(databaseProvider: environment.databaseProvider),
                historyProvider: mileageDataProvider()),
                standbyDrainAPI: SettingsBackedActivityAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ),
                navigate: navigate(to:)
            )
        case let .activitySession(carId, sessionId):
            ActivitySessionDetailView(
                carId: carId,
                sessionId: sessionId,
                viewModel: ActivitySessionDetailViewModel(
                    sessionStore: DatabaseBackedSmartActivityStore(
                        databaseProvider: environment.databaseProvider
                    ),
                    labelStore: DatabaseBackedActivityLabelOverrideStore(
                        databaseProvider: environment.databaseProvider
                    ),
                    initialSession: activityTimelineViewModel.session(id: sessionId)
                ),
                standbyDrainAPI: SettingsBackedActivityAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ),
                labelStore: activityLabelStore(),
                pricingService: chargePricingObservationService(),
                currencyCode: settingsViewModel.settings.resolvedCurrencyCode(),
                smartActivityIndexer: smartActivityIndexer,
                navigate: navigate(to:)
            )
        case let .places(carId):
            let api = SettingsBackedActivityAPI(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore,
                networkPolicy: .cacheOnly
            )
            PlaceInsightsView(
                carId: carId,
                viewModel: PlaceInsightsViewModel(
                    api: api,
                    placesAPI: SettingsBackedServerPlacesAPI(
                        settingsStore: environment.settingsStore,
                        secretStore: environment.secretStore,
                        networkPolicy: .cacheOnly
                    ),
                    settingsStore: environment.settingsStore,
                    summaryProvider: DatabasePlaceActivitySummaryProvider(
                        databaseProvider: environment.databaseProvider
                    ),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                standbyDrainAPI: api,
                settingsViewModel: settingsViewModel
            )
        case let .achievements(carId, exteriorColor):
            AchievementsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: AchievementsViewModel(api: SettingsBackedAchievementsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), cacheKey: vehiclePageCacheKey(carId: carId)),
                navigate: navigate(to:)
            )
        case let .drives(carId, exteriorColor):
            DrivesView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: drivesViewModel(),
                detailCacheKey: { driveId in
                    driveDetailCacheKey(carId: carId, driveId: driveId)
                },
                navigate: navigate(to:)
            )
        case let .recentDrivingMap(carId, exteriorColor):
            RecentDrivingMapView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: RecentDrivingMapViewModel(api: SettingsBackedDrivingCoordinatesAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), cacheKey: vehiclePageCacheKey(carId: carId)),
                navigate: navigate
            )
        case let .driveDetail(carId, driveId, exteriorColor):
            let cacheKey = driveDetailCacheKey(carId: carId, driveId: driveId)
            DriveDetailView(
                carId: carId,
                driveId: driveId,
                exteriorColor: exteriorColor,
                viewModel: DriveDetailViewModel(
                    api: driveAPI(),
                    weatherService: weatherService,
                    tripMembershipManager: tripMembershipService(),
                    settingsStore: environment.settingsStore,
                    summaryCache: DatabaseBackedDriveSummaryCache(databaseProvider: environment.databaseProvider),
                    cacheKey: cacheKey
                ),
                navigate: navigate(to:)
            )
        case let .driveMetricDetail(carId, driveId, metric, _):
            let cacheKey = driveDetailCacheKey(carId: carId, driveId: driveId)
            DriveMetricDetailView(
                carId: carId,
                driveId: driveId,
                metric: metric,
                viewModel: DriveMetricDetailViewModel(
                    api: driveAPI(),
                    initialState: driveMetricInitialState(cacheKey: cacheKey)
                )
            )
        case let .compareDrives(carId, baseDriveId, _):
            let cacheKey = CompareDrivesCacheKey(
                serverURL: settingsViewModel.settings.serverURL,
                carId: carId,
                baseDriveId: baseDriveId
            )
            CompareDrivesView(
                carId: carId,
                baseDriveId: baseDriveId,
                viewModel: CompareDrivesViewModel(
                    api: driveAPI(),
                    historyProvider: mileageDataProvider(),
                    cacheKey: cacheKey
                )
            )
        case let .battery(carId, efficiency, _):
            BatteryView(
                carId: carId,
                viewModel: batteryViewModel(carId: carId, efficiency: efficiency)
            )
        case let .mileage(carId, exteriorColor, targetDay):
            MileageView(
                carId: carId,
                exteriorColor: exteriorColor,
                targetDay: targetDay,
                viewModel: MileageViewModel(
                    provider: DatabaseMileageDataProvider(
                        databaseProvider: environment.databaseProvider,
                        settingsStore: environment.settingsStore
                    ),
                    settingsStore: environment.settingsStore,
                    costOverrideStore: chargeCostOverrideStore(),
                    chargePricingAggregateStore: DatabaseBackedChargePricingAggregateStore(databaseProvider: environment.databaseProvider),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                navigate: navigate(to:)
            )
        case let .updates(carId, _):
            SoftwareUpdatesView(
                carId: carId,
                viewModel: SoftwareUpdatesViewModel(
                    api: analyticsAPI(),
                    settingsStore: environment.settingsStore,
                    snapshotStore: SoftwareUpdateSnapshotStore.shared,
                    cacheKey: vehiclePageCacheKey(carId: carId)
                )
            )
        case let .stats(carId, exteriorColor):
            StatsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: StatsViewModel(
                    api: analyticsAPI(),
                    settingsStore: environment.settingsStore,
                    costOverrideStore: chargeCostOverrideStore(),
                    chargePricingAggregateStore: DatabaseBackedChargePricingAggregateStore(databaseProvider: environment.databaseProvider),
                    activityAPI: SettingsBackedActivityAPI(
                        settingsStore: environment.settingsStore,
                        secretStore: environment.secretStore,
                        networkPolicy: .cacheOnly
                    ),
                    historyProvider: DatabaseMileageDataProvider(
                        databaseProvider: environment.databaseProvider,
                        settingsStore: environment.settingsStore
                    ),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                navigate: navigate(to:)
            )
        case let .costReview(carId, exteriorColor):
            CostReviewView(
                carId: carId,
                exteriorColor: exteriorColor,
                currencySymbol: MateDriveCurrencyFormatter.symbol(for: settingsViewModel.settings.resolvedCurrencyCode()),
                viewModel: CostReviewViewModel(api: SettingsBackedCostReviewAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), cacheKey: vehiclePageCacheKey(carId: carId)),
                navigate: navigate(to:)
            )
        case let .drivingRecords(carId, exteriorColor):
            DrivingRecordsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: DrivingRecordsViewModel(api: SettingsBackedDrivingRecordsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), cacheKey: vehiclePageCacheKey(carId: carId)),
                navigate: navigate
            )
        case let .driveInsights(carId, exteriorColor):
            DriveInsightsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: DriveInsightsViewModel(
                    api: SettingsBackedDriveInsightsAPI(
                        settingsStore: environment.settingsStore,
                        secretStore: environment.secretStore,
                        networkPolicy: .cacheOnly
                    ),
                    historyProvider: mileageDataProvider(),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                navigate: navigate(to:)
            )
        case let .environmentHistory(carId):
            EnvironmentHistoryView(
                carId: carId,
                viewModel: EnvironmentHistoryViewModel(api: SettingsBackedEnvironmentHistoryAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), cacheKey: vehiclePageCacheKey(carId: carId))
            )
        case let .topDrainLocations(carId):
            let activityAPI = standbyActivityAPI()
            TopDrainLocationsView(
                carId: carId,
                viewModel: TopDrainLocationsViewModel(
                    api: topDrainLocationsAPI(),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                standbyDrainAPI: activityAPI,
                standbyDrainCacheKey: { latitude, longitude in
                    vehiclePageCacheKey(
                        carId: carId,
                        scope: StandbyDrainViewModel.cacheScope(
                            latitude: latitude,
                            longitude: longitude
                        )
                    )
                }
            )
        case let .commuteRoutes(carId):
            CommuteRoutesView(
                carId: carId,
                viewModel: CommuteRoutesViewModel(api: SettingsBackedCommuteRoutesAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ), cacheKey: vehiclePageCacheKey(carId: carId))
            )
        case let .countriesVisited(carId, exteriorColor, year):
            CountriesVisitedView(
                carId: carId,
                exteriorColor: exteriorColor,
                year: year,
                viewModel: countriesVisitedViewModel(
                    cacheKey: vehiclePageCacheKey(
                        carId: carId,
                        scope: "countries:\(year.map(String.init) ?? "all")"
                    )
                ),
                navigate: navigate(to:)
            )
        case let .regionsVisited(carId, countryCode, countryName, _, year):
            RegionsVisitedView(
                carId: carId,
                countryName: countryName,
                year: year,
                viewModel: regionsVisitedViewModel(
                    cacheKey: vehiclePageCacheKey(
                        carId: carId,
                        scope: "regions:\(countryCode):\(year.map(String.init) ?? "all")"
                    )
                )
            )
        case let .whereWasI(carId, timestamp, exteriorColor):
            WhereWasIView(
                carId: carId,
                timestamp: timestamp,
                exteriorColor: exteriorColor,
                viewModel: WhereWasIViewModel(
                    api: analyticsAPI(),
                    historyProvider: mileageDataProvider(),
                    cacheKey: vehiclePageCacheKey(
                        carId: carId,
                        scope: "where-was-i:\(timestamp)"
                    )
                ),
                navigate: navigate(to:)
            )
        case let .trips(carId, exteriorColor):
            TripsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: TripsViewModel(
                    dataProvider: tripDataProvider(),
                    tripStore: tripStore(),
                    settingsStore: environment.settingsStore,
                    cacheKey: vehiclePageCacheKey(carId: carId)
                ),
                navigate: navigate(to:)
            )
        case let .createTrip(carId, exteriorColor):
            CreateTripView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: CreateTripViewModel(
                    tripStore: tripStore(),
                    dataProvider: tripDataProvider(),
                    cacheKey: vehiclePageCacheKey(
                        carId: carId,
                        scope: "create-trip"
                    )
                ),
                navigate: navigate(to:)
            )
        case let .tripDetail(carId, tripStartDate, exteriorColor):
            TripDetailView(
                carId: carId,
                tripStartDate: tripStartDate,
                exteriorColor: exteriorColor,
                viewModel: TripDetailViewModel(
                    dataProvider: tripDataProvider(),
                    tripStore: tripStore(),
                    settingsStore: environment.settingsStore,
                    cacheKey: TripDetailCacheKey(
                        serverURL: settingsViewModel.settings.serverURL,
                        carId: carId,
                        tripStartDate: tripStartDate
                    )
                ),
                navigate: navigate(to:)
            )
        case let .sentryHistory(carId, _):
            SentryHistoryView(
                carId: carId,
                viewModel: SentryHistoryViewModel(
                    store: sentryStore(),
                    cacheKey: vehiclePageCacheKey(carId: carId)
                )
            )
        }
    }

    private func chargesViewModel() -> ChargesViewModel {
        let api = chargeAPI()
        return ChargesViewModel(
            store: APIChargeSummaryProvider(
                api: api,
                cache: DatabaseBackedChargeSummaryCache(databaseProvider: environment.databaseProvider)
            ),
            settingsStore: environment.settingsStore,
            costOverrideStore: chargeCostOverrideStore(),
            chargePricingAggregateStore: DatabaseBackedChargePricingAggregateStore(databaseProvider: environment.databaseProvider),
            costUpdater: api,
            pricingAuditStore: DatabaseBackedChargePricingAuditStore(databaseProvider: environment.databaseProvider)
        )
    }

    private func chargeCostOverrideStore() -> any ChargeCostOverriding {
        DatabaseBackedChargeCostOverrideStore(databaseProvider: environment.databaseProvider)
    }

    private func activityLabelStore() -> DatabaseBackedActivityLabelOverrideStore {
        DatabaseBackedActivityLabelOverrideStore(databaseProvider: environment.databaseProvider)
    }

    private func chargePricingObservationStore() -> DatabaseBackedChargePricingObservationStore {
        DatabaseBackedChargePricingObservationStore(databaseProvider: environment.databaseProvider)
    }

    private func chargePricingObservationService() -> ChargePricingObservationService {
        ChargePricingObservationService(
            observationStore: chargePricingObservationStore(),
            costOverrideStore: chargeCostOverrideStore(),
            settingsStore: environment.settingsStore
        )
    }

    @MainActor
    private func smartActivityCarIds() -> [Int] {
        Array(Set(dashboardViewModel.state.cars.map(\.id) + [
            dashboardViewModel.state.selectedCarId,
            settingsViewModel.settings.lastSelectedCarId
        ].compactMap { $0 })).sorted()
    }

    private func chargeAPI() -> SettingsBackedChargeAPI {
        SettingsBackedChargeAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            networkPolicy: .cacheOnly
        )
    }

    private func chargeDetailCacheKey(carId: Int, chargeId: Int) -> ChargeDetailCacheKey {
        ChargeDetailCacheKey(
            serverURL: settingsViewModel.settings.serverURL,
            carId: carId,
            chargeId: chargeId
        )
    }

    private func drivesViewModel() -> DrivesViewModel {
        let api = driveAPI()
        return DrivesViewModel(
            store: APIDriveSummaryProvider(
                api: api,
                cache: DatabaseBackedDriveSummaryCache(databaseProvider: environment.databaseProvider)
            ),
            settingsStore: environment.settingsStore
        )
    }

    private func driveAPI() -> SettingsBackedDriveAPI {
        SettingsBackedDriveAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            networkPolicy: .cacheOnly
        )
    }

    private func driveDetailCacheKey(carId: Int, driveId: Int) -> DriveDetailCacheKey {
        DriveDetailCacheKey(
            serverURL: settingsViewModel.settings.serverURL,
            carId: carId,
            driveId: driveId
        )
    }

    private func vehiclePageCacheKey(carId: Int, scope: String = "") -> VehiclePageCacheKey {
        VehiclePageCacheKey(
            serverURL: settingsViewModel.settings.serverURL,
            carId: carId,
            scope: scope
        )
    }

    private func driveMetricInitialState(cacheKey: DriveDetailCacheKey) -> DriveMetricDetailState {
        guard let cached = DriveDetailStateCache.shared.state(for: cacheKey),
              let detail = cached.driveDetail
        else { return DriveMetricDetailState() }
        return DriveMetricDetailState(
            isLoading: false,
            driveDetail: detail,
            stats: cached.stats ?? DriveStatsCalculator.calculateStats(detail),
            units: cached.units
        )
    }

    private func analyticsAPI() -> SettingsBackedAnalyticsAPI {
        SettingsBackedAnalyticsAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            networkPolicy: .cacheOnly
        )
    }

    private func standbyActivityAPI() -> any ActivityAPIProviding {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MATEDRIVE_UI_TEST_MODE"] == "1" {
            return DebugUITestStandbyAPI()
        }
        #endif
        return SettingsBackedActivityAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            networkPolicy: .cacheOnly
        )
    }

    private func topDrainLocationsAPI() -> any TopDrainLocationsAPIProviding {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MATEDRIVE_UI_TEST_MODE"] == "1" {
            return DebugUITestStandbyAPI()
        }
        #endif
        return SettingsBackedTopDrainLocationsAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore,
            networkPolicy: .cacheOnly
        )
    }

    private func batteryViewModel(carId: Int, efficiency: Double?) -> BatteryViewModel {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MATEDRIVE_UI_TEST_MODE"] == "1" {
            return BatteryViewModel(
                api: DebugUITestAnalyticsAPI(),
                ratedEfficiencyFallback: efficiency,
                settingsStore: environment.settingsStore,
                historyProvider: mileageDataProvider(),
                cacheKey: vehiclePageCacheKey(carId: carId)
            )
        }
        #endif
        return BatteryViewModel(
            api: analyticsAPI(),
            ratedEfficiencyFallback: efficiency,
            settingsStore: environment.settingsStore,
            historyProvider: mileageDataProvider(),
            cacheKey: vehiclePageCacheKey(carId: carId)
        )
    }

    private func countriesVisitedViewModel(cacheKey: VehiclePageCacheKey) -> CountriesVisitedViewModel {
        let api = analyticsAPI()
        return CountriesVisitedViewModel(
            api: api,
            geographyEnricher: historicalGeographyEnricher(api: api),
            historyProvider: mileageDataProvider(),
            cacheKey: cacheKey
        )
    }

    private func regionsVisitedViewModel(cacheKey: VehiclePageCacheKey) -> RegionsVisitedViewModel {
        let api = analyticsAPI()
        return RegionsVisitedViewModel(
            api: api,
            geographyEnricher: historicalGeographyEnricher(api: api),
            historyProvider: mileageDataProvider(),
            cacheKey: cacheKey
        )
    }

    private func mileageDataProvider() -> DatabaseMileageDataProvider {
        DatabaseMileageDataProvider(
            databaseProvider: environment.databaseProvider,
            settingsStore: environment.settingsStore
        )
    }

    private func historicalGeographyEnricher(api: any AnalyticsAPIProviding) -> HistoricalGeographyEnricher {
        let geocoder = GeocodingService(
            queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider),
            reverseGeocoder: AppleReverseGeocodingAPI()
        )
        return HistoricalGeographyEnricher(api: api, geocoder: geocoder, maximumAddresses: 0)
    }

    private func tripDataProvider() -> CachedTripDataProvider {
        CachedTripDataProvider(
            summarySource: DatabaseBackedTripSummarySource(
                databaseProvider: environment.databaseProvider,
                settingsStore: environment.settingsStore
            ),
            routeProvider: APITripDataProvider(
                api: analyticsAPI(),
                routeCache: DatabaseBackedTripRouteCache(databaseProvider: environment.databaseProvider)
            )
        )
    }

    private func tripStore() -> DatabaseBackedTripStore {
        DatabaseBackedTripStore(databaseProvider: environment.databaseProvider)
    }

    private func tripMembershipService() -> TripMembershipService {
        TripMembershipService(dataProvider: tripDataProvider(), tripStore: tripStore())
    }

    private func sentryStore() -> DatabaseBackedSentryAlertLogStore {
        DatabaseBackedSentryAlertLogStore(databaseProvider: environment.databaseProvider)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: settingsViewModel.settings.appLanguage)
    }
}
