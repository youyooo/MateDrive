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
    private let sleepIntervalStore: any SleepIntervalStoring
    private let serverProfileStore: any TeslaMateServerProfileStoring
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var lastStartedAt: Date?

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        clientOverride: (any HTTPClient)? = nil,
        databaseProvider: any AppDatabaseProviding = LiveAppDatabaseProvider(),
        sleepIntervalStore: (any SleepIntervalStoring)? = nil,
        serverProfileStore: (any TeslaMateServerProfileStoring)? = nil,
        minimumInterval: TimeInterval = 5 * 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.clientOverride = clientOverride
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
        let sleepResult = await loadSleepIntervals(
            cars: orderedCars,
            api: api,
            referenceDate: startedAt
        )

        return AppDataPreloadReport(
            didRun: true,
            requestedEndpointCount: 1 + sleepResult.requestedCount,
            successfulEndpointCount: 1 + sleepResult.successfulCount
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
}
