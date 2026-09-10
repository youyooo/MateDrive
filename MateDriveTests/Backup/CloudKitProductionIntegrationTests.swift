import CryptoKit
import Foundation
import XCTest
@testable import MateDriveApp

final class CloudKitProductionIntegrationTests: XCTestCase {
    func testPrivateDatabaseUploadListDownloadAndDeleteRoundTrip() async throws {
        guard ProcessInfo.processInfo.environment["MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS"] == "1" else {
            throw XCTSkip("Set MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS=1 for the release-device CloudKit gate.")
        }
#if targetEnvironment(simulator)
        throw XCTSkip("The CloudKit release gate requires a physical device.")
#else
        var phase = "account status"
        let service = CloudKitBackupService()
        let accountStatus = try await service.accountStatus()
        XCTAssertEqual(accountStatus, .available)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitProductionIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let marker = UUID().uuidString
        let databaseData = Data("MateDrive CloudKit release probe \(marker)".utf8)
        let settingsData = Data(#"{"releaseProbe":true}"#.utf8)
        let databaseURL = directory.appendingPathComponent("probe.sqlite")
        try databaseData.write(to: databaseURL, options: .atomic)
        let checksum = SHA256.hash(data: databaseData)
            .map { String(format: "%02x", $0) }
            .joined()
        let artifact = DatabaseBackupArtifact(
            databaseURL: databaseURL,
            settingsData: settingsData,
            databaseSchemaVersion: 0,
            appVersion: "cloudkit-release-probe-\(marker)",
            databaseByteCount: Int64(databaseData.count),
            databaseSHA256: checksum
        )

        var uploaded: CloudBackupDescriptor?
        do {
            phase = "upload"
            let descriptor = try await service.upload(artifact, kind: .manual)
            uploaded = descriptor
            XCTAssertEqual(descriptor.appVersion, artifact.appVersion)
            XCTAssertEqual(descriptor.databaseByteCount, artifact.databaseByteCount)
            XCTAssertEqual(descriptor.databaseSHA256, artifact.databaseSHA256)

            phase = "list after upload"
            let listed = try await service.listBackups()
            XCTAssertTrue(listed.contains { $0.id == descriptor.id })

            phase = "download"
            let downloaded = try await service.download(descriptor)
            defer {
                try? FileManager.default.removeItem(
                    at: downloaded.databaseURL.deletingLastPathComponent()
                )
            }
            XCTAssertEqual(try Data(contentsOf: downloaded.databaseURL), databaseData)
            XCTAssertEqual(downloaded.settingsData, settingsData)
            XCTAssertEqual(downloaded.descriptor, descriptor)

            phase = "delete"
            try await service.delete(descriptor)
            uploaded = nil
            phase = "list after delete"
            let remaining = try await service.listBackups()
            XCTAssertFalse(remaining.contains { $0.id == descriptor.id })
            XCTAssertFalse(
                remaining.contains { $0.appVersion.hasPrefix("cloudkit-release-probe-") },
                "CloudKit Production still contains a release-probe backup."
            )
        } catch {
            if let uploaded {
                try? await service.delete(uploaded)
            }
            XCTFail("CloudKit production \(phase) failed: \(error.localizedDescription)")
            throw error
        }
#endif
    }
}
