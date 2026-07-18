import Foundation

public struct AppDataPreloadReport: Equatable, Sendable {
    public let didRun: Bool
    public let requestedEndpointCount: Int
    public let successfulEndpointCount: Int

    public init(didRun: Bool, requestedEndpointCount: Int, successfulEndpointCount: Int) {
        self.didRun = didRun
        self.requestedEndpointCount = requestedEndpointCount
        self.successfulEndpointCount = successfulEndpointCount
    }

    public static let skipped = AppDataPreloadReport(
        didRun: false,
        requestedEndpointCount: 0,
        successfulEndpointCount: 0
    )
}

public actor AppDataPreloader {
    private let settingsStore: any SettingsStoring
    private let secretStore: any SecretStoring
    private let clientOverride: (any HTTPClient)?
    private let activitiesCache: any ActivitiesStateCaching
    private let sleepIntervalStore: any SleepIntervalStoring
    private let serverProfileStore: any TeslaMateServerProfileStoring
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var lastStartedAt: Date?

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        clientOverride: (any HTTPClient)? = nil,
        activitiesCache: any ActivitiesStateCaching = EmptyActivitiesStateCache(),
        databaseProvider: any AppDatabaseProviding = LiveAppDatabaseProvider(),
        sleepIntervalStore: (any SleepIntervalStoring)? = nil,
        serverProfileStore: (any TeslaMateServerProfileStoring)? = nil,
        minimumInterval: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.clientOverride = clientOverride
        self.activitiesCache = activitiesCache
        self.sleepIntervalStore = sleepIntervalStore
            ?? DatabaseBackedSleepIntervalStore(databaseProvider: databaseProvider)
        self.serverProfileStore = serverProfileStore
            ?? DatabaseBackedTeslaMateServerProfileStore(databaseProvider: databaseProvider)
        self.minimumInterval = minimumInterval
        self.now = now
    }

    public func preload(force: Bool = false) async -> AppDataPreloadReport {
        let startedAt = now()
        if !force,
           let lastStartedAt,
           startedAt.timeIntervalSince(lastStartedAt) < minimumInterval {
            return .skipped
        }
        lastStartedAt = startedAt

        let settings = await settingsStore.load()
        guard !Task.isCancelled, settings.isConfigured else {
            return AppDataPreloadReport(
                didRun: true,
                requestedEndpointCount: 0,
                successfulEndpointCount: 0
            )
        }

        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: secretStore,
            clientOverride: clientOverride
        )
        let apiResult = await factory.makeAPI(settings: settings)
        guard !Task.isCancelled, case let .success(api) = apiResult else {
            return AppDataPreloadReport(
                didRun: true,
                requestedEndpointCount: 0,
                successfulEndpointCount: 0
            )
        }

        let carsResult = await api.cars()
        guard !Task.isCancelled else {
            return AppDataPreloadReport(
                didRun: true,
                requestedEndpointCount: 1,
                successfulEndpointCount: 0
            )
        }
        guard case let .success(cars) = carsResult, !cars.isEmpty else {
            return AppDataPreloadReport(
                didRun: true,
                requestedEndpointCount: 1,
                successfulEndpointCount: 0
            )
        }

        let selected = cars.first(where: { $0.carId == settings.lastSelectedCarId })
        let orderedCars = (selected.map { [$0] } ?? [])
            + cars.filter { $0.carId != selected?.carId }
        async let sleepTask = loadSleepIntervals(
            cars: orderedCars,
            api: api,
            referenceDate: startedAt
        )
        async let activitiesTask = loadActivitySnapshots(
            cars: orderedCars,
            api: api,
            settings: settings
        )
        let (sleepResult, activitiesResult) = await (sleepTask, activitiesTask)

        return AppDataPreloadReport(
            didRun: true,
            requestedEndpointCount: 1 + sleepResult.requestedCount + activitiesResult.requestedPageCount,
            successfulEndpointCount: 1 + sleepResult.successfulCount + activitiesResult.successfulPageCount
        )
    }

    private func loadSleepIntervals(
        cars: [CarData],
        api: TeslamateAPI,
        referenceDate: Date
    ) async -> (requestedCount: Int, successfulCount: Int) {
        let calendar = Calendar.current
        guard let monthStart = calendar.dateInterval(of: .month, for: referenceDate)?.start else {
            return (0, 0)
        }

        let formatter = ISO8601DateFormatter()
        let startDate = formatter.string(from: monthStart)
        let endDate = formatter.string(from: referenceDate)
        let serverKey = TeslaMateServerIdentity.key(for: api.baseURL)
        var requestedCount = 0
        var successfulCount = 0

        for car in cars where !Task.isCancelled {
            let profile = try? await serverProfileStore.profile(
                serverKey: serverKey,
                carId: car.carId
            )
            guard !Task.isCancelled else { break }
            guard profile?.status(for: .stateHistory)?.state == .available else {
                continue
            }

            requestedCount += 1
            let response = await api.vehicleStateHistory(
                carId: car.carId,
                startDate: startDate,
                endDate: endDate
            )
            guard !Task.isCancelled else { break }
            guard case let .success(intervals) = response else {
                continue
            }

            let records = intervals.compactMap { interval -> SleepIntervalRecord? in
                guard let sleepInterval = interval.sleepInterval(now: referenceDate) else {
                    return nil
                }
                return SleepIntervalRecord(
                    carId: car.carId,
                    startDate: formatter.string(from: sleepInterval.start),
                    endDate: formatter.string(from: sleepInterval.end)
                )
            }
            guard !Task.isCancelled else { break }
            try? await sleepIntervalStore.upsertAll(records)
            guard !Task.isCancelled else { break }
            successfulCount += 1
        }

        return (requestedCount, successfulCount)
    }

    private func loadActivitySnapshots(
        cars: [CarData],
        api: TeslamateAPI,
        settings: AppSettings
    ) async -> (requestedPageCount: Int, successfulPageCount: Int) {
        let cache = activitiesCache
        let savedAt = now()
        return await withTaskGroup(of: (requested: Int, successful: Int).self) { group in
            for car in cars {
                group.addTask {
                    let pageSize = 200
                    let maximumPages = 250
                    let cachedSnapshot = await cache.load(
                        serverURL: settings.serverURL,
                        carId: car.carId,
                        now: savedAt
                    )
                    let cachedHistoryIsComplete = cachedSnapshot?.state.historyFullyLoaded == true
                    let cachedIDs = Set(cachedSnapshot?.state.items.map(\.stableID) ?? [])
                    var page = 1
                    var requested = 0
                    var successful = 0
                    var items = cachedSnapshot?.state.items ?? []
                    var seenIDs = Set(items.map(\.stableID))
                    var units = cachedSnapshot?.state.units
                    var paginationIsDegraded = cachedSnapshot?.state.paginationIsDegraded ?? false
                    var hasMore = true

                    while hasMore, page <= maximumPages, !Task.isCancelled {
                        requested += 1
                        guard case let .success(response) = await api.activities(
                            carId: car.carId,
                            page: page,
                            show: pageSize
                        ) else { break }
                        successful += 1
                        if let responseUnits = response.units {
                            units = UnitPreferences(
                                unitOfLength: responseUnits.unitOfLength,
                                unitOfTemperature: responseUnits.unitOfTemperature,
                                unitOfPressure: responseUnits.unitOfPressure
                            )
                        }

                        let pageIDs = Set(response.data.map(\.stableID))
                        let overlapsCachedHistory = !cachedIDs.isDisjoint(with: pageIDs)
                        let newItems = response.data.filter { seenIDs.insert($0.stableID).inserted }
                        items.removeAll { pageIDs.contains($0.stableID) }
                        items.append(contentsOf: response.data)
                        let reportedPages = response.pagination?.totalPages
                        let metadataIsReliable = reportedPages.map { $0 > 0 && $0 < 9_999 } ?? false
                        paginationIsDegraded = paginationIsDegraded
                            || (reportedPages ?? 0) >= 9_999
                            || (!response.data.isEmpty && response.pagination?.totalRecords == 0)
                        if metadataIsReliable, let reportedPages {
                            hasMore = page < reportedPages && !newItems.isEmpty
                        } else {
                            let serverLimit = max(response.pagination?.limit ?? pageSize, 1)
                            hasMore = response.data.count >= serverLimit && !newItems.isEmpty
                        }
                        if cachedHistoryIsComplete, overlapsCachedHistory {
                            hasMore = false
                        }
                        page += 1
                    }

                    guard successful > 0, !Task.isCancelled else {
                        return (requested, successful)
                    }
                    var state = ActivitiesState()
                    state.items = items.sorted {
                        let lhs = $0.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
                        let rhs = $1.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
                        return lhs > rhs
                    }
                    state.hasMore = hasMore
                    state.source = .unifiedAPI
                    state.paginationIsDegraded = paginationIsDegraded
                    state.historyFullyLoaded = cachedHistoryIsComplete || !hasMore
                    state.historyLoadCapped = !cachedHistoryIsComplete && hasMore && page > maximumPages
                    state.loadedPageCount = cachedHistoryIsComplete
                        ? max(cachedSnapshot?.state.loadedPageCount ?? 0, successful)
                        : successful
                    state.currencyCode = settings.resolvedCurrencyCode()
                    state.units = units
                    await cache.save(
                        ActivitiesCacheSnapshot(state: state, savedAt: savedAt),
                        serverURL: settings.serverURL,
                        carId: car.carId
                    )
                    return (requested, successful)
                }
            }

            var requested = 0
            var successful = 0
            for await result in group {
                requested += result.requested
                successful += result.successful
            }
            return (requested, successful)
        }
    }
}
