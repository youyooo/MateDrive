import Foundation

public struct SyncDrivePosition: Codable, Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let elevation: Int?
    public let insideTemp: Double?
    public let outsideTemp: Double?
    public let power: Int?
    public let isClimateOn: Bool

    public init(latitude: Double? = nil, longitude: Double? = nil, elevation: Int? = nil, insideTemp: Double? = nil, outsideTemp: Double? = nil, power: Int? = nil, isClimateOn: Bool = false) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.insideTemp = insideTemp
        self.outsideTemp = outsideTemp
        self.power = power
        self.isClimateOn = isClimateOn
    }
}

public struct SyncDriveDetail: Codable, Equatable, Sendable {
    public let driveId: Int
    public let positions: [SyncDrivePosition]
    public let energyConsumedNet: Double?
    public let consumptionNet: Double?
    public let energySource: String?

    public init(
        driveId: Int,
        positions: [SyncDrivePosition],
        energyConsumedNet: Double? = nil,
        consumptionNet: Double? = nil,
        energySource: String? = nil
    ) {
        self.driveId = driveId
        self.positions = positions
        self.energyConsumedNet = energyConsumedNet
        self.consumptionNet = consumptionNet
        self.energySource = energySource
    }
}

public struct SyncChargerDetails: Codable, Equatable, Sendable {
    public let fastChargerPresent: Bool?
    public let fastChargerBrand: String?
    public let fastChargerType: String?
    public let chargerPhases: Int?

    public init(fastChargerPresent: Bool? = nil, fastChargerBrand: String? = nil, fastChargerType: String? = nil, chargerPhases: Int? = nil) {
        self.fastChargerPresent = fastChargerPresent
        self.fastChargerBrand = fastChargerBrand
        self.fastChargerType = fastChargerType
        self.chargerPhases = chargerPhases
    }
}

public struct SyncChargePoint: Codable, Equatable, Sendable {
    public let date: String?
    public let chargeEnergyAdded: Double?
    public let chargerPower: Int?
    public let chargerVoltage: Int?
    public let chargerCurrent: Int?
    public let outsideTemp: Double?
    public let chargerDetails: SyncChargerDetails?

    public init(date: String? = nil, chargeEnergyAdded: Double? = nil, chargerPower: Int? = nil, chargerVoltage: Int? = nil, chargerCurrent: Int? = nil, outsideTemp: Double? = nil, chargerDetails: SyncChargerDetails? = nil) {
        self.date = date
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargerPower = chargerPower
        self.chargerVoltage = chargerVoltage
        self.chargerCurrent = chargerCurrent
        self.outsideTemp = outsideTemp
        self.chargerDetails = chargerDetails
    }
}

public struct SyncChargeDetail: Codable, Equatable, Sendable {
    public let chargeId: Int
    public let latitude: Double?
    public let longitude: Double?
    public let chargePoints: [SyncChargePoint]
    public let chargeEnergyAdded: Double?
    public let chargeEnergyUsed: Double?
    public let startBatteryLevel: Int?
    public let endBatteryLevel: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let odometerKm: Double?

    public init(
        chargeId: Int,
        latitude: Double? = nil,
        longitude: Double? = nil,
        chargePoints: [SyncChargePoint],
        chargeEnergyAdded: Double? = nil,
        chargeEnergyUsed: Double? = nil,
        startBatteryLevel: Int? = nil,
        endBatteryLevel: Int? = nil,
        startRatedRangeKm: Double? = nil,
        endRatedRangeKm: Double? = nil,
        odometerKm: Double? = nil
    ) {
        self.chargeId = chargeId
        self.latitude = latitude
        self.longitude = longitude
        self.chargePoints = chargePoints
        self.chargeEnergyAdded = chargeEnergyAdded
        self.chargeEnergyUsed = chargeEnergyUsed
        self.startBatteryLevel = startBatteryLevel
        self.endBatteryLevel = endBatteryLevel
        self.startRatedRangeKm = startRatedRangeKm
        self.endRatedRangeKm = endRatedRangeKm
        self.odometerKm = odometerKm
    }
}

public protocol SyncAPIProviding: Sendable {
    func drives(carId: Int, page: Int, show: Int) async -> APIResult<[DriveData]>
    func charges(carId: Int, page: Int, show: Int) async -> APIResult<[ChargeData]>
    func driveDetail(carId: Int, driveId: Int) async -> APIResult<SyncDriveDetail>
    func chargeDetail(carId: Int, chargeId: Int) async -> APIResult<SyncChargeDetail>
}

