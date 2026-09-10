import Combine
import Foundation

public struct DriveReplaySample: Equatable, Sendable {
    public let position: DrivePosition
    public let latitude: Double
    public let longitude: Double

    public init(position: DrivePosition, latitude: Double, longitude: Double) {
        self.position = position
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum DriveReplayBuilder {
    public static func samples(from positions: [DrivePosition]) -> [DriveReplaySample] {
        var accepted: [DriveReplaySample] = []
        for position in positions {
            guard let location = GeoCoordinateValidator.location(latitude: position.latitude, longitude: position.longitude) else {
                continue
            }
            if let previous = accepted.last {
                let route = GeoCoordinateValidator.sanitizedRoute([
                    GeocodeRouteSample(latitude: previous.latitude, longitude: previous.longitude, date: previous.position.date),
                    GeocodeRouteSample(latitude: location.latitude, longitude: location.longitude, date: position.date)
                ])
                guard route.count == 2 else { continue }
            }
            accepted.append(DriveReplaySample(position: position, latitude: location.latitude, longitude: location.longitude))
        }
        return accepted
    }
}

public enum DriveReplayRenderPolicy {
    private static let maximumTrailRefreshCount = 120

    public static func shouldRefreshTrail(
        lastRenderedIndex: Int?,
        currentIndex: Int,
        sampleCount: Int
    ) -> Bool {
        guard sampleCount > 0 else { return false }
        let boundedIndex = min(max(currentIndex, 0), sampleCount - 1)
        guard let lastRenderedIndex else { return true }
        if boundedIndex == sampleCount - 1 { return true }
        let stride = max(Int(ceil(Double(sampleCount) / Double(maximumTrailRefreshCount))), 1)
        return abs(boundedIndex - lastRenderedIndex) >= stride
    }
}

public struct DriveWeatherPoint: Equatable, Identifiable, Sendable {
    public var id: String { "\(latitude),\(longitude),\(temperatureCelsius),\(weatherCode)" }

    public let latitude: Double
    public let longitude: Double
    public let temperatureCelsius: Double
    public let weatherCode: Int

    public init(point: WeatherPoint) {
        self.latitude = point.latitude
        self.longitude = point.longitude
        self.temperatureCelsius = point.temperatureCelsius
        self.weatherCode = point.weatherCode
    }
}

public struct DriveDetailState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var isShowingSummary: Bool
    public var isLoadingWeather: Bool
    public var isEnablingRouteWeather: Bool
    public var allowsThirdPartyRouteWeather: Bool
    public var routeWeatherPermissionFailed: Bool
    public var errorMessage: String?
    public var driveDetail: DriveDetail?
    public var units: UnitPreferences?
    public var stats: DriveDetailStats?
    public var weatherPoints: [DriveWeatherPoint]
    public var tripMembership: TripMembership?
    public var annotation: DriveAnnotation
    public var startGeofence: GeofenceRule?
    public var endGeofence: GeofenceRule?
    public var intelligence: DriveIntelligenceResult?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        isShowingSummary: Bool = false,
        isLoadingWeather: Bool = false,
        isEnablingRouteWeather: Bool = false,
        allowsThirdPartyRouteWeather: Bool = false,
        routeWeatherPermissionFailed: Bool = false,
        errorMessage: String? = nil,
        driveDetail: DriveDetail? = nil,
        units: UnitPreferences? = nil,
        stats: DriveDetailStats? = nil,
        weatherPoints: [DriveWeatherPoint] = [],
        tripMembership: TripMembership? = nil,
        annotation: DriveAnnotation = DriveAnnotation(),
        startGeofence: GeofenceRule? = nil,
        endGeofence: GeofenceRule? = nil,
        intelligence: DriveIntelligenceResult? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.isShowingSummary = isShowingSummary
        self.isLoadingWeather = isLoadingWeather
        self.isEnablingRouteWeather = isEnablingRouteWeather
        self.allowsThirdPartyRouteWeather = allowsThirdPartyRouteWeather
        self.routeWeatherPermissionFailed = routeWeatherPermissionFailed
        self.errorMessage = errorMessage
        self.driveDetail = driveDetail
        self.units = units
        self.stats = stats
        self.weatherPoints = weatherPoints
        self.tripMembership = tripMembership
        self.annotation = annotation
        self.startGeofence = startGeofence
        self.endGeofence = endGeofence
        self.intelligence = intelligence
    }
}

