import Combine
import Foundation

public struct SentryAlertRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let detectedAt: Date
    public let locationText: String

    public init(id: String, detectedAt: Date, locationText: String) {
        self.id = id
        self.detectedAt = detectedAt
        self.locationText = locationText
    }
}

public struct SentryDayGroup: Equatable, Identifiable, Sendable {
    public let id: Int64
    public let date: Date
    public let alerts: [SentryAlertRow]

    public init(id: Int64, date: Date, alerts: [SentryAlertRow]) {
        self.id = id
        self.date = date
        self.alerts = alerts
    }
}

public enum SentryHeatmap {
    public static let blocks = 72
    public static let rows = 6
    public static let bucketHours = 2
}

public struct SentryHistoryState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var hasLoadedData: Bool
    public var isSessionActive: Bool
    public var sessionStartedAt: Date?
    public var currentSessionAlerts: [SentryAlertRow]
    public var pastAlertsByDay: [SentryDayGroup]
    public var heatmapCounts: [Int]
    public var heatmapStart: Date?
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        hasLoadedData: Bool = false,
        isSessionActive: Bool = false,
        sessionStartedAt: Date? = nil,
        currentSessionAlerts: [SentryAlertRow] = [],
        pastAlertsByDay: [SentryDayGroup] = [],
        heatmapCounts: [Int] = Array(repeating: 0, count: SentryHeatmap.blocks),
        heatmapStart: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.hasLoadedData = hasLoadedData
        self.isSessionActive = isSessionActive
        self.sessionStartedAt = sessionStartedAt
        self.currentSessionAlerts = currentSessionAlerts
        self.pastAlertsByDay = pastAlertsByDay
        self.heatmapCounts = heatmapCounts
        self.heatmapStart = heatmapStart
        self.errorMessage = errorMessage
    }
}

@MainActor
public final class SentryHistoryViewModel: ObservableObject {
    nonisolated public static let heatmapBlocks = SentryHeatmap.blocks
    nonisolated public static let heatmapRows = SentryHeatmap.rows
    nonisolated public static let heatmapBucketHours = SentryHeatmap.bucketHours
    private static let hourMillis: Int64 = 3_600_000
    private static let bucketMillis: Int64 = Int64(heatmapBucketHours) * hourMillis
    private static let sharedStateCache = VehiclePageStateCache<SentryHistoryState>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: SentryHistoryState

    private let store: any SentryAlertLogStoring
    private let calendar: Calendar
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<SentryHistoryState>
    private var carId: Int?

    public init(
        store: any SentryAlertLogStoring,
        calendar: Calendar = Calendar(identifier: .gregorian),
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<SentryHistoryState>? = nil,
        initialState: SentryHistoryState = SentryHistoryState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.store = store
        self.calendar = calendar
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int, now: Date = Date()) async {
        guard !state.isRefreshing else { return }
        self.carId = carId
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        do {
            let alerts = try await store.alertLogs(carId: carId)
            let activeSession = try await store.activeSessionStartedAt(carId: carId)
            let rows = alerts.map(Self.row(from:))
            let currentSession = activeSession.map { session in
                rowsForSession(session, alerts: alerts, rows: rows)
            } ?? []
            let pastRows = activeSession.map { session in
                rows.enumerated().compactMap { index, row in
                    alerts[index].sessionStartedAtMillis == session ? nil : row
                }
            } ?? rows
            let heatmap = heatmap(alerts: alerts, now: now)

            state.isSessionActive = activeSession != nil
            state.sessionStartedAt = activeSession.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
            state.currentSessionAlerts = currentSession
            state.pastAlertsByDay = groupByDay(pastRows)
            state.heatmapCounts = heatmap.counts
            state.heatmapStart = heatmap.start
            state.hasLoadedData = true
            saveCachedState()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    public func refresh(now: Date = Date()) async {
        guard let carId else { return }
        await load(carId: carId, now: now)
    }

    private func rowsForSession(_ session: Int64, alerts: [SentryAlertLogRecord], rows: [SentryAlertRow]) -> [SentryAlertRow] {
        rows.enumerated().compactMap { index, row in
            alerts[index].sessionStartedAtMillis == session ? row : nil
        }
    }

    private func groupByDay(_ rows: [SentryAlertRow]) -> [SentryDayGroup] {
        let grouped = Dictionary(grouping: rows) { row -> Int64 in
            let start = calendar.startOfDay(for: row.detectedAt)
            return Int64(start.timeIntervalSince1970 * 1000)
        }
        return grouped.map { key, rows in
            SentryDayGroup(
                id: key,
                date: Date(timeIntervalSince1970: Double(key) / 1000.0),
                alerts: rows.sorted { $0.detectedAt > $1.detectedAt }
            )
        }
        .sorted { $0.date > $1.date }
    }

    private func heatmap(
        alerts: [SentryAlertLogRecord],
        now: Date
    ) -> (counts: [Int], start: Date) {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(Self.heatmapRows - 1), to: today) else {
            return (Array(repeating: 0, count: Self.heatmapBlocks), today)
        }
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        var counts = Array(repeating: 0, count: Self.heatmapBlocks)
        for alert in alerts where alert.detectedAtMillis >= startMillis {
            let index = Int((alert.detectedAtMillis - startMillis) / Self.bucketMillis)
            if counts.indices.contains(index) {
                counts[index] += 1
            }
        }
        return (counts, start)
    }

    private func saveCachedState() {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }

    private static func row(from record: SentryAlertLogRecord) -> SentryAlertRow {
        let location: String
        if let address = record.address, !address.isEmpty {
            location = address
        } else if let latitude = record.latitude, let longitude = record.longitude {
            location = String(format: "%.4f, %.4f", latitude, longitude)
        } else {
            location = "Unknown location"
        }
        return SentryAlertRow(
            id: record.id,
            detectedAt: Date(timeIntervalSince1970: Double(record.detectedAtMillis) / 1000.0),
            locationText: location
        )
    }
}
