import XCTest
@testable import MateDroidIOS

final class BackgroundRefreshWorkRunnerTests: XCTestCase {
    func testSuccessfulRefreshRequiresHistoryAndVehicleStatus() async {
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: StubBackgroundHistoryRunner(
                report: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
            ),
            refreshVehicleStatus: { true }
        )

        let report = await runner.run()

        XCTAssertTrue(report.isSuccessful)
        XCTAssertTrue(report.vehicleStatusRefreshed)
        XCTAssertFalse(report.wasCancelled)
    }

    func testVehicleStatusFailureMakesBackgroundRefreshFail() async {
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: StubBackgroundHistoryRunner(
                report: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
            ),
            refreshVehicleStatus: { false }
        )

        let report = await runner.run()

        XCTAssertFalse(report.isSuccessful)
        XCTAssertFalse(report.vehicleStatusRefreshed)
    }

    func testCancellationSkipsVehicleStatusRefresh() async {
        let counter = BackgroundRefreshCounter()
        let runner = BackgroundRefreshWorkRunner(
            historySyncRunner: SlowBackgroundHistoryRunner(),
            refreshVehicleStatus: {
                await counter.increment()
                return true
            }
        )

        let task = Task { await runner.run() }
        task.cancel()
        let report = await task.value
        let refreshCount = await counter.value

        XCTAssertTrue(report.wasCancelled)
        XCTAssertFalse(report.isSuccessful)
        XCTAssertEqual(refreshCount, 0)
    }

    func testDataPreloaderCachesExplicitSleepIntervalsWhenStateHistoryIsAvailable() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3StateHistoryHTTPClient(stateHistoryBody: #"""
        {"data":{"states":[
          {"state":"asleep","start_date":"2026-07-15T00:00:00Z","end_date":"2026-07-15T02:00:00Z"},
          {"state":"online","start_date":"2026-07-15T03:00:00Z","end_date":"2026-07-15T04:00:00Z"},
          {"state":"asleep","start_date":"not-a-date","end_date":"2026-07-15T06:00:00Z"},
          {"state":"asleep","start_date":"2026-07-16T00:00:00Z","end_date":null}
        ]}}
        """#)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let stateHistoryPath = try XCTUnwrap(requestedPaths.first { $0.hasPrefix("/api/v1/cars/7/states?") })
        let stateHistoryURL = try XCTUnwrap(URL(string: "https://teslamate.example\(stateHistoryPath)"))
        let queryItems = try XCTUnwrap(URLComponents(url: stateHistoryURL, resolvingAgainstBaseURL: false)?.queryItems)
        let monthStart = try XCTUnwrap(Calendar.current.dateInterval(of: .month, for: now)?.start)
        let formatter = ISO8601DateFormatter()
        let records = try await SleepIntervalStore(database: database).records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-17T12:00:00Z"
        )

        XCTAssertTrue(report.didRun)
        XCTAssertEqual(queryItems.map(\.name), ["startDate", "endDate"])
        XCTAssertEqual(queryItems.map(\.value), [formatter.string(from: monthStart), formatter.string(from: now)])
        XCTAssertEqual(records, [
            SleepIntervalRecord(carId: 7, startDate: "2026-07-15T00:00:00Z", endDate: "2026-07-15T02:00:00Z"),
            SleepIntervalRecord(carId: 7, startDate: "2026-07-16T00:00:00Z", endDate: "2026-07-17T12:00:00Z")
        ])
    }

    func testCancellingStateHistoryResponseDoesNotCountSuccessOrWriteSleepIntervals() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3GatedStateHistoryHTTPClient()
        let store = Task3RecordingSleepIntervalStore()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            sleepIntervalStore: store,
            now: { now }
        )

        let task = Task { await preloader.preload(force: true) }
        await client.waitUntilStateHistoryRequested()
        task.cancel()
        await client.releaseStateHistoryResponse()
        let report = await task.value
        let savedRecords = await store.savedRecords

        XCTAssertEqual(report.successfulEndpointCount, 1)
        XCTAssertTrue(savedRecords.isEmpty)
    }

    func testDataPreloaderSkipsSleepHistoryWhenCachedProfileDoesNotSupportIt() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .unavailable)
        let client = Task3StateHistoryHTTPClient()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let records = try await SleepIntervalStore(database: database).records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-17T12:00:00Z"
        )

        XCTAssertTrue(report.didRun)
        XCTAssertFalse(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/states?") })
        XCTAssertTrue(records.isEmpty)
    }

    func testDataPreloaderContinuesWhenOptionalSleepHistoryRequestFails() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3StateHistoryHTTPClient(stateHistoryStatusCode: 500)
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths
        let records = try await SleepIntervalStore(database: database).records(
            carId: 7,
            start: "2026-07-01T00:00:00Z",
            end: "2026-07-17T12:00:00Z"
        )

        XCTAssertTrue(report.didRun)
        XCTAssertGreaterThan(report.successfulEndpointCount, 0)
        XCTAssertTrue(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/states?") })
        XCTAssertTrue(records.isEmpty)
    }

    func testDataPreloaderContinuesWhenSavingSleepHistoryFails() async throws {
        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-17T12:00:00Z"))
        try await saveTask3StateHistoryProfile(in: database, carId: 7, at: now, state: .available)
        let client = Task3StateHistoryHTTPClient()
        let preloader = AppDataPreloader(
            settingsStore: Task3PreloadSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 7
            )),
            secretStore: Task3PreloadSecretStore(),
            clientOverride: client,
            databaseProvider: Task3StaticDatabaseProvider(database: database),
            sleepIntervalStore: Task3FailingSleepIntervalStore(),
            now: { now }
        )

        let report = await preloader.preload(force: true)
        let requestedPaths = await client.requestedPaths

        XCTAssertTrue(report.didRun)
        XCTAssertGreaterThan(report.successfulEndpointCount, 0)
        XCTAssertTrue(requestedPaths.contains { $0.hasPrefix("/api/v1/cars/7/states?") })
    }
}

private struct StubBackgroundHistoryRunner: HistorySyncRunning {
    let report: HistorySyncReport
    func run() async -> HistorySyncReport { report }
}

private struct SlowBackgroundHistoryRunner: HistorySyncRunning {
    func run() async -> HistorySyncReport {
        try? await Task.sleep(for: .seconds(1))
        return HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
    }
}

private actor BackgroundRefreshCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private struct Task3StaticDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase

    func database() async throws -> SQLiteDatabase { database }
}

private struct Task3FailingSleepIntervalStore: SleepIntervalStoring {
    func upsertAll(_: [SleepIntervalRecord]) async throws {
        throw SQLiteError.executionFailed("Storage unavailable")
    }

    func records(carId _: Int, start _: String, end _: String) async throws -> [SleepIntervalRecord] {
        []
    }
}

private actor Task3RecordingSleepIntervalStore: SleepIntervalStoring {
    private(set) var savedRecords: [SleepIntervalRecord] = []

    func upsertAll(_ records: [SleepIntervalRecord]) async throws {
        savedRecords.append(contentsOf: records)
    }

    func records(carId _: Int, start _: String, end _: String) async throws -> [SleepIntervalRecord] {
        savedRecords
    }
}

private func saveTask3StateHistoryProfile(
    in database: SQLiteDatabase,
    carId: Int,
    at checkedAt: Date,
    state: TeslaMateCapabilityState
) async throws {
    try await TeslaMateServerProfileStore(database: database).save(TeslaMateServerProfile(
        serverKey: TeslaMateServerIdentity.key(for: URL(string: "https://teslamate.example")!),
        carId: carId,
        version: TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: nil, buildInfo: nil),
        capabilities: [
            .stateHistory: TeslaMateCapabilityStatus(
                state: state,
                source: .cached,
                checkedAt: checkedAt
            )
        ],
        checkedAt: checkedAt
    ))
}

private actor Task3StateHistoryHTTPClient: HTTPClient {
    private(set) var requestedPaths: [String] = []
    private let stateHistoryBody: String
    private let stateHistoryStatusCode: Int

    init(
        stateHistoryBody: String = #"{"data":{"states":[]}}"#,
        stateHistoryStatusCode: Int = 200
    ) {
        self.stateHistoryBody = stateHistoryBody
        self.stateHistoryStatusCode = stateHistoryStatusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        requestedPaths.append(url.path + (url.query.map { "?" + $0 } ?? ""))
        let isStateHistory = url.path.hasSuffix("/states")
        let body: String
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
        } else if isStateHistory {
            body = stateHistoryBody
        } else {
            body = #"{}"#
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(
                url: url,
                statusCode: isStateHistory ? stateHistoryStatusCode : 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private actor Task3GatedStateHistoryHTTPClient: HTTPClient {
    private var stateHistoryRequested = false
    private var stateHistoryReleased = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://teslamate.example")!
        let body: String
        let statusCode: Int
        if url.path == "/api/v1/cars" {
            body = #"{"data":{"cars":[{"car_id":7,"name":"Test car 7"}]}}"#
            statusCode = 200
        } else if url.path.hasSuffix("/states") {
            stateHistoryRequested = true
            requestWaiters.forEach { $0.resume() }
            requestWaiters.removeAll()
            if !stateHistoryReleased {
                await withCheckedContinuation { releaseWaiters.append($0) }
            }
            body = #"{"data":{"states":[{"state":"asleep","start_date":"2026-07-15T00:00:00Z","end_date":"2026-07-15T02:00:00Z"}]}}"#
            statusCode = 200
        } else {
            body = #"{}"#
            statusCode = 500
        }
        return (
            Data(body.utf8),
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }

    func waitUntilStateHistoryRequested() async {
        guard !stateHistoryRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseStateHistoryResponse() {
        stateHistoryReleased = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor Task3PreloadSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings { settings }
    func save(_ settings: AppSettings) async { self.settings = settings }
}

private struct Task3PreloadSecretStore: SecretStoring {
    func get(_ key: String) async throws -> String? { nil }
    func set(_ value: String, for key: String) async throws {}
    func remove(_ key: String) async throws {}
}
