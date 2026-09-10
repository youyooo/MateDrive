import XCTest
@testable import MateDriveApp

@MainActor
final class CurrentChargeViewModelTests: XCTestCase {
    func testCurrentChargeLoadsActiveChargeAndStats() async throws {
        let api = FakeChargeAPI(
            currentChargeResult: .success(.active(.activeFixture)),
            statusResult: .success(.chargingStatus)
        )
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertTrue(viewModel.state.hasLoadedData)
        XCTAssertEqual(viewModel.state.chargeDetail?.chargeId, 9)
        XCTAssertEqual(viewModel.state.stats?.powerMax, 120)
        XCTAssertEqual(viewModel.state.stats?.batteryAdded, 30)
        XCTAssertTrue(viewModel.state.isDcCharge)
        XCTAssertEqual(viewModel.state.chronologicalPoints.map(\.batteryLevel), [40, 70])
        XCTAssertEqual(viewModel.state.chargeLimitSoc, 80)
        XCTAssertNotNil(viewModel.state.lastUpdatedAt)
        XCTAssertFalse(viewModel.state.isRefreshing)
    }

    // Production break caught: a successful detail response fails to upgrade the selected vehicle's partial data or reconcile foreground start.
    func testCurrentChargeDetailUpgradesPartialSnapshotToComplete() async throws {
        let suiteName = "CurrentChargeCompleteIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let reloader = CurrentChargeRecordingWidgetTimelineReloader()
        let liveActivity = CurrentChargeRecordingLiveActivityManager()
        let vehicleIdentifier = String(repeating: "a", count: 64)
        let timestamp = Date(timeIntervalSince1970: 1_786_100_000)
        store.save(
            .fixture(carName: "Test car 7", batteryLevel: 67, isCharging: true),
            vehicleIdentifier: vehicleIdentifier
        )
        let viewModel = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .success(.active(.widgetIntegrationFixture)),
                statusResult: .success(.chargingIntegrationStatus)
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: reloader,
            liveActivityCoordinator: ChargeLiveActivityCoordinator(manager: liveActivity),
            vehicleIdentifier: vehicleIdentifier,
            displayLanguage: .english,
            now: { timestamp }
        )

        await viewModel.load(carId: 7)

