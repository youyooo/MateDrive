import Foundation

public protocol CloudBackupCoordinating: Sendable {
    func accountStatus() async throws -> CloudBackupAccountStatus
    func preferences() async -> CloudBackupPreferences
    func acceptDisclosure() async
    func setAutomaticBackupEnabled(_ isEnabled: Bool) async throws
    func listBackups(forceRefresh: Bool) async throws -> [CloudBackupDescriptor]
    func createManualBackup() async throws -> CloudBackupDescriptor
    func createAutomaticBackup(after report: BackgroundRefreshReport) async -> CloudBackupDescriptor?
    func restore(_ descriptor: CloudBackupDescriptor) async throws
    func delete(_ descriptor: CloudBackupDescriptor) async throws
    func deleteAll() async throws
    func cleanupWarning() async -> CloudBackupError?
}

public extension CloudBackupCoordinating {
    func createAutomaticBackup(after _: BackgroundRefreshReport) async -> CloudBackupDescriptor? { nil }
}

public actor CloudBackupCoordinator: CloudBackupCoordinating {
    public enum Operation: Equatable, Sendable {
        case listing
        case backingUp(CloudBackupKind)
        case restoring(String)
        case deleting(String)
        case deletingAll
    }

    private let service: any CloudBackupServicing
    private let databaseProvider: any DatabaseBackupProviding
    private let preferencesStore: any CloudBackupPreferencesStoring
    private let syncController: any AppDataSyncSuspending
    private let cacheInvalidator: any BackupCacheInvalidating
    private let appVersion: @Sendable () -> String
    private let didRestore: @Sendable () async throws -> Void
    private let now: @Sendable () -> Date
    private let automaticInterval: TimeInterval
    private let retentionCount: Int

    private var operation: Operation?
    private var lastCleanupError: CloudBackupError?
    private var lastOperationError: CloudBackupError?

    public init(
        service: any CloudBackupServicing,
        databaseProvider: any DatabaseBackupProviding,
        preferencesStore: any CloudBackupPreferencesStoring,
        syncController: any AppDataSyncSuspending = NoopAppDataSyncSuspender(),
        cacheInvalidator: any BackupCacheInvalidating = NoopBackupCacheInvalidator(),
        appVersion: @escaping @Sendable () -> String,
        didRestore: @escaping @Sendable () async throws -> Void = {},
        now: @escaping @Sendable () -> Date = Date.init,
        automaticInterval: TimeInterval = 24 * 60 * 60,
        retentionCount: Int = 3
    ) {
        self.service = service
        self.databaseProvider = databaseProvider
        self.preferencesStore = preferencesStore
        self.syncController = syncController
        self.cacheInvalidator = cacheInvalidator
        self.appVersion = appVersion
        self.didRestore = didRestore
        self.now = now
        self.automaticInterval = automaticInterval
        self.retentionCount = retentionCount
    }

    public func currentOperation() -> Operation? { operation }
    public func cleanupWarning() -> CloudBackupError? { lastCleanupError }
    public func operationError() -> CloudBackupError? { lastOperationError }

    public func preferences() async -> CloudBackupPreferences {
        await preferencesStore.load()
    }

    public func accountStatus() async throws -> CloudBackupAccountStatus {
        do {
            return try await service.accountStatus()
        } catch {
            throw Self.map(error)
        }
    }

    public func acceptDisclosure() async {
        var preferences = await preferencesStore.load()
        preferences.hasAcceptedDisclosure = true
        await preferencesStore.save(preferences)
    }

    public func setAutomaticBackupEnabled(_ isEnabled: Bool) async throws {
        var preferences = await preferencesStore.load()
        if isEnabled, !preferences.hasAcceptedDisclosure {
            throw CloudBackupError.disclosureRequired
        }
        preferences.isAutomaticBackupEnabled = isEnabled
        await preferencesStore.save(preferences)
    }

    public func listBackups(forceRefresh: Bool) async throws -> [CloudBackupDescriptor] {
        if !forceRefresh {
            return (await preferencesStore.load()).cachedBackups
        }

        try begin(.listing)
        defer { endOperation() }
        do {
            let descriptors = try await service.listBackups().sorted { $0.createdAt > $1.createdAt }
            var preferences = await preferencesStore.load()
            preferences.cachedBackups = Array(descriptors.prefix(retentionCount))
            await preferencesStore.save(preferences)
            lastOperationError = nil
            return preferences.cachedBackups
        } catch {
            let mapped = Self.map(error)
            lastOperationError = mapped
            throw mapped
        }
    }

    public func createManualBackup() async throws -> CloudBackupDescriptor {
        let preferences = await preferencesStore.load()
        guard preferences.hasAcceptedDisclosure else {
            throw CloudBackupError.disclosureRequired
        }
        return try await createBackup(kind: .manual)
    }

    public func createAutomaticBackup(after report: BackgroundRefreshReport) async -> CloudBackupDescriptor? {
        guard report.isSuccessful else { return nil }
        let preferences = await preferencesStore.load()
        guard preferences.hasAcceptedDisclosure, preferences.isAutomaticBackupEnabled else { return nil }
        if let lastBackup = preferences.lastAutomaticBackupAt,
           now().timeIntervalSince(lastBackup) < automaticInterval {
            return nil
        }

        do {
            return try await createBackup(kind: .automatic)
        } catch {
            lastOperationError = Self.map(error)
            return nil
        }
    }

    public func restore(_ descriptor: CloudBackupDescriptor) async throws {
        try begin(.restoring(descriptor.id))
        await syncController.suspendAndWait()

        do {
            try await restoreWhileSuspended(descriptor)
            lastOperationError = nil
            await syncController.resume()
            endOperation()
        } catch {
            let mapped = Self.map(error)
            lastOperationError = mapped
            await syncController.resume()
            endOperation()
            throw mapped
        }
    }

    public func delete(_ descriptor: CloudBackupDescriptor) async throws {
        try begin(.deleting(descriptor.id))
        defer { endOperation() }
        do {
            try await service.delete(descriptor)
            var preferences = await preferencesStore.load()
            preferences.cachedBackups.removeAll { $0.id == descriptor.id }
            await preferencesStore.save(preferences)
            lastOperationError = nil
        } catch {
            let mapped = Self.map(error)
            lastOperationError = mapped
            throw mapped
        }
    }

    public func deleteAll() async throws {
        try begin(.deletingAll)
        defer { endOperation() }
        do {
            try await service.deleteAll()
            var preferences = await preferencesStore.load()
            preferences.cachedBackups = []
            preferences.lastSuccessfulBackupAt = nil
            preferences.lastAutomaticBackupAt = nil
            await preferencesStore.save(preferences)
            lastOperationError = nil
        } catch {
            let mapped = Self.map(error)
            lastOperationError = mapped
            throw mapped
        }
    }

    private func createBackup(kind: CloudBackupKind) async throws -> CloudBackupDescriptor {
        try begin(.backingUp(kind))
        defer { endOperation() }
        lastCleanupError = nil

        var artifact: DatabaseBackupArtifact?
        do {
            let createdArtifact = try await databaseProvider.createArtifact(appVersion: appVersion())
            artifact = createdArtifact
            let saved = try await service.upload(createdArtifact, kind: kind)

            var preferences = await preferencesStore.load()
            preferences.lastSuccessfulBackupAt = saved.createdAt
            if kind == .automatic {
                preferences.lastAutomaticBackupAt = saved.createdAt
            }
            await preferencesStore.save(preferences)

            await applyRetention(including: saved)
            lastOperationError = nil
            if let artifact { databaseProvider.removeArtifact(at: artifact.databaseURL) }
            return saved
        } catch {
            if let artifact { databaseProvider.removeArtifact(at: artifact.databaseURL) }
            let mapped = Self.map(error)
            lastOperationError = mapped
            throw mapped
        }
    }

    private func applyRetention(including saved: CloudBackupDescriptor) async {
        do {
            let all = try await service.listBackups().sorted { $0.createdAt > $1.createdAt }
            let retained = Array(all.prefix(retentionCount))
            for descriptor in all.dropFirst(retentionCount) {
                do {
                    try await service.delete(descriptor)
                } catch {
                    lastCleanupError = Self.map(error)
                }
            }
            var preferences = await preferencesStore.load()
            preferences.cachedBackups = retained
            if !retained.contains(where: { $0.id == saved.id }) {
                preferences.cachedBackups.insert(saved, at: 0)
                preferences.cachedBackups = Array(preferences.cachedBackups.prefix(retentionCount))
            }
            await preferencesStore.save(preferences)
        } catch {
            lastCleanupError = Self.map(error)
            var preferences = await preferencesStore.load()
            preferences.cachedBackups.removeAll { $0.id == saved.id }
            preferences.cachedBackups.insert(saved, at: 0)
            preferences.cachedBackups = Array(preferences.cachedBackups.prefix(retentionCount))
            await preferencesStore.save(preferences)
        }
    }

    private func restoreWhileSuspended(_ descriptor: CloudBackupDescriptor) async throws {
        var downloaded: DownloadedCloudBackup?
        var safetyArtifact: DatabaseBackupArtifact?

        do {
            let cloudBackup = try await service.download(descriptor)
            downloaded = cloudBackup
            let validated = try await databaseProvider.validate(cloudBackup)
            let originalSettings = await databaseProvider.currentSettings()
            let safety = try await databaseProvider.createArtifact(appVersion: appVersion())
            safetyArtifact = safety

            do {
                try await databaseProvider.restoreDatabase(from: validated.databaseURL)
                try await databaseProvider.migrateRestoredDatabase()
                await databaseProvider.restoreSettings(validated.settings)
                try await cacheInvalidator.invalidateAfterRestore()
                try await didRestore()
            } catch {
                do {
                    try await databaseProvider.restoreDatabase(from: safety.databaseURL)
                    try await databaseProvider.migrateRestoredDatabase()
                    await databaseProvider.restoreSettings(originalSettings)
                    try await cacheInvalidator.invalidateAfterRestore()
                    try await didRestore()
                } catch {
                    throw CloudBackupError.rollbackFailed(error.localizedDescription)
                }
                throw CloudBackupError.restoreFailed(error.localizedDescription)
            }

            databaseProvider.removeArtifact(at: cloudBackup.databaseURL)
            databaseProvider.removeArtifact(at: safety.databaseURL)
        } catch {
            if let downloaded {
                databaseProvider.removeArtifact(at: downloaded.databaseURL)
            }
            if let safetyArtifact {
                databaseProvider.removeArtifact(at: safetyArtifact.databaseURL)
            }
            throw error
        }
    }

    private func begin(_ newOperation: Operation) throws {
        guard operation == nil else { throw CloudBackupError.operationInProgress }
        operation = newOperation
    }

    private func endOperation() {
        operation = nil
    }

    private static func map(_ error: Error) -> CloudBackupError {
        if let error = error as? CloudBackupError { return error }
        if error is CancellationError { return .cancelled }
        return .serviceFailure(error.localizedDescription)
    }
}
