import CloudKit
import Foundation

enum CloudKitBackupRecordMapper {
    static let recordType = "MateDriveBackup"
    static let zoneName = "MateDriveBackupZone"

    static func record(
        artifact: DatabaseBackupArtifact,
        kind: CloudBackupKind,
        createdAt: Date,
        recordID: CKRecord.ID
    ) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["createdAt"] = createdAt
        record["kind"] = kind.rawValue
        record["formatVersion"] = artifact.formatVersion
        record["databaseSchemaVersion"] = artifact.databaseSchemaVersion
        record["appVersion"] = artifact.appVersion
        record["databaseByteCount"] = artifact.databaseByteCount
        record["databaseSHA256"] = artifact.databaseSHA256
        record["databaseAsset"] = CKAsset(fileURL: artifact.databaseURL)
        record.encryptedValues["settingsData"] = artifact.settingsData
        return record
    }

    static func descriptor(from record: CKRecord) throws -> CloudBackupDescriptor {
        guard let createdAt = record["createdAt"] as? Date,
              let kindValue = record["kind"] as? String,
              let kind = CloudBackupKind(rawValue: kindValue),
              let formatVersion = (record["formatVersion"] as? NSNumber)?.intValue,
              let databaseSchemaVersion = (record["databaseSchemaVersion"] as? NSNumber)?.intValue,
              let appVersion = record["appVersion"] as? String,
              let databaseByteCount = (record["databaseByteCount"] as? NSNumber)?.int64Value,
              let databaseSHA256 = record["databaseSHA256"] as? String
        else { throw CloudBackupError.invalidDatabase }

        return CloudBackupDescriptor(
            id: record.recordID.recordName,
            createdAt: createdAt,
            kind: kind,
            formatVersion: formatVersion,
            databaseSchemaVersion: databaseSchemaVersion,
            appVersion: appVersion,
            databaseByteCount: databaseByteCount,
            databaseSHA256: databaseSHA256
        )
    }

    static func asset(from record: CKRecord) throws -> CKAsset {
        guard let asset = record["databaseAsset"] as? CKAsset, asset.fileURL != nil else {
            throw CloudBackupError.invalidDatabase
        }
        return asset
    }

    static func settingsData(from record: CKRecord) throws -> Data {
        guard let data = record.encryptedValues["settingsData"] as? Data else {
            throw CloudBackupError.invalidSettings
        }
        return data
    }
}

public final class CloudKitBackupService: CloudBackupServicing, @unchecked Sendable {
    public static let containerIdentifier = "iCloud.com.matedrive.ios"

    private let container: CKContainer
    private let now: @Sendable () -> Date

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: CloudKitBackupRecordMapper.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    public init(
        container: CKContainer = CKContainer(identifier: CloudKitBackupService.containerIdentifier),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.container = container
        self.now = now
    }

