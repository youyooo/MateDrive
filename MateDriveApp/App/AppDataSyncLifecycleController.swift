import SwiftUI
import UIKit

@MainActor
protocol AppBackgroundTaskManaging: AnyObject {
    func begin(name: String, expirationHandler: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
final class UIApplicationBackgroundTaskManager: AppBackgroundTaskManaging {
    func begin(
        name: String,
        expirationHandler: @escaping @Sendable () -> Void
    ) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(
            withName: name,
            expirationHandler: expirationHandler
        )
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
final class AppDataSyncLifecycleController: ObservableObject {
    @Published private(set) var cacheRevision = 0

    private let coordinator: AppDataSyncCoordinator
    private let didCompleteSync: @Sendable (BackgroundRefreshReport) async -> Void
    private let backgroundTaskManager: any AppBackgroundTaskManaging
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    private var completionObserver: Task<Void, Never>?

    init(
        coordinator: AppDataSyncCoordinator,
        backgroundTaskManager: (any AppBackgroundTaskManaging)? = nil,
        didCompleteSync: @escaping @Sendable (BackgroundRefreshReport) async -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.backgroundTaskManager = backgroundTaskManager ?? UIApplicationBackgroundTaskManager()
        self.didCompleteSync = didCompleteSync
    }

    func appDidBecomeActive() async {
        endBackgroundTaskIfNeeded()
        await startAndObserveSync()
    }

    func appDidEnterBackground() {
        guard backgroundTaskIdentifier == .invalid else { return }

        let coordinator = coordinator
        backgroundTaskIdentifier = backgroundTaskManager.begin(name: "MateDrive full data sync") { [weak self] in
            Task {
                await coordinator.cancelAndWait()
            }
            Task { @MainActor in
                self?.endBackgroundTaskIfNeeded()
            }
        }

        Task(priority: .utility) { [weak self] in
            await self?.startAndObserveSync()
            _ = await coordinator.waitUntilIdle()
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func startAndObserveSync() async {
        let didStart = await coordinator.start()
        let isRunning = await coordinator.isRunning
        guard didStart || isRunning else {
            return
        }
        observeSyncCompletionIfNeeded()
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskIdentifier != .invalid else { return }
        backgroundTaskManager.end(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }

    private func observeSyncCompletionIfNeeded() {
        guard completionObserver == nil else { return }

        let coordinator = coordinator
        completionObserver = Task { [weak self] in
            guard let self else { return }
            defer { completionObserver = nil }
            guard let report = await coordinator.waitUntilIdle(),
                  !Task.isCancelled
            else { return }
            await didCompleteSync(report)
            cacheRevision &+= 1
        }
    }

    func publishRestoredDataRevision() {
        cacheRevision &+= 1
    }

    func serverConfigurationDidChange() async {
        completionObserver?.cancel()
        completionObserver = nil
        await coordinator.cancelAndWait()
        cacheRevision &+= 1
        await startAndObserveSync()
    }
}
