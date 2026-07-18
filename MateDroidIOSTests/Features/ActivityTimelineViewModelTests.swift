import XCTest
@testable import MateDroidIOS

@MainActor
final class ActivityTimelineViewModelTests: XCTestCase {
    func testLoadPublishesCachedSessionsWithoutLoadingSpinnerAndSortsNewestFirst() async {
        let older = makeSession(id: "older", startDate: date(1_000), kinds: [.drive])
        let newer = makeSession(id: "newer", startDate: date(2_000), kinds: [.charge])
        let store = TimelineSessionStoreSpy(listResponses: [[older, newer]])
        let viewModel = ActivityTimelineViewModel(
            sessionStore: store,
            notificationCenter: NotificationCenter()
        )

        XCTAssertFalse(viewModel.state.isLoading)
        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.sessions.map(\.id), ["newer", "older"])
        XCTAssertFalse(viewModel.state.isLoading)
        let loadCount = await store.listCallCountValue()
        XCTAssertEqual(loadCount, 1)
    }

    func testFiltersAndDaySectionsStayInMemoryWithoutAnotherStoreRead() async {
        let drive = makeSession(
            id: "drive",
            startDate: date(172_800 + 3_600),
            kinds: [.drive]
        )
        let charge = makeSession(
            id: "charge",
            startDate: date(172_800 + 1_800),
            kinds: [.charge]
        )
        let parking = makeSession(
            id: "parking",
            startDate: date(86_400 + 3_600),
            kinds: [.unknown],
            provisionalKind: .parking
        )
        let store = TimelineSessionStoreSpy(listResponses: [[parking, charge, drive]])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let viewModel = ActivityTimelineViewModel(
            sessionStore: store,
            calendar: calendar,
            notificationCenter: NotificationCenter()
        )
        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.daySections.map(\.sessions).map { $0.map(\.id) }, [
            ["drive", "charge"],
            ["parking"]
        ])

        viewModel.setFilter(.drive)
        XCTAssertEqual(viewModel.filteredSessions.map(\.id), ["drive"])
        viewModel.setFilter(.charge)
        XCTAssertEqual(viewModel.filteredSessions.map(\.id), ["charge"])
        viewModel.setFilter(.park)
        XCTAssertEqual(viewModel.filteredSessions.map(\.id), ["parking"])
        viewModel.setFilter(.all)
        XCTAssertEqual(viewModel.filteredSessions.map(\.id), ["drive", "charge", "parking"])
        let loadCount = await store.listCallCountValue()
        XCTAssertEqual(loadCount, 1)
    }

    func testIndexNotificationReloadsOnlyCurrentCar() async {
        let initial = makeSession(id: "initial", startDate: date(1_000), kinds: [.drive])
        let refreshed = makeSession(id: "refreshed", startDate: date(2_000), kinds: [.drive])
        let store = TimelineSessionStoreSpy(listResponses: [[initial], [refreshed]])
        let center = NotificationCenter()
        let viewModel = ActivityTimelineViewModel(sessionStore: store, notificationCenter: center)
        await viewModel.load(carId: 1)

        center.post(
            name: .smartActivityIndexDidChange,
            object: nil,
            userInfo: ["carId": 2]
        )
        await viewModel.waitUntilIdle()
        let ignoredNotificationLoadCount = await store.listCallCountValue()
        XCTAssertEqual(ignoredNotificationLoadCount, 1)

        center.post(
            name: .smartActivityIndexDidChange,
            object: nil,
            userInfo: ["carId": 1]
        )
        await viewModel.waitUntilIdle()

        let requestedCarIds = await store.requestedCarIdsValue()
        XCTAssertEqual(requestedCarIds, [1, 1])
        XCTAssertEqual(viewModel.state.sessions.map(\.id), ["refreshed"])
    }

    func testNotificationBurstDuringReadCoalescesAndDoesNotLoseFinalReload() async {
        let initial = makeSession(id: "initial", startDate: date(1_000), kinds: [.drive])
        let interim = makeSession(id: "interim", startDate: date(2_000), kinds: [.drive])
        let final = makeSession(id: "final", startDate: date(3_000), kinds: [.drive])
        let store = TimelineSessionStoreSpy(
            listResponses: [[initial], [interim], [final]],
            gatedListCalls: [2]
        )
        let center = NotificationCenter()
        let viewModel = ActivityTimelineViewModel(sessionStore: store, notificationCenter: center)
        await viewModel.load(carId: 1)

        center.post(
            name: .smartActivityIndexDidChange,
            object: nil,
            userInfo: ["carId": 1]
        )
        await store.waitUntilListCallCount(2)

        for _ in 0..<4 {
            center.post(
                name: .smartActivityIndexDidChange,
                object: nil,
                userInfo: ["carId": 1]
            )
        }
        let gatedLoadCount = await store.listCallCountValue()
        XCTAssertEqual(gatedLoadCount, 2)

        await store.releaseListCall(2)
        await viewModel.waitUntilIdle()

        let finalLoadCount = await store.listCallCountValue()
        let maximumConcurrentReads = await store.maximumConcurrentListReadsValue()
        XCTAssertEqual(finalLoadCount, 3)
        XCTAssertEqual(maximumConcurrentReads, 1)
        XCTAssertEqual(viewModel.state.sessions.map(\.id), ["final"])
    }

    func testTimelineLocalErrorKeepsAlreadyDisplayedSessions() async {
        let cached = makeSession(id: "cached", startDate: date(1_000), kinds: [.drive])
        let store = TimelineSessionStoreSpy(
            listResponses: [[cached]],
            failingListCalls: [2]
        )
        let center = NotificationCenter()
        let viewModel = ActivityTimelineViewModel(sessionStore: store, notificationCenter: center)
        await viewModel.load(carId: 1)

        center.post(
            name: .smartActivityIndexDidChange,
            object: nil,
            userInfo: ["carId": 1]
        )
        await viewModel.waitUntilIdle()

        XCTAssertEqual(viewModel.state.sessions.map(\.id), ["cached"])
        XCTAssertEqual(viewModel.state.errorMessage, "activity_timeline_local_error")
        XCTAssertFalse(viewModel.state.isLoading)
    }

    func testDetailReadsExactSessionAndCachedLabelOverride() async {
        let expected = makeSession(id: "session-7", carId: 7, startDate: date(1_000), kinds: [.park])
        let label = ActivityLabelOverride(
            id: "label-7",
            carId: 7,
            sessionId: expected.id,
            placeKey: nil,
            scope: .sessionOnly,
            purpose: .shopping,
            customName: "Market",
            icon: "cart.fill",
            colorHex: "#00AA00",
            startMinute: nil,
            endMinute: nil,
            updatedAt: date(2_000)
        )
        let store = TimelineSessionStoreSpy(detailSession: expected)
        let labels = TimelineLabelStoreStub(values: [label])
        let viewModel = ActivitySessionDetailViewModel(
            sessionStore: store,
            labelStore: labels
        )

        await viewModel.load(carId: 7, sessionId: "session-7")

        XCTAssertEqual(viewModel.session, expected)
        XCTAssertEqual(viewModel.labelOverride, label)
        XCTAssertNil(viewModel.errorMessage)
        let request = await store.detailRequestValue()
        let listLoadCount = await store.listCallCountValue()
        XCTAssertEqual(request?.carId, 7)
        XCTAssertEqual(request?.sessionId, "session-7")
        XCTAssertEqual(listLoadCount, 0)
    }

    func testDetailUsesStableMissingAndLocalErrorKeys() async {
        let missingStore = TimelineSessionStoreSpy(detailSession: nil)
        let missingViewModel = ActivitySessionDetailViewModel(sessionStore: missingStore)
        await missingViewModel.load(carId: 1, sessionId: "missing")
        XCTAssertNil(missingViewModel.session)
        XCTAssertEqual(missingViewModel.errorMessage, "activity_session_missing")

        let failingStore = TimelineSessionStoreSpy(
            detailSession: nil,
            detailShouldFail: true
        )
        let failingViewModel = ActivitySessionDetailViewModel(sessionStore: failingStore)
        await failingViewModel.load(carId: 2, sessionId: "broken")
        XCTAssertNil(failingViewModel.session)
        XCTAssertEqual(failingViewModel.errorMessage, "activity_session_local_error")
    }

    private func makeSession(
        id: String,
        carId: Int = 1,
        startDate: Date,
        kinds: [TeslaMateActivityKind],
        provisionalKind: SmartActivityPurpose = .unclassified
    ) -> SmartActivitySession {
        let references = kinds.enumerated().map { index, kind in
            SmartActivityEventReference(sourceActivity: TeslaMateActivity(
                id: index + 1,
                type: kind.rawValue
            ))
        }
        return SmartActivitySession(
            id: id,
            carId: carId,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(300),
            placeKey: "place-\(id)",
            latitude: nil,
            longitude: nil,
            geofenceID: nil,
            provisionalKind: provisionalKind,
            classification: nil,
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: references,
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "source-\(id)",
            derivationFingerprint: "derivation"
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

private enum TimelineStoreError: Error {
    case failed
}

private actor TimelineSessionStoreSpy: SmartActivitySessionStoring {
    private let listResponses: [[SmartActivitySession]]
    private let gatedListCalls: Set<Int>
    private let failingListCalls: Set<Int>
    private let detailSession: SmartActivitySession?
    private let detailShouldFail: Bool
    private var listCallCount = 0
    private var requestedCarIds: [Int] = []
    private var detailRequest: (carId: Int, sessionId: String)?
    private var activeListReads = 0
    private var maximumConcurrentListReads = 0
    private var releasedListCalls: Set<Int> = []
    private var listReleaseWaiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var listCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(
        listResponses: [[SmartActivitySession]] = [],
        gatedListCalls: Set<Int> = [],
        failingListCalls: Set<Int> = [],
        detailSession: SmartActivitySession? = nil,
        detailShouldFail: Bool = false
    ) {
        self.listResponses = listResponses
        self.gatedListCalls = gatedListCalls
        self.failingListCalls = failingListCalls
        self.detailSession = detailSession
        self.detailShouldFail = detailShouldFail
    }

    func sessions(carId: Int) async throws -> [SmartActivitySession] {
        listCallCount += 1
        let call = listCallCount
        requestedCarIds.append(carId)
        activeListReads += 1
        maximumConcurrentListReads = max(maximumConcurrentListReads, activeListReads)
        resumeListCountWaiters()

        if gatedListCalls.contains(call), !releasedListCalls.contains(call) {
            await withCheckedContinuation { listReleaseWaiters[call] = $0 }
        }
        activeListReads -= 1

        if failingListCalls.contains(call) {
            throw TimelineStoreError.failed
        }
        guard !listResponses.isEmpty else { return [] }
        return listResponses[min(call - 1, listResponses.count - 1)]
    }

    func session(carId: Int, sessionId: String) async throws -> SmartActivitySession? {
        detailRequest = (carId, sessionId)
        if detailShouldFail { throw TimelineStoreError.failed }
        guard detailSession?.carId == carId, detailSession?.id == sessionId else { return nil }
        return detailSession
    }

    func replace(carId: Int, sessions: [SmartActivitySession]) async throws {}

    func removeDerivedSessions() async throws {}

    func waitUntilListCallCount(_ target: Int) async {
        guard listCallCount < target else { return }
        await withCheckedContinuation { listCountWaiters.append((target, $0)) }
    }

    func releaseListCall(_ call: Int) {
        releasedListCalls.insert(call)
        listReleaseWaiters.removeValue(forKey: call)?.resume()
    }

    func listCallCountValue() -> Int { listCallCount }

    func requestedCarIdsValue() -> [Int] { requestedCarIds }

    func detailRequestValue() -> (carId: Int, sessionId: String)? { detailRequest }

    func maximumConcurrentListReadsValue() -> Int { maximumConcurrentListReads }

    private func resumeListCountWaiters() {
        var remaining: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in listCountWaiters {
            if listCallCount >= waiter.0 {
                waiter.1.resume()
            } else {
                remaining.append(waiter)
            }
        }
        listCountWaiters = remaining
    }
}

private actor TimelineLabelStoreStub: ActivityLabelOverrideStoring {
    private let values: [ActivityLabelOverride]

    init(values: [ActivityLabelOverride]) {
        self.values = values
    }

    func overrides(carId: Int) async throws -> [ActivityLabelOverride] {
        values.filter { $0.carId == carId }
    }

    func override(id: String) async throws -> ActivityLabelOverride? {
        values.first { $0.id == id }
    }

    func save(_ value: ActivityLabelOverride) async throws {}

    func delete(id: String) async throws {}

    func removeAll() async throws {}
}
