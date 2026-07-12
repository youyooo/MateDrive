import Combine
import Foundation

public struct SoftwareUpdateItem: Equatable, Identifiable, Sendable {
    public let id: Int
    public let version: String
    public let installDate: Date?
    public let endDate: Date?
    public let updateDurationMinutes: Int?
    public let daysInstalled: Int?
    public let isCurrent: Bool
}

public struct UpdatesStats: Equatable, Sendable {
    public let totalUpdates: Int
    public let meanDaysBetweenUpdates: Double
    public let oldestVersion: String?
    public let newestVersion: String?

    public static let empty = UpdatesStats(totalUpdates: 0, meanDaysBetweenUpdates: 0, oldestVersion: nil, newestVersion: nil)
}

public struct MonthlyUpdateCount: Equatable, Identifiable, Sendable {
    public var id: String { month }
    public let month: String
    public let count: Int
}

public struct SoftwareUpdatesState: Equatable, Sendable {
    public var isLoading: Bool
    public var updates: [SoftwareUpdateItem]
    public var stats: UpdatesStats
    public var monthlyData: [MonthlyUpdateCount]
    public var longestInstalledId: Int?
    public var filterMonths: Int?
    public var errorMessage: String?

    public init(isLoading: Bool = true, updates: [SoftwareUpdateItem] = [], stats: UpdatesStats = .empty, monthlyData: [MonthlyUpdateCount] = [], longestInstalledId: Int? = nil, filterMonths: Int? = nil, errorMessage: String? = nil) {
        self.isLoading = isLoading
        self.updates = updates
        self.stats = stats
        self.monthlyData = monthlyData
        self.longestInstalledId = longestInstalledId
        self.filterMonths = filterMonths
        self.errorMessage = errorMessage
    }
}

@MainActor
public final class SoftwareUpdatesViewModel: ObservableObject {
    @Published public private(set) var state: SoftwareUpdatesState

    private let api: any AnalyticsAPIProviding
    private var allUpdates: [UpdateData] = []
    private var carId: Int?

    public init(api: any AnalyticsAPIProviding, initialState: SoftwareUpdatesState = SoftwareUpdatesState()) {
        self.api = api
        self.state = initialState
    }

    public func load(carId: Int) async {
        self.carId = carId
        state.isLoading = true
        state.errorMessage = nil
        switch await api.updates(carId: carId, page: 1, show: 50_000) {
        case let .success(updates):
            allUpdates = updates
            applyFilter()
            state.isLoading = false
        case let .failure(error):
            state.isLoading = false
            state.errorMessage = error.analyticsMessage
        }
    }

    public func setFilter(months: Int?) {
        state.filterMonths = months
        applyFilter()
    }

    private func applyFilter(now: Date = Date()) {
        let cutoff = state.filterMonths.flatMap {
            Calendar.current.date(byAdding: .month, value: -$0, to: now)
        }
        let filtered = allUpdates.filter { update in
            guard let cutoff else { return true }
            guard let date = update.startDate.flatMap(DomainDateParser.date(from:)) else { return true }
            return date >= cutoff
        }
        let items = filtered.enumerated().map { index, update -> SoftwareUpdateItem in
            let start = update.startDate.flatMap(DomainDateParser.date(from:))
            let end = update.endDate.flatMap(DomainDateParser.date(from:))
            let isCurrent = index == 0 && (end == nil || start == end)
            let durationMin: Int?
            if let start, let end, start != end {
                durationMin = max(Int(end.timeIntervalSince(start) / 60), 0)
            } else {
                durationMin = nil
            }
            let daysInstalled: Int?
            if let start {
                if isCurrent {
                    daysInstalled = max(Int(now.timeIntervalSince(start) / 86_400), 0)
                } else if index > 0, let newerStart = filtered[index - 1].startDate.flatMap(DomainDateParser.date(from:)) {
                    daysInstalled = max(Int(newerStart.timeIntervalSince(start) / 86_400), 0)
                } else {
                    daysInstalled = nil
                }
            } else {
                daysInstalled = nil
            }
            return SoftwareUpdateItem(
                id: update.updateId ?? index,
                version: Self.cleanVersion(update.version),
                installDate: start,
                endDate: end,
                updateDurationMinutes: durationMin,
                daysInstalled: daysInstalled,
                isCurrent: isCurrent
            )
        }

        state.updates = items
        state.stats = Self.stats(for: items)
        state.monthlyData = Self.monthlyData(for: items, monthLimit: state.filterMonths ?? 24, now: now)
        let installedItems = items.filter { item in
            (item.daysInstalled ?? 0) > 0
        }
        let longestInstalled = installedItems.max { lhs, rhs in
            (lhs.daysInstalled ?? 0) < (rhs.daysInstalled ?? 0)
        }
        state.longestInstalledId = longestInstalled?.id
    }

    private static func cleanVersion(_ value: String?) -> String {
        value?.split(separator: " ").first.map(String.init) ?? "Unknown"
    }

    private static func stats(for items: [SoftwareUpdateItem]) -> UpdatesStats {
        guard !items.isEmpty else {
            return .empty
        }
        let dates = items.compactMap(\.installDate).sorted(by: >)
        let mean = dates.count >= 2
            ? zip(dates, dates.dropFirst()).map { newer, older in newer.timeIntervalSince(older) / 86_400 }.reduce(0, +) / Double(dates.count - 1)
            : 0
        return UpdatesStats(
            totalUpdates: items.count,
            meanDaysBetweenUpdates: mean,
            oldestVersion: items.last?.version,
            newestVersion: items.first?.version
        )
    }

    private static func monthlyData(for items: [SoftwareUpdateItem], monthLimit: Int, now: Date) -> [MonthlyUpdateCount] {
        let calendar = Calendar(identifier: .gregorian)
        let grouped = Dictionary(grouping: items.compactMap(\.installDate)) { date -> String in
            let components = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        }
        let current = calendar.dateComponents([.year, .month], from: now)
        guard let currentDate = calendar.date(from: DateComponents(year: current.year, month: current.month, day: 1)) else {
            return []
        }
        return (0..<max(monthLimit, 1)).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset - max(monthLimit, 1) + 1, to: currentDate) else {
                return nil
            }
            let components = calendar.dateComponents([.year, .month], from: month)
            let key = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            return MonthlyUpdateCount(month: key, count: grouped[key]?.count ?? 0)
        }
    }
}
