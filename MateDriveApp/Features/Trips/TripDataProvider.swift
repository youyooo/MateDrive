import Foundation

public protocol TripDataProviding: Sendable {
    func sourceData(carId: Int) async -> APIResult<TripSourceData>
    func routeSegments(carId: Int, driveIds: [Int]) async -> [SavedTripRouteSegment]
}

public extension TripDataProviding {
    func routeSegments(carId _: Int, driveIds _: [Int]) async -> [SavedTripRouteSegment] { [] }
}

public protocol TripSummarySnapshotProviding: Sendable {
    func driveRecords(carId: Int) async throws -> [DriveSummaryRecord]
    func chargeRecords(carId: Int) async throws -> [ChargeSummaryRecord]
    func units(carId: Int) async -> UnitPreferences?
}

public struct DatabaseBackedTripSummarySource: TripSummarySnapshotProviding {
    private let databaseProvider: any AppDatabaseProviding
    private let settingsStore: any SettingsStoring
    private let dashboardSnapshotStore: any DashboardSnapshotStoring

    public init(
        databaseProvider: any AppDatabaseProviding,
        settingsStore: any SettingsStoring,
        dashboardSnapshotStore: any DashboardSnapshotStoring = DashboardSnapshotStore.shared
    ) {
        self.databaseProvider = databaseProvider
        self.settingsStore = settingsStore
        self.dashboardSnapshotStore = dashboardSnapshotStore
    }

    public func driveRecords(carId: Int) async throws -> [DriveSummaryRecord] {
        let database = try await databaseProvider.database()
        return try await DriveSummaryStore(database: database).records(carId: carId)
    }

    public func chargeRecords(carId: Int) async throws -> [ChargeSummaryRecord] {
        let database = try await databaseProvider.database()
        return try await ChargeSummaryStore(database: database).records(carId: carId)
    }

    public func units(carId: Int) async -> UnitPreferences? {
        let settings = await settingsStore.load()
        guard let snapshot = await dashboardSnapshotStore.load(
            serverURL: settings.serverURL,
            carId: carId,
            now: Date()
        ) else {
            return nil
        }
        return snapshot.units?.value
    }
}

public struct CachedTripDataProvider: TripDataProviding {
    private let summarySource: any TripSummarySnapshotProviding
    private let routeProvider: any TripDataProviding

    public init(
        summarySource: any TripSummarySnapshotProviding,
        routeProvider: any TripDataProviding
    ) {
        self.summarySource = summarySource
        self.routeProvider = routeProvider
    }

