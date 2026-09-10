import Foundation

public protocol AppDatabaseProviding: Sendable {
    func database() async throws -> SQLiteDatabase
}

public actor LiveAppDatabaseProvider: AppDatabaseProviding {
    private static let legacyNamespace = "legacy"

    private var cached: [String: SQLiteDatabase] = [:]
    private let fileManager: FileManager
    private let applicationSupportBaseDirectory: URL?
    private let settingsStore: (any SettingsStoring)?

    public init(
        fileManager: FileManager = .default,
        applicationSupportBaseDirectory: URL? = nil,
        settingsStore: (any SettingsStoring)? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportBaseDirectory = applicationSupportBaseDirectory
        self.settingsStore = settingsStore
    }

    public func database() async throws -> SQLiteDatabase {
        let namespace = await databaseNamespace()
        if let database = cached[namespace] {
            return database
        }

        let directory = try applicationSupportDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        let url = databaseURL(in: directory, namespace: namespace)
        if namespace != Self.legacyNamespace {
            try await adoptLegacyDatabaseIfNeeded(targetURL: url, directory: directory)
        }
        let database = try SQLiteDatabase.open(path: url.path)
        try await Migrations.applyAll(to: database)
        protectDatabaseFiles(at: url)
        cached[namespace] = database
        return database
    }

    private func databaseNamespace() async -> String {
        guard let settingsStore else {
            return Self.legacyNamespace
        }
        let value = await settingsStore.load().serverURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.scheme != nil,
              url.host != nil
        else {
            return Self.legacyNamespace
        }
        return TeslaMateServerIdentity.key(for: url)
    }

    private func databaseURL(in directory: URL, namespace: String) -> URL {
        let filename = namespace == Self.legacyNamespace
            ? "matedrive.sqlite"
            : "matedrive-\(namespace).sqlite"
        return directory.appendingPathComponent(filename)
    }

    private func adoptLegacyDatabaseIfNeeded(targetURL: URL, directory: URL) async throws {
        let markerURL = directory.appendingPathComponent(".legacy-database-adopted")
        guard !fileManager.fileExists(atPath: markerURL.path) else {
            return
        }
        if fileManager.fileExists(atPath: targetURL.path) {
            try markLegacyDatabaseAdopted(at: markerURL)
            return
        }
        let legacyURL = databaseURL(in: directory, namespace: Self.legacyNamespace)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            try markLegacyDatabaseAdopted(at: markerURL)
            return
        }

        let legacyDatabase: SQLiteDatabase
        if let existing = cached[Self.legacyNamespace] {
            legacyDatabase = existing
        } else {
            legacyDatabase = try SQLiteDatabase.open(path: legacyURL.path)
            try await Migrations.applyAll(to: legacyDatabase)
            cached[Self.legacyNamespace] = legacyDatabase
        }
        _ = try await legacyDatabase.backup(to: targetURL)
        protectDatabaseFiles(at: targetURL)
        try markLegacyDatabaseAdopted(at: markerURL)
    }

    private func markLegacyDatabaseAdopted(at markerURL: URL) throws {
        try Data().write(to: markerURL, options: .atomic)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: markerURL.path
        )
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

        return baseDirectory.appendingPathComponent("MateDrive", isDirectory: true)
    }

    private func protectDatabaseFiles(at databaseURL: URL) {
        for url in [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ] where fileManager.fileExists(atPath: url.path) {
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
    }
}
