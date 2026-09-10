import XCTest
@testable import MateDriveApp

@MainActor
final class SentryHistoryViewModelTests: XCTestCase {
    func testSentryHistoryGroupsCurrentSessionPastDaysAndHeatmap() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01T00:00:00Z
        let activeSession: Int64 = 1_767_218_400_000
        let location = SyntheticCoordinates.point()
        let records = [
            SentryAlertLogRecord(
                id: "current",
                carId: 1,
                detectedAtMillis: 1_767_218_460_000,
                sessionStartedAtMillis: activeSession,
                latitude: location.latitude,
                longitude: location.longitude
            ),
            SentryAlertLogRecord(
                id: "past",
                carId: 1,
                detectedAtMillis: 1_767_132_000_000,
                sessionStartedAtMillis: 1_767_131_000_000,
                address: "Garage"
            )
        ]
        let viewModel = SentryHistoryViewModel(
            store: FakeSentryStore(records: records, activeSession: activeSession),
            calendar: calendar
        )

        await viewModel.load(carId: 1, now: now)

        XCTAssertTrue(viewModel.state.isSessionActive)
        XCTAssertEqual(viewModel.state.currentSessionAlerts.map(\.id), ["current"])
        XCTAssertEqual(
            viewModel.state.currentSessionAlerts.first?.locationText,
            String(format: "%.4f, %.4f", location.latitude, location.longitude)
        )
        XCTAssertEqual(viewModel.state.pastAlertsByDay.count, 1)
        XCTAssertEqual(viewModel.state.pastAlertsByDay.first?.alerts.first?.locationText, "Garage")
        XCTAssertEqual(viewModel.state.heatmapCounts.reduce(0, +), 2)
        XCTAssertEqual(viewModel.state.heatmapCounts.count, SentryHistoryViewModel.heatmapBlocks)
    }

    func testSentryHistoryRepeatedEntryRestoresRowsAndFailedRefreshPreservesThem() async {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let record = SentryAlertLogRecord(
            id: "cached",
            carId: 1,
            detectedAtMillis: 1_767_218_460_000,
            address: "Garage"
        )
        let cache = VehiclePageStateCache<SentryHistoryState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = SentryHistoryViewModel(
            store: FakeSentryStore(records: [record], activeSession: nil),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1, now: now)

        let reopened = SentryHistoryViewModel(
            store: FailingSentryStore(),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.pastAlertsByDay.flatMap(\.alerts).map(\.id), ["cached"])

        await reopened.load(carId: 1, now: now)

        XCTAssertEqual(reopened.state.pastAlertsByDay.flatMap(\.alerts).map(\.id), ["cached"])
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testSentryHistoryOverlappingLoadsReadStoreOnceAndReuseRowsForHeatmap() async {
        let store = SlowSentryStore()
        let viewModel = SentryHistoryViewModel(store: store)

        async let first: Void = viewModel.load(carId: 1)
        async let second: Void = viewModel.load(carId: 1)
        _ = await (first, second)

        let counts = await store.requestCounts
        XCTAssertEqual(counts.alerts, 1)
        XCTAssertEqual(counts.activeSession, 1)
        XCTAssertEqual(counts.hourly, 0)
    }

    func testSentryHistoryCachesSuccessfulEmptyResult() async {
        let cache = VehiclePageStateCache<SentryHistoryState>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = SentryHistoryViewModel(
            store: FakeSentryStore(records: [], activeSession: nil),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)

        let reopened = SentryHistoryViewModel(
            store: FailingSentryStore(),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertTrue(reopened.state.currentSessionAlerts.isEmpty)
        XCTAssertTrue(reopened.state.pastAlertsByDay.isEmpty)
    }
}

struct FakeSentryStore: SentryAlertLogStoring {
    let records: [SentryAlertLogRecord]
    let activeSession: Int64?

    func alertLogs(carId: Int) async throws -> [SentryAlertLogRecord] {
        records.filter { $0.carId == carId }.sorted { $0.detectedAtMillis > $1.detectedAtMillis }
    }

    func activeSessionStartedAt(carId _: Int) async throws -> Int64? {
        activeSession
    }

    func hourlyCounts(carId: Int, sinceMillis: Int64) async throws -> [SentryHourlyCount] {
        let filtered = records.filter { $0.carId == carId && $0.detectedAtMillis >= sinceMillis }
        let grouped = Dictionary(grouping: filtered) { $0.detectedAtMillis / 3_600_000 }
        return grouped.map { SentryHourlyCount(hourBucket: $0.key, count: $0.value.count) }
    }

    func upsert(_ record: SentryAlertLogRecord) async throws {}
}

private struct FailingSentryStore: SentryAlertLogStoring {
    func alertLogs(carId _: Int) async throws -> [SentryAlertLogRecord] {
        throw SentryStoreTestError.offline
    }

    func activeSessionStartedAt(carId _: Int) async throws -> Int64? {
        throw SentryStoreTestError.offline
    }

    func hourlyCounts(carId _: Int, sinceMillis _: Int64) async throws -> [SentryHourlyCount] {
        throw SentryStoreTestError.offline
    }

    func upsert(_ record: SentryAlertLogRecord) async throws {}
}

private actor SlowSentryStore: SentryAlertLogStoring {
    private var alertRequests = 0
    private var activeSessionRequests = 0
    private var hourlyRequests = 0

    var requestCounts: (alerts: Int, activeSession: Int, hourly: Int) {
        (alertRequests, activeSessionRequests, hourlyRequests)
    }

    func alertLogs(carId _: Int) async throws -> [SentryAlertLogRecord] {
        alertRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return []
    }

    func activeSessionStartedAt(carId _: Int) async throws -> Int64? {
        activeSessionRequests += 1
        return nil
    }

    func hourlyCounts(carId _: Int, sinceMillis _: Int64) async throws -> [SentryHourlyCount] {
        hourlyRequests += 1
        return []
    }

    func upsert(_ record: SentryAlertLogRecord) async throws {}
}

private enum SentryStoreTestError: Error {
    case offline
}