    public func accountStatus() async throws -> CloudBackupAccountStatus {
        do {
            let status: CKAccountStatus = try await withCheckedThrowingContinuation { continuation in
                container.accountStatus { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
            switch status {
            case .available: return .available
            case .noAccount: return .noAccount
            case .restricted: return .restricted
            case .couldNotDetermine, .temporarilyUnavailable: return .unavailable
            @unknown default: return .unavailable
            }
        } catch {
            throw Self.mapError(error, now: now())
        }
    }

    public func listBackups() async throws -> [CloudBackupDescriptor] {
        try await requireAvailableAccount()
        let database = container.privateCloudDatabase
        try await ensureZone(in: database)
        let query = CKQuery(recordType: CloudKitBackupRecordMapper.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            var response = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                resultsLimit: 100
            )
            var descriptors = try response.matchResults.map { try CloudKitBackupRecordMapper.descriptor(from: $0.1.get()) }
            while let cursor = response.queryCursor {
                response = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
                descriptors.append(contentsOf: try response.matchResults.map {
                    try CloudKitBackupRecordMapper.descriptor(from: $0.1.get())
                })
            }
            return descriptors.sorted { $0.createdAt > $1.createdAt }
        } catch {
            throw Self.mapError(error, now: now())
        }
    }

    public func upload(_ artifact: DatabaseBackupArtifact, kind: CloudBackupKind) async throws -> CloudBackupDescriptor {
        try await requireAvailableAccount()
        let database = container.privateCloudDatabase
        try await ensureZone(in: database)
        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CloudKitBackupRecordMapper.record(
            artifact: artifact,
            kind: kind,
            createdAt: now(),
            recordID: recordID
        )

        do {
            let result = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            guard let saved = result.saveResults[recordID] else {
                throw CloudBackupError.serviceFailure("CloudKit did not return the saved backup.")
            }
            return try CloudKitBackupRecordMapper.descriptor(from: saved.get())
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw Self.mapError(error, now: now())
        }
    }

    public func download(_ descriptor: CloudBackupDescriptor) async throws -> DownloadedCloudBackup {
        try await requireAvailableAccount()
        let database = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: descriptor.id, zoneID: zoneID)

        do {
            let results = try await database.records(for: [recordID])
            guard let result = results[recordID] else { throw CloudBackupError.recordNotFound }
            let record = try result.get()
            let asset = try CloudKitBackupRecordMapper.asset(from: record)
            let settingsData = try CloudKitBackupRecordMapper.settingsData(from: record)
            guard let sourceURL = asset.fileURL else { throw CloudBackupError.invalidDatabase }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MateDriveCloudRestore", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
            let destinationURL = directory.appendingPathComponent("matedrive.sqlite")
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destinationURL.path
            )
            return DownloadedCloudBackup(
                descriptor: try CloudKitBackupRecordMapper.descriptor(from: record),
                databaseURL: destinationURL,
                settingsData: settingsData
            )
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw Self.mapError(error, now: now())
        }
    }

    public func delete(_ descriptor: CloudBackupDescriptor) async throws {
        try await requireAvailableAccount()
        let recordID = CKRecord.ID(recordName: descriptor.id, zoneID: zoneID)
        do {
            let result = try await container.privateCloudDatabase.modifyRecords(
                saving: [],
                deleting: [recordID],
                atomically: true
            )
            guard let deletion = result.deleteResults[recordID] else {
                throw CloudBackupError.recordNotFound
            }
            try deletion.get()
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw Self.mapError(error, now: now())
        }
    }

    public func deleteAll() async throws {
        for descriptor in try await listBackups() {
            try await delete(descriptor)
        }
    }

    private func ensureZone(in database: CKDatabase) async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            let result = try await database.modifyRecordZones(saving: [zone], deleting: [])
            guard let saved = result.saveResults[zoneID] else {
                throw CloudBackupError.serviceFailure("CloudKit did not return the backup zone.")
            }
            _ = try saved.get()
        } catch let error as CloudBackupError {
            throw error
        } catch {
            throw Self.mapError(error, now: now())
        }
    }

    private func requireAvailableAccount() async throws {
        switch try await accountStatus() {
        case .available: return
        case .noAccount: throw CloudBackupError.noICloudAccount
        case .restricted, .unavailable: throw CloudBackupError.iCloudUnavailable
        }
    }

    static func mapError(_ error: Error, now: Date) -> CloudBackupError {
        if let error = error as? CloudBackupError { return error }
        if error is CancellationError { return .cancelled }
        let nsError = error as NSError
        guard nsError.domain == CKErrorDomain else {
            return .serviceFailure(nsError.localizedDescription)
        }

        switch CKError.Code(rawValue: nsError.code) {
        case .notAuthenticated:
            return .noICloudAccount
        case .quotaExceeded:
            return .quotaExceeded
        case .requestRateLimited, .zoneBusy, .serviceUnavailable:
            let delay = nsError.userInfo[CKErrorRetryAfterKey] as? TimeInterval
            return .rateLimited(retryAfter: delay.map { now.addingTimeInterval($0) })
        case .networkUnavailable, .networkFailure:
            return .iCloudUnavailable
        case .unknownItem:
            return .recordNotFound
        case .operationCancelled:
            return .cancelled
        default:
            return .serviceFailure(nsError.localizedDescription)
        }
    }
}