public struct TeslamateSyncAPI: SyncAPIProviding {
    private let api: TeslamateAPI

    public init(api: TeslamateAPI) {
        self.api = api
    }

    public func drives(carId: Int, page: Int, show: Int) async -> APIResult<[DriveData]> {
        await api.refreshDrives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
    }

    public func charges(carId: Int, page: Int, show: Int) async -> APIResult<[ChargeData]> {
        await api.refreshCharges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
    }

    public func driveDetail(carId: Int, driveId: Int) async -> APIResult<SyncDriveDetail> {
        switch await api.driveDetail(carId: carId, driveId: driveId) {
        case let .success(detail):
            let directEnergy = detail.usableEnergyConsumedNet
            let estimatedEnergy = directEnergy == nil
                ? DriveStatsCalculator.estimatedNetEnergyKWh(from: detail.positions ?? [])
                : nil
            let resolvedEnergy = directEnergy ?? estimatedEnergy
            let resolvedConsumption = detail.usableConsumptionNet ?? resolvedEnergy.flatMap { energy in
                guard let distance = detail.distance, distance > 0 else { return nil }
                return energy * 1_000 / distance
            }
            return .success(SyncDriveDetail(
                driveId: detail.driveId,
                positions: (detail.positions ?? []).map {
                    SyncDrivePosition(
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        elevation: $0.elevation,
                        insideTemp: $0.insideTemp,
                        outsideTemp: $0.outsideTemp,
                        power: $0.power,
                        isClimateOn: $0.isClimateOn
                    )
                },
                energyConsumedNet: resolvedEnergy,
                consumptionNet: resolvedConsumption,
                energySource: directEnergy != nil ? DriveEnergySource.api.rawValue : (estimatedEnergy != nil ? DriveEnergySource.powerSamples.rawValue : nil)
            ))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func chargeDetail(carId: Int, chargeId: Int) async -> APIResult<SyncChargeDetail> {
        switch await api.chargeDetail(carId: carId, chargeId: chargeId) {
        case let .success(detail):
            return .success(SyncChargeDetail(
                chargeId: detail.chargeId,
                latitude: detail.latitude,
                longitude: detail.longitude,
                chargePoints: (detail.chargePoints ?? []).map { point in
                    SyncChargePoint(
                        date: point.date,
                        chargeEnergyAdded: point.chargeEnergyAdded,
                        chargerPower: point.chargerPower,
                        chargerVoltage: point.chargerVoltage,
                        chargerCurrent: point.chargerCurrent,
                        outsideTemp: point.outsideTemp,
                        chargerDetails: (point.chargerDetails != nil || point.connectorType != nil) ? SyncChargerDetails(
                            fastChargerPresent: point.chargerDetails?.fastChargerPresent,
                            fastChargerBrand: point.chargerDetails?.fastChargerBrand,
                            fastChargerType: point.chargerDetails?.fastChargerType ?? point.connectorType,
                            chargerPhases: point.chargerDetails?.chargerPhases
                        ) : nil
                    )
                },
                chargeEnergyAdded: detail.chargeEnergyAdded,
                chargeEnergyUsed: detail.chargeEnergyUsed,
                startBatteryLevel: detail.startBatteryLevel,
                endBatteryLevel: detail.endBatteryLevel,
                startRatedRangeKm: detail.rangeRated?.startRange,
                endRatedRangeKm: detail.rangeRated?.endRange,
                odometerKm: detail.odometer
            ))
        case let .failure(error):
            return .failure(error)
        }
    }
}

public protocol SyncPersisting: Sendable {
    func upsertDriveSummaries(_ records: [DriveSummaryRecord]) async throws
    func upsertChargeSummaries(_ records: [ChargeSummaryRecord]) async throws
    func unprocessedDriveIds(carId: Int, schemaVersion: Int) async throws -> [Int]
    func unprocessedChargeIds(carId: Int, schemaVersion: Int) async throws -> [Int]
    func upsertDriveAggregates(_ records: [DriveDetailAggregateRecord]) async throws
    func upsertChargeAggregates(_ records: [ChargeDetailAggregateRecord]) async throws
    func state(carId: Int) async throws -> SyncStateRecord?
    func upsertState(_ state: SyncStateRecord) async throws
}

public struct DatabaseBackedSyncStore: SyncPersisting {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func upsertDriveSummaries(_ records: [DriveSummaryRecord]) async throws {
        let database = try await databaseProvider.database()
        try await DriveSummaryStore(database: database).upsertAll(records)
    }

    public func upsertChargeSummaries(_ records: [ChargeSummaryRecord]) async throws {
        let database = try await databaseProvider.database()
        try await ChargeSummaryStore(database: database).upsertAll(records)
    }

    public func unprocessedDriveIds(carId: Int, schemaVersion: Int) async throws -> [Int] {
        let database = try await databaseProvider.database()
        return try await DriveSummaryStore(database: database).unprocessedDriveIds(carId: carId, schemaVersion: schemaVersion)
    }

    public func unprocessedChargeIds(carId: Int, schemaVersion: Int) async throws -> [Int] {
        let database = try await databaseProvider.database()
        return try await ChargeSummaryStore(database: database).unprocessedChargeIds(carId: carId, schemaVersion: schemaVersion)
    }

    public func upsertDriveAggregates(_ records: [DriveDetailAggregateRecord]) async throws {
        let database = try await databaseProvider.database()
        let aggregateStore = AggregateStore(database: database)
        let summaryStore = DriveSummaryStore(database: database)
        for record in records {
            try await aggregateStore.upsertDriveAggregate(record)
            try await summaryStore.updateEnergy(
                driveId: record.driveId,
                energyConsumedNet: record.energyConsumedNet,
                consumptionNet: record.consumptionNet,
                source: record.energySource
            )
        }
        try await summaryStore.markProcessed(ids: records.map(\.driveId), schemaVersion: SchemaVersion.current)
    }

    public func upsertChargeAggregates(_ records: [ChargeDetailAggregateRecord]) async throws {
        let database = try await databaseProvider.database()
        let aggregateStore = AggregateStore(database: database)
        let summaryStore = ChargeSummaryStore(database: database)
        for record in records {
            try await aggregateStore.upsertChargeAggregate(record)
            try await summaryStore.updateTelemetry(
                chargeId: record.chargeId,
                chargeEnergyAdded: record.chargeEnergyAdded,
                chargeEnergyUsed: record.chargeEnergyUsed,
                startBatteryLevel: record.startBatteryLevel,
                endBatteryLevel: record.endBatteryLevel,
                startRatedRangeKm: record.startRatedRangeKm,
                endRatedRangeKm: record.endRatedRangeKm,
                odometerKm: record.odometerKm,
                latitude: record.latitude,
                longitude: record.longitude
            )
        }
        try await summaryStore.markProcessed(ids: records.map(\.chargeId), schemaVersion: SchemaVersion.current)
    }

    public func state(carId: Int) async throws -> SyncStateRecord? {
        let database = try await databaseProvider.database()
        return try await SQLiteSyncStateStore(database: database).state(carId: carId)
    }

    public func upsertState(_ state: SyncStateRecord) async throws {
        let database = try await databaseProvider.database()
        try await SQLiteSyncStateStore(database: database).upsertState(state)
    }
}

public struct HistorySyncReport: Equatable, Sendable {
    public let attemptedCarIDs: [Int]
    public let completedCarIDs: [Int]
    public let failedCarIDs: [Int]

    public var isComplete: Bool { !attemptedCarIDs.isEmpty && failedCarIDs.isEmpty }

    public init(attemptedCarIDs: [Int], completedCarIDs: [Int], failedCarIDs: [Int]) {
        self.attemptedCarIDs = attemptedCarIDs
        self.completedCarIDs = completedCarIDs
        self.failedCarIDs = failedCarIDs
    }
}

public protocol HistorySyncRunning: Sendable {
    func run() async -> HistorySyncReport
}

public struct EmptyHistorySyncRunner: HistorySyncRunning {
    public init() {}

    public func run() async -> HistorySyncReport {
        HistorySyncReport(attemptedCarIDs: [], completedCarIDs: [], failedCarIDs: [])
    }
}

public struct HistorySyncRunner: HistorySyncRunning {
    private let settingsStore: any SettingsStoring
    private let secretStore: any SecretStoring
    private let databaseProvider: any AppDatabaseProviding

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring, databaseProvider: any AppDatabaseProviding) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.databaseProvider = databaseProvider
    }

