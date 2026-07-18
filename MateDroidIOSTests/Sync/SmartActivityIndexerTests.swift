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
        let aggregateStore = RecordingChargePricingAggregateStore(values: [
            20: ChargeDetailPricingAggregate(
                chargeId: 20,
                isDc: true,
                chargerIdentity: .teslaSupercharger
            )
        ])
        let loader = CachedSmartActivitySourceLoader(
            activitiesCache: cache,
            sleepIntervalStore: sleepStore,
            settingsStore: MutableIndexerSettingsStore(settings),
            chargeCostOverrideStore: costStore,
            chargePricingAggregateStore: aggregateStore,
            tariffCatalog: { Self.tariffCatalog }
        )

        let snapshot = try await loader.snapshot(carId: 1)

        XCTAssertEqual(snapshot?.activities, Self.activityFixture)
        XCTAssertEqual(snapshot?.sleepIntervals.count, 1)
        XCTAssertEqual(snapshot?.chargeCostOverrides, [20: 8.5])
        XCTAssertEqual(snapshot?.chargePricingAggregates[20]?.isDc, true)
        XCTAssertEqual(snapshot?.tariffCatalog.version, 7)
        let sleepReadCount = await sleepStore.readCount
        let costReadCount = await costStore.readCount
        let aggregateReadCount = await aggregateStore.readCount
        XCTAssertEqual(sleepReadCount, 1)
        XCTAssertEqual(costReadCount, 1)
        XCTAssertEqual(aggregateReadCount, 1)
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

    func testOverlappingRebuildsAreSerializedAndNewestSnapshotWins() async throws {
        let source = SequencedGatedSmartActivitySourceLoader(
            first: Self.snapshot(overrides: [20: 1]),
            latest: Self.snapshot(overrides: [20: 2])
        )
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let first = Task { await indexer.rebuild(carIds: [1]) }
        await source.waitUntilFirstRequest()
        let second = Task { await indexer.rebuild(carIds: [1]) }
        try await Task.sleep(for: .milliseconds(20))
        let requestCountBeforeRelease = await source.requestCount
        XCTAssertEqual(requestCountBeforeRelease, 1)

        await source.releaseFirstRequest()
        _ = await first.value
        _ = await second.value

        let sessions = try await store.sessions(carId: 1)
        let replaceCount = await store.replaceCount
        XCTAssertEqual(sessions.first?.chargeCost?.amount, 2)
        XCTAssertEqual(replaceCount, 2)
    }

    func testRemoveWaitsForRebuildAndCannotBeRepopulatedByStaleWork() async throws {
        let source = SequencedGatedSmartActivitySourceLoader(
            first: Self.snapshot(),
            latest: Self.snapshot()
        )
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let rebuild = Task { await indexer.rebuild(carIds: [1]) }
        await source.waitUntilFirstRequest()
        let removal = Task { try await indexer.removeDerivedData() }
        try await Task.sleep(for: .milliseconds(20))
        let removeCountBeforeRelease = await store.removeAllCount
        XCTAssertEqual(removeCountBeforeRelease, 0)

        await source.releaseFirstRequest()
        _ = await rebuild.value
        try await removal.value

        let sessions = try await store.sessions(carId: 1)
        let fingerprint = try await store.derivationFingerprint(carId: 1)
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertNil(fingerprint)
    }

    func testCancellationAfterCommittedReplaceRestoresOriginalSnapshotAndFingerprint() async throws {
        let previous = Self.previousSession(carId: 1)
        let store = PostCommitGatedSmartActivitySessionStore(
            sessions: [previous],
            fingerprint: "original"
        )
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot()),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let task = Task { await indexer.rebuild(carIds: [1]) }
        await store.waitUntilFirstReplaceCommitted()
        task.cancel()
        await store.releaseFirstReplace()
        _ = await task.value

        let sessions = try await store.sessions(carId: 1)
        let fingerprint = try await store.derivationFingerprint(carId: 1)
        XCTAssertEqual(sessions, [previous])
        XCTAssertEqual(fingerprint, "original")
    }

    func testCancellationAfterCommittedReplaceWithoutIndexStateRestoresLegacySnapshotFingerprint() async throws {
        let previous = Self.previousSession(carId: 1)
        let store = PostCommitGatedSmartActivitySessionStore(
            sessions: [previous],
            fingerprint: nil
        )
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot()),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        let task = Task { await indexer.rebuild(carIds: [1]) }
        await store.waitUntilFirstReplaceCommitted()
        task.cancel()
        await store.releaseFirstReplace()
        _ = await task.value

        let sessions = try await store.sessions(carId: 1)
        let fingerprint = try await store.derivationFingerprint(carId: 1)
        let removeCarCount = await store.removeCarCount
        XCTAssertEqual(sessions, [previous])
        XCTAssertEqual(fingerprint, previous.derivationFingerprint)
        XCTAssertEqual(removeCarCount, 0)
    }

    func testCancellationRestorationFailureNotifiesCommittedReplacementOnce() async throws {
        let notifications = IndexNotificationCounter()
        let previous = Self.previousSession(carId: 1)
        let store = PostCommitGatedSmartActivitySessionStore(
            sessions: [previous],
            fingerprint: "original",
            failRestoration: true
        )
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot()),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore(),
            postChange: { carId in await notifications.record(carId) }
        )

        let task = Task { await indexer.rebuild(carIds: [1]) }
        await store.waitUntilFirstReplaceCommitted()
        task.cancel()
        await store.releaseFirstReplace()
        let report = await task.value
        let committedSessions = try await store.sessions(carId: 1)
        let committedFingerprint = try await store.derivationFingerprint(carId: 1)
        let notificationsAfterFailure = await notifications.carIds

        XCTAssertEqual(report.failedCarIds, [1])
        XCTAssertTrue(report.completedCarIds.isEmpty)
        XCTAssertNotEqual(committedSessions, [previous])
        XCTAssertNotEqual(committedFingerprint, "original")
        XCTAssertEqual(committedSessions.first?.derivationFingerprint, committedFingerprint)
        XCTAssertEqual(notificationsAfterFailure, [1])

        let retryReport = await indexer.rebuild(carIds: [1])
        let notificationsAfterRetry = await notifications.carIds
        XCTAssertEqual(retryReport.unchangedCarIds, [1])
        XCTAssertTrue(retryReport.completedCarIds.isEmpty)
        XCTAssertTrue(retryReport.failedCarIds.isEmpty)
        XCTAssertEqual(notificationsAfterRetry, [1])
    }

    func testCancelledQueuedRebuildReturnsPromptlyWithoutReleasingActiveOperation() async throws {
        let source = SequencedGatedSmartActivitySourceLoader(
            first: Self.snapshot(overrides: [20: 1]),
            latest: Self.snapshot(overrides: [20: 3])
        )
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )
        let cancelledReturned = expectation(description: "cancelled waiter returns")

        let first = Task { await indexer.rebuild(carIds: [1]) }
        await source.waitUntilFirstRequest()
        let second = Task {
            let report = await indexer.rebuild(carIds: [1])
            cancelledReturned.fulfill()
            return report
        }
        await waitUntilQueuedOperationCount(1, indexer: indexer)
        second.cancel()
        await fulfillment(of: [cancelledReturned], timeout: 0.5)
        let cancelledReport = await second.value
        await waitUntilQueuedOperationCount(0, indexer: indexer)
        let requestCountAfterCancellation = await source.requestCount
        XCTAssertEqual(cancelledReport.failedCarIds, [1])
        XCTAssertEqual(requestCountAfterCancellation, 1)

        let third = Task { await indexer.rebuild(carIds: [1]) }
        await waitUntilQueuedOperationCount(1, indexer: indexer)
        let requestCountWhileFirstIsActive = await source.requestCount
        XCTAssertEqual(requestCountWhileFirstIsActive, 1)

        await source.releaseFirstRequest()
        _ = await first.value
        let thirdReport = await third.value
        let finalRequestCount = await source.requestCount
        let finalSessions = try await store.sessions(carId: 1)
        XCTAssertEqual(thirdReport.completedCarIds, [1])
        XCTAssertEqual(finalRequestCount, 2)
        XCTAssertEqual(finalSessions.first?.chargeCost?.amount, 3)
    }

    private func waitUntilQueuedOperationCount(
        _ expectedCount: Int,
        indexer: SmartActivityIndexer
    ) async {
        while await indexer.queuedOperationCount != expectedCount {
            await Task.yield()
        }
    }

    func testKnownDcChargeUsesDcRuleAndDoesNotUseResidentialTariff() async throws {
        let dcRule = ChargePricingRule(
            id: "tesla-dc",
            name: "Tesla DC",
            chargeType: .teslaSupercharger,
            pricePerKWh: 2,
            currencyCode: "CNY"
        )
        let aggregate = ChargeDetailPricingAggregate(
            chargeId: 20,
            isDc: true,
            chargerIdentity: .teslaSupercharger
        )
        let dcStore = InMemorySmartActivitySessionStore()
        let dcIndexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
                overrides: [:],
                pricingRules: [dcRule],
                aggregates: [20: aggregate]
            )),
            sessionStore: dcStore,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        _ = await dcIndexer.rebuild(carIds: [1])
        let dcSessions = try await dcStore.sessions(carId: 1)
        let dcCost = try XCTUnwrap(dcSessions.first?.chargeCost)
        XCTAssertEqual(dcCost.amount, 20)
        XCTAssertEqual(dcCost.ruleID, "tesla-dc")

        let regionalStore = InMemorySmartActivitySessionStore()
        let regionalIndexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
                overrides: [:],
                pricingRules: [],
                aggregates: [20: aggregate],
                residentialTariffRegionCode: "CN-43",
                tariffCatalog: Self.regionalTariffCatalog
            )),
            sessionStore: regionalStore,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        _ = await regionalIndexer.rebuild(carIds: [1])
        let regionalSessions = try await regionalStore.sessions(carId: 1)
        XCTAssertNil(regionalSessions.first?.chargeCost)
    }

    func testUnknownChargeTypeDoesNotUseResidentialOrAcSpecificPricingButUsesAnyRule() async throws {
        let unknownCharge = TeslaMateActivity(
            id: 20,
            type: "charge",
            startDate: "2026-07-18T01:00:00Z",
            endDate: "2026-07-18T03:00:00Z",
            durationMin: nil,
            startAddress: "Home",
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            kwh: 10
        )
        let activities = [Self.activityFixture[0], Self.activityFixture[1], unknownCharge]
        let acRule = ChargePricingRule(
            id: "ac-only",
            name: "AC only",
            chargeType: .ac,
            pricePerKWh: 1,
            currencyCode: "CNY"
        )

        let regionalStore = InMemorySmartActivitySessionStore()
        let regionalIndexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
                activities: activities,
                overrides: [:],
                pricingRules: [],
                residentialTariffRegionCode: "CN-43",
                tariffCatalog: Self.regionalTariffCatalog
            )),
            sessionStore: regionalStore,
            labelStore: InMemoryActivityLabelOverrideStore()
        )
        _ = await regionalIndexer.rebuild(carIds: [1])
        let regionalSessions = try await regionalStore.sessions(carId: 1)
        XCTAssertNil(regionalSessions.first?.chargeCost)

        let acStore = InMemorySmartActivitySessionStore()
        let acIndexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
                activities: activities,
                overrides: [:],
                pricingRules: [acRule]
            )),
            sessionStore: acStore,
            labelStore: InMemoryActivityLabelOverrideStore()
        )
        _ = await acIndexer.rebuild(carIds: [1])
        let acSessions = try await acStore.sessions(carId: 1)
        XCTAssertNil(acSessions.first?.chargeCost)

        let anyRule = ChargePricingRule(
            id: "any",
            name: "Any charger",
            chargeType: .any,
            pricePerKWh: 1.5,
            currencyCode: "CNY"
        )
        let anyStore = InMemorySmartActivitySessionStore()
        let anyIndexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
                activities: activities,
                overrides: [:],
                pricingRules: [acRule, anyRule]
            )),
            sessionStore: anyStore,
            labelStore: InMemoryActivityLabelOverrideStore()
        )
        _ = await anyIndexer.rebuild(carIds: [1])
        let anySessions = try await anyStore.sessions(carId: 1)
        let anyCost = try XCTUnwrap(anySessions.first?.chargeCost)
        XCTAssertEqual(anyCost.amount, 15)
        XCTAssertEqual(anyCost.ruleID, "any")
    }

    func testPricingRuleOrderParticipatesInFingerprint() async {
        let firstRule = ChargePricingRule(id: "first", name: "Tied", pricePerKWh: 1, currencyCode: "CNY")
        let secondRule = ChargePricingRule(id: "second", name: "Tied", pricePerKWh: 2, currencyCode: "CNY")
        let source = MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
            overrides: [:],
            pricingRules: [firstRule, secondRule]
        ))
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: source,
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        _ = await indexer.rebuild(carIds: [1])
        await source.setSnapshot(Self.snapshot(overrides: [:], pricingRules: [secondRule, firstRule]))
        let reordered = await indexer.rebuild(carIds: [1])
        let replaceCount = await store.replaceCount

        XCTAssertEqual(reordered.completedCarIds, [1])
        XCTAssertEqual(replaceCount, 2)
    }

    func testOverflowingChargeAggregationDoesNotPersistNonfiniteCostOrComponents() async throws {
        let secondCharge = TeslaMateActivity(
            id: 21,
            type: "charge",
            startDate: "2026-07-18T03:00:00Z",
            endDate: "2026-07-18T03:30:00Z",
            startAddress: "Home",
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            kwh: 1
        )
        let store = InMemorySmartActivitySessionStore()
        let indexer = SmartActivityIndexer(
            source: MutableSmartActivitySourceLoader(snapshot: Self.snapshot(
                activities: Self.activityFixture + [secondCharge],
                overrides: [20: .greatestFiniteMagnitude, 21: .greatestFiniteMagnitude]
            )),
            sessionStore: store,
            labelStore: InMemoryActivityLabelOverrideStore()
        )

        _ = await indexer.rebuild(carIds: [1])
        let sessions = try await store.sessions(carId: 1)
        XCTAssertNil(sessions.first?.chargeCost)
    }

    private static func snapshot(
        carId: Int = 1,
        historyFullyLoaded: Bool = true,
        activities: [TeslaMateActivity] = activityFixture,
        pricing: Double = 0.5,
        overrides: [Int: Double] = [20: 8.5],
        pricingRules: [ChargePricingRule]? = nil,
        aggregates: [Int: ChargeDetailPricingAggregate] = [:],
        residentialTariffRegionCode: String? = nil,
        tariffCatalog: RegionalChargingTariffCatalog = tariffCatalog
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
                residentialTariffRegionCode: residentialTariffRegionCode,
                chargePricingRules: pricingRules ?? [ChargePricingRule(
                    id: "home",
                    name: "Home",
                    pricePerKWh: pricing,
                    currencyCode: "CNY"
                )],
                geofenceRules: [homeGeofence]
            ),
            chargeCostOverrides: overrides,
            tariffCatalog: tariffCatalog,
            chargePricingAggregates: aggregates
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

    private static let regionalTariffCatalog = RegionalChargingTariffCatalog(
        version: 8,
        generatedAt: "2026-07-18T00:00:00Z",
        regions: [RegionalChargingTariffRegion(
            regionCode: "CN-43",
            names: ["en": "Hunan"],
            availability: .verified,
            verifiedAt: "2026-07-01",
            tariffs: [RegionalChargingTariff(
                id: "cn-43-home",
                status: .active,
                customerClass: "residential-ev",
                chargeType: .ac,
                currencyCode: "CNY",
                effectiveFromDate: "2026-01-01",
                effectiveToDate: nil,
                documentID: "fixture",
                sourceURL: URL(string: "https://example.com/tariff")!,
                basePricePerKWh: 0.5,
                timeSegments: [],
                serviceFeePerKWh: 0,
                sessionFee: 0,
                applicableWeekdays: nil,
                applicableMonths: nil
            )]
        )]
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
    case restorationFailure
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

private actor SequencedGatedSmartActivitySourceLoader: SmartActivitySourceLoading {
    private let first: SmartActivitySourceSnapshot
    private var latest: SmartActivitySourceSnapshot
    private var firstRequested = false
    private var firstReleased = false
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0

    init(first: SmartActivitySourceSnapshot, latest: SmartActivitySourceSnapshot) {
        self.first = first
        self.latest = latest
    }

    func snapshot(carId _: Int) async throws -> SmartActivitySourceSnapshot? {
        requestCount += 1
        guard requestCount == 1 else { return latest }
        firstRequested = true
        firstRequestWaiters.forEach { $0.resume() }
        firstRequestWaiters.removeAll()
        if !firstReleased {
            await withCheckedContinuation { firstReleaseWaiters.append($0) }
        }
        return first
    }

    func waitUntilFirstRequest() async {
        guard !firstRequested else { return }
        await withCheckedContinuation { firstRequestWaiters.append($0) }
    }

    func releaseFirstRequest() {
        firstReleased = true
        firstReleaseWaiters.forEach { $0.resume() }
        firstReleaseWaiters.removeAll()
    }
}

private actor InMemorySmartActivitySessionStore: SmartActivitySessionStoring {
    private var values: [Int: [SmartActivitySession]]
    private var fingerprints: [Int: String]
    private(set) var replaceCount = 0
    private(set) var removeAllCount = 0

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
        removeAllCount += 1
        values.removeAll()
        fingerprints.removeAll()
    }

    func removeDerivedSessions(carId: Int) async throws {
        values[carId] = nil
        fingerprints[carId] = nil
    }
}

