import XCTest
@testable import MateDriveApp

final class AppDataSyncSuspensionTests: XCTestCase {
    func testSuspendCancelsRunningSyncAndBlocksNewStartsUntilResume() async {
        let worker = SuspensionTestWorker()
        let coordinator = AppDataSyncCoordinator(workRunner: worker)

        let firstStart = await coordinator.start()
        XCTAssertTrue(firstStart)
        await worker.waitUntilStarted()

        await coordinator.suspendAndWait()

        let isRunningWhileSuspended = await coordinator.isRunning
        let isSuspended = await coordinator.isSuspended
        let blockedStart = await coordinator.start()
        let cancellationCount = await worker.cancellationCount
        XCTAssertFalse(isRunningWhileSuspended)
        XCTAssertTrue(isSuspended)
        XCTAssertFalse(blockedStart)
        XCTAssertEqual(cancellationCount, 1)

        await coordinator.resume()

        let isSuspendedAfterResume = await coordinator.isSuspended
        let resumedStart = await coordinator.start()
        XCTAssertFalse(isSuspendedAfterResume)
        XCTAssertTrue(resumedStart)
        await worker.waitUntilRunCount(2)
        await worker.finish()
        _ = await coordinator.waitUntilIdle()
        let runCount = await worker.runCount
        XCTAssertEqual(runCount, 2)
    }

    func testNestedSuspensionsRequireMatchingResumes() async {
        let coordinator = AppDataSyncCoordinator(workRunner: SuspensionTestWorker())

        await coordinator.suspendAndWait()
        await coordinator.suspendAndWait()
        await coordinator.resume()

        let remainsSuspended = await coordinator.isSuspended
        let blockedStart = await coordinator.start()
        XCTAssertTrue(remainsSuspended)
        XCTAssertFalse(blockedStart)

        await coordinator.resume()

        let isSuspendedAfterMatchingResume = await coordinator.isSuspended
        XCTAssertFalse(isSuspendedAfterMatchingResume)
    }
}

private actor SuspensionTestWorker: BackgroundRefreshWorkRunning {
    private(set) var runCount = 0
    private(set) var cancellationCount = 0
    private var finishRequested = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var runCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    func run() async -> BackgroundRefreshReport {
        runCount += 1
        startedWaiters.forEach { $0.resume() }
        startedWaiters.removeAll()
        let ready = runCountWaiters.filter { runCount >= $0.0 }
        runCountWaiters.removeAll { runCount >= $0.0 }
        ready.forEach { $0.1.resume() }

        if !finishRequested {
            await withTaskCancellationHandler {
                await withCheckedContinuation { finishWaiters.append($0) }
            } onCancel: {
                Task { await self.cancelled() }
            }
        }

        return BackgroundRefreshReport(
            historySyncReport: HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: []),
            vehicleStatusRefreshed: !Task.isCancelled,
            wasCancelled: Task.isCancelled
        )
    }

    func waitUntilStarted() async {
        guard runCount == 0 else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func waitUntilRunCount(_ target: Int) async {
        guard runCount < target else { return }
        await withCheckedContinuation { runCountWaiters.append((target, $0)) }
    }

    func finish() {
        finishRequested = true
        finishWaiters.forEach { $0.resume() }
        finishWaiters.removeAll()
    }

    private func cancelled() {
        cancellationCount += 1
        finishWaiters.forEach { $0.resume() }
        finishWaiters.removeAll()
    }
}