    public func run() async -> HistorySyncReport {
        let settings = await settingsStore.load()
        guard settings.isConfigured else {
            return HistorySyncReport(attemptedCarIDs: [], completedCarIDs: [], failedCarIDs: [])
        }
        let factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
        guard let (api, cars) = await resolveAPIAndCars(settings: settings, factory: factory) else {
            return HistorySyncReport(attemptedCarIDs: [], completedCarIDs: [], failedCarIDs: [])
        }

        let geocodingService = GeocodingService(
            queueStore: DatabaseBackedGeocodeQueueStore(databaseProvider: databaseProvider)
        )
        let coordinator = SyncCoordinator(
            api: TeslamateSyncAPI(api: api),
            stores: DatabaseBackedSyncStore(databaseProvider: databaseProvider),
            geocodingService: geocodingService
        )
        let carIDs = cars.map(\.carId)
        var completed: [Int] = []
        var failed: [Int] = []
        for carID in carIDs {
            if Task.isCancelled {
                failed.append(contentsOf: carIDs.filter { !completed.contains($0) && !failed.contains($0) })
                break
            }
            do {
                if try await coordinator.syncCar(carId: carID) {
                    completed.append(carID)
                } else {
                    failed.append(carID)
                }
            } catch {
                failed.append(carID)
            }
        }
        return HistorySyncReport(attemptedCarIDs: carIDs, completedCarIDs: completed, failedCarIDs: failed)
    }