public struct DriveDetailCacheKey: Hashable, Sendable {
    public let serverURL: String
    public let carId: Int
    public let driveId: Int

    public init(serverURL: String, carId: Int, driveId: Int) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.carId = carId
        self.driveId = driveId
    }
}

public final class DriveDetailStateCache: @unchecked Sendable {
    public static let shared = DriveDetailStateCache()

    private let lock = NSLock()
    private let maximumEntryCount: Int
    private var states: [DriveDetailCacheKey: DriveDetailState] = [:]
    private var recency: [DriveDetailCacheKey] = []

    public init(maximumEntryCount: Int = 32) {
        self.maximumEntryCount = max(maximumEntryCount, 1)
    }

    public func state(for key: DriveDetailCacheKey) -> DriveDetailState? {
        lock.withLock {
            guard let state = states[key] else { return nil }
            markRecentlyUsed(key)
            return state
        }
    }

    public func save(_ state: DriveDetailState, for key: DriveDetailCacheKey) {
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.isLoadingWeather = false
        snapshot.isEnablingRouteWeather = false
        snapshot.routeWeatherPermissionFailed = false
        snapshot.errorMessage = nil
        lock.withLock {
            states[key] = snapshot
            markRecentlyUsed(key)
            while recency.count > maximumEntryCount, let oldest = recency.first {
                recency.removeFirst()
                states.removeValue(forKey: oldest)
            }
        }
    }

    public func removeAll() {
        lock.withLock {
            states.removeAll()
            recency.removeAll()
        }
    }

