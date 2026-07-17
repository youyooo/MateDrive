import Foundation
@testable import MateDroidIOS

actor InMemoryCloudBackupService: CloudBackupServicing {
    var status: CloudBackupAccountStatus = .available
    var descriptors: [CloudBackupDescriptor]
    var uploadCount = 0
    var deletedIDs: [String] = []
    var uploadError: Error?
    var deleteError: Error?
    private let now: @Sendable () -> Date

    init(
        descriptors: [CloudBackupDescriptor] = [],
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.descriptors = descriptors
        self.now = now
    }

    func accountStatus() async throws -> CloudBackupAccountStatus { status }

    func listBackups() async throws -> [CloudBackupDescriptor] {
        descriptors.sorted { $0.createdAt > $1.createdAt }
    }

    func upload(_ artifact: DatabaseBackupArtifact, kind: CloudBackupKind) async throws -> CloudBackupDescriptor {
        if let uploadError { throw uploadError }
        uploadCount += 1
        let descriptor = CloudBackupDescriptor(
            id: "uploaded-\(uploadCount)",
            createdAt: now(),
            kind: kind,
            formatVersion: artifact.formatVersion,
            databaseSchemaVersion: artifact.databaseSchemaVersion,
            appVersion: artifact.appVersion,
            databaseByteCount: artifact.databaseByteCount,
            databaseSHA256: artifact.databaseSHA256
        )
        descriptors.append(descriptor)
        return descriptor
    }

    func download(_ descriptor: CloudBackupDescriptor) async throws -> DownloadedCloudBackup {
        throw CloudBackupError.recordNotFound
    }

    func delete(_ descriptor: CloudBackupDescriptor) async throws {
        if let deleteError { throw deleteError }
        descriptors.removeAll { $0.id == descriptor.id }
        deletedIDs.append(descriptor.id)
    }

    func deleteAll() async throws {
        deletedIDs.append(contentsOf: descriptors.map(\.id))
        descriptors.removeAll()
    }

    func counts() -> (uploads: Int, deletions: [String]) {
        (uploadCount, deletedIDs)
    }
}