private actor PostCommitGatedSmartActivitySessionStore: SmartActivitySessionStoring {
    private var storedSessions: [SmartActivitySession]
    private var storedFingerprint: String?
    private var shouldGateNextReplace = true
    private var firstReplaceCommitted = false
    private var firstReplaceReleased = false
    private var commitWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var removeCarCount = 0
    private let failRestoration: Bool

    init(sessions: [SmartActivitySession], fingerprint: String?, failRestoration: Bool = false) {
        storedSessions = sessions
        storedFingerprint = fingerprint
        self.failRestoration = failRestoration
    }

    func sessions(carId _: Int) async throws -> [SmartActivitySession] { storedSessions }
    func session(carId _: Int, sessionId: String) async throws -> SmartActivitySession? {
        storedSessions.first { $0.id == sessionId }
    }
    func derivationFingerprint(carId _: Int) async throws -> String? { storedFingerprint }
    func replace(carId: Int, sessions: [SmartActivitySession]) async throws {
        try await replace(
            carId: carId,
            sessions: sessions,
            derivationFingerprint: sessions.first?.derivationFingerprint ?? ""
        )
    }
    func replace(
        carId _: Int,
        sessions: [SmartActivitySession],
        derivationFingerprint: String
    ) async throws {
        if !shouldGateNextReplace, failRestoration {
            throw SmartActivityIndexerTestError.restorationFailure
        }
        storedSessions = sessions
        storedFingerprint = derivationFingerprint
        guard shouldGateNextReplace else { return }
        shouldGateNextReplace = false
        firstReplaceCommitted = true
        commitWaiters.forEach { $0.resume() }
        commitWaiters.removeAll()
        if !firstReplaceReleased {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }
    func removeDerivedSessions(carId _: Int) async throws {
        removeCarCount += 1
        storedSessions = []
        storedFingerprint = nil
    }
    func removeDerivedSessions() async throws {
        storedSessions = []
        storedFingerprint = nil
    }

    func waitUntilFirstReplaceCommitted() async {
        guard !firstReplaceCommitted else { return }
        await withCheckedContinuation { commitWaiters.append($0) }
    }

    func releaseFirstReplace() {
        firstReplaceReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
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

private actor RecordingChargePricingAggregateStore: ChargePricingAggregateProviding {
    private let values: [Int: ChargeDetailPricingAggregate]
    private(set) var readCount = 0

    init(values: [Int: ChargeDetailPricingAggregate]) { self.values = values }

    func chargePricingAggregates(carId _: Int) async throws -> [Int: ChargeDetailPricingAggregate] {
        readCount += 1
        return values
    }
}

private actor IndexNotificationCounter {
    private(set) var carIds: [Int] = []
    func record(_ carId: Int) { carIds.append(carId) }
}
