import CryptoKit
import Foundation

public struct ActivitiesCacheSnapshot: Codable, Equatable, Sendable {
    public let state: ActivitiesState
    public let savedAt: Date

    public init(state: ActivitiesState, savedAt: Date = Date()) {
        var cachedState = state
        cachedState.isLoading = false
        cachedState.isLoadingMore = false
        cachedState.isLoadingHistory = false
        cachedState.errorMessage = nil
        cachedState.filter = .all
        cachedState.dateFilter = .all
        cachedState.locationQuery = ""
        cachedState.isUsingCachedData = true
        self.state = cachedState
        self.savedAt = savedAt
    }
}

public protocol ActivitiesStateCaching: Sendable {
    func load(serverURL: String, carId: Int, now: Date) async -> ActivitiesCacheSnapshot?
    func save(_ snapshot: ActivitiesCacheSnapshot, serverURL: String, carId: Int) async
    func removeAll() async
}

public extension ActivitiesStateCaching {
    func removeAll() async {}
}

public actor ActivitiesStateCache: ActivitiesStateCaching {
    public static let shared = ActivitiesStateCache(storageURL: liveStorageURL)
    public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    private struct Key: Codable, Hashable {
        let serverDigest: String
        let carId: Int
    }

    private struct StoredSnapshot: Codable {
        let key: Key
        let snapshot: ActivitiesCacheSnapshot
    }

    private var snapshots: [Key: ActivitiesCacheSnapshot] = [:]
    private let maximumAge: TimeInterval
    private let storageURL: URL?
    private var restoredFromDisk = false

    public init(
        maximumAge: TimeInterval = ActivitiesStateCache.maximumAge,
        storageURL: URL? = nil
    ) {
        self.maximumAge = maximumAge
        self.storageURL = storageURL
    }

    public func load(serverURL: String, carId: Int, now: Date = Date()) async -> ActivitiesCacheSnapshot? {
        restoreFromDiskIfNeeded()
        let key = Self.key(serverURL: serverURL, carId: carId)
        guard let snapshot = snapshots[key],
              now.timeIntervalSince(snapshot.savedAt) >= 0,
              now.timeIntervalSince(snapshot.savedAt) <= maximumAge
        else {
            snapshots.removeValue(forKey: key)
            persist()
            return nil
        }
        return snapshot
    }

    public func save(_ snapshot: ActivitiesCacheSnapshot, serverURL: String, carId: Int) async {
        restoreFromDiskIfNeeded()
        let key = Self.key(serverURL: serverURL, carId: carId)
        let candidate = Self.normalized(snapshot)
        if let existing = snapshots[key], !candidate.state.historyFullyLoaded {
            let existingIDs = Set(existing.state.items.map(\.stableID))
            let candidateIDs = Set(candidate.state.items.map(\.stableID))
            let existingAnchor = Self.continuityAnchor(for: existing.state)
            let preservesAnchor = existingAnchor == nil
                || candidate.state.historyContinuityAnchorID == existingAnchor
            let isMergedPartialCheckpoint = existing.state.historyFullyLoaded
                && existingIDs.isSubset(of: candidateIDs)
                && candidateIDs.count > existingIDs.count
            if !existingIDs.isSubset(of: candidateIDs)
                || !preservesAnchor
                || (!isMergedPartialCheckpoint
                    && (existing.state.historyFullyLoaded
                        || existing.state.loadedPageCount > candidate.state.loadedPageCount)) {
                return
            }
        }
        snapshots[key] = candidate
        persist()
    }

    public func removeAll() async {
        snapshots.removeAll()
        restoredFromDisk = true
        guard let storageURL else { return }
        try? FileManager.default.removeItem(at: storageURL)
    }

    public func snapshotCount() async -> Int {
        restoreFromDiskIfNeeded()
        return snapshots.count
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
              let data = try? JSONEncoder().encode(snapshots.map { StoredSnapshot(key: $0.key, snapshot: $0.value) })
        else { return }
        try? FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: storageURL, options: .atomic)
    }

    private static func key(serverURL: String, carId: Int) -> Key {
        let canonical = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
        return Key(serverDigest: digest, carId: carId)
    }

    private static func normalized(_ snapshot: ActivitiesCacheSnapshot) -> ActivitiesCacheSnapshot {
        guard snapshot.state.historyFullyLoaded,
              snapshot.state.historyContinuityAnchorID == nil,
              let anchor = snapshot.state.items.first?.stableID
        else { return snapshot }
        var state = snapshot.state
        state.historyContinuityAnchorID = anchor
        return ActivitiesCacheSnapshot(state: state, savedAt: snapshot.savedAt)
    }

    private static func continuityAnchor(for state: ActivitiesState) -> String? {
        state.historyContinuityAnchorID
            ?? (state.historyFullyLoaded ? state.items.first?.stableID : nil)
    }

    private static var liveStorageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MateDrive", isDirectory: true)
            .appendingPathComponent("activities-cache.json", isDirectory: false)
    }
}

public struct EmptyActivitiesStateCache: ActivitiesStateCaching {
    public init() {}
    public func load(serverURL _: String, carId _: Int, now _: Date) async -> ActivitiesCacheSnapshot? { nil }
    public func save(_: ActivitiesCacheSnapshot, serverURL _: String, carId _: Int) async {}
}
