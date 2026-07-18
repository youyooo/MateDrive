import XCTest
@testable import MateDroidIOS

final class SmartActivityIndexerTests: XCTestCase {
    func testCachedSourceLoaderReadsOnlyLocalStores() async throws {
        let cache = ActivitiesStateCache(maximumAge: 60)
        var state = ActivitiesState()
        state.items = Self.activityFixture
        state.historyFullyLoaded = true
        let settings = AppSettings(
            serverURL: "https://teslamate.example",
            currencyCode: "CNY",
            geofenceRules: [Self.homeGeofence]
        )
        await cache.save(
            ActivitiesCacheSnapshot(state: state),
            serverURL: settings.serverURL,
            carId: 1
        )
        let sleepStore = RecordingSleepStore(records: [
            SleepIntervalRecord(
                carId: 1,
                startDate: "2026-07-18T01:00:00Z",
                endDate: "2026-07-18T02:00:00Z"
            )
        ])
        let costStore = RecordingCostOverrideStore(values: [20: 8.5])
        let loader = CachedSmartActivitySourceLoader(
            activitiesCache: cache,
            sleepIntervalStore: sleepStore,
            settingsStore: MutableIndexerSettingsStore(settings),
            chargeCostOverrideStore: costStore,
            tariffCatalog: { Self.tariffCatalog }
        )

        let snapshot = try await loader.snapshot(carId: 1)

        XCTAssertEqual(snapshot?.activities, Self.activityFixture)
        XCTAssertEqual(snapshot?.sleepIntervals.count, 1)
        XCTAssertEqual(snapshot?.chargeCostOverrides, [20: 8.5])
        XCTAssertEqual(snapshot?.tariffCatalog.version, 7)
        let sleepReadCount = await sleepStore.readCount
        let costReadCount = await costStore.readCount
        XCTAssertEqual(sleepReadCount, 1)
        XCTAssertEqual(costReadCount, 1)
    }

    func testIndexerBuildsFromCacheAndPersistsCodableChargeCost() async throws {
        let source = MutableSmartActivitySourceLoader(snapshot: Self.snapshot())
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let report = await indexer.rebuild(carIds: [1])
        let sessions = try await store.sessions(carId: 1)
        let networkRequestCount = await source.networkRequestCount
        let encoded = try JSONEncoder().encode(try XCTUnwrap(sessions.first?.chargeCost))

        XCTAssertEqual(report.completedCarIds, [1])
        XCTAssertEqual(networkRequestCount, 0)
        XCTAssertEqual(sessions.first?.chargeCost?.amount, 8.5)
        XCTAssertNoThrow(try JSONDecoder().decode(SmartActivityChargeCost.self, from: encoded))
    }

    func testCancellationDoesNotReplaceExistingSnapshot() async throws {
        let previous = Self.previousSession(carId: 1)
        let store = InMemorySmartActivitySessionStore(initial: [1: [previous]])
        let source = CancellingSmartActivitySourceLoader(snapshot: Self.snapshot())
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let task = Task { await indexer.rebuild(carIds: [1]) }
        await source.waitUntilRequested()
        task.cancel()
        await source.release()
        _ = await task.value
        let sessions = try await store.sessions(carId: 1)
        let replaceCount = await store.replaceCount

        XCTAssertEqual(sessions, [previous])
        XCTAssertEqual(replaceCount, 0)
    }

    func testMissingCacheFailsCarWithoutReplacingExistingSnapshot() async throws {
        let previous = Self.previousSession(carId: 1)
        let store = InMemorySmartActivitySessionStore(initial: [1: [previous]])
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: nil),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let report = await indexer.rebuild(carIds: [1])
        let sessions = try await store.sessions(carId: 1)

