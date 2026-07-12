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
    public var isSessionActive: Bool
    public var sessionStartedAt: Date?
    public var currentSessionAlerts: [SentryAlertRow]
    public var pastAlertsByDay: [SentryDayGroup]
    public var heatmapCounts: [Int]
    public var heatmapStart: Date?
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        isSessionActive: Bool = false,
        sessionStartedAt: Date? = nil,
        currentSessionAlerts: [SentryAlertRow] = [],
        pastAlertsByDay: [SentryDayGroup] = [],
        heatmapCounts: [Int] = Array(repeating: 0, count: SentryHeatmap.blocks),
        heatmapStart: Date? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
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

    @Published public private(set) var state: SentryHistoryState

    private let store: any SentryAlertLogStoring
    private let calendar: Calendar

    public init(
        store: any SentryAlertLogStoring,
        calendar: Calendar = Calendar(identifier: .gregorian),
        initialState: SentryHistoryState = SentryHistoryState()
    ) {
        self.store = store
        self.calendar = calendar
        self.state = initialState
    }

    public func load(carId: Int, now: Date = Date()) async {
        state.isLoading = true
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
            let heatmap = try await heatmap(carId: carId, now: now)

            state.isSessionActive = activeSession != nil
            state.sessionStartedAt = activeSession.map { Date(timeIntervalSince1970: Double($0) / 1000.0) }
            state.currentSessionAlerts = currentSession
            state.pastAlertsByDay = groupByDay(pastRows)
            state.heatmapCounts = heatmap.counts
            state.heatmapStart = heatmap.start
            state.isLoading = false
        } catch {
            state.errorMessage = error.localizedDescription
            state.isLoading = false
        }
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

    private func heatmap(carId: Int, now: Date) async throws -> (counts: [Int], start: Date) {
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(Self.heatmapRows - 1), to: today) else {
            return (Array(repeating: 0, count: Self.heatmapBlocks), today)
        }
        let startMillis = Int64(start.timeIntervalSince1970 * 1000)
        var counts = Array(repeating: 0, count: Self.heatmapBlocks)
        for hourly in try await store.hourlyCounts(carId: carId, sinceMillis: startMillis) {
            let alertMillis = hourly.hourBucket * Self.hourMillis
            let index = Int((alertMillis - startMillis) / Self.bucketMillis)
            if counts.indices.contains(index) {
                counts[index] += hourly.count
            }
        }
        return (counts, start)
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
