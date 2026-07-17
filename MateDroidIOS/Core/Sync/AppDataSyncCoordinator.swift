import Foundation

public protocol AppDataSyncSuspending: Sendable {
    func suspendAndWait() async
    func resume() async
}

public actor AppDataSyncCoordinator: AppDataSyncSuspending {
    private struct RunningSync {
        let id: UUID
        let task: Task<BackgroundRefreshReport, Never>
    }

    private let workRunner: any BackgroundRefreshWorkRunning
    private var runningSync: RunningSync?
    private var lastReport: BackgroundRefreshReport?
    private var suspensionDepth = 0

    public init(workRunner: any BackgroundRefreshWorkRunning) {
        self.workRunner = workRunner
    }

    public var isRunning: Bool {
        runningSync != nil
    }

    public var isSuspended: Bool {
        suspensionDepth > 0
    }

    @discardableResult
    public func start() -> Bool {
        guard runningSync == nil, suspensionDepth == 0 else { return false }

        let id = UUID()
        let runner = workRunner
        let task = Task.detached(priority: .utility) {
            await runner.run()
        }
        runningSync = RunningSync(id: id, task: task)

        Task { [weak self] in
            let report = await task.value
            await self?.finish(id: id, report: report)
        }
        return true
    }

    public func waitUntilIdle() async -> BackgroundRefreshReport? {
        guard let runningSync else { return lastReport }
        let report = await runningSync.task.value
        finish(id: runningSync.id, report: report)
        return report
    }

    public func cancel() {
        runningSync?.task.cancel()
    }

    public func cancelAndWait() async {
        guard let runningSync else { return }
        runningSync.task.cancel()
        let report = await runningSync.task.value
        finish(id: runningSync.id, report: report)
    }

    public func suspendAndWait() async {
        suspensionDepth += 1
        guard suspensionDepth == 1 else { return }
        await cancelAndWait()
    }

    public func resume() {
        suspensionDepth = max(0, suspensionDepth - 1)
    }

    private func finish(id: UUID, report: BackgroundRefreshReport) {
        guard runningSync?.id == id else { return }
        runningSync = nil
        lastReport = report
    }
}
