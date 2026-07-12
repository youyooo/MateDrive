import XCTest
@testable import MateDroidIOS

final class AppDatabaseProviderTests: XCTestCase {
    func testDatabaseProviderCreatesMateDriveDatabaseForNewInstall() async throws {
        let baseDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let provider = LiveAppDatabaseProvider(applicationSupportBaseDirectory: baseDirectory)
        _ = try await provider.database()

        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDirectory.appending(path: "MateDrive/matedrive.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: baseDirectory.appending(path: "MateDroid").path))
    }

    func testDatabaseProviderMigratesLegacyMateDroidDatabase() async throws {
        let baseDirectory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let legacyDirectory = baseDirectory.appending(path: "MateDroid", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        let legacyDatabaseURL = legacyDirectory.appending(path: "matedroid.sqlite")
        FileManager.default.createFile(atPath: legacyDatabaseURL.path, contents: Data())

        let provider = LiveAppDatabaseProvider(applicationSupportBaseDirectory: baseDirectory)
        _ = try await provider.database()

        XCTAssertTrue(FileManager.default.fileExists(atPath: baseDirectory.appending(path: "MateDrive/matedrive.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDatabaseURL.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "MateDriveDatabaseProviderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
