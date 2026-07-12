import Foundation

public protocol AppDatabaseProviding: Sendable {
    func database() async throws -> SQLiteDatabase
}

public actor LiveAppDatabaseProvider: AppDatabaseProviding {
    private var cached: SQLiteDatabase?
    private let fileManager: FileManager
    private let applicationSupportBaseDirectory: URL?

    public init(fileManager: FileManager = .default, applicationSupportBaseDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.applicationSupportBaseDirectory = applicationSupportBaseDirectory
    }

    public func database() async throws -> SQLiteDatabase {
        if let cached {
            return cached
        }

        let directory = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("matedrive.sqlite")
        try migrateLegacyDatabaseFileIfNeeded(to: url, in: directory)
        let database = try SQLiteDatabase.open(path: url.path)
        try await Migrations.applyAll(to: database)
        cached = database
        return database
    }

    private func applicationSupportDirectory() throws -> URL {
        let baseDirectory: URL
        if let applicationSupportBaseDirectory {
            baseDirectory = applicationSupportBaseDirectory
        } else {
            guard let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw SQLiteError.openFailed("Application Support directory is unavailable")
            }
            baseDirectory = directory
        }

        let directory = baseDirectory.appendingPathComponent("MateDrive", isDirectory: true)
        try migrateLegacySupportDirectoryIfNeeded(to: directory, baseDirectory: baseDirectory)
        return directory
    }

    private func migrateLegacySupportDirectoryIfNeeded(to directory: URL, baseDirectory: URL) throws {
        let legacyDirectory = baseDirectory.appendingPathComponent("MateDroid", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyDirectory.path),
              !fileManager.fileExists(atPath: directory.path)
        else {
            return
        }

        try fileManager.moveItem(at: legacyDirectory, to: directory)
    }

    private func migrateLegacyDatabaseFileIfNeeded(to databaseURL: URL, in directory: URL) throws {
        guard !fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }

        let legacyURL = directory.appendingPathComponent("matedroid.sqlite")
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        try fileManager.moveItem(at: legacyURL, to: databaseURL)
    }
}
