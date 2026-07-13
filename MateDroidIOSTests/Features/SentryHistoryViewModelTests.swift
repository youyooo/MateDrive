import XCTest
@testable import MateDroidIOS

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
