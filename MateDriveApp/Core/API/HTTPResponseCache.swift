import CryptoKit
import Foundation

public struct HTTPResponseCacheStatistics: Equatable, Sendable {
    public let recordCount: Int
    public let byteCount: Int
    public let oldestStoredAt: Date?
    public let newestStoredAt: Date?

    public init(
        recordCount: Int,
        byteCount: Int,
        oldestStoredAt: Date? = nil,
        newestStoredAt: Date? = nil
    ) {
        self.recordCount = recordCount
        self.byteCount = byteCount
        self.oldestStoredAt = oldestStoredAt
        self.newestStoredAt = newestStoredAt
    }

    public static let empty = HTTPResponseCacheStatistics(recordCount: 0, byteCount: 0)
}

private struct HTTPResponseDiskRecord: Codable, Sendable {
    let data: Data
    let responseURL: String
    let statusCode: Int
    let headerFields: [String: String]
    let storedAt: Date
}

private protocol HTTPResponseDiskStoring: Sendable {
    func load(identifier: String) async -> HTTPResponseDiskRecord?
    func save(_ record: HTTPResponseDiskRecord, identifier: String) async
    func remove(identifier: String) async
    func removeAll() async
    func statistics() async -> HTTPResponseCacheStatistics
}

public actor FileHTTPResponseDiskStore: HTTPResponseDiskStoring {
    public static let live = FileHTTPResponseDiskStore(directory: defaultDirectory())

    private let directory: URL
    private let maximumBytes: Int
    private let fileManager: FileManager

    public init(
        directory: URL,
        maximumBytes: Int = 96 * 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.maximumBytes = maximumBytes
        self.fileManager = fileManager
    }

    fileprivate func load(identifier: String) -> HTTPResponseDiskRecord? {
        guard let data = try? Data(contentsOf: fileURL(identifier: identifier)) else { return nil }
        return try? PropertyListDecoder().decode(HTTPResponseDiskRecord.self, from: data)
    }

    fileprivate func save(_ record: HTTPResponseDiskRecord, identifier: String) {
        do {
            try createDirectoryIfNeeded()
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(record)
            let url = fileURL(identifier: identifier)
            try data.write(to: url, options: .atomic)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            trimIfNeeded()
        } catch {
            return
        }
    }

    fileprivate func remove(identifier: String) {
        try? fileManager.removeItem(at: fileURL(identifier: identifier))
    }

    public func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    public func statistics() -> HTTPResponseCacheStatistics {
        let files = cacheFiles()
        return HTTPResponseCacheStatistics(
            recordCount: files.count,
            byteCount: files.reduce(0) { $0 + $1.byteCount },
            oldestStoredAt: files.map(\.modifiedAt).min(),
            newestStoredAt: files.map(\.modifiedAt).max()
        )
    }

    private func trimIfNeeded() {
        var files = cacheFiles().sorted { $0.modifiedAt < $1.modifiedAt }
        var total = files.reduce(0) { $0 + $1.byteCount }
        while total > maximumBytes, let oldest = files.first {
            try? fileManager.removeItem(at: oldest.url)
            total -= oldest.byteCount
            files.removeFirst()
        }
    }

    private func cacheFiles() -> [(url: URL, byteCount: Int, modifiedAt: Date)] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "cache",
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private func createDirectoryIfNeeded() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
    }

    private func fileURL(identifier: String) -> URL {
        directory.appendingPathComponent(identifier).appendingPathExtension("cache")
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("MateDriveAPIResponses", isDirectory: true)
    }
}