        XCTAssertEqual(report.failedCarIds, [1])
        XCTAssertEqual(sessions, [previous])
    }

    func testPartialCarFailureDoesNotRemoveSuccessfulOrPriorSnapshots() async throws {
        let priorFailedCar = Self.previousSession(carId: 2)
        let source = MutableSmartActivitySourceLoader(
            snapshots: [1: Self.snapshot(carId: 1)],
            failedCarIds: [2]
        )
        let store = InMemorySmartActivitySessionStore(initial: [2: [priorFailedCar]])
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let report = await indexer.rebuild(carIds: [2, 1])
        let successfulSessions = try await store.sessions(carId: 1)
        let failedSessions = try await store.sessions(carId: 2)

        XCTAssertEqual(report.attemptedCarIds, [1, 2])
        XCTAssertEqual(report.completedCarIds, [1])
        XCTAssertEqual(report.failedCarIds, [2])
        XCTAssertFalse(successfulSessions.isEmpty)
        XCTAssertEqual(failedSessions, [priorFailedCar])
    }

    func testTruncatedHistoryMarksOldestBoundarySessionPartial() async throws {
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(historyFullyLoaded: false)),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        _ = await indexer.rebuild(carIds: [1])
        let sessions = try await store.sessions(carId: 1)
        let oldest = try XCTUnwrap(sessions.last)

        XCTAssertEqual(oldest.quality, .partial)
    }

    func testUnchangedFingerprintDoesNotReplaceOrNotify() async {
        let notifications = IndexNotificationCounter()
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot()),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore(),
            postChange: { carId in await notifications.record(carId) }
        )

        let first = await indexer.rebuild(carIds: [1])
        let second = await indexer.rebuild(carIds: [1])
        let replaceCount = await store.replaceCount
        let notifiedCarIds = await notifications.carIds

        XCTAssertEqual(first.completedCarIds, [1])
        XCTAssertEqual(second.unchangedCarIds, [1])
        XCTAssertEqual(replaceCount, 1)
        XCTAssertEqual(notifiedCarIds, [1])
    }

    func testEmptyDerivationPersistsFingerprintAndOnlyRebuildsWhenInputChanges() async throws {
        let notifications = IndexNotificationCounter()
        let source = MutableSmartActivitySourceLoader(snapshot: Self.snapshot(activities: []))
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore(),
            postChange: { carId in await notifications.record(carId) }
        )

        let first = await indexer.rebuild(carIds: [1])
        let firstFingerprint = try await store.derivationFingerprint(carId: 1)
        let second = await indexer.rebuild(carIds: [1])
        await source.setSnapshot(Self.snapshot(activities: [], pricing: 1.0))
        let changed = await indexer.rebuild(carIds: [1])
        let changedFingerprint = try await store.derivationFingerprint(carId: 1)
        let replaceCount = await store.replaceCount
        let notifiedCarIds = await notifications.carIds

        XCTAssertEqual(first.completedCarIds, [1])
        XCTAssertNotNil(firstFingerprint)
        XCTAssertEqual(second.unchangedCarIds, [1])
        XCTAssertEqual(changed.completedCarIds, [1])
        XCTAssertNotEqual(changedFingerprint, firstFingerprint)
        XCTAssertEqual(replaceCount, 2)
        XCTAssertEqual(notifiedCarIds, [1, 1])
    }

    func testLabelTimestampChangeRebuildsUnchangedRawEvents() async throws {
        let labels = InMemoryActivityLabelOverrideStore()
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot()),
            sessionStore: store,
            labelStore: labels
        )
        _ = await indexer.rebuild(carIds: [1])
        let initialSessions = try await store.sessions(carId: 1)
        let session = try XCTUnwrap(initialSessions.first)
        try await labels.save(ActivityLabelOverride(
            id: "label-1",
            carId: 1,
            sessionId: session.id,
            placeKey: nil,
            scope: .sessionOnly,
            purpose: .shopping,
            customName: nil,
            icon: "cart.fill",
            colorHex: "#00AA00",
            startMinute: nil,
            endMinute: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        ))

        let report = await indexer.rebuild(carIds: [1])
        let rebuiltSessions = try await store.sessions(carId: 1)
        let rebuilt = try XCTUnwrap(rebuiltSessions.first)
        let replaceCount = await store.replaceCount

        XCTAssertEqual(report.completedCarIds, [1])
        XCTAssertEqual(rebuilt.classification?.purpose, .shopping)
        XCTAssertEqual(replaceCount, 2)
    }

    func testPricingRuleChangeRebuildsUnchangedRawEvents() async throws {
        let source = MutableSmartActivitySourceLoader(snapshot: Self.snapshot(pricing: 0.5, overrides: [:]))
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )
        _ = await indexer.rebuild(carIds: [1])
        let firstSessions = try await store.sessions(carId: 1)
        let firstCost = try XCTUnwrap(firstSessions.first?.chargeCost?.amount)
        await source.setSnapshot(Self.snapshot(pricing: 1.0, overrides: [:]))

        let report = await indexer.rebuild(carIds: [1])
        let secondSessions = try await store.sessions(carId: 1)
        let secondCost = try XCTUnwrap(secondSessions.first?.chargeCost?.amount)

        XCTAssertEqual(report.completedCarIds, [1])
        XCTAssertEqual(secondCost, firstCost * 2, accuracy: 0.001)
    }

    private static func snapshot(
        carId: Int = 1,
        historyFullyLoaded: Bool = true,
        activities: [TeslaMateActivity] = activityFixture,
        pricing: Double = 0.5,
        overrides: [Int: Double] = [20: 8.5]
    ) -> SmartActivitySourceSnapshot {
        SmartActivitySourceSnapshot(
            carId: carId,
            activities: activities,
            historyFullyLoaded: historyFullyLoaded,
            sleepIntervals: [],
            geofences: [homeGeofence],
            settings: AppSettings(
                serverURL: "https://teslamate.example",
                currencyCode: "CNY",
                chargePricingRules: [ChargePricingRule(
                    id: "home",
                    name: "Home",
                    pricePerKWh: pricing,
                    currencyCode: "CNY"
                )],
                geofenceRules: [homeGeofence]
            ),
            chargeCostOverrides: overrides,
            tariffCatalog: tariffCatalog
        )
    }

    private static let activityFixture: [TeslaMateActivity] = [
        TeslaMateActivity(
            id: 10,
            type: "drive",
            startDate: "2026-07-18T00:00:00Z",
            endDate: "2026-07-18T00:30:00Z",
            endLatitude: 31.2304,
            endLongitude: 121.4737
        ),
        TeslaMateActivity(
            id: 11,
            type: "park",
            startDate: "2026-07-18T00:30:00Z",
            endDate: "2026-07-18T04:00:00Z",
            startLatitude: 31.2304,
            startLongitude: 121.4737
        ),
        TeslaMateActivity(
            id: 20,
            type: "charge",
            startDate: "2026-07-18T01:00:00Z",
            endDate: "2026-07-18T03:00:00Z",
            startAddress: "Home",
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            kwh: 10,
            cost: nil
        )
    ]

    private static let homeGeofence = GeofenceRule(
        id: "home",
        name: "Home",
        kind: .home,
        latitude: 31.2304,
        longitude: 121.4737,
        radiusMeters: 200
    )

    private static let tariffCatalog = RegionalChargingTariffCatalog(
        version: 7,
        generatedAt: "2026-07-18T00:00:00Z",
        regions: []
    )

    private static func previousSession(carId: Int) -> SmartActivitySession {
        SmartActivitySession(
            id: "old-\(carId)",
            carId: carId,
            startDate: Date(timeIntervalSince1970: 1),
            endDate: Date(timeIntervalSince1970: 2),
            placeKey: "old",
            latitude: nil,
            longitude: nil,
            geofenceID: nil,
            provisionalKind: .parking,
            classification: nil,
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: [],
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "old",
            derivationFingerprint: "old"
        )
    }
}

