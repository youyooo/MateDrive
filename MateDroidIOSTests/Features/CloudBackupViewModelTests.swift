import Foundation
import XCTest
@testable import MateDroidIOS

@MainActor
final class CloudBackupViewModelTests: XCTestCase {
    func testCachedBackupsRemainVisibleWhileRemoteRefreshRuns() async {
        let cached = backup(id: "cached", age: 120)
        let remote = backup(id: "remote", age: 0)
        let coordinator = CloudBackupViewModelCoordinator(cached: [cached], remote: [remote])
        let viewModel = CloudBackupViewModel(coordinator: coordinator)

        await viewModel.loadCached()
        XCTAssertEqual(viewModel.state.backups, [cached])

        let refresh = Task { await viewModel.refreshRemote() }
        await coordinator.waitUntilRemoteListStarts()

        XCTAssertEqual(viewModel.state.backups, [cached])
        XCTAssertTrue(viewModel.state.isRefreshing)

        await coordinator.releaseRemoteList()
        await refresh.value

        XCTAssertEqual(viewModel.state.backups, [remote])
        XCTAssertFalse(viewModel.state.isRefreshing)
    }

    func testEnablingAutomaticBackupRequiresOneDisclosureConfirmation() async {
        let coordinator = CloudBackupViewModelCoordinator()
        let viewModel = CloudBackupViewModel(coordinator: coordinator)

        await viewModel.loadCached()
        await viewModel.requestAutomaticBackup(true)

        XCTAssertTrue(viewModel.state.showsDisclosure)
        XCTAssertFalse(viewModel.state.preferences.isAutomaticBackupEnabled)

        await viewModel.confirmDisclosureAndEnableAutomaticBackup()

        XCTAssertFalse(viewModel.state.showsDisclosure)
        XCTAssertTrue(viewModel.state.preferences.hasAcceptedDisclosure)
        XCTAssertTrue(viewModel.state.preferences.isAutomaticBackupEnabled)
    }

    func testRestorePublishesCredentialReminderAndResetsOperation() async {
        let descriptor = backup(id: "restore", age: 0)
        let coordinator = CloudBackupViewModelCoordinator(cached: [descriptor])
        let viewModel = CloudBackupViewModel(coordinator: coordinator)
        await viewModel.loadCached()

        await viewModel.restore(descriptor)

        XCTAssertNil(viewModel.state.operation)
        XCTAssertTrue(viewModel.state.showsCredentialReminder)
        let restoreCount = await coordinator.restoreCount
        XCTAssertEqual(restoreCount, 1)
    }

    func testDuplicateManualBackupTapStartsOnlyOneOperation() async {
        let coordinator = CloudBackupViewModelCoordinator()
        await coordinator.acceptDisclosure()
        let viewModel = CloudBackupViewModel(coordinator: coordinator)
        await viewModel.loadCached()

        let first = Task { await viewModel.createManualBackup() }
        await coordinator.waitUntilManualBackupStarts()
        await viewModel.createManualBackup()
        let manualBackupCount = await coordinator.manualBackupCount
        XCTAssertEqual(manualBackupCount, 1)

        await coordinator.releaseManualBackup()
        await first.value
        XCTAssertNil(viewModel.state.operation)
    }

    private func backup(id: String, age: TimeInterval) -> CloudBackupDescriptor {
        CloudBackupDescriptor(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 - age),
            kind: .manual,
            formatVersion: 1,
            databaseSchemaVersion: DatabaseSchemaVersion.current,
            appVersion: "1.0",
            databaseByteCount: 1_024,
            databaseSHA256: "hash-\(id)"
        )
    }
}

private actor CloudBackupViewModelCoordinator: CloudBackupCoordinating {
    private var preferencesValue = CloudBackupPreferences()
    private let cached: [CloudBackupDescriptor]
    private let remote: [CloudBackupDescriptor]
    private var remoteListStarted = false
    private var remoteListReleased = false
    private var remoteStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var remoteReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var manualStarted = false
    private var manualReleased = false
    private var manualStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var manualReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var manualBackupCount = 0
    private(set) var restoreCount = 0

    init(cached: [CloudBackupDescriptor] = [], remote: [CloudBackupDescriptor] = []) {
        self.cached = cached
        self.remote = remote
        preferencesValue.cachedBackups = cached
    }

    func accountStatus() async throws -> CloudBackupAccountStatus { .available }
    func preferences() -> CloudBackupPreferences { preferencesValue }

    func acceptDisclosure() {
        preferencesValue.hasAcceptedDisclosure = true
    }

    func setAutomaticBackupEnabled(_ isEnabled: Bool) throws {
        if isEnabled, !preferencesValue.hasAcceptedDisclosure {
            throw CloudBackupError.disclosureRequired
        }
        preferencesValue.isAutomaticBackupEnabled = isEnabled
    }

    func listBackups(forceRefresh: Bool) async throws -> [CloudBackupDescriptor] {
        guard forceRefresh else { return preferencesValue.cachedBackups }
        remoteListStarted = true
        remoteStartWaiters.forEach { $0.resume() }
        remoteStartWaiters.removeAll()
        if !remoteListReleased {
            await withCheckedContinuation { remoteReleaseWaiters.append($0) }
        }
        preferencesValue.cachedBackups = remote
        return remote
    }

    func createManualBackup() async throws -> CloudBackupDescriptor {
        manualBackupCount += 1
        manualStarted = true
        manualStartWaiters.forEach { $0.resume() }
        manualStartWaiters.removeAll()
        if !manualReleased {
            await withCheckedContinuation { manualReleaseWaiters.append($0) }
        }
        let descriptor = cached.first ?? remote.first ?? CloudBackupDescriptor(
            id: "created",
            createdAt: Date(),
            kind: .manual,
            formatVersion: 1,
            databaseSchemaVersion: DatabaseSchemaVersion.current,
            appVersion: "1.0",
            databaseByteCount: 1,
            databaseSHA256: "hash"
        )
        preferencesValue.cachedBackups = [descriptor]
        return descriptor
    }

    func restore(_: CloudBackupDescriptor) async throws { restoreCount += 1 }
    func delete(_: CloudBackupDescriptor) async throws {}
    func deleteAll() async throws {}
    func cleanupWarning() -> CloudBackupError? { nil }

    func waitUntilRemoteListStarts() async {
        guard !remoteListStarted else { return }
        await withCheckedContinuation { remoteStartWaiters.append($0) }
    }

    func releaseRemoteList() {
        remoteListReleased = true
        remoteReleaseWaiters.forEach { $0.resume() }
        remoteReleaseWaiters.removeAll()
    }

    func waitUntilManualBackupStarts() async {
        guard !manualStarted else { return }
        await withCheckedContinuation { manualStartWaiters.append($0) }
    }

    func releaseManualBackup() {
        manualReleased = true
        manualReleaseWaiters.forEach { $0.resume() }
        manualReleaseWaiters.removeAll()
    }
}
