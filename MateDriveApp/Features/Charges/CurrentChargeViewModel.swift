import Combine
import Foundation

public struct CurrentChargeState: Equatable, Sendable {
    public var isLoading: Bool
    public var hasLoadedData: Bool
    public var errorMessage: String?
    public var chargeDetail: ChargeDetail?
    public var units: UnitPreferences?
    public var stats: ChargeDetailStats?
    public var isDcCharge: Bool
    public var isNotCharging: Bool
    public var isChargeStarting: Bool
    public var timeToFullCharge: Double?
    public var chargeLimitSoc: Int?
    public var chronologicalPoints: [ChargePoint]
    public var isRefreshing: Bool
    public var lastUpdatedAt: Date?

    public init(
        isLoading: Bool = true,
        hasLoadedData: Bool = false,
        errorMessage: String? = nil,
        chargeDetail: ChargeDetail? = nil,
        units: UnitPreferences? = nil,
        stats: ChargeDetailStats? = nil,
        isDcCharge: Bool = false,
        isNotCharging: Bool = false,
        isChargeStarting: Bool = false,
        timeToFullCharge: Double? = nil,
        chargeLimitSoc: Int? = nil,
        chronologicalPoints: [ChargePoint] = [],
        isRefreshing: Bool = false,
        lastUpdatedAt: Date? = nil
    ) {
        self.isLoading = isLoading
        self.hasLoadedData = hasLoadedData
        self.errorMessage = errorMessage
        self.chargeDetail = chargeDetail
        self.units = units
        self.stats = stats
        self.isDcCharge = isDcCharge
        self.isNotCharging = isNotCharging
        self.isChargeStarting = isChargeStarting
        self.timeToFullCharge = timeToFullCharge
        self.chargeLimitSoc = chargeLimitSoc
        self.chronologicalPoints = chronologicalPoints
        self.isRefreshing = isRefreshing
        self.lastUpdatedAt = lastUpdatedAt
    }
}