    public func sourceData(carId: Int) async -> APIResult<TripSourceData> {
        do {
            async let driveRecords = summarySource.driveRecords(carId: carId)
            async let chargeRecords = summarySource.chargeRecords(carId: carId)
            async let units = summarySource.units(carId: carId)
            let drives = try await driveRecords.compactMap(Self.tripDrive(from:))
            let charges = try await chargeRecords.compactMap(Self.tripCharge(from:))
            let dcChargeIds = Set(charges.compactMap { charge -> Int? in
                guard ChargingSessionAnalyzer.isDcCharge(
                    chargeId: charge.id,
                    energyAddedKwh: charge.energyAdded,
                    durationMin: charge.durationMin,
                    dcChargeIds: [],
                    processedChargeIds: []
                ) else {
                    return nil
                }
                return charge.id
            })
            return .success(TripSourceData(
                drives: drives,
                charges: charges,
                dcChargeIds: dcChargeIds,
                units: await units
            ))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    public func routeSegments(carId: Int, driveIds: [Int]) async -> [SavedTripRouteSegment] {
        await routeProvider.routeSegments(carId: carId, driveIds: driveIds)
    }

    private static func tripDrive(from record: DriveSummaryRecord) -> TripDrive? {
        guard let distance = record.distance, let duration = record.durationMin else { return nil }
        return TripDrive(
            id: record.driveId,
            startDate: record.startDate,
            endDate: record.endDate,
            distance: distance,
            durationMin: duration,
            energyConsumed: record.energyConsumedNet,
            speedMax: nil,
            startAddress: record.startAddress,
            endAddress: record.endAddress,
            startBatteryLevel: record.startBatteryLevel,
            endBatteryLevel: record.endBatteryLevel
        )
    }

    private static func tripCharge(from record: ChargeSummaryRecord) -> TripCharge? {
        guard let endDate = record.endDate else { return nil }
        return TripCharge(
            id: record.chargeId,
            startDate: record.startDate,
            endDate: endDate,
            energyAdded: record.chargeEnergyAdded,
            cost: record.cost,
            durationMin: record.durationMin,
            address: record.address
        )
    }
}

public struct APITripDataProvider: TripDataProviding {
    private let api: any AnalyticsAPIProviding
    private let routeCache: (any TripRouteCaching)?
    private let maximumConcurrentRouteRequests: Int

    public init(
        api: any AnalyticsAPIProviding,
        routeCache: (any TripRouteCaching)? = nil,
        maximumConcurrentRouteRequests: Int = 8
    ) {
        self.api = api
        self.routeCache = routeCache
        self.maximumConcurrentRouteRequests = max(maximumConcurrentRouteRequests, 1)
    }

    public func sourceData(carId: Int) async -> APIResult<TripSourceData> {
        async let drivesResult = VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
        async let chargesResult = VehicleHistoryPaginator.charges(loadPage: { page, show in
            await self.api.charges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
        async let statusResult = api.carStatus(carId: carId)

        let status = await statusResult
        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            let tripDrives = drives.compactMap(Self.tripDrive(from:))
            let tripCharges = charges.compactMap(Self.tripCharge(from:))
            let dcChargeIds = Set(charges.compactMap { charge -> Int? in
                guard let id = charge.chargeId else { return nil }
                return ChargingSessionAnalyzer.isDcCharge(
                    chargeId: id,
                    energyAddedKwh: charge.chargeEnergyAdded,
                    durationMin: charge.durationMin,
                    dcChargeIds: [],
                    processedChargeIds: []
                ) ? id : nil
            })
            let units: UnitPreferences?
            if case let .success(payload) = status {
                units = UnitPreferences(
                    unitOfLength: payload.units?.unitOfLength,
                    unitOfTemperature: payload.units?.unitOfTemperature,
                    unitOfPressure: payload.units?.unitOfPressure
                )
            } else {
                units = nil
            }
            return .success(TripSourceData(drives: tripDrives, charges: tripCharges, dcChargeIds: dcChargeIds, units: units))
        case let (.failure(error), _), let (_, .failure(error)):
            return .failure(error)
        }
    }

    public func routeSegments(carId: Int, driveIds: [Int]) async -> [SavedTripRouteSegment] {
        var uniqueDriveIds: [Int] = []
        var seenDriveIds: Set<Int> = []
        for driveId in driveIds where seenDriveIds.insert(driveId).inserted {
            uniqueDriveIds.append(driveId)
        }

        var segmentsById: [Int: SavedTripRouteSegment] = [:]
        for offset in stride(from: 0, to: uniqueDriveIds.count, by: maximumConcurrentRouteRequests) {
            guard !Task.isCancelled else { break }
            let batch = Array(
                uniqueDriveIds[offset..<min(offset + maximumConcurrentRouteRequests, uniqueDriveIds.count)]
            )
            let api = self.api
            let routeCache = self.routeCache
            let batchSegments = await withTaskGroup(of: SavedTripRouteSegment?.self, returning: [SavedTripRouteSegment].self) { group in
                for driveId in batch {
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        if let routeCache,
                           let cached = try? await routeCache.points(carId: carId, driveId: driveId),
                           cached.count >= 2 {
                            return SavedTripRouteSegment(driveId: driveId, points: cached)
                        }
                        guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: driveId) else {
                            return nil
                        }
                        let segment = SavedTripRouteSegment(driveId: driveId, positions: detail.positions ?? [])
                        if segment.points.count >= 2 {
                            try? await routeCache?.save(points: segment.points, carId: carId, driveId: driveId)
                        }
                        return segment
                    }
                }
                var values: [SavedTripRouteSegment] = []
                for await segment in group {
                    if let segment { values.append(segment) }
                }
                return values
            }
            for segment in batchSegments {
                segmentsById[segment.driveId] = segment
            }
        }
        return driveIds.compactMap { segmentsById[$0] }
    }

    private static func tripDrive(from drive: DriveData) -> TripDrive? {
        guard
            let id = drive.driveId,
            let startDate = drive.startDate,
            let endDate = drive.endDate,
            let distance = drive.distance,
            let durationMin = drive.durationMin
        else {
            return nil
        }
        return TripDrive(
            id: id,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            durationMin: durationMin,
            energyConsumed: drive.usableEnergyConsumedNet,
            speedMax: drive.speedMax.map(Double.init),
            startAddress: drive.startAddress,
            endAddress: drive.endAddress,
            startBatteryLevel: drive.startBatteryLevel,
            endBatteryLevel: drive.endBatteryLevel
        )
    }

    private static func tripCharge(from charge: ChargeData) -> TripCharge? {
        guard
            let id = charge.chargeId,
            let startDate = charge.startDate,
            let endDate = charge.endDate
        else {
            return nil
        }
        return TripCharge(
            id: id,
            startDate: startDate,
            endDate: endDate,
            energyAdded: charge.chargeEnergyAdded,
            cost: charge.cost,
            durationMin: charge.durationMin,
            address: charge.address
        )
    }
}