        let snapshot = try XCTUnwrap(
            store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge
        )
        let calls = await liveActivity.recordedCalls()
        let activitySnapshots = await liveActivity.recordedStartSnapshots()
        let reloadedKinds = await reloader.recordedKinds()
        XCTAssertEqual(snapshot.phase, .charging)
        XCTAssertEqual(snapshot.quality, .complete)
        XCTAssertEqual(snapshot.energyAddedKWh, 18.4)
        XCTAssertEqual(calls, [.startOrUpdate(carId: 7)])
        let activitySnapshot = try XCTUnwrap(activitySnapshots.first)
        XCTAssertEqual(activitySnapshots.count, 1)
        XCTAssertEqual(activitySnapshot.vehicleIdentifier, vehicleIdentifier)
        XCTAssertEqual(activitySnapshot.batteryLevel, 67)
        XCTAssertEqual(activitySnapshot.quality, .complete)
        XCTAssertEqual(activitySnapshot.energyAddedKWh, 18.4)
        XCTAssertEqual(reloadedKinds, [WidgetConstants.currentChargeKind])
    }

    // Production break caught: a charge-detail failure discards authoritative charging status or emits an end event.
    func testCurrentChargeDetailFailurePublishesPartialWithoutEnding() async throws {
        let suiteName = "CurrentChargeDetailFailureIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let liveActivity = CurrentChargeRecordingLiveActivityManager()
        let vehicleIdentifier = String(repeating: "b", count: 64)
        store.save(
            .fixture(carName: "Test car 7", batteryLevel: 67, isCharging: true),
            vehicleIdentifier: vehicleIdentifier
        )
        let viewModel = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .failure(.network("detail unavailable")),
                statusResult: .success(.chargingIntegrationStatus)
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: CurrentChargeRecordingWidgetTimelineReloader(),
            liveActivityCoordinator: ChargeLiveActivityCoordinator(manager: liveActivity),
            vehicleIdentifier: vehicleIdentifier,
            now: { Date(timeIntervalSince1970: 1_786_100_100) }
        )

        await viewModel.load(carId: 7)

        let snapshot = try XCTUnwrap(
            store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge
        )
        let calls = await liveActivity.recordedCalls()
        let activitySnapshots = await liveActivity.recordedStartSnapshots()
        XCTAssertEqual(snapshot.phase, .charging)
        XCTAssertEqual(snapshot.quality, .partial)
        XCTAssertEqual(calls, [.startOrUpdate(carId: 7)])
        let activitySnapshot = try XCTUnwrap(activitySnapshots.first)
        XCTAssertEqual(activitySnapshots.count, 1)
        XCTAssertEqual(activitySnapshot.vehicleIdentifier, vehicleIdentifier)
        XCTAssertEqual(activitySnapshot.batteryLevel, 67)
        XCTAssertEqual(activitySnapshot.quality, .partial)
        XCTAssertEqual(activitySnapshot.energyAddedKWh, 12.5)
        XCTAssertFalse(calls.contains { call in
            if case .end = call { return true }
            return false
        })
    }

    // Production break caught: a failed status observation fabricates a new snapshot, advances stale data, or ends the existing activity.
    func testCurrentChargeStatusFailurePreservesActivityAndNeverEnds() async throws {
        let suiteName = "CurrentChargeStatusFailureIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let liveActivity = CurrentChargeRecordingLiveActivityManager()
        let vehicleIdentifier = String(repeating: "c", count: 64)
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_786_100_200)
        store.save(
            .fixture(carName: "Test car 7", batteryLevel: 61, isCharging: true),
            vehicleIdentifier: vehicleIdentifier
        )
        XCTAssertTrue(store.updateCurrentCharge(
            WidgetCurrentChargeData(
                phase: .charging,
                quality: .complete,
                batteryLevel: 61,
                chargeLimitSoc: 80,
                chargerPowerKW: 64,
                energyAddedKWh: 16.2,
                timeToFullMinutes: 35,
                isDC: true,
                updatedAt: originalUpdatedAt
            ),
            vehicleIdentifier: vehicleIdentifier
        ))
        let viewModel = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .failure(.network("detail unavailable")),
                statusResult: .failure(.network("status unavailable"))
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: CurrentChargeRecordingWidgetTimelineReloader(),
            liveActivityCoordinator: ChargeLiveActivityCoordinator(manager: liveActivity),
            vehicleIdentifier: vehicleIdentifier,
            now: { Date(timeIntervalSince1970: 1_786_100_500) }
        )

        await viewModel.load(carId: 7)

        let snapshot = try XCTUnwrap(
            store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge
        )
        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(snapshot.quality, .offline)
        XCTAssertEqual(snapshot.batteryLevel, 61)
        XCTAssertEqual(snapshot.energyAddedKWh, 16.2)
        XCTAssertEqual(snapshot.updatedAt, originalUpdatedAt)
        XCTAssertEqual(calls, [])
        XCTAssertFalse(calls.contains { call in
            if case .end = call { return true }
            return false
        })
    }

    // Production break caught: authoritative idle retains stale charging metrics or ends a same-car activity without exact opaque identity.
    func testAuthoritativeIdleClearsMetricsAndEndsActivity() async throws {
        let suiteName = "CurrentChargeIdleIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let liveActivity = CurrentChargeRecordingLiveActivityManager()
        let expectedOpaqueID = String(repeating: "d", count: 64)
        store.save(
            .fixture(carName: "Test car 7", batteryLevel: 55),
            vehicleIdentifier: expectedOpaqueID
        )
        let viewModel = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .success(.noActiveCharge),
                statusResult: .success(.idleIntegrationStatus)
            ),
            widgetSnapshotStore: store,
            widgetTimelineReloader: CurrentChargeRecordingWidgetTimelineReloader(),
            liveActivityCoordinator: ChargeLiveActivityCoordinator(manager: liveActivity),
            vehicleIdentifier: expectedOpaqueID,
            now: { Date(timeIntervalSince1970: 1_786_100_600) }
        )

        await viewModel.load(carId: 7)

        let snapshot = try XCTUnwrap(
            store.vehicleSnapshot(vehicleIdentifier: expectedOpaqueID)?.currentCharge
        )
        let calls = await liveActivity.recordedCalls()
        XCTAssertEqual(snapshot.phase, .idle)
        XCTAssertEqual(snapshot.quality, .complete)
        XCTAssertEqual(snapshot.batteryLevel, 55)
        XCTAssertNil(snapshot.chargerPowerKW)
        XCTAssertNil(snapshot.energyAddedKWh)
        XCTAssertNil(snapshot.timeToFullMinutes)
        XCTAssertEqual(calls, [
            .end(carId: 7, vehicleIdentifier: expectedOpaqueID)
        ])
    }

    func testCurrentChargeShowsNotChargingWhenNoActiveChargeAndStatusIdle() async throws {
        let api = FakeChargeAPI(
            currentChargeResult: .success(.noActiveCharge),
            statusResult: .success(.idleStatus)
        )
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertTrue(viewModel.state.isNotCharging)
        XCTAssertFalse(viewModel.state.isChargeStarting)
    }

    func testRefreshFromActiveToIdleClearsStaleChargeSession() async {
        let api = SequencedChargeAPI(
            currentChargeResults: [.success(.active(.activeFixture)), .success(.noActiveCharge)],
            statusResults: [.success(.chargingStatus), .success(.idleStatus)]
        )
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 1)
        XCTAssertNotNil(viewModel.state.chargeDetail)

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.isNotCharging)
        XCTAssertNil(viewModel.state.chargeDetail)
        XCTAssertNil(viewModel.state.stats)
        XCTAssertTrue(viewModel.state.chronologicalPoints.isEmpty)
        XCTAssertNil(viewModel.state.timeToFullCharge)
        XCTAssertFalse(viewModel.state.isDcCharge)
    }

    func testForcedRefreshUsesLiveStatusAndChargeEndpoints() async {
        let api = RefreshRecordingChargeAPI()
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 7, forceRefresh: true)

        let counts = await api.requestCounts
        XCTAssertEqual(counts.cachedStatus, 0)
        XCTAssertEqual(counts.cachedCharge, 0)
        XCTAssertEqual(counts.liveStatus, 1)
        XCTAssertEqual(counts.liveCharge, 1)
    }

    func testAutomaticRefreshUsesFiveSecondsOnlyWhileCharging() {
        let charging = CurrentChargeViewModel(
            api: FakeChargeAPI(currentChargeResult: .success(.noActiveCharge), statusResult: .success(.idleStatus)),
            initialState: CurrentChargeState(chargeDetail: .activeFixture)
        )
        let idle = CurrentChargeViewModel(
            api: FakeChargeAPI(currentChargeResult: .success(.noActiveCharge), statusResult: .success(.idleStatus)),
            initialState: CurrentChargeState(isLoading: false, isNotCharging: true)
        )

        XCTAssertEqual(charging.automaticRefreshInterval, .seconds(5))
        XCTAssertEqual(idle.automaticRefreshInterval, .seconds(30))
    }

    func testDisconnectedStatusDoesNotExposeChargingOrSentinelLocationValues() {
        let status = CarStatus(
            carGeodata: CarGeodata(geofence: "", latitude: SyntheticCoordinates.zero.latitude, longitude: SyntheticCoordinates.zero.longitude),
            chargingDetails: ChargingDetails(pluggedIn: false, chargingState: "disconnected", chargerPhases: 0, chargerPower: 0)
        )

        XCTAssertFalse(status.isCharging)
        XCTAssertFalse(status.isDcCharging)
        XCTAssertNil(status.chargerPower)
        XCTAssertNil(status.geofence)
        XCTAssertNil(status.latitude)
        XCTAssertNil(status.longitude)
    }

    func testChronologicalSortUsesTimestampsInsteadOfBlindlyReversingSamples() {
        let early = ChargePoint(date: "2026-07-01T09:00:00Z", batteryLevel: 40)
        let middle = ChargePoint(date: "2026-07-01T09:10:00Z", batteryLevel: 55)
        let late = ChargePoint(date: "2026-07-01T09:20:00Z", batteryLevel: 70)

        XCTAssertEqual(
            CurrentChargeViewModel.chronological([early, middle, late]).map(\.batteryLevel),
            [40, 55, 70]
        )
        XCTAssertEqual(
            CurrentChargeViewModel.chronological([late, middle, early]).map(\.batteryLevel),
            [40, 55, 70]
        )
    }

    func testRepeatedEntryRestoresActiveChargeAndFailedRefreshPreservesIt() async {
        let cache = VehiclePageStateCache<CurrentChargeState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .success(.active(.activeFixture)),
                statusResult: .success(.chargingStatus)
            ),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)
        let updatedAt = initial.state.lastUpdatedAt

        let reopened = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .failure(.network("offline")),
                statusResult: .failure(.network("offline"))
            ),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.chargeDetail?.chargeId, 9)

        await reopened.load(carId: 1, forceRefresh: true)

        XCTAssertEqual(reopened.state.chargeDetail?.chargeId, 9)
        XCTAssertEqual(reopened.state.lastUpdatedAt, updatedAt)
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testSuccessfulNoActiveChargeIsCachedAsResolvedState() async {
        let cache = VehiclePageStateCache<CurrentChargeState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .success(.noActiveCharge),
                statusResult: .success(.idleStatus)
            ),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)

        let reopened = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .failure(.network("offline")),
                statusResult: .failure(.network("offline"))
            ),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertTrue(reopened.state.isNotCharging)
        XCTAssertFalse(reopened.state.isLoading)
    }

    func testOverlappingLoadsStartOnlyOneStatusAndChargeRequest() async {
        let api = SlowCurrentChargeAPI()
        let viewModel = CurrentChargeViewModel(api: api)

        async let first: Void = viewModel.load(carId: 1)
        async let second: Void = viewModel.load(carId: 1)
        _ = await (first, second)

        let counts = await api.requestCounts
        XCTAssertEqual(counts.status, 1)
        XCTAssertEqual(counts.charge, 1)
    }

    func testCurrentChargeCacheIsIsolatedByServerAndVehicle() async {
        let cache = VehiclePageStateCache<CurrentChargeState>()
        let activeKey = VehiclePageCacheKey(serverURL: "https://one.example.com", carId: 1)
        let idleKey = VehiclePageCacheKey(serverURL: "https://two.example.com", carId: 2)
        let active = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .success(.active(.activeFixture)),
                statusResult: .success(.chargingStatus)
            ),
            cacheKey: activeKey,
            stateCache: cache
        )
        let idle = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .success(.noActiveCharge),
                statusResult: .success(.idleStatus)
            ),
            cacheKey: idleKey,
            stateCache: cache
        )

        await active.load(carId: 1)
        await idle.load(carId: 2)

        let restoredActive = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .failure(.emptyBody),
                statusResult: .failure(.emptyBody)
            ),
            cacheKey: activeKey,
            stateCache: cache
        )
        let restoredIdle = CurrentChargeViewModel(
            api: FakeChargeAPI(
                currentChargeResult: .failure(.emptyBody),
                statusResult: .failure(.emptyBody)
            ),
            cacheKey: idleKey,
            stateCache: cache
        )

        XCTAssertEqual(restoredActive.state.chargeDetail?.chargeId, 9)
        XCTAssertFalse(restoredActive.state.isNotCharging)
        XCTAssertNil(restoredIdle.state.chargeDetail)
        XCTAssertTrue(restoredIdle.state.isNotCharging)
    }
}