    private func resolveAPIAndCars(
        settings: AppSettings,
        factory: SettingsBackedTeslamateAPIFactory
    ) async -> (TeslamateAPI, [CarData])? {
        var candidates = [settings]
        let secondary = settings.secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondary.isEmpty, secondary != settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines) {
            var fallback = settings
            fallback.serverURL = secondary
            candidates.append(fallback)
        }
        for candidate in candidates {
            guard case let .success(api) = await factory.makeAPI(settings: candidate),
                  case let .success(cars) = await api.cars(),
                  !cars.isEmpty
            else { continue }
            return (api, cars)
        }
        return nil
    }
}

public protocol SyncGeocodingServicing: Sendable {
    @discardableResult
    func enqueueLocations(carId: Int, locations: [GeocodeLocation]) async throws -> Int
}

public actor SyncCoordinator {
    public static let detailBatchSize = 3
    public static let summaryPageSize = 200
    public static let maximumSummaryPages = 2_500

    private let api: any SyncAPIProviding
    private let stores: any SyncPersisting
    private let geocodingService: any SyncGeocodingServicing
    private let jsonEncoder = JSONEncoder()
    private var carProgresses: [Int: SyncProgress] = [:]

    public init(api: any SyncAPIProviding, stores: any SyncPersisting, geocodingService: any SyncGeocodingServicing) {
        self.api = api
        self.stores = stores
        self.geocodingService = geocodingService
    }

    public var overallStatus: OverallSyncStatus {
        let isAnySyncing = carProgresses.values.contains { progress in
            progress.phase != .complete && progress.phase != .idle && !progress.isError
        }
        let allComplete = !carProgresses.isEmpty && carProgresses.values.allSatisfy { $0.phase == .complete }
        return OverallSyncStatus(carProgresses: carProgresses, isAnySyncing: isAnySyncing, allComplete: allComplete)
    }

    public func progress(for carId: Int) -> SyncProgress? {
        carProgresses[carId]
    }

    @discardableResult
    public func syncCar(carId: Int) async throws -> Bool {
        updateProgress(carId: carId, phase: .syncingSummaries, current: 0, total: 1, message: "Fetching drives and charges...")

        guard try await syncSummaries(carId: carId) else {
            if !Task.isCancelled {
                markError(carId: carId, message: "Failed to sync summaries")
            }
            return false
        }

        var state = try await markSummariesComplete(carId: carId)
        if state.detailsSynced {
            updateProgress(carId: carId, phase: .complete, current: 1, total: 1)
            return true
        }

        guard try await syncDriveDetails(carId: carId) else {
            if !Task.isCancelled {
                markError(carId: carId, message: "Failed to sync drive details")
            }
            return false
        }

        state = try await markDriveDetailsComplete(carId: carId)
        if state.detailsSynced {
            updateProgress(carId: carId, phase: .complete, current: 1, total: 1)
            return true
        }

        guard try await syncChargeDetails(carId: carId) else {
            if !Task.isCancelled {
                markError(carId: carId, message: "Failed to sync charge details")
            }
            return false
        }

        state.detailsSynced = true
        try await stores.upsertState(state)
        updateProgress(carId: carId, phase: .complete, current: 1, total: 1)
        return true
    }

    private func syncSummaries(carId: Int) async throws -> Bool {
        async let drivesComplete = syncDriveSummaryPages(carId: carId)
        async let chargesComplete = syncChargeSummaryPages(carId: carId)
        let results = try await (drivesComplete, chargesComplete)
        guard !Task.isCancelled else { return false }
        return results.0 && results.1
    }

    private func syncDriveSummaryPages(carId: Int) async throws -> Bool {
        var page = 1
        var seenIDs: Set<Int> = []

        while page <= Self.maximumSummaryPages {
            guard !Task.isCancelled else { return false }
            switch await api.drives(carId: carId, page: page, show: Self.summaryPageSize) {
            case .failure:
                return false
            case let .success(items):
                guard !Task.isCancelled else { return false }
                let newItems = items.filter { item in
                    guard let id = item.driveId else { return false }
                    return seenIDs.insert(id).inserted
                }
                try await stores.upsertDriveSummaries(newItems.compactMap {
                    Self.driveSummaryRecord(from: $0, carId: carId)
                })

                if items.isEmpty {
                    return true
                }
                guard !newItems.isEmpty else {
                    return false
                }
                page += 1
            }
        }

        return false
    }

    private func syncChargeSummaryPages(carId: Int) async throws -> Bool {
        var page = 1
        var seenIDs: Set<Int> = []

        while page <= Self.maximumSummaryPages {
            guard !Task.isCancelled else { return false }
            switch await api.charges(carId: carId, page: page, show: Self.summaryPageSize) {
            case .failure:
                return false
            case let .success(items):
                guard !Task.isCancelled else { return false }
                let newItems = items.filter { item in
                    guard let id = item.chargeId else { return false }
                    return seenIDs.insert(id).inserted
                }
                try await stores.upsertChargeSummaries(newItems.compactMap {
                    Self.chargeSummaryRecord(from: $0, carId: carId)
                })

                if items.isEmpty {
                    return true
                }
                guard !newItems.isEmpty else {
                    return false
                }
                page += 1
            }
        }

        return false
    }

    private static func driveSummaryRecord(from drive: DriveData, carId: Int) -> DriveSummaryRecord? {
        guard let driveId = drive.driveId,
              let startDate = drive.startDate, !startDate.isEmpty,
              let endDate = drive.endDate, !endDate.isEmpty
        else { return nil }
        return DriveSummaryRecord(
            driveId: driveId,
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            distance: drive.distance,
            durationMin: drive.durationMin,
            energyConsumedNet: drive.usableEnergyConsumedNet,
            consumptionNet: drive.usableConsumptionNet,
            energySource: (drive.usableEnergyConsumedNet != nil || drive.usableConsumptionNet != nil) ? "api" : nil,
            startBatteryLevel: drive.startBatteryLevel,
            endBatteryLevel: drive.endBatteryLevel,
            startRatedRangeKm: drive.rangeRated?.startRange,
            endRatedRangeKm: drive.rangeRated?.endRange,
            startAddress: drive.startAddress,
            endAddress: drive.endAddress,
            speedAvg: drive.speedAvg ?? drive.averageSpeed,
            outsideTempAvg: drive.outsideTempAvg,
            schemaVersion: 0
        )
    }

    private static func chargeSummaryRecord(from charge: ChargeData, carId: Int) -> ChargeSummaryRecord? {
        guard let chargeId = charge.chargeId,
              let startDate = charge.startDate, !startDate.isEmpty
        else { return nil }
        return ChargeSummaryRecord(
            chargeId: chargeId,
            carId: carId,
            startDate: startDate,
            endDate: charge.endDate,
            chargeEnergyAdded: charge.chargeEnergyAdded,
            cost: charge.cost,
            durationMin: charge.durationMin,
            address: charge.address,
            latitude: charge.latitude,
            longitude: charge.longitude,
            chargeEnergyUsed: charge.chargeEnergyUsed,
            startBatteryLevel: charge.startBatteryLevel,
            endBatteryLevel: charge.endBatteryLevel,
            startRatedRangeKm: charge.rangeRated?.startRange,
            endRatedRangeKm: charge.rangeRated?.endRange,
            odometerKm: charge.odometer,
            schemaVersion: 0
        )
    }

    private func markSummariesComplete(carId: Int) async throws -> SyncStateRecord {
        let unprocessedDrives = try await stores.unprocessedDriveIds(carId: carId, schemaVersion: SchemaVersion.current)
        let unprocessedCharges = try await stores.unprocessedChargeIds(carId: carId, schemaVersion: SchemaVersion.current)
        var state = try await stores.state(carId: carId) ?? SyncStateRecord(carId: carId)
        let now = Int64(Date().timeIntervalSince1970 * 1000)

        state.lastDriveSyncAt = now
        state.lastChargeSyncAt = now
        state.totalDrivesToProcess = unprocessedDrives.count
        state.totalChargesToProcess = unprocessedCharges.count
        state.drivesProcessed = 0
        state.chargesProcessed = 0
        state.summariesSynced = true
        state.detailSchemaVersion = SchemaVersion.current
        state.detailsSynced = unprocessedDrives.isEmpty && unprocessedCharges.isEmpty
        try await stores.upsertState(state)

        if state.detailsSynced {
            updateProgress(carId: carId, phase: .complete, current: 1, total: 1)
        } else {
            updateProgress(carId: carId, phase: .syncingDriveDetails, current: 0, total: unprocessedDrives.count + unprocessedCharges.count)
        }

        return state
    }

    private func syncDriveDetails(carId: Int) async throws -> Bool {
        let ids = try await stores.unprocessedDriveIds(carId: carId, schemaVersion: SchemaVersion.current)
        let total = ids.count + (try await stores.unprocessedChargeIds(carId: carId, schemaVersion: SchemaVersion.current).count)

        for batch in ids.chunked(into: Self.detailBatchSize) {
            guard !Task.isCancelled else { return false }
            var aggregates: [DriveDetailAggregateRecord] = []
            var locations: [GeocodeLocation] = []
            let api = api
            let details = await withTaskGroup(of: (Int, APIResult<SyncDriveDetail>).self) { group in
                for driveId in batch {
                    group.addTask {
                        (driveId, await api.driveDetail(carId: carId, driveId: driveId))
                    }
                }
                var values: [Int: APIResult<SyncDriveDetail>] = [:]
                for await (driveId, result) in group {
                    values[driveId] = result
                }
                return values
            }
            guard !Task.isCancelled else { return false }

            for driveId in batch {
                guard let result = details[driveId] else { continue }
                switch result {
                case let .success(detail):
                    let aggregate = try computeDriveAggregate(carId: carId, detail: detail)
                    aggregates.append(aggregate.record)
                    locations.append(contentsOf: aggregate.locations)
                case .failure:
                    continue
                }
            }

            if !aggregates.isEmpty {
                try await stores.upsertDriveAggregates(aggregates)
            }
            if !locations.isEmpty {
                try await geocodingService.enqueueLocations(carId: carId, locations: locations)
            }

            if let lastSyncedId = aggregates.last?.driveId {
                var state = try await stores.state(carId: carId) ?? SyncStateRecord(carId: carId)
                state.lastDriveDetailId = lastSyncedId
                state.drivesProcessed += aggregates.count
                try await stores.upsertState(state)
                updateProgress(carId: carId, phase: .syncingDriveDetails, current: state.drivesProcessed, total: total)
            }
        }

        return try await stores.unprocessedDriveIds(carId: carId, schemaVersion: SchemaVersion.current).isEmpty
    }

    private func markDriveDetailsComplete(carId: Int) async throws -> SyncStateRecord {
        var state = try await stores.state(carId: carId) ?? SyncStateRecord(carId: carId)
        let total = state.totalDrivesToProcess + state.totalChargesToProcess

        if state.totalChargesToProcess > 0 {
            updateProgress(carId: carId, phase: .syncingChargeDetails, current: state.drivesProcessed, total: total)
        } else {
            state.detailsSynced = true
            try await stores.upsertState(state)
            updateProgress(carId: carId, phase: .complete, current: 1, total: 1)
        }

        return state
    }

    private func syncChargeDetails(carId: Int) async throws -> Bool {
        let ids = try await stores.unprocessedChargeIds(carId: carId, schemaVersion: SchemaVersion.current)
        let total = (try await stores.state(carId: carId)?.totalDrivesToProcess ?? 0) + ids.count

        for batch in ids.chunked(into: Self.detailBatchSize) {
            guard !Task.isCancelled else { return false }
            var aggregates: [ChargeDetailAggregateRecord] = []
            var locations: [GeocodeLocation] = []
            let api = api
            let details = await withTaskGroup(of: (Int, APIResult<SyncChargeDetail>).self) { group in
                for chargeId in batch {
                    group.addTask {
                        (chargeId, await api.chargeDetail(carId: carId, chargeId: chargeId))
                    }
                }
                var values: [Int: APIResult<SyncChargeDetail>] = [:]
                for await (chargeId, result) in group {
                    values[chargeId] = result
                }
                return values
            }
            guard !Task.isCancelled else { return false }

            for chargeId in batch {
                guard let result = details[chargeId] else { continue }
                switch result {
                case let .success(detail):
                    aggregates.append(try computeChargeAggregate(carId: carId, detail: detail))
                    if let location = GeoCoordinateValidator.location(latitude: detail.latitude, longitude: detail.longitude) {
                        locations.append(location)
                    }
                case .failure:
                    continue
                }
            }

            if !aggregates.isEmpty {
                try await stores.upsertChargeAggregates(aggregates)
            }
            if !locations.isEmpty {
                try await geocodingService.enqueueLocations(carId: carId, locations: locations)
            }

            if let lastSyncedId = aggregates.last?.chargeId {
                var state = try await stores.state(carId: carId) ?? SyncStateRecord(carId: carId)
                state.lastChargeDetailId = lastSyncedId
                state.chargesProcessed += aggregates.count
                try await stores.upsertState(state)
                updateProgress(carId: carId, phase: .syncingChargeDetails, current: state.drivesProcessed + state.chargesProcessed, total: total)
            }
        }

        return try await stores.unprocessedChargeIds(carId: carId, schemaVersion: SchemaVersion.current).isEmpty
    }

    private func computeDriveAggregate(carId: Int, detail: SyncDriveDetail) throws -> (record: DriveDetailAggregateRecord, locations: [GeocodeLocation]) {
        let positions = detail.positions
        var maxElevation: Int?
        var minElevation: Int?
        var maxInsideTemp: Double?
        var minInsideTemp: Double?
        var maxOutsideTemp: Double?
        var minOutsideTemp: Double?
        var maxPower: Int?
        var minPower: Int?
        var climateOnCount = 0
        var elevationGain = 0
        var elevationLoss = 0
        var previousElevation: Int?

        for position in positions {
            if let elevation = position.elevation {
                maxElevation = max(maxElevation ?? elevation, elevation)
                minElevation = min(minElevation ?? elevation, elevation)
                if let previousElevation {
                    let diff = elevation - previousElevation
                    if diff > 0 {
                        elevationGain += diff
                    } else {
                        elevationLoss += -diff
                    }
                }
                previousElevation = elevation
            }
            if let insideTemp = position.insideTemp {
                maxInsideTemp = max(maxInsideTemp ?? insideTemp, insideTemp)
                minInsideTemp = min(minInsideTemp ?? insideTemp, insideTemp)
            }
            if let outsideTemp = position.outsideTemp {
                maxOutsideTemp = max(maxOutsideTemp ?? outsideTemp, outsideTemp)
                minOutsideTemp = min(minOutsideTemp ?? outsideTemp, outsideTemp)
            }
            if let power = position.power {
                maxPower = max(maxPower ?? power, power)
                minPower = min(minPower ?? power, power)
            }
            if position.isClimateOn {
                climateOnCount += 1
            }
        }

        let first = positions.first
        let last = positions.last
        let payload = SyncDriveAggregatePayload(
            maxElevation: maxElevation,
            minElevation: minElevation,
            startElevation: first?.elevation,
            endElevation: last?.elevation,
            elevationGain: maxElevation == nil ? nil : elevationGain,
            elevationLoss: maxElevation == nil ? nil : elevationLoss,
            hasElevationData: maxElevation != nil,
            maxInsideTemp: maxInsideTemp,
            minInsideTemp: minInsideTemp,
            maxOutsideTemp: maxOutsideTemp,
            minOutsideTemp: minOutsideTemp,
            maxPower: maxPower,
            minPower: minPower,
            climateOnPositions: climateOnCount,
            positionCount: positions.count,
            startLatitude: first?.latitude,
            startLongitude: first?.longitude,
            endLatitude: last?.latitude,
            endLongitude: last?.longitude
        )
        let json = String(decoding: try jsonEncoder.encode(payload), as: UTF8.self)
        let record = DriveDetailAggregateRecord(
            driveId: detail.driveId,
            carId: carId,
            payloadJSON: json,
            schemaVersion: SchemaVersion.current,
            energyConsumedNet: detail.energyConsumedNet,
            consumptionNet: detail.consumptionNet,
            energySource: detail.energySource
        )
        let locations = [first, last].compactMap { position -> GeocodeLocation? in
            GeoCoordinateValidator.location(latitude: position?.latitude, longitude: position?.longitude)
        }
        return (record, locations)
    }

    private func computeChargeAggregate(carId: Int, detail: SyncChargeDetail) throws -> ChargeDetailAggregateRecord {
        let points = detail.chargePoints
        let firstChargerDetails = points.first { $0.chargerDetails != nil }?.chargerDetails
        var maxPower: Int?
        var maxVoltage: Int?
        var maxCurrent: Int?
        var maxOutsideTemp: Double?
        var minOutsideTemp: Double?
        var phaseVotes: [Int: Int] = [:]

        for point in points {
            if let chargerPower = point.chargerPower {
                maxPower = max(maxPower ?? chargerPower, chargerPower)
            }
            if let chargerVoltage = point.chargerVoltage {
                maxVoltage = max(maxVoltage ?? chargerVoltage, chargerVoltage)
            }
            if let chargerCurrent = point.chargerCurrent {
                maxCurrent = max(maxCurrent ?? chargerCurrent, chargerCurrent)
            }
            if let outsideTemp = point.outsideTemp {
                maxOutsideTemp = max(maxOutsideTemp ?? outsideTemp, outsideTemp)
                minOutsideTemp = min(minOutsideTemp ?? outsideTemp, outsideTemp)
            }
            if let phases = point.chargerDetails?.chargerPhases {
                phaseVotes[phases, default: 0] += 1
            }
        }

        let modePhases = phaseVotes.max { lhs, rhs in lhs.value < rhs.value }?.key
        let isFastCharger = firstChargerDetails?.fastChargerPresent ?? modePhases.map { $0 == 0 }
        let payload = SyncChargeAggregatePayload(
            isFastCharger: isFastCharger,
            fastChargerBrand: firstChargerDetails?.fastChargerBrand == "<invalid>" ? nil : firstChargerDetails?.fastChargerBrand,
            connectorType: firstChargerDetails?.fastChargerType,
            maxChargerPower: maxPower,
            maxChargerVoltage: maxVoltage,
            maxChargerCurrent: maxCurrent,
            chargerPhases: firstChargerDetails?.chargerPhases,
            maxOutsideTemp: maxOutsideTemp,
            minOutsideTemp: minOutsideTemp,
            chargePointCount: points.count,
            energySamples: points.map {
                SyncChargeEnergySamplePayload(date: $0.date, chargeEnergyAdded: $0.chargeEnergyAdded)
            }
        )
        let json = String(decoding: try jsonEncoder.encode(payload), as: UTF8.self)
        return ChargeDetailAggregateRecord(
            chargeId: detail.chargeId,
            carId: carId,
            payloadJSON: json,
            schemaVersion: SchemaVersion.current,
            chargeEnergyAdded: detail.chargeEnergyAdded,
            chargeEnergyUsed: detail.chargeEnergyUsed,
            startBatteryLevel: detail.startBatteryLevel,
            endBatteryLevel: detail.endBatteryLevel,
            startRatedRangeKm: detail.startRatedRangeKm,
            endRatedRangeKm: detail.endRatedRangeKm,
            odometerKm: detail.odometerKm,
            latitude: detail.latitude,
            longitude: detail.longitude
        )
    }

    private func updateProgress(carId: Int, phase: SyncPhase, current: Int, total: Int, message: String? = nil) {
        carProgresses[carId] = SyncProgress(carId: carId, phase: phase, currentItem: current, totalItems: total, message: message)
    }

    private func markError(carId: Int, message: String) {
        updateProgress(carId: carId, phase: .error(message), current: 0, total: 0, message: message)
    }
}

