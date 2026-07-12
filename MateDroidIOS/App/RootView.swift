import SwiftUI

@MainActor
public struct RootView: View {
    private let environment: AppEnvironment
    private let capabilityService: TeslaMateCapabilityService
    private let historySyncRunner: HistorySyncRunner
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var path: [AppRoute] = []

    public init(environment: AppEnvironment) {
        self.environment = environment
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
        self.historySyncRunner = historySyncRunner
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
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if settingsViewModel.settings.isConfigured {
                    DashboardView(
                        viewModel: dashboardViewModel(),
                        navigate: navigate(to:)
                    )
                } else {
                    SettingsView(viewModel: settingsViewModel)
                }
            }
            .navigationDestination(for: AppRoute.self, destination: destination(for:))
        }
        .environment(\.locale, appLocale)
        .environment(\.appLanguage, settingsViewModel.settings.appLanguage)
        .environment(\.appDisplayUnitSystem, settingsViewModel.settings.displayUnitSystem)
        .task {
            #if DEBUG
            await DebugLocalTeslamateSeeder.seedIfNeeded(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore
            )
            #endif
            await settingsViewModel.load()
            async let historySync: HistorySyncReport = historySyncRunner.run()
            await processPendingGeography()
            await refreshCapabilityProfileIfNeeded()
            _ = await historySync
            await processPendingGeography()
            await settingsViewModel.refreshHistorySyncHealth()
        }
        .accessibilityIdentifier("root_view")
    }

    private var appLocale: Locale {
        guard let localeIdentifier = settingsViewModel.settings.appLanguage.localeIdentifier else {
            return .autoupdatingCurrent
        }
        return Locale(identifier: localeIdentifier)
    }

    private func navigate(to route: AppRoute) {
        path.append(route)
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

    private func dashboardViewModel() -> DashboardViewModel {
        DashboardViewModel(
            api: SettingsBackedDashboardAPI(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore
            ),
            settingsStore: environment.settingsStore,
            notificationService: environment.notificationService,
            sentryAlertStore: sentryStore(),
            locationResolver: dashboardLocationResolver()
        )
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .settings:
            SettingsView(viewModel: settingsViewModel)
        case .dashboard:
            DashboardView(
                viewModel: dashboardViewModel(),
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
        case let .chargeDetail(carId, chargeId, exteriorColor):
            ChargeDetailView(
                carId: carId,
                chargeId: chargeId,
                exteriorColor: exteriorColor,
                viewModel: ChargeDetailViewModel(
                    api: chargeAPI(),
                    settingsStore: environment.settingsStore,
                    costOverrideStore: chargeCostOverrideStore(),
                    tripMembershipManager: tripMembershipService()
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
                viewModel: CurrentChargeViewModel(api: chargeAPI())
            )
        case let .activities(carId, exteriorColor):
            ActivitiesView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: ActivitiesViewModel(api: SettingsBackedActivityAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
                ), settingsStore: environment.settingsStore),
                standbyDrainAPI: SettingsBackedActivityAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
                ),
                navigate: navigate(to:)
            )
        case let .places(carId):
            let api = SettingsBackedActivityAPI(
                settingsStore: environment.settingsStore,
                secretStore: environment.secretStore
            )
            PlaceInsightsView(
                carId: carId,
                viewModel: PlaceInsightsViewModel(
                    api: api,
                    placesAPI: SettingsBackedServerPlacesAPI(settingsStore: environment.settingsStore, secretStore: environment.secretStore),
                    settingsStore: environment.settingsStore
                ),
                standbyDrainAPI: api
            )
        case let .achievements(carId, exteriorColor):
            AchievementsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: AchievementsViewModel(api: SettingsBackedAchievementsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
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
                    secretStore: environment.secretStore
                )),
                navigate: navigate
            )
        case let .driveDetail(carId, driveId, exteriorColor):
            DriveDetailView(
                carId: carId,
                driveId: driveId,
                exteriorColor: exteriorColor,
                viewModel: DriveDetailViewModel(api: driveAPI(), weatherService: weatherService(), tripMembershipManager: tripMembershipService(), settingsStore: environment.settingsStore),
                navigate: navigate(to:)
            )
        case let .driveMetricDetail(carId, driveId, metric, _):
            DriveMetricDetailView(
                carId: carId,
                driveId: driveId,
                metric: metric,
                viewModel: DriveMetricDetailViewModel(api: driveAPI())
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
                    activityAPI: SettingsBackedActivityAPI(settingsStore: environment.settingsStore, secretStore: environment.secretStore)
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
                    secretStore: environment.secretStore
                )),
                navigate: navigate(to:)
            )
        case let .drivingRecords(carId, exteriorColor):
            DrivingRecordsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: DrivingRecordsViewModel(api: SettingsBackedDrivingRecordsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
                )),
                navigate: navigate
            )
        case let .driveInsights(carId, exteriorColor):
            DriveInsightsView(
                carId: carId,
                exteriorColor: exteriorColor,
                viewModel: DriveInsightsViewModel(api: SettingsBackedDriveInsightsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
                )),
                navigate: navigate(to:)
            )
        case let .environmentHistory(carId):
            EnvironmentHistoryView(
                carId: carId,
                viewModel: EnvironmentHistoryViewModel(api: SettingsBackedEnvironmentHistoryAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
                ))
            )
        case let .topDrainLocations(carId):
            let activityAPI = SettingsBackedActivityAPI(settingsStore: environment.settingsStore, secretStore: environment.secretStore)
            TopDrainLocationsView(
                carId: carId,
                viewModel: TopDrainLocationsViewModel(api: SettingsBackedTopDrainLocationsAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
                )),
                standbyDrainAPI: activityAPI
            )
        case let .commuteRoutes(carId):
            CommuteRoutesView(
                carId: carId,
                viewModel: CommuteRoutesViewModel(api: SettingsBackedCommuteRoutesAPI(
                    settingsStore: environment.settingsStore,
                    secretStore: environment.secretStore
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
            store: APIChargeSummaryProvider(api: api),
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
            secretStore: environment.secretStore
        )
    }

    private func drivesViewModel() -> DrivesViewModel {
        let api = driveAPI()
        return DrivesViewModel(
            store: APIDriveSummaryProvider(api: api),
            settingsStore: environment.settingsStore
        )
    }

    private func driveAPI() -> SettingsBackedDriveAPI {
        SettingsBackedDriveAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore
        )
    }

    private func weatherService() -> WeatherService {
        WeatherService(api: OpenMeteoAPI())
    }

    private func analyticsAPI() -> SettingsBackedAnalyticsAPI {
        SettingsBackedAnalyticsAPI(
            settingsStore: environment.settingsStore,
            secretStore: environment.secretStore
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
        return HistoricalGeographyEnricher(api: api, geocoder: geocoder)
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

    private func dashboardLocationResolver() -> CachedDashboardLocationResolver {
        CachedDashboardLocationResolver(
            queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: environment.databaseProvider),
            reverseGeocoder: AppleReverseGeocodingAPI()
        )
    }
}