private actor SequencedChargeAPI: ChargeAPIProviding {
    private var currentChargeResults: [APIResult<CurrentChargeOutcome>]
    private var statusResults: [APIResult<CarStatusPayload>]

    init(currentChargeResults: [APIResult<CurrentChargeOutcome>], statusResults: [APIResult<CarStatusPayload>]) {
        self.currentChargeResults = currentChargeResults
        self.statusResults = statusResults
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> { currentChargeResults.removeFirst() }
    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> { .failure(.emptyBody) }
    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> { statusResults.removeFirst() }
}

private actor CurrentChargeRecordingWidgetTimelineReloader: WidgetTimelineReloading {
    private var kinds: [String] = []

    func reloadTimelines(ofKind kind: String) async {
        kinds.append(kind)
    }

    func recordedKinds() -> [String] {
        kinds
    }
}

private actor CurrentChargeRecordingLiveActivityManager: ChargeLiveActivityManaging {
    enum Call: Equatable, Sendable {
        case startOrUpdate(carId: Int)
        case updateExisting(carId: Int)
        case end(carId: Int, vehicleIdentifier: String?)
    }

    private var calls: [Call] = []
    private var startSnapshots: [ChargeLiveActivitySnapshot] = []

    func update(carId: Int, snapshot: ChargeLiveActivitySnapshot) async {
        calls.append(.startOrUpdate(carId: carId))
        startSnapshots.append(snapshot)
    }

    func updateExisting(carId: Int, snapshot _: ChargeLiveActivitySnapshot) async {
        calls.append(.updateExisting(carId: carId))
    }

    func end(carId: Int) async {
        calls.append(.end(carId: carId, vehicleIdentifier: nil))
    }

    func end(carId: Int, vehicleIdentifier: String?) async {
        calls.append(.end(carId: carId, vehicleIdentifier: vehicleIdentifier))
    }

    func recordedCalls() -> [Call] {
        calls
    }

    func recordedStartSnapshots() -> [ChargeLiveActivitySnapshot] {
        startSnapshots
    }
}

private actor RefreshRecordingChargeAPI: ChargeAPIProviding {
    private(set) var cachedStatus = 0
    private(set) var cachedCharge = 0
    private(set) var liveStatus = 0
    private(set) var liveCharge = 0

    var requestCounts: (cachedStatus: Int, cachedCharge: Int, liveStatus: Int, liveCharge: Int) {
        (cachedStatus, cachedCharge, liveStatus, liveCharge)
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> { .failure(.emptyBody) }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        cachedCharge += 1
        return .success(.noActiveCharge)
    }

    func refreshCurrentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        liveCharge += 1
        return .success(.active(.activeFixture))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        cachedStatus += 1
        return .success(.idleStatus)
    }

    func refreshCarStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        liveStatus += 1
        return .success(.chargingStatus)
    }
}

