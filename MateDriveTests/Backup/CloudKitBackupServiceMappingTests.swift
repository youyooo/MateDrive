import CloudKit
import XCTest
@testable import MateDriveApp

final class CloudKitBackupServiceMappingTests: XCTestCase {
    func testInitializationDoesNotCreateCloudKitContainer() async {
        let probe = CloudKitContainerCreationProbe()
        let service = CloudKitBackupService(
            containerProvider: {
                probe.markCreated()
                throw CloudBackupError.iCloudUnavailable
            }
        )

        XCTAssertFalse(probe.wasCreated)

        do {
            _ = try await service.accountStatus()
            XCTFail("Expected the unavailable CloudKit error.")
        } catch {
            XCTAssertEqual(error as? CloudBackupError, .iCloudUnavailable)
        }
        XCTAssertTrue(probe.wasCreated)
    }

    func testRecordMapperKeepsSensitiveSettingsEncryptedAndQueryableMetadataMinimal() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitBackupServiceMappingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("snapshot.sqlite")
        try Data("database".utf8).write(to: databaseURL)
        let artifact = DatabaseBackupArtifact(
            databaseURL: databaseURL,
            settingsData: Data("private settings".utf8),
            databaseSchemaVersion: 19,
            appVersion: "1.2.3",
            databaseByteCount: 8,
            databaseSHA256: "abc"
        )
        let zoneID = CKRecordZone.ID(zoneName: "MateDriveBackupZone", ownerName: CKCurrentUserDefaultName)
        let record = CloudKitBackupRecordMapper.record(
            artifact: artifact,
            kind: .manual,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            recordID: CKRecord.ID(recordName: "backup-1", zoneID: zoneID)
        )

        XCTAssertEqual(record.recordType, "MateDriveBackup")
        XCTAssertEqual(record["kind"] as? String, "manual")
        XCTAssertNil(record["settingsData"])
        XCTAssertEqual(record.encryptedValues["settingsData"] as? Data, artifact.settingsData)
        XCTAssertNotNil(record["databaseAsset"] as? CKAsset)
        XCTAssertNil(record["serverURL"])
        XCTAssertNil(record["vehicleName"])

        let descriptor = try CloudKitBackupRecordMapper.descriptor(from: record)
        XCTAssertEqual(descriptor.id, "backup-1")
        XCTAssertEqual(descriptor.databaseSchemaVersion, 19)
        XCTAssertEqual(descriptor.databaseByteCount, 8)
    }

    func testErrorMapperDistinguishesAccountQuotaAndRateLimiting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let unauthenticated = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.notAuthenticated.rawValue
        )
        let quota = NSError(domain: CKErrorDomain, code: CKError.Code.quotaExceeded.rawValue)
        let limited = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.requestRateLimited.rawValue,
            userInfo: [CKErrorRetryAfterKey: 30.0]
        )

        XCTAssertEqual(CloudKitBackupService.mapError(unauthenticated, now: now), .noICloudAccount)
        XCTAssertEqual(CloudKitBackupService.mapError(quota, now: now), .quotaExceeded)
        XCTAssertEqual(
            CloudKitBackupService.mapError(limited, now: now),
            .rateLimited(retryAfter: now.addingTimeInterval(30))
        )
    }

    func testErrorMapperPreservesSafeServerRejectionDiagnostics() {
        let rejected = NSError(
            domain: CKErrorDomain,
            code: CKError.Code.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "The query was rejected.",
                "CKErrorServerDescription": "Field 'createdAt' is not marked sortable.",
                "CKErrorOperationID": "must-not-be-exposed"
            ]
        )

        XCTAssertEqual(
            CloudKitBackupService.mapError(rejected, now: Date()),
            .serviceFailure(
                "CloudKit request failed (15): The query was rejected. "
                    + "Field 'createdAt' is not marked sortable."
            )
        )
    }
}

private final class CloudKitContainerCreationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var created = false

    var wasCreated: Bool {
        lock.withLock { created }
    }

    func markCreated() {
        lock.withLock {
            created = true
        }
    }
}