@MainActor
public final class CurrentChargeViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<CurrentChargeState>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: CurrentChargeState

    private let api: any ChargeAPIProviding
    private let widgetSnapshotStore: WidgetSnapshotStore
    private let widgetTimelineReloader: any WidgetTimelineReloading
    private let liveActivityCoordinator: ChargeLiveActivityCoordinator
    private let vehicleIdentifier: String?
    private let displayLanguage: WidgetDisplayLanguage
    private let now: @Sendable () -> Date
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<CurrentChargeState>
    private var requestIsRunning = false

    public init(
        api: any ChargeAPIProviding,
        widgetSnapshotStore: WidgetSnapshotStore = .shared,
        widgetTimelineReloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(),
        liveActivityCoordinator: ChargeLiveActivityCoordinator = .disabled,
        vehicleIdentifier: String? = nil,
        displayLanguage: WidgetDisplayLanguage = .system,
        now: @escaping @Sendable () -> Date = Date.init,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<CurrentChargeState>? = nil,
        initialState: CurrentChargeState = CurrentChargeState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.widgetSnapshotStore = widgetSnapshotStore
        self.widgetTimelineReloader = widgetTimelineReloader
        self.liveActivityCoordinator = liveActivityCoordinator
        self.vehicleIdentifier = vehicleIdentifier
        self.displayLanguage = displayLanguage
        self.now = now
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public var automaticRefreshInterval: Duration {
        state.chargeDetail?.isCharging == true || state.isChargeStarting ? .seconds(5) : .seconds(30)
    }

    public func load(carId: Int, forceRefresh: Bool = false) async {
        guard !requestIsRunning else { return }
        requestIsRunning = true
        state.isRefreshing = state.hasLoadedData
        defer {
            requestIsRunning = false
            state.isRefreshing = false
        }
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil

        async let statusRequest = forceRefresh
            ? api.refreshCarStatus(carId: carId)
            : api.carStatus(carId: carId)
        async let chargeRequest = forceRefresh
            ? api.refreshCurrentCharge(carId: carId)
            : api.currentCharge(carId: carId)
        let (statusResult, currentChargeResult) = await (statusRequest, chargeRequest)
        let statusPayload: CarStatusPayload?
        switch statusResult {
        case let .success(payload):
            statusPayload = payload
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
            state.timeToFullCharge = payload.status?.chargingDetails?.timeToFullCharge
            state.chargeLimitSoc = payload.status?.chargeLimitSoc
        case .failure:
            statusPayload = nil
        }

        switch currentChargeResult {
        case let .success(.active(detail)):
            let chronological = Self.chronological(detail.chargePoints ?? [])
            let normalized = ChargeDetail(
                chargeId: detail.chargeId,
                startDate: detail.startDate,
                endDate: detail.endDate,
                address: detail.address,
                chargeEnergyAdded: detail.chargeEnergyAdded,
                chargeEnergyUsed: detail.chargeEnergyUsed,
                cost: detail.cost,
                durationMin: detail.durationMin,
                durationStr: detail.durationStr,
                batteryDetails: detail.batteryDetails,
                rangeIdeal: detail.rangeIdeal,
                rangeRated: detail.rangeRated,
                outsideTempAvg: detail.outsideTempAvg,
                odometer: detail.odometer,
                latitude: detail.latitude,
                longitude: detail.longitude,
                chargePoints: chronological,
                isCharging: detail.isCharging
            )
            state.chargeDetail = normalized
            state.stats = ChargingSessionAnalyzer.calculateStats(normalized)
            state.isDcCharge = statusPayload?.status?.isDcCharging ?? ChargingSessionAnalyzer.detectDcCharge(normalized)
            state.isNotCharging = normalized.isCharging == false
            state.isChargeStarting = false
            state.chronologicalPoints = normalized.chargePoints ?? []
            state.isLoading = false
            state.hasLoadedData = true
            state.lastUpdatedAt = now()
            saveCachedState()

        case .success(.noActiveCharge):
            state.chargeDetail = nil
            state.stats = nil
            state.isDcCharge = false
            state.chronologicalPoints = []
            if statusPayload?.status?.isCharging == true {
                state.isChargeStarting = true
                state.isNotCharging = false
            } else {
                state.isChargeStarting = false
                state.isNotCharging = true
                state.timeToFullCharge = nil
            }
            state.isLoading = false
            state.hasLoadedData = true
            state.lastUpdatedAt = now()
            saveCachedState()

        case let .failure(error):
            state.isLoading = false
            state.errorMessage = error.chargeMessage
        }

        let previous = vehicleIdentifier.flatMap {
            widgetSnapshotStore.vehicleSnapshot(vehicleIdentifier: $0)?.currentCharge
        }
        let currentCharge = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: statusResult,
            currentChargeResult: currentChargeResult,
            previous: previous,
            now: now()
        )
        guard let vehicleIdentifier else { return }

        if let currentCharge {
            let didChange = widgetSnapshotStore.updateCurrentCharge(
                currentCharge,
                vehicleIdentifier: vehicleIdentifier
            )
            if didChange {
                await widgetTimelineReloader.reloadTimelines(
                    ofKind: WidgetConstants.currentChargeKind
                )
            }
        }
        await liveActivityCoordinator.reconcile(
            carId: carId,
            event: ChargeLiveActivityEventFactory.event(
                currentCharge: currentCharge,
                carName: statusPayload?.status?.displayName ?? "MateDrive",
                vehicleIdentifier: vehicleIdentifier,
                displayLanguage: displayLanguage
            ),
            policy: .allowStart
        )
    }

    private func saveCachedState() {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }

    public static func chronological(_ points: [ChargePoint]) -> [ChargePoint] {
        let dated = points.compactMap { point -> (ChargePoint, Date)? in
            guard let date = point.date.flatMap(DomainDateParser.date(from:)) else { return nil }
            return (point, date)
        }
        guard dated.count == points.count, points.count > 1 else {
            return Array(points.reversed())
        }
        return dated.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
