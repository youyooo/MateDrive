import Foundation

public enum CloudBackupAccountStatus: Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case unavailable
}

public protocol CloudBackupServicing: Sendable {
    func accountStatus() async throws -> CloudBackupAccountStatus
    func listBackups() async throws -> [CloudBackupDescriptor]
    func upload(_ artifact: DatabaseBackupArtifact, kind: CloudBackupKind) async throws -> CloudBackupDescriptor
    func download(_ descriptor: CloudBackupDescriptor) async throws -> DownloadedCloudBackup
    func delete(_ descriptor: CloudBackupDescriptor) async throws
    func deleteAll() async throws
}