private struct SyncDriveAggregatePayload: Codable, Equatable, Sendable {
    let maxElevation: Int?
    let minElevation: Int?
    let startElevation: Int?
    let endElevation: Int?
    let elevationGain: Int?
    let elevationLoss: Int?
    let hasElevationData: Bool
    let maxInsideTemp: Double?
    let minInsideTemp: Double?
    let maxOutsideTemp: Double?
    let minOutsideTemp: Double?
    let maxPower: Int?
    let minPower: Int?
    let climateOnPositions: Int
    let positionCount: Int
    let startLatitude: Double?
    let startLongitude: Double?
    let endLatitude: Double?
    let endLongitude: Double?
}

private struct SyncChargeAggregatePayload: Codable, Equatable, Sendable {
    let isFastCharger: Bool?
    let fastChargerBrand: String?
    let connectorType: String?
    let maxChargerPower: Int?
    let maxChargerVoltage: Int?
    let maxChargerCurrent: Int?
    let chargerPhases: Int?
    let maxOutsideTemp: Double?
    let minOutsideTemp: Double?
    let chargePointCount: Int
    let energySamples: [SyncChargeEnergySamplePayload]
}

private struct SyncChargeEnergySamplePayload: Codable, Equatable, Sendable {
    let date: String?
    let chargeEnergyAdded: Double?
}

private extension SyncProgress {
    var isError: Bool {
        if case .error = phase {
            return true
        }
        return false
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