private actor SlowCurrentChargeAPI: ChargeAPIProviding {
    private var statusRequests = 0
    private var chargeRequests = 0

    var requestCounts: (status: Int, charge: Int) {
        (statusRequests, chargeRequests)
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        chargeRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success(.noActiveCharge)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        statusRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success(.idleStatus)
    }
}

private final class FakeChargeAPI: ChargeAPIProviding, @unchecked Sendable {
    private let currentChargeResult: APIResult<CurrentChargeOutcome>
    private let statusResult: APIResult<CarStatusPayload>

    init(currentChargeResult: APIResult<CurrentChargeOutcome>, statusResult: APIResult<CarStatusPayload>) {
        self.currentChargeResult = currentChargeResult
        self.statusResult = statusResult
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        currentChargeResult
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        statusResult
    }
}

private extension ChargeDetail {
    static let widgetIntegrationFixture = ChargeDetail(
        chargeId: 10,
        startDate: "2026-08-10T09:00:00Z",
        chargeEnergyAdded: 18.4,
        chargeEnergyUsed: 18.4,
        durationMin: 18,
        batteryDetails: ChargeBatteryDetails(startBatteryLevel: 40, endBatteryLevel: 67),
        chargePoints: [],
        isCharging: true
    )

    static let activeFixture = ChargeDetail(
        chargeId: 9,
        startDate: "2026-07-01T09:00:00Z",
        chargeEnergyAdded: 28,
        chargeEnergyUsed: 28,
        durationMin: 20,
        batteryDetails: ChargeBatteryDetails(startBatteryLevel: 40, endBatteryLevel: 70),
        chargePoints: [
            ChargePoint(batteryLevel: 70, chargerDetails: ChargerDetails(chargerPower: 80, chargerVoltage: 390, chargerActualCurrent: 205, chargerPhases: 0), outsideTemp: 18),
            ChargePoint(batteryLevel: 40, chargerDetails: ChargerDetails(chargerPower: 120, chargerVoltage: 400, chargerActualCurrent: 300, chargerPhases: 0), outsideTemp: 17)
        ],
        isCharging: true
    )
}

private extension CarStatusPayload {
    static let chargingIntegrationStatus = CarStatusPayload(
        status: CarStatus(
            displayName: "Test car 7",
            batteryDetails: BatteryDetails(batteryLevel: 67),
            chargingDetails: ChargingDetails(
                pluggedIn: true,
                chargingState: "Charging",
                chargeEnergyAdded: 12.5,
                chargeLimitSoc: 80,
                chargerPhases: 0,
                chargerPower: 72,
                timeToFullCharge: 0.75
            )
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let idleIntegrationStatus = CarStatusPayload(
        status: CarStatus(
            displayName: "Test car 7",
            batteryDetails: BatteryDetails(batteryLevel: 55),
            chargingDetails: ChargingDetails(
                pluggedIn: false,
                chargingState: "Disconnected"
            )
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let chargingStatus = CarStatusPayload(
        status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: true, chargingState: "Charging", chargeLimitSoc: 80, chargerPhases: 0, timeToFullCharge: 0.5)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let idleStatus = CarStatusPayload(
        status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: false, chargingState: "Disconnected")
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )
}
