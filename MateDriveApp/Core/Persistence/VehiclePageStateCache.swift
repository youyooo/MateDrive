import Foundation

protocol RebuildableVehiclePageStateCaching: AnyObject, Sendable {
    func removeAll()
}

enum VehiclePageStateCacheRegistry {
    private static let storage = Storage()

    static func register(_ cache: any RebuildableVehiclePageStateCaching) {
        storage.register(cache)
    }

    static func releaseMemory() {
        storage.releaseMemory()
    }

    private final class Storage: @unchecked Sendable {
        private final class WeakCache {
            weak var value: (any RebuildableVehiclePageStateCaching)?

            init(_ value: any RebuildableVehiclePageStateCaching) {
                self.value = value
            }
        }

        private let lock = NSLock()
        private var caches: [WeakCache] = []

        func register(_ cache: any RebuildableVehiclePageStateCaching) {
            lock.withLock {
                caches.removeAll { $0.value == nil }
                caches.append(WeakCache(cache))
            }
        }

        func releaseMemory() {
            let liveCaches = lock.withLock {
                caches.removeAll { $0.value == nil }
                return caches.compactMap(\.value)
            }
            liveCaches.forEach { $0.removeAll() }
        }
    }
}

public struct VehiclePageCacheKey: Hashable, Sendable {
    public let serverURL: String
    public let carId: Int
    public let scope: String

    public init(serverURL: String, carId: Int, scope: String = "") {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.carId = carId
        self.scope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public final class VehiclePageStateCache<State: Sendable>: RebuildableVehiclePageStateCaching, @unchecked Sendable {
    private let lock = NSLock()
    private let maximumEntryCount: Int
    private var states: [VehiclePageCacheKey: State] = [:]
    private var recency: [VehiclePageCacheKey] = []

    public init(maximumEntryCount: Int = 12) {
        self.maximumEntryCount = max(maximumEntryCount, 1)
        VehiclePageStateCacheRegistry.register(self)
    }

    public func state(for key: VehiclePageCacheKey) -> State? {
        lock.withLock {
            guard let state = states[key] else { return nil }
            markRecentlyUsed(key)
            return state
        }
    }

    public func save(_ state: State, for key: VehiclePageCacheKey) {
        lock.withLock {
            states[key] = state
            markRecentlyUsed(key)
            while recency.count > maximumEntryCount, let oldest = recency.first {
                recency.removeFirst()
                states.removeValue(forKey: oldest)
            }
        }
    }

    public func remove(for key: VehiclePageCacheKey) {
        lock.withLock {
            states.removeValue(forKey: key)
            recency.removeAll { $0 == key }
        }
    }

    public func removeAll() {
        lock.withLock {
            states.removeAll()
            recency.removeAll()
        }
    }

    private func markRecentlyUsed(_ key: VehiclePageCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
