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
