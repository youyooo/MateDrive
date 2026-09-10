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

public struct UnavailableCloudBackupService: CloudBackupServicing {
    public init() {}

    public func accountStatus() async throws -> CloudBackupAccountStatus {
        .unavailable
    }

    public func listBackups() async throws -> [CloudBackupDescriptor] {
        throw CloudBackupError.iCloudUnavailable
    }

    public func upload(
        _ artifact: DatabaseBackupArtifact,
        kind: CloudBackupKind
    ) async throws -> CloudBackupDescriptor {
        throw CloudBackupError.iCloudUnavailable
    }

    public func download(_ descriptor: CloudBackupDescriptor) async throws -> DownloadedCloudBackup {
        throw CloudBackupError.iCloudUnavailable
    }

    public func delete(_ descriptor: CloudBackupDescriptor) async throws {
        throw CloudBackupError.iCloudUnavailable
    }

    public func deleteAll() async throws {
        throw CloudBackupError.iCloudUnavailable
    }
}
