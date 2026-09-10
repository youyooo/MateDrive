import Foundation

public struct WeatherPoint: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let temperatureCelsius: Double
    public let weatherCode: Int
    public let windSpeedKph: Double?
    public let windDirectionDegrees: Double?
    public let precipitationMillimeters: Double?
    public let visibilityMeters: Double?

    public init(
        latitude: Double,
        longitude: Double,
        temperatureCelsius: Double,
        weatherCode: Int,
        windSpeedKph: Double? = nil,
        windDirectionDegrees: Double? = nil,
        precipitationMillimeters: Double? = nil,
        visibilityMeters: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.temperatureCelsius = temperatureCelsius
        self.weatherCode = weatherCode
        self.windSpeedKph = windSpeedKph
        self.windDirectionDegrees = windDirectionDegrees
        self.precipitationMillimeters = precipitationMillimeters
        self.visibilityMeters = visibilityMeters
    }
}

public protocol WeatherAPIProviding: Sendable {
    func weather(latitude: Double, longitude: Double, date: String?) async -> APIResult<WeatherPoint>
}

public struct WeatherCacheKey: Codable, Hashable, Sendable {
    private let latitudeTenThousandths: Int
    private let longitudeTenThousandths: Int
    private let epochHour: Int64

    public init?(latitude: Double, longitude: Double, date: String?) {
        guard GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil,
              let date,
              let parsedDate = DomainDateParser.date(from: date)
        else {
            return nil
        }
        latitudeTenThousandths = Int((latitude * 10_000).rounded())
        longitudeTenThousandths = Int((longitude * 10_000).rounded())
        epochHour = Int64(floor(parsedDate.timeIntervalSince1970 / 3_600))
    }
}

public protocol WeatherCaching: Sendable {
    func load(_ key: WeatherCacheKey) async -> WeatherPoint?
    func save(_ point: WeatherPoint, for key: WeatherCacheKey) async
}

public actor WeatherCache: WeatherCaching {
    public static let shared = WeatherCache(storageURL: liveStorageURL)

    private struct StoredEntry: Codable {
        let key: WeatherCacheKey
        let point: WeatherPoint
        let savedAt: Date
    }

    private let storageURL: URL?
    private let maximumEntryCount: Int
    private var entries: [WeatherCacheKey: StoredEntry] = [:]
    private var restoredFromDisk = false

    public init(storageURL: URL?, maximumEntryCount: Int = 2_048) {
        self.storageURL = storageURL
        self.maximumEntryCount = max(maximumEntryCount, 1)
    }

    public func load(_ key: WeatherCacheKey) -> WeatherPoint? {
        restoreFromDiskIfNeeded()
        return entries[key]?.point
    }

    public func save(_ point: WeatherPoint, for key: WeatherCacheKey) {
        restoreFromDiskIfNeeded()
        entries[key] = StoredEntry(key: key, point: point, savedAt: Date())
        trimIfNeeded()
        persist()
    }

    public func removeAll() {
        entries.removeAll()
        restoredFromDisk = true
        guard let storageURL else { return }
        try? FileManager.default.removeItem(at: storageURL)
    }

    public func releaseMemory() {
        entries.removeAll()
        restoredFromDisk = false
    }

    private func restoreFromDiskIfNeeded() {
        guard !restoredFromDisk else { return }
        restoredFromDisk = true
        guard let storageURL,
              let data = try? Data(contentsOf: storageURL),
              let storedEntries = try? JSONDecoder().decode([StoredEntry].self, from: data)
        else {
            return
        }
        entries = Dictionary(
            storedEntries.map { ($0.key, $0) },
            uniquingKeysWith: { current, candidate in
                candidate.savedAt > current.savedAt ? candidate : current
            }
        )
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        guard entries.count > maximumEntryCount else { return }
        let oldestKeys = entries.values
            .sorted { $0.savedAt < $1.savedAt }
            .prefix(entries.count - maximumEntryCount)
            .map(\.key)
        for key in oldestKeys {
            entries.removeValue(forKey: key)
        }
    }

    private func persist() {
        guard let storageURL,
              let data = try? JSONEncoder().encode(entries.values.sorted { $0.savedAt < $1.savedAt })
        else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: storageURL.path
            )
        } catch {
            return
        }
    }

    private static var liveStorageURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MateDrive", isDirectory: true)
            .appendingPathComponent("historical-weather-cache-v1.json", isDirectory: false)
    }
}

public actor WeatherService {
    private let api: any WeatherAPIProviding
    private let cache: any WeatherCaching
    private var inFlight: [WeatherCacheKey: Task<WeatherPoint?, Never>] = [:]

    public init(
        api: any WeatherAPIProviding,
        cache: any WeatherCaching = WeatherCache.shared
    ) {
        self.api = api
        self.cache = cache
    }

    public func drivingEnvironment(positions: [WeatherRoutePosition]) async -> WeatherPoint? {
        guard let selected = WeatherSelection.driveEnvironmentPosition(positions: positions),
              let latitude = selected.latitude,
              let longitude = selected.longitude,
              let key = WeatherCacheKey(latitude: latitude, longitude: longitude, date: selected.date)
        else {
            return nil
        }

        if let cached = await cache.load(key) {
            return cached
        }
        if let existing = inFlight[key] {
            return await existing.value
        }

        let api = self.api
        let date = selected.date
        let request = Task<WeatherPoint?, Never> {
            switch await api.weather(latitude: latitude, longitude: longitude, date: date) {
            case let .success(point):
                return point
            case .failure:
                return nil
            }
        }
        inFlight[key] = request
        let point = await request.value
        inFlight[key] = nil
        if let point {
            await cache.save(point, for: key)
        }
        return point
    }

    public func weatherAlongDrive(
        positions: [WeatherRoutePosition],
        totalDistanceKm _: Double
    ) async -> [WeatherPoint] {
        guard let point = await drivingEnvironment(positions: positions) else { return [] }
        return [point]
    }
}
