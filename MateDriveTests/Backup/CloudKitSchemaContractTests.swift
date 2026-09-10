import Foundation
import XCTest
@testable import MateDriveApp

final class CloudKitSchemaContractTests: XCTestCase {
    func testCheckedInSchemaMatchesBackupRecordContract() throws {
#if targetEnvironment(simulator)
        let schemaURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/release/cloudkit/MateDrive.ckdb")
        let schema = try String(contentsOf: schemaURL, encoding: .utf8)

        XCTAssertTrue(schema.contains("RECORD TYPE \(CloudKitBackupRecordMapper.recordType)"))
        XCTAssertTrue(schema.contains("createdAt TIMESTAMP SORTABLE"))
        XCTAssertTrue(schema.contains("\"___recordID\" REFERENCE QUERYABLE"))
        XCTAssertTrue(schema.contains("kind STRING"))
        XCTAssertTrue(schema.contains("formatVersion INT64"))
        XCTAssertTrue(schema.contains("databaseSchemaVersion INT64"))
        XCTAssertTrue(schema.contains("appVersion STRING"))
        XCTAssertTrue(schema.contains("databaseByteCount INT64"))
        XCTAssertTrue(schema.contains("databaseSHA256 STRING"))
        XCTAssertTrue(schema.contains("databaseAsset ASSET"))
        XCTAssertTrue(schema.contains("settingsData ENCRYPTED BYTES"))
        XCTAssertTrue(schema.contains("GRANT READ, WRITE TO \"_creator\""))
        XCTAssertTrue(schema.contains("GRANT CREATE TO \"_icloud\""))
#else
        throw XCTSkip("The source-schema contract runs on the simulator.")
#endif
    }

    func testProductionEnvironmentIsExplicitInAppEntitlements() throws {
#if targetEnvironment(simulator)
        let entitlementURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MateDriveApp/MateDriveApp.entitlements")
        let data = try Data(contentsOf: entitlementURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(
            entitlements["com.apple.developer.icloud-container-environment"] as? String,
            "Production"
        )
        XCTAssertEqual(
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
            [CloudKitBackupService.containerIdentifier]
        )
#else
        throw XCTSkip("The source-entitlement contract runs on the simulator.")
#endif
    }
}
