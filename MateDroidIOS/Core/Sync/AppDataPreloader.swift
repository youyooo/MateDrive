import Foundation
import WidgetKit

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
    private struct Request: Sendable {
        let path: String
        let queryItems: [URLQueryItem]

        init(_ path: String, queryItems: [URLQueryItem] = []) {
            self.path = path
            self.queryItems = queryItems
        }
    }

    private struct DetailRequest: Sendable {
        let request: Request
        let refreshesLatest: Bool
    }

    private let settingsStore: any SettingsStoring
    private let secretStore: any SecretStoring
    private let clientOverride: (any HTTPClient)?
    private let widgetSnapshotStore: WidgetSnapshotStore
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
        widgetSnapshotStore: WidgetSnapshotStore = .shared,
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
        self.widgetSnapshotStore = widgetSnapshotStore
        self.activitiesCache = activitiesCache
        self.sleepIntervalStore = sleepIntervalStore ?? DatabaseBackedSleepIntervalStore(databaseProvider: databaseProvider)
        self.serverProfileStore = serverProfileStore ?? DatabaseBackedTeslaMateServerProfileStore(databaseProvider: databaseProvider)
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
        guard settings.isConfigured, !Task.isCancelled else {
            return AppDataPreloadReport(didRun: true, requestedEndpointCount: 0, successfulEndpointCount: 0)
        }
        let factory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: secretStore,
            clientOverride: clientOverride
        )
        guard case let .success(api) = await factory.makeAPI(settings: settings) else {
            return AppDataPreloadReport(didRun: true, requestedEndpointCount: 0, successfulEndpointCount: 0)
        }

        guard case let .success(cars) = await api.cars(), !cars.isEmpty else {
            return AppDataPreloadReport(didRun: true, requestedEndpointCount: 1, successfulEndpointCount: 0)
        }

        let selected = cars.first(where: { $0.carId == settings.lastSelectedCarId })
        let orderedCars = (selected.map { [$0] } ?? [])
            + cars.filter { $0.carId != selected?.carId }
        let requests = orderedCars.flatMap { Self.requests(carId: $0.carId, referenceDate: startedAt) }
            + [Request("api/v1/globalsettings")]
        async let widgetTask = loadWidgetSnapshots(cars: orderedCars, api: api, settings: settings)
        async let activitiesTask = loadActivitySnapshots(cars: orderedCars, api: api, settings: settings)
        async let detailsTask = loadDetailSnapshots(cars: orderedCars, api: api)
        async let placesTask = loadPlaceSnapshots(cars: orderedCars, api: api)
        async let standbyTask = loadStandbyDrainSnapshots(cars: orderedCars, api: api)
        async let sleepTask = loadSleepIntervals(cars: orderedCars, api: api, referenceDate: startedAt)
        async let endpointTask = execute(requests, api: api)
        let (widgetResult, activitiesResult, detailsResult, placesResult, standbyResult, sleepResult, successful) = await (
            widgetTask,
            activitiesTask,
            detailsTask,
            placesTask,
            standbyTask,
            sleepTask,
            endpointTask
        )
        return AppDataPreloadReport(
            didRun: true,
            requestedEndpointCount: requests.count + cars.count * 4 + activitiesResult.requestedPageCount
                + detailsResult.requestedCount + placesResult.requestedCount + standbyResult.requestedCount
                + sleepResult.requestedCount + 1,
            successfulEndpointCount: successful + widgetResult.successfulRequestCount + activitiesResult.successfulPageCount
                + detailsResult.successfulCount + placesResult.successfulCount + standbyResult.successfulCount
                + sleepResult.successfulCount + 1
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
        var requested = 0
        var successful = 0

        for car in cars where !Task.isCancelled {
            let profile = try? await serverProfileStore.profile(serverKey: serverKey, carId: car.carId)
            guard !Task.isCancelled else { break }
            guard let profile, profile.status(for: .stateHistory)?.state == .available else {
                continue
            }

            requested += 1
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
            successful += 1
        }

        return (requested, successful)
    }

    private func loadDetailSnapshots(
        cars: [CarData],
        api: TeslamateAPI
    ) async -> (requestedCount: Int, successfulCount: Int) {
        await withTaskGroup(of: (requested: Int, successful: Int).self) { group in
            for car in cars {
                group.addTask {
                    async let drivesResult = api.refreshDrives(
                        carId: car.carId,
                        startDate: nil,
                        endDate: nil,
                        page: 1,
                        show: 50_000
                    )
                    async let chargesResult = api.refreshCharges(
                        carId: car.carId,
                        startDate: nil,
                        endDate: nil,
                        page: 1,
                        show: 50_000
                    )
                    let (drives, charges) = await (drivesResult, chargesResult)
                    var requested = 2
                    var successful = [drives.isSuccess, charges.isSuccess].filter { $0 }.count
                    var detailRequests: [DetailRequest] = []

                    if case let .success(values) = drives {
                        let ids = values.sorted { lhs, rhs in
                            let lhsDate = lhs.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
                            let rhsDate = rhs.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
                            return lhsDate > rhsDate
                        }.compactMap(\.driveId).prefix(300)
                        detailRequests += ids.enumerated().map { index, id in
                            DetailRequest(
                                request: Request("api/v1/cars/\(car.carId)/drives/\(id)"),
                                refreshesLatest: index == 0
                            )
                        }
                    }
                    if case let .success(values) = charges {
                        let ids = values.sorted { lhs, rhs in
                            let lhsDate = lhs.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
                            let rhsDate = rhs.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
                            return lhsDate > rhsDate
                        }.compactMap(\.chargeId).prefix(1_000)
                        detailRequests += ids.enumerated().map { index, id in
                            DetailRequest(
                                request: Request("api/v1/cars/\(car.carId)/charges/\(id)"),
                                refreshesLatest: index == 0
                            )
                        }
                    }

                    requested += detailRequests.count
                    successful += await Self.executeDetailRequests(detailRequests, api: api)
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

    private static func executeDetailRequests(_ requests: [DetailRequest], api: TeslamateAPI) async -> Int {
        var successful = 0
        for offset in stride(from: 0, to: requests.count, by: 4) {
            guard !Task.isCancelled else { break }
            let batch = requests[offset ..< min(offset + 4, requests.count)]
            successful += await withTaskGroup(of: Bool.self) { group in
                for detailRequest in batch {
                    group.addTask {
                        let request = detailRequest.request
                        if !detailRequest.refreshesLatest,
                           case .success = await api.probe(
                               path: request.path,
                               queryItems: request.queryItems,
                               cachePolicy: .returnCacheDataDontLoad
                           ) {
                            return true
                        }
                        if case .success = await api.probe(
                            path: request.path,
                            queryItems: request.queryItems,
                            cachePolicy: .reloadIgnoringLocalCacheData
                        ) {
                            return true
                        }
                        return false
                    }
                }
                var count = 0
                for await result in group where result { count += 1 }
                return count
            }
        }
        return successful
    }

    private func loadPlaceSnapshots(
        cars: [CarData],
        api: TeslamateAPI
    ) async -> (requestedCount: Int, successfulCount: Int) {
        await withTaskGroup(of: (requested: Int, successful: Int).self) { group in
            for car in cars {
                group.addTask {
                    var page = 1
                    var requested = 0
                    var successful = 0
                    while page <= 100, !Task.isCancelled {
                        let queryItems = [
                            URLQueryItem(name: "page", value: String(page)),
                            URLQueryItem(name: "show", value: "100")
                        ]
                        requested += 1
                        guard case let .success(probe) = await api.probe(
                            path: "api/v1/cars/\(car.carId)/places",
                            queryItems: queryItems,
                            cachePolicy: .reloadIgnoringLocalCacheData
                        ) else { break }
                        successful += 1
                        guard let response = try? JSONDecoder.teslamate.decode(ServerPlacesResponse.self, from: probe.data) else {
                            break
                        }
                        let totalPages = max(response.pagination?.totalPages ?? page, page)
                        guard page < totalPages else { break }
                        page += 1
                    }
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

    private func loadStandbyDrainSnapshots(
        cars: [CarData],
        api: TeslamateAPI
    ) async -> (requestedCount: Int, successfulCount: Int) {
        await withTaskGroup(of: (requested: Int, successful: Int).self) { group in
            for car in cars {
                group.addTask {
                    var requested = 1
                    var successful = 0
                    guard case let .success(probe) = await api.probe(
                        path: "api/v1/cars/\(car.carId)/top-drain-locations",
                        cachePolicy: .reloadIgnoringLocalCacheData
                    ) else { return (requested, successful) }
                    successful += 1
                    guard let response = try? JSONDecoder.teslamate.decode(TopDrainLocationsResponse.self, from: probe.data) else {
                        return (requested, successful)
                    }

                    var seenCoordinates: Set<String> = []
                    for location in response.locations {
                        guard !Task.isCancelled,
                              let coordinate = GeoCoordinateValidator.location(
                                  latitude: location.latitude,
                                  longitude: location.longitude
                              )
                        else { continue }
                        let key = "\(coordinate.latitude),\(coordinate.longitude)"
                        guard seenCoordinates.insert(key).inserted, seenCoordinates.count <= 12 else { continue }
                        requested += 1
                        if case .success = await api.probe(
                            path: "api/v1/cars/\(car.carId)/standby-drain",
                            queryItems: [
                                URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                                URLQueryItem(name: "lng", value: String(coordinate.longitude))
                            ],
                            cachePolicy: .reloadIgnoringLocalCacheData
                        ) {
                            successful += 1
                        }
                    }
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
                        guard case let .success(response) = await api.refreshActivities(
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

                        guard !items.isEmpty else { continue }
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
                    }

                    guard successful > 0, !items.isEmpty else {
                        return (requested, successful)
                    }
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

    private func loadWidgetSnapshots(
        cars: [CarData],
        api: TeslamateAPI,
        settings: AppSettings
    ) async -> (successfulRequestCount: Int, snapshots: [WidgetVehicleSnapshot]) {
        let referenceDate = now()
        let results = await withTaskGroup(of: (WidgetVehicleSnapshot?, Int).self) { group in
            for car in cars {
                group.addTask {
                    guard let identifier = WidgetVehicleIdentity.identifier(
                        serverURL: settings.serverURL,
                        carID: car.carId
                    ) else { return (nil, 0) }

                    async let statusResult = api.refreshCarStatus(carId: car.carId)
                    async let healthResult = api.refreshBatteryHealth(carId: car.carId)
                    async let historyResult = api.refreshBatteryHistory(carId: car.carId)
                    async let chargesResult = api.refreshCharges(carId: car.carId, page: 1, show: 50_000)
                    let results = await (statusResult, healthResult, historyResult, chargesResult)
                    let payload: CarStatusPayload?
                    switch results.0 {
                    case let .success(value):
                        payload = value
                    case .failure:
                        payload = nil
                    }
                    let data = Self.widgetDisplayData(car: car, payload: payload, settings: settings)
                    let batteryTrend = await Self.batteryTrendData(
                        carId: car.carId,
                        healthResult: results.1,
                        historyResult: results.2,
                        status: payload?.status,
                        units: payload?.units.map {
                            UnitPreferences(
                                unitOfLength: $0.unitOfLength,
                                unitOfTemperature: $0.unitOfTemperature,
                                unitOfPressure: $0.unitOfPressure
                            )
                        },
                        settings: settings
                    )
                    let chargingTrend = Self.chargingTrendData(
                        chargesResult: results.3,
                        settings: settings,
                        referenceDate: referenceDate
                    )
                    let successfulRequestCount = [
                        results.0.isSuccess,
                        results.1.isSuccess,
                        results.2.isSuccess,
                        results.3.isSuccess
                    ].filter { $0 }.count
                    return (
                        WidgetVehicleSnapshot(
                            id: identifier,
                            data: data,
                            batteryTrend: batteryTrend,
                            chargingTrend: chargingTrend,
                            updatedAt: referenceDate
                        ),
                        successfulRequestCount
                    )
                }
            }

            var snapshots: [WidgetVehicleSnapshot] = []
            var successfulRequestCount = 0
            for await (snapshot, requestCount) in group {
                if let snapshot { snapshots.append(snapshot) }
                successfulRequestCount += requestCount
            }
            return (successfulRequestCount: successfulRequestCount, snapshots: snapshots)
        }

        let preferredIdentifier = settings.lastSelectedCarId.flatMap {
            WidgetVehicleIdentity.identifier(serverURL: settings.serverURL, carID: $0)
        }
        widgetSnapshotStore.replaceVehicleSnapshots(results.snapshots, preferredIdentifier: preferredIdentifier)
        WidgetCenter.shared.reloadAllTimelines()
        return results
    }

    private static func batteryTrendData(
        carId: Int,
        healthResult: APIResult<BatteryHealth>,
        historyResult: APIResult<BatteryHistoryData>,
        status: CarStatus?,
        units: UnitPreferences?,
        settings: AppSettings
    ) async -> WidgetBatteryTrendData? {
        guard case let .success(health) = healthResult else { return nil }
        let history = historyResult.value
        let summary: BatteryHistorySummary?
        if let history {
            summary = await BatteryViewModel.historySummary(from: history)
        } else {
            summary = nil
        }
        let calibration = settings.batteryCalibration(for: carId)
        let recordingStart = [calibration.recordingStartOdometerKm, summary?.startOdometerKm]
            .compactMap { $0 }
            .filter { $0.isFinite && $0 > 0 }
            .min()
        let stats = await BatteryViewModel.computeStats(
            health: health,
            status: status,
            ratedEfficiencyFallback: history?.efficiency?.whPerKm,
            batteryReferenceRangeKm: calibration.referenceRangeKm,
            batteryReferenceCapacityKWh: calibration.referenceCapacityKWh,
            batteryRecordingStartOdometerKm: recordingStart
        )
        let medianCapacity = history?.charts?.capacityMedian
            .compactMap { point in point.capacity.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } } ?? []
        let rawCapacity = history?.charts?.capacity
            .compactMap { point in point.capacity.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } } ?? []
        let capacity = medianCapacity.count >= 2 ? medianCapacity : rawCapacity
        let ranges = history?.charts?.range
            .compactMap { point in point.range.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } } ?? []
        let metric: WidgetBatteryTrendMetric
        let samples: [Double]
        let currentValue: Double?
        if capacity.count >= 2 || ranges.isEmpty {
            metric = .capacity
            samples = capacity.isEmpty ? [stats.currentCapacity].compactMap { $0 } : capacity
            currentValue = stats.currentCapacity ?? capacity.last
        } else {
            metric = .range
            samples = ranges
            currentValue = stats.maxRangeNow ?? ranges.last
        }
        return WidgetBatteryTrendData(
            healthPercent: stats.healthPercent,
            showsAbsoluteHealth: stats.showsAbsoluteHealth,
            metric: metric,
            samples: samples,
            currentValue: currentValue,
            recordedDays: summary?.quality.recordedDays ?? 0,
            qualityScore: summary?.quality.score,
            displayLanguage: WidgetDisplayLanguage(appLanguage: settings.appLanguage),
            displayUnitSystem: widgetUnitSystem(settings: settings, units: units)
        )
    }

    private static func chargingTrendData(
        chargesResult: APIResult<[ChargeData]>,
        settings: AppSettings,
        referenceDate: Date
    ) -> WidgetChargingTrendData? {
        guard case let .success(charges) = chargesResult else { return nil }
        let periodDays = 30
        let calendar = Calendar(identifier: .gregorian)
        guard let cutoff = calendar.date(byAdding: .day, value: -(periodDays - 1), to: calendar.startOfDay(for: referenceDate)) else {
            return nil
        }
        let recent = charges.compactMap { charge -> (ChargeData, Date)? in
            guard let date = charge.startDate.flatMap(DomainDateParser.date(from:)),
                  date >= cutoff,
                  date <= referenceDate
            else { return nil }
            return (charge, date)
        }
        let energies = recent.compactMap { charge, _ -> Double? in
            let value = charge.chargeEnergyAdded ?? charge.chargeEnergyUsed
            return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        let costs = recent.compactMap { charge, _ in
            charge.cost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        var buckets = Array(repeating: 0.0, count: 6)
        for (charge, date) in recent {
            guard let energy = (charge.chargeEnergyAdded ?? charge.chargeEnergyUsed), energy.isFinite, energy >= 0 else { continue }
            let age = max(calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: referenceDate)).day ?? 0, 0)
            let bucket = max(0, 5 - min(age / 5, 5))
            buckets[bucket] += energy
        }
        return WidgetChargingTrendData(
            periodDays: periodDays,
            sessionCount: recent.count,
            energyKWh: energies.isEmpty ? nil : energies.reduce(0, +),
            energyKnownCount: energies.count,
            cost: costs.isEmpty ? nil : costs.reduce(0, +),
            costKnownCount: costs.count,
            currencyCode: settings.resolvedCurrencyCode(),
            energyBuckets: buckets,
            displayLanguage: WidgetDisplayLanguage(appLanguage: settings.appLanguage)
        )
    }

    private static func widgetDisplayData(
        car: CarData,
        payload: CarStatusPayload?,
        settings: AppSettings
    ) -> WidgetDisplayData {
        let status = payload?.status
        let statusName = status?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let carName = statusName.flatMap { name in
            !name.isEmpty && !CarData.isLegacyAppDisplayName(name) ? name : nil
        } ?? car.dashboardPrimaryName
        let units = payload?.units.map {
            UnitPreferences(
                unitOfLength: $0.unitOfLength,
                unitOfTemperature: $0.unitOfTemperature,
                unitOfPressure: $0.unitOfPressure
            )
        }
        return WidgetDisplayData(
            carName: carName,
            batteryLevel: status?.batteryLevel,
            ratedRange: status?.ratedBatteryRangeKm,
            isCharging: status?.isCharging ?? false,
            isLocked: status?.locked,
            sentryModeActive: status?.sentryMode ?? false,
            insideTemperature: status?.insideTemp,
            outsideTemperature: status?.outsideTemp,
            locationText: status?.locationSummary,
            isReadOnly: true,
            displayLanguage: WidgetDisplayLanguage(appLanguage: settings.appLanguage),
            displayUnitSystem: widgetUnitSystem(settings: settings, units: units)
        )
    }

    private static func widgetUnitSystem(settings: AppSettings, units: UnitPreferences?) -> WidgetDisplayUnitSystem {
        WidgetDisplayUnitSystem(units: units, displayUnitSystem: settings.displayUnitSystem)
    }

    private func execute(_ requests: [Request], api: TeslamateAPI) async -> Int {
        var successful = 0
        let batchSize = 4
        for offset in stride(from: 0, to: requests.count, by: batchSize) {
            guard !Task.isCancelled else { break }
            let batch = requests[offset..<min(offset + batchSize, requests.count)]
            successful += await withTaskGroup(of: Bool.self) { group in
                for request in batch {
                    group.addTask {
                        if case .success = await api.probe(
                            path: request.path,
                            queryItems: request.queryItems,
                            cachePolicy: .reloadIgnoringLocalCacheData
                        ) {
                            return true
                        }
                        return false
                    }
                }
                var count = 0
                for await result in group where result {
                    count += 1
                }
                return count
            }
        }
        return successful
    }

    private static func requests(carId: Int, referenceDate: Date) -> [Request] {
        let base = "api/v1/cars/\(carId)"
        let firstPage = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "show", value: "50000")
        ]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let costReviewRequests = CostReviewRange.allCases.map { range in
            let window = range.dateWindow(containing: referenceDate)
            return Request("\(base)/stats/cost-charging-detail", queryItems: [
                URLQueryItem(name: "start_date", value: formatter.string(from: window.startDate)),
                URLQueryItem(name: "end_date", value: formatter.string(from: window.endDate))
            ])
        }
        let environmentHistoryRequests = EnvironmentHistoryRange.allCases.map { range in
            Request("\(base)/environment-history", queryItems: [
                URLQueryItem(name: "range", value: range.rawValue),
                URLQueryItem(name: "grain", value: range.grain)
            ])
        }
        return [
            Request("\(base)/charges/current"),
            Request("\(base)/battery"),
            Request("\(base)/stats"),
            Request("\(base)/updates", queryItems: firstPage),
            Request("\(base)/drive-stats"),
            Request("\(base)/commute-routes"),
            Request("\(base)/stats/extremes"),
            Request("\(base)/driving-coordinates"),
            Request("\(base)/achievements")
        ] + environmentHistoryRequests + costReviewRequests
    }
}

private extension APIResult {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var value: Value? {
        if case let .success(value) = self { return value }
        return nil
    }
}
