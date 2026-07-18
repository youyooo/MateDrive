import SwiftUI

@MainActor
public struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    private let environment: AppEnvironment
    private let capabilityService: TeslaMateCapabilityService
    private let dataSyncCoordinator: AppDataSyncCoordinator
    private let cloudBackupCoordinator: any CloudBackupCoordinating
    private let weatherService: WeatherService
    private let launchSnapshot: WidgetVehicleSnapshot?
    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var syncLifecycleController: AppDataSyncLifecycleController
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var activityTimelineViewModel: ActivityTimelineViewModel
    @State private var navigation = RootNavigationState()
    @State private var isLaunchExperienceVisible = true

    public init(
        environment: AppEnvironment,
        dataSyncCoordinator: AppDataSyncCoordinator,
        cloudBackupCoordinator: any CloudBackupCoordinating
    ) {
        self.environment = environment
        self.dataSyncCoordinator = dataSyncCoordinator
        self.cloudBackupCoordinator = cloudBackupCoordinator
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
                notificationService: environment.notificationService
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
                )
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
                        cloudBackupCoordinator: cloudBackupCoordinator
                    )
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route)
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
                        #endif
                        do {
                            try await Task.sleep(for: .milliseconds(1_450))
                        } catch {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.3)) {
                            isLaunchExperienceVisible = false
                        }
                    }
            }
        }
        .task {
            await syncLifecycleController.appDidBecomeActive()
            #if DEBUG
            await DebugLocalTeslamateSeeder.seedIfNeeded(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore
            )
            #endif
            await settingsViewModel.load()
            await openPendingShortcutIfNeeded()
            await processPendingGeography()
            await refreshCapabilityProfileIfNeeded()
            let coordinator = dataSyncCoordinator
            Task(priority: .utility) {
                _ = await coordinator.waitUntilIdle()
                await processPendingGeography()
                await settingsViewModel.refreshHistorySyncHealth()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
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
        .onReceive(NotificationCenter.default.publisher(for: .mateDriveCloudRestoreCompleted)) { _ in
            Task {
                await settingsViewModel.load()
                syncLifecycleController.publishRestoredDataRevision()
            }
        }
        .onChange(of: syncLifecycleController.cacheRevision) {
            Task { await dashboardViewModel.load() }
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
                }
            }
            .tabItem {
                Label(t("Home", "首页"), systemImage: "house.fill")
            }
            .tag(RootTab.home)

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
                }
            }
            .tabItem {
                Label(t("Activity", "动态"), systemImage: "clock.arrow.circlepath")
            }
            .tag(RootTab.activity)

            NavigationStack(path: $navigation.featuresPath) {
                FeatureHubView(
                    viewModel: dashboardViewModel,
                    navigate: navigate(to:)
                )
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
            }
            .tabItem {
                Label(t("Features", "功能"), systemImage: "square.grid.2x2.fill")
            }
            .tag(RootTab.features)

            NavigationStack(path: $navigation.settingsPath) {
                SettingsView(
                    viewModel: settingsViewModel,
                    cloudBackupCoordinator: cloudBackupCoordinator
                )
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem {
                Label(t("Settings", "设置"), systemImage: "gearshape.fill")
            }
            .tag(RootTab.settings)
        }
        .tint(Color(red: 0.10, green: 0.68, blue: 0.32))
    }

    private var appLocale: Locale {
        guard let localeIdentifier = settingsViewModel.settings.appLanguage.localeIdentifier else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: localeIdentifier)
    }

    private func navigate(to route: AppRoute) {
        navigation.open(route, source: navigation.selectedTab)
    }

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
                    provider: DatabaseBackedEnergyCycleDataProvider(databaseProvider: environment.databaseProvider)
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
                navigate: navigate(to:)
            )
        case let .compareCharges(carId, baseChargeId, _):
            CompareChargesView(
                carId: carId,
                baseChargeId: baseChargeId,
                viewModel: CompareChargesViewModel(
                    api: chargeAPI(),
                    costOverrideStore: chargeCostOverrideStore(),
                    settingsStore: environment.settingsStore
                )
            )
        case let .currentCharge(carId, _):
            CurrentChargeView(
                carId: carId,
                viewModel: CurrentChargeViewModel(
                    api: chargeAPI(),
                    liveActivityManager: SystemChargeLiveActivityManager.shared
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
                sleepSummaryProvider: DashboardSummaryProvider(databaseProvider: environment.databaseProvider)),
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
                    )
                ),
                standbyDrainAPI: SettingsBackedActivityAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ),
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
                    settingsStore: environment.settingsStore
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
                )),
                navigate: navigate(to:)
            )
        case let .drives(carId, exteriorColor):
            DrivesView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: drivesViewModel(),
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
                )),
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
            CompareDrivesView(
                carId: carId,
                baseDriveId: baseDriveId,
                viewModel: CompareDrivesViewModel(api: driveAPI())
            )
        case let .battery(carId, efficiency, _):
            BatteryView(
                carId: carId,
                viewModel: BatteryViewModel(
                    api: analyticsAPI(),
                    ratedEfficiencyFallback: efficiency,
                    settingsStore: environment.settingsStore
                )
            )
        case let .mileage(carId, exteriorColor, targetDay):
            MileageView(
                carId: carId,
                exteriorColor: exteriorColor,
                targetDay: targetDay,
                viewModel: MileageViewModel(
                    provider: APIMileageDataProvider(api: analyticsAPI()),
                    settingsStore: environment.settingsStore,
                    costOverrideStore: chargeCostOverrideStore(),
                    chargePricingAggregateStore: DatabaseBackedChargePricingAggregateStore(databaseProvider: environment.databaseProvider)
                ),
                navigate: navigate(to:)
            )
        case let .updates(carId, _):
            SoftwareUpdatesView(
                carId: carId,
                viewModel: SoftwareUpdatesViewModel(api: analyticsAPI())
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
                    )
                ),
                navigate: navigate(to:)
            )
        case let .costReview(carId, exteriorColor):
            CostReviewView(
                carId: carId,
                exteriorColor: exteriorColor,
                currencySymbol: MateDroidCurrencyFormatter.symbol(for: settingsViewModel.settings.resolvedCurrencyCode()),
                viewModel: CostReviewViewModel(api: SettingsBackedCostReviewAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                )),
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
                )),
                navigate: navigate
            )
        case let .driveInsights(carId, exteriorColor):
            DriveInsightsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: DriveInsightsViewModel(api: SettingsBackedDriveInsightsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                )),
                navigate: navigate(to:)
            )
        case let .environmentHistory(carId):
            EnvironmentHistoryView(
                carId: carId,
                viewModel: EnvironmentHistoryViewModel(api: SettingsBackedEnvironmentHistoryAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ))
            )
        case let .topDrainLocations(carId):
            let activityAPI = SettingsBackedActivityAPI(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore,
                networkPolicy: .cacheOnly
            )
            TopDrainLocationsView(
                carId: carId,
                viewModel: TopDrainLocationsViewModel(api: SettingsBackedTopDrainLocationsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                )),
                standbyDrainAPI: activityAPI
            )
        case let .commuteRoutes(carId):
            CommuteRoutesView(
                carId: carId,
                viewModel: CommuteRoutesViewModel(api: SettingsBackedCommuteRoutesAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore,
                    networkPolicy: .cacheOnly
                ))
            )
        case let .countriesVisited(carId, exteriorColor, year):
            CountriesVisitedView(
                carId: carId,
                exteriorColor: exteriorColor,
                year: year,
                viewModel: countriesVisitedViewModel(),
                navigate: navigate(to:)
            )
        case let .regionsVisited(carId, _, countryName, _, year):
            RegionsVisitedView(
                carId: carId,
                countryName: countryName,
                year: year,
                viewModel: regionsVisitedViewModel()
            )
        case let .whereWasI(carId, timestamp, exteriorColor):
            WhereWasIView(
                carId: carId,
                timestamp: timestamp,
                exteriorColor: exteriorColor,
                viewModel: WhereWasIViewModel(api: analyticsAPI()),
                navigate: navigate(to:)
            )
        case let .trips(carId, exteriorColor):
            TripsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: TripsViewModel(
                    dataProvider: tripDataProvider(),
                    tripStore: tripStore(),
                    settingsStore: environment.settingsStore
                ),
                navigate: navigate(to:)
            )
        case let .createTrip(carId, exteriorColor):
            CreateTripView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: CreateTripViewModel(
                    tripStore: tripStore(),
                    dataProvider: tripDataProvider()
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
                    settingsStore: environment.settingsStore
                ),
                navigate: navigate(to:)
            )
        case let .sentryHistory(carId, _):
            SentryHistoryView(
                carId: carId,
                viewModel: SentryHistoryViewModel(store: sentryStore())
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

    private func countriesVisitedViewModel() -> CountriesVisitedViewModel {
        let api = analyticsAPI()
        return CountriesVisitedViewModel(api: api, geographyEnricher: historicalGeographyEnricher(api: api))
    }

    private func regionsVisitedViewModel() -> RegionsVisitedViewModel {
        let api = analyticsAPI()
        return RegionsVisitedViewModel(api: api, geographyEnricher: historicalGeographyEnricher(api: api))
    }

    private func historicalGeographyEnricher(api: any AnalyticsAPIProviding) -> HistoricalGeographyEnricher {
        let geocoder = GeocodingService(
            queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider),
            reverseGeocoder: AppleReverseGeocodingAPI()
        )
        return HistoricalGeographyEnricher(api: api, geocoder: geocoder, maximumAddresses: 0)
    }

    private func tripDataProvider() -> APITripDataProvider {
        APITripDataProvider(
            api: analyticsAPI(),
            routeCache: DatabaseBackedTripRouteCache(databaseProvider: environment.databaseProvider)
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