    private func markRecentlyUsed(_ key: DriveDetailCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

@MainActor
public final class DriveDetailViewModel: ObservableObject {
    @Published public private(set) var state: DriveDetailState

    private let api: any DriveAPIProviding
    private let weatherService: (any DriveWeatherServicing)?
    private let tripMembershipManager: (any TripMembershipManaging)?
    private let settingsStore: (any SettingsStoring)?
    private let summaryCache: (any DriveSummaryCaching)?
    private let cacheKey: DriveDetailCacheKey?
    private let stateCache: DriveDetailStateCache

    public init(
        api: any DriveAPIProviding,
        weatherService: (any DriveWeatherServicing)? = nil,
        tripMembershipManager: (any TripMembershipManaging)? = nil,
        settingsStore: (any SettingsStoring)? = nil,
        summaryCache: (any DriveSummaryCaching)? = nil,
        cacheKey: DriveDetailCacheKey? = nil,
        stateCache: DriveDetailStateCache = .shared,
        initialState: DriveDetailState = DriveDetailState()
    ) {
        self.api = api
        self.weatherService = weatherService
        self.tripMembershipManager = tripMembershipManager
        self.settingsStore = settingsStore
        self.summaryCache = summaryCache
        self.cacheKey = cacheKey
        self.stateCache = stateCache
        self.state = cacheKey.flatMap { stateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int, driveId: Int) async {
        guard !state.isRefreshing else { return }
        state.allowsThirdPartyRouteWeather = await routeWeatherPermission()
        if !state.allowsThirdPartyRouteWeather {
            state.weatherPoints = []
            state.isLoadingWeather = false
        }
        state.routeWeatherPermissionFailed = false
        state.isRefreshing = true
        state.isLoading = state.driveDetail == nil
        state.errorMessage = nil
        if state.driveDetail == nil {
            state.weatherPoints = []
        }

        async let detailResult = api.driveDetail(carId: carId, driveId: driveId)
        async let statusResult = api.carStatus(carId: carId)
        async let membershipResult = loadMembership(carId: carId, driveId: driveId)
        async let annotationResult = loadAnnotation(carId: carId, driveId: driveId)
        async let cachedSummary = loadCachedSummary(carId: carId, driveId: driveId)

        if state.driveDetail == nil, let summary = await cachedSummary {
            let detail = summary.previewDetail
            state.driveDetail = detail
            state.stats = DriveStatsCalculator.calculateStats(detail)
            state.isShowingSummary = true
            state.isLoading = false
            saveCachedState()
        } else {
            _ = await cachedSummary
        }

        switch await detailResult {
        case let .success(detail):
            state.driveDetail = detail
            state.stats = DriveStatsCalculator.calculateStats(detail)
            await updateGeofenceMatches(detail: detail, carId: carId)
            state.isShowingSummary = false
            state.isLoading = false
            state.isRefreshing = false
            saveCachedState()
            if state.allowsThirdPartyRouteWeather {
                await loadWeather(detail)
            }
            saveCachedState()
        case let .failure(error):
            state.isLoading = false
            state.isRefreshing = false
            state.isLoadingWeather = false
            state.errorMessage = error.driveMessage
        }

        switch await statusResult {
        case let .success(payload):
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
        case .failure:
            state.units = nil
        }
        state.tripMembership = await membershipResult
        state.annotation = await annotationResult
        if let detail = state.driveDetail {
            await updateIntelligence(detail: detail, carId: carId)
        }
        saveCachedState()
    }

    public func enableRouteWeather() async {
        guard !state.isEnablingRouteWeather else { return }
        guard let settingsStore else {
            state.routeWeatherPermissionFailed = true
            return
        }

        state.isEnablingRouteWeather = true
        state.routeWeatherPermissionFailed = false
        defer {
            state.isEnablingRouteWeather = false
            saveCachedState()
        }

        do {
            if let atomicStore = settingsStore as? any AtomicSettingsUpdating {
                _ = try await atomicStore.updateAtomically { current in
                    var updated = current
                    updated.allowsThirdPartyRouteWeather = true
                    return updated
                }
            } else {
                var settings = await settingsStore.load()
                settings.allowsThirdPartyRouteWeather = true
                try await settingsStore.saveThrowing(settings)
            }
            state.allowsThirdPartyRouteWeather = true
            if let detail = state.driveDetail {
                await loadWeather(detail)
            }
        } catch {
            state.routeWeatherPermissionFailed = true
        }
    }

    public func saveAnnotation(carId: Int, driveId: Int, annotation: DriveAnnotation) async {
        guard let settingsStore else {
            state.annotation = annotation
            saveCachedState()
            return
        }
        var settings = await settingsStore.load()
        settings.setDriveAnnotation(annotation, carId: carId, driveId: driveId)
        await settingsStore.save(settings)
        state.annotation = annotation
        if let detail = state.driveDetail {
            await updateIntelligence(detail: detail, carId: carId)
        }
        saveCachedState()
    }

    public func confirmSuggestion(carId: Int, driveId: Int) async {
        guard let settingsStore,
              let suggestion = state.intelligence?.suggestion,
              let detail = state.driveDetail
        else { return }
        var settings = await settingsStore.load()
        let rule = DriveIntelligenceEngine.confirmedRule(from: suggestion, carId: carId)
        settings.driveRouteLabelRules.append(rule)
        await settingsStore.save(settings)
        await updateIntelligence(detail: detail, carId: carId)
        saveCachedState()
    }

    public func updateRouteLabelRule(carId: Int, rule: DriveRouteLabelRule) async {
        guard let settingsStore, let detail = state.driveDetail else { return }
        var settings = await settingsStore.load()
        if let index = settings.driveRouteLabelRules.firstIndex(where: { $0.id == rule.id }) {
            settings.driveRouteLabelRules[index] = rule
        } else {
            settings.driveRouteLabelRules.append(rule)
        }
        await settingsStore.save(settings)
        await updateIntelligence(detail: detail, carId: carId)
        saveCachedState()
    }

    public func removeFromTrip(carId: Int, driveId: Int) async {
        guard let tripMembershipManager else { return }
        do {
            try await tripMembershipManager.remove(carId: carId, leg: .drive(driveId))
            state.tripMembership = nil
            state.errorMessage = nil
            saveCachedState()
        } catch { state.errorMessage = error.localizedDescription }
    }

    private func loadMembership(carId: Int, driveId: Int) async -> TripMembership? {
        try? await tripMembershipManager?.membership(carId: carId, leg: .drive(driveId))
    }

    private func loadAnnotation(carId: Int, driveId: Int) async -> DriveAnnotation {
        guard let settingsStore else { return DriveAnnotation() }
        return (await settingsStore.load()).driveAnnotation(carId: carId, driveId: driveId)
    }

    private func updateGeofenceMatches(detail: DriveDetail, carId: Int) async {
        guard let settingsStore else {
            state.startGeofence = nil
            state.endGeofence = nil
            return
        }
        let coordinates = (detail.positions ?? []).compactMap { position -> (Double, Double)? in
            guard let latitude = position.latitude, let longitude = position.longitude,
                  GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil
            else { return nil }
            return (latitude, longitude)
        }
        let settings = await settingsStore.load()
        state.startGeofence = coordinates.first.flatMap {
            GeofenceRuleEngine.matchingRule(latitude: $0.0, longitude: $0.1, carId: carId, rules: settings.geofenceRules)
        }
        state.endGeofence = coordinates.last.flatMap {
            GeofenceRuleEngine.matchingRule(latitude: $0.0, longitude: $0.1, carId: carId, rules: settings.geofenceRules)
        }
    }

    private func loadCachedSummary(carId: Int, driveId: Int) async -> DriveSummaryItem? {
        await summaryCache?.load(carId: carId).first { $0.driveId == driveId }
    }

    private func updateIntelligence(detail: DriveDetail, carId: Int) async {
        var summaries = await summaryCache?.load(carId: carId) ?? []
        let base = summaries.first(where: { $0.driveId == detail.driveId }) ?? DriveSummaryItem(
            driveId: detail.driveId,
            carId: carId,
            startDate: detail.startDate ?? "",
            endDate: detail.endDate,
            distance: detail.distance,
            durationMin: detail.durationMin,
            startAddress: detail.startAddress,
            endAddress: detail.endAddress,
            speedMax: detail.speedMax,
            speedAvg: detail.speedAvg,
            energyConsumedNet: detail.usableEnergyConsumedNet,
            efficiency: detail.usableConsumptionNet,
            outsideTempAvg: detail.outsideTempAvg,
            startBatteryLevel: detail.startBatteryLevel,
            endBatteryLevel: detail.endBatteryLevel,
            startRatedRangeKm: detail.rangeRated?.startRange,
            endRatedRangeKm: detail.rangeRated?.endRange
        )
        let enriched = base.withDetailAnalytics(detail)
        if let index = summaries.firstIndex(where: { $0.driveId == detail.driveId }) {
            summaries[index] = enriched
        } else {
            summaries.append(enriched)
        }
        await summaryCache?.save(summaries, carId: carId)
        guard let settingsStore else { return }
        let settings = await settingsStore.load()
        state.intelligence = DriveIntelligenceEngine.analyze(
            items: summaries,
            carId: carId,
            routeLabels: settings.driveRouteLabelRules,
            annotations: settings.driveAnnotations,
            geofences: settings.usesGeofencesForCommuteClassification ? settings.geofenceRules : []
        )[detail.driveId]
    }

    private func saveCachedState() {
        guard let cacheKey, state.driveDetail != nil else { return }
        stateCache.save(state, for: cacheKey)
    }

    private func routeWeatherPermission() async -> Bool {
        guard let settingsStore else { return false }
        return await settingsStore.load().allowsThirdPartyRouteWeather
    }

    private func loadWeather(_ detail: DriveDetail) async {
        guard state.weatherPoints.isEmpty else {
            state.isLoadingWeather = false
            return
        }
        guard let weatherService,
              let positions = detail.positions,
              let distance = detail.distance,
              !positions.isEmpty,
              distance > 0
        else {
            state.isLoadingWeather = false
            return
        }

        state.isLoadingWeather = true
        let routePositions = positions.map {
            WeatherRoutePosition(latitude: $0.latitude, longitude: $0.longitude, date: $0.date)
        }
        let points = await weatherService.weatherAlongDrive(positions: routePositions, totalDistanceKm: distance)
        state.weatherPoints = points.map(DriveWeatherPoint.init(point:))
        state.isLoadingWeather = false
    }
}

extension DriveSummaryItem {
    var previewDetail: DriveDetail {
        DriveDetail(
            driveId: driveId,
            startDate: startDate,
            endDate: endDate,
            startAddress: startAddress,
            endAddress: endAddress,
            distance: distance,
            durationMin: durationMin,
            speedMax: speedMax,
            speedAvg: speedAvg,
            batteryDetails: DriveBatteryDetails(
                startBatteryLevel: startBatteryLevel,
                endBatteryLevel: endBatteryLevel
            ),
            outsideTempAvg: outsideTempAvg,
            energyConsumedNet: energyConsumedNet,
            consumptionNet: efficiency
        )
    }
}