private enum SmartActivityIndexerTestError: Error {
    case sourceFailure
}

private actor MutableSmartActivitySourceLoader: SmartActivitySourceLoading {
    private var snapshots: [Int: SmartActivitySourceSnapshot]
    private let failedCarIds: Set<Int>
    private(set) var networkRequestCount = 0

    init(snapshot: SmartActivitySourceSnapshot?) {
        snapshots = snapshot.map { [$0.carId: $0] } ?? [:]
        failedCarIds = []
    }

    init(snapshots: [Int: SmartActivitySourceSnapshot], failedCarIds: Set<Int>) {
        self.snapshots = snapshots
        self.failedCarIds = failedCarIds
    }

    func snapshot(carId: Int) async throws -> SmartActivitySourceSnapshot? {
        if failedCarIds.contains(carId) { throw SmartActivityIndexerTestError.sourceFailure }
        return snapshots[carId]
    }

    func setSnapshot(_ snapshot: SmartActivitySourceSnapshot) {
        snapshots[snapshot.carId] = snapshot
    }
}

private actor CancellingSmartActivitySourceLoader: SmartActivitySourceLoading {
    private let value: SmartActivitySourceSnapshot
    private var requested = false
    private var released = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(snapshot: SmartActivitySourceSnapshot) { value = snapshot }

    func snapshot(carId _: Int) async throws -> SmartActivitySourceSnapshot? {
        requested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return value
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor InMemorySmartActivitySessionStore: SmartActivitySessionStoring {
    private var values: [Int: [SmartActivitySession]]
    private var fingerprints: [Int: String]
    private(set) var replaceCount = 0

    init(initial: [Int: [SmartActivitySession]] = [:]) {
        values = initial
        fingerprints = initial.compactMapValues { $0.first?.derivationFingerprint }
    }

    func sessions(carId: Int) async throws -> [SmartActivitySession] { values[carId] ?? [] }
    func session(carId: Int, sessionId: String) async throws -> SmartActivitySession? {
        values[carId]?.first { $0.id == sessionId }
    }
    func replace(carId: Int, sessions: [SmartActivitySession]) async throws {
        replaceCount += 1
        values[carId] = sessions
        fingerprints[carId] = sessions.first?.derivationFingerprint
    }
    func derivationFingerprint(carId: Int) async throws -> String? { fingerprints[carId] }
    func replace(
        carId: Int,
        sessions: [SmartActivitySession],
        derivationFingerprint: String
    ) async throws {
        replaceCount += 1
        values[carId] = sessions
        fingerprints[carId] = derivationFingerprint
    }
    func removeDerivedSessions() async throws {
        values.removeAll()
        fingerprints.removeAll()
    }
}

private actor InMemoryActivityLabelOverrideStore: ActivityLabelOverrideStoring {
    private var values: [String: ActivityLabelOverride] = [:]

    func overrides(carId: Int) async throws -> [ActivityLabelOverride] {
        values.values.filter { $0.carId == carId }
    }
    func override(id: String) async throws -> ActivityLabelOverride? { values[id] }
    func save(_ value: ActivityLabelOverride) async throws { values[value.id] = value }
    func delete(id: String) async throws { values[id] = nil }
    func removeAll() async throws { values.removeAll() }
}

private actor MutableIndexerSettingsStore: SettingsStoring {
    private var settings: AppSettings
    init(_ settings: AppSettings) { self.settings = settings }
    func load() async -> AppSettings { settings }
    func save(_ settings: AppSettings) async { self.settings = settings }
}

private actor RecordingSleepStore: SleepIntervalStoring {
    private let values: [SleepIntervalRecord]
    private(set) var readCount = 0
    init(records: [SleepIntervalRecord]) { values = records }
    func upsertAll(_: [SleepIntervalRecord]) async throws {}
    func records(carId _: Int, start _: String, end _: String) async throws -> [SleepIntervalRecord] {
        readCount += 1
        return values
    }
}

private actor RecordingCostOverrideStore: ChargeCostOverriding {
    private let values: [Int: Double]
    private(set) var readCount = 0
    init(values: [Int: Double]) { self.values = values }
    func costOverrides(carId _: Int) async throws -> [Int: Double] {
        readCount += 1
        return values
    }
    func costOverride(carId _: Int, chargeId: Int) async throws -> Double? { values[chargeId] }
    func saveCostOverride(carId _: Int, chargeId _: Int, cost _: Double?) async throws {}
}

private actor IndexNotificationCounter {
    private(set) var carIds: [Int] = []
    func record(_ carId: Int) { carIds.append(carId) }
}
