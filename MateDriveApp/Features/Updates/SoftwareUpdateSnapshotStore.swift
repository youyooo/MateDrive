import CryptoKit
import Foundation

public struct SoftwareUpdateSnapshot: Codable, Equatable, Sendable {
    public let updates: [UpdateData]
    public let savedAt: Date

    public init(updates: [UpdateData], savedAt: Date = Date()) {
        self.updates = updates
        self.savedAt = savedAt
    }
}

public protocol SoftwareUpdateSnapshotStoring: Sendable {
    func load(serverURL: String, carId: Int) async -> SoftwareUpdateSnapshot?
    func save(_ snapshot: SoftwareUpdateSnapshot, serverURL: String, carId: Int) async
    func releaseMemory() async
    func removeAll() async
}

public extension SoftwareUpdateSnapshotStoring {
    func releaseMemory() async {}
    func removeAll() async {}
}

public actor SoftwareUpdateSnapshotStore: SoftwareUpdateSnapshotStoring {
    public static let shared = SoftwareUpdateSnapshotStore(storageURL: liveStorageURL)

    private struct Key: Codable, Hashable {
        let serverDigest: String
        let carId: Int
    }

    private struct StoredSnapshot: Codable {
        let key: Key
        let snapshot: SoftwareUpdateSnapshot
    }

    private var snapshots: [Key: SoftwareUpdateSnapshot] = [:]
    private let storageURL: URL?
    private var restoredFromDisk = false

    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
    }

    public func load(serverURL: String, carId: Int) async -> SoftwareUpdateSnapshot? {
        restoreFromDiskIfNeeded()
        return snapshots[Self.key(serverURL: serverURL, carId: carId)]
    }

    public func save(_ snapshot: SoftwareUpdateSnapshot, serverURL: String, carId: Int) async {
        restoreFromDiskIfNeeded()
        snapshots[Self.key(serverURL: serverURL, carId: carId)] = snapshot
        persist()
    }

    public func releaseMemory() async {
        snapshots.removeAll()
        restoredFromDisk = false
    }

    public func removeAll() async {
        snapshots.removeAll()
        restoredFromDisk = true
        guard let storageURL else { return }
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func restoreFromDiskIfNeeded() {
        guard !restoredFromDisk else { return }
        restoredFromDisk = true
        guard let storageURL,
              let data = try? Data(contentsOf: storageURL),
              let stored = try? JSONDecoder().decode([StoredSnapshot].self, from: data)
        else { return }
        snapshots = Dictionary(stored.map { ($0.key, $0.snapshot) }, uniquingKeysWith: { _, latest in latest })
    }

    private func persist() {
        guard let storageURL,
              let data = try? JSONEncoder().encode(
                  snapshots.map { StoredSnapshot(key: $0.key, snapshot: $0.value) }
              )
        else { return }
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    private static func key(serverURL: String, carId: Int) -> Key {
        let canonical = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return Key(serverDigest: digest, carId: carId)
    }

    private static var liveStorageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MateDrive", isDirectory: true)
            .appendingPathComponent("software-updates.json", isDirectory: false)
    }
}

public struct EmptySoftwareUpdateSnapshotStore: SoftwareUpdateSnapshotStoring {
    public init() {}
    public func load(serverURL _: String, carId _: Int) async -> SoftwareUpdateSnapshot? { nil }
    public func save(_: SoftwareUpdateSnapshot, serverURL _: String, carId _: Int) async {}
}