public actor HTTPResponseCache {
    public static let shared = HTTPResponseCache(diskStore: FileHTTPResponseDiskStore.live)

    private struct Key: Hashable {
        let namespace: String
        let method: String
        let url: String
        let headers: [String]

        var diskIdentifier: String {
            let canonical = ([namespace, method, url] + headers).joined(separator: "\n")
            return SHA256.hash(data: Data(canonical.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    private struct Entry {
        let data: Data
        let response: HTTPURLResponse
        let storedAt: Date
    }

    private struct Transfer: @unchecked Sendable {
        let data: Data
        let response: HTTPURLResponse
    }

    private struct InFlightRequest {
        let id: UUID
        let task: Task<Transfer, Error>
    }

    private let refreshAfter: TimeInterval
    private let maximumAge: TimeInterval
    private let maximumBytes: Int
    private let now: @Sendable () -> Date
    private let diskStore: (any HTTPResponseDiskStoring)?
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: InFlightRequest] = [:]
    private var storedBytes = 0
    private var generation = 0

    public init(
        refreshAfter: TimeInterval = 30,
        maximumAge: TimeInterval = 30 * 24 * 60 * 60,
        maximumBytes: Int = 96 * 1_024 * 1_024,
        diskStore: FileHTTPResponseDiskStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.refreshAfter = refreshAfter
        self.maximumAge = maximumAge
        self.maximumBytes = maximumBytes
        self.diskStore = diskStore
        self.now = now
    }

    fileprivate func data(
        for request: URLRequest,
        namespace: String,
        upstream: any HTTPClient
    ) async throws -> (Data, HTTPURLResponse) {
        guard Self.isCacheable(request) else {
            return try await upstream.data(for: request)
        }

        let key = Self.key(for: request, namespace: namespace)
        let isCacheOnly = request.cachePolicy == .returnCacheDataDontLoad
        if request.cachePolicy == .reloadIgnoringLocalCacheData {
            let transfer = try await fetch(key: key, request: request, upstream: upstream)
            return (transfer.data, transfer.response)
        }
        if let entry = entries[key] {
            let age = now().timeIntervalSince(entry.storedAt)
            if isCacheOnly || age <= maximumAge {
                if !isCacheOnly, age >= refreshAfter, inFlight[key] == nil {
                    refreshInBackground(key: key, request: request, upstream: upstream)
                }
                return (entry.data, entry.response)
            }
            removeEntry(for: key)
        }

        if let record = await diskStore?.load(identifier: key.diskIdentifier) {
            let age = now().timeIntervalSince(record.storedAt)
            if (isCacheOnly || age <= maximumAge),
               let responseURL = URL(string: record.responseURL),
               let response = HTTPURLResponse(
                   url: responseURL,
                   statusCode: record.statusCode,
                   httpVersion: "HTTP/1.1",
                   headerFields: record.headerFields
               ) {
                let entry = Entry(data: record.data, response: response, storedAt: record.storedAt)
                restore(entry, for: key)
                if !isCacheOnly, age >= refreshAfter, inFlight[key] == nil {
                    refreshInBackground(key: key, request: request, upstream: upstream)
                }
                return (entry.data, entry.response)
            }
            if !isCacheOnly {
                await diskStore?.remove(identifier: key.diskIdentifier)
            }
        }

        if isCacheOnly {
            throw URLError(.resourceUnavailable)
        }

        let transfer = try await fetch(key: key, request: request, upstream: upstream)
        return (transfer.data, transfer.response)
    }

    public func removeAll() async {
        cancelInFlightRequests()
        entries.removeAll()
        storedBytes = 0
        await diskStore?.removeAll()
    }

    public func releaseMemory() {
        entries.removeAll()
        storedBytes = 0
    }

    public func cancelInFlightRequests() {
        generation += 1
        let requests = inFlight.values
        inFlight.removeAll()
        for request in requests {
            request.task.cancel()
        }
    }

    public func statistics() async -> HTTPResponseCacheStatistics {
        if let diskStore {
            return await diskStore.statistics()
        }
        let storedDates = entries.values.map(\.storedAt)
        return HTTPResponseCacheStatistics(
            recordCount: entries.count,
            byteCount: storedBytes,
            oldestStoredAt: storedDates.min(),
            newestStoredAt: storedDates.max()
        )
    }

    private func fetch(
        key: Key,
        request: URLRequest,
        upstream: any HTTPClient
    ) async throws -> Transfer {
        if let existing = inFlight[key] {
            return try await existing.task.value
        }

        let id = UUID()
        let task = Task {
            let (data, response) = try await upstream.data(for: request)
            return Transfer(data: data, response: response)
        }
        let startedGeneration = generation
        inFlight[key] = InFlightRequest(id: id, task: task)
        do {
            let transfer = try await task.value
            finishInFlightRequest(for: key, id: id)
            await store(transfer, for: key, generation: startedGeneration)
            return transfer
        } catch {
            finishInFlightRequest(for: key, id: id)
            throw error
        }
    }

    private func refreshInBackground(
        key: Key,
        request: URLRequest,
        upstream: any HTTPClient
    ) {
        let startedGeneration = generation
        let id = UUID()
        let task = Task {
            let (data, response) = try await upstream.data(for: request)
            return Transfer(data: data, response: response)
        }
        inFlight[key] = InFlightRequest(id: id, task: task)
        Task { [weak self] in
            do {
                let transfer = try await task.value
                await self?.finishBackgroundRefresh(transfer, for: key, id: id, generation: startedGeneration)
            } catch {
                await self?.finishBackgroundRefresh(nil, for: key, id: id, generation: startedGeneration)
            }
        }
    }

    private func finishBackgroundRefresh(
        _ transfer: Transfer?,
        for key: Key,
        id: UUID,
        generation startedGeneration: Int
    ) async {
        finishInFlightRequest(for: key, id: id)
        if let transfer {
            await store(transfer, for: key, generation: startedGeneration)
        }
    }

    private func finishInFlightRequest(for key: Key, id: UUID) {
        guard inFlight[key]?.id == id else { return }
        inFlight[key] = nil
    }

    private func store(_ transfer: Transfer, for key: Key, generation startedGeneration: Int) async {
        guard startedGeneration == generation,
              (200...299).contains(transfer.response.statusCode),
              transfer.data.count <= maximumBytes else {
            return
        }
        if let existing = entries[key] {
            storedBytes -= existing.data.count
        }
        entries[key] = Entry(data: transfer.data, response: transfer.response, storedAt: now())
        storedBytes += transfer.data.count
        trimIfNeeded()
        let responseHeaders = Self.safePersistedHeaders(transfer.response)
        await diskStore?.save(
            HTTPResponseDiskRecord(
                data: transfer.data,
                responseURL: Self.safePersistedURL(key.url),
                statusCode: transfer.response.statusCode,
                headerFields: responseHeaders,
                storedAt: now()
            ),
            identifier: key.diskIdentifier
        )
    }

    private func restore(_ entry: Entry, for key: Key) {
        if let existing = entries[key] {
            storedBytes -= existing.data.count
        }
        entries[key] = entry
        storedBytes += entry.data.count
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        while storedBytes > maximumBytes,
              let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt })?.key {
            removeEntry(for: oldest)
        }
    }

    private func removeEntry(for key: Key) {
        if let entry = entries.removeValue(forKey: key) {
            storedBytes -= entry.data.count
        }
    }

    private static func isCacheable(_ request: URLRequest) -> Bool {
        (request.httpMethod ?? "GET").uppercased() == "GET" && request.httpBody == nil
    }

    private static func safePersistedHeaders(_ response: HTTPURLResponse) -> [String: String] {
        let allowed = Set(["content-type", "content-language"])
        return response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            let name = String(describing: item.key)
            guard allowed.contains(name.lowercased()) else { return }
            result[name] = String(describing: item.value)
        }
    }

    private static func safePersistedURL(_ value: String) -> String {
        guard var components = URLComponents(string: value) else { return "" }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString ?? ""
    }

    private static func key(for request: URLRequest, namespace: String) -> Key {
        let volatileSignatureHeaders: Set<String> = [
            "x-api-timestamp",
            "x-api-nonce",
            "x-api-content-sha256",
            "x-api-signature"
        ]
        let headers = (request.allHTTPHeaderFields ?? [:])
            .compactMap { name, value -> String? in
                let normalizedName = name.lowercased()
                guard !volatileSignatureHeaders.contains(normalizedName) else { return nil }
                return "\(normalizedName):\(value)"
            }
            .sorted()
        return Key(
            namespace: namespace,
            method: (request.httpMethod ?? "GET").uppercased(),
            url: request.url?.absoluteString ?? "",
            headers: headers
        )
    }
}

public enum APIRequestNetworkPolicy: Sendable {
    case online
    case cacheOnly
}

public struct NetworkPolicyHTTPClient: HTTPClient {
    public let upstream: any HTTPClient
    public let policy: APIRequestNetworkPolicy

    public init(upstream: any HTTPClient, policy: APIRequestNetworkPolicy) {
        self.upstream = upstream
        self.policy = policy
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard policy == .cacheOnly,
              (request.httpMethod ?? "GET").uppercased() == "GET",
              request.httpBody == nil
        else {
            return try await upstream.data(for: request)
        }
        var cacheOnlyRequest = request
        cacheOnlyRequest.cachePolicy = .returnCacheDataDontLoad
        return try await upstream.data(for: cacheOnlyRequest)
    }
}

public struct CachedHTTPClient: HTTPClient {
    public let upstream: any HTTPClient
    public let cache: HTTPResponseCache
    public let namespace: String

    public init(
        upstream: any HTTPClient,
        cache: HTTPResponseCache = .shared,
        namespace: String = "teslamate"
    ) {
        self.upstream = upstream
        self.cache = cache
        self.namespace = namespace
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await cache.data(for: request, namespace: namespace, upstream: upstream)
    }
}
