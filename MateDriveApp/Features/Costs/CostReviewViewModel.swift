import Combine
import Foundation

public enum CostReviewRange: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365

    public var id: Int { rawValue }

    public func dateWindow(containing date: Date) -> (startDate: Date, endDate: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let startOfToday = calendar.startOfDay(for: date)
        let endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let startDate = calendar.date(byAdding: .day, value: -rawValue, to: endDate)
            ?? endDate.addingTimeInterval(-Double(rawValue) * 24 * 60 * 60)
        return (startDate, endDate)
    }
}

public struct CostReviewState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var hasLoadedData = false
    public var errorMessage: String?
    public var response: CostReviewResponse?
    public var range: CostReviewRange = .thirtyDays

    public init() {}
}

public struct CostReviewPageSnapshot: Sendable {
    public var state: CostReviewState
    public var responsesByRange: [CostReviewRange: CostReviewResponse]

    public init(
        state: CostReviewState,
        responsesByRange: [CostReviewRange: CostReviewResponse]
    ) {
        self.state = state
        self.responsesByRange = responsesByRange
    }
}

@MainActor
public final class CostReviewViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<CostReviewPageSnapshot>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: CostReviewState

    private let api: any CostReviewAPIProviding
    private let now: @Sendable () -> Date
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<CostReviewPageSnapshot>
    private var responsesByRange: [CostReviewRange: CostReviewResponse]
    private var carId: Int?

    public init(
        api: any CostReviewAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<CostReviewPageSnapshot>? = nil,
        initialState: CostReviewState = CostReviewState(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let restored = cacheKey.flatMap { resolvedStateCache.state(for: $0) }
        self.api = api
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = restored?.state ?? initialState
        self.responsesByRange = restored?.responsesByRange ?? [:]
        self.now = now
    }

    public var missingCostCount: Int {
        guard let quality = state.response?.data.dataQuality else { return 0 }
        return (quality.chargingCost.missingCostCount ?? 0) + (quality.parkingCost.missingCostCount ?? 0)
    }

    public var hasCompleteRecordedSpend: Bool {
        guard let quality = state.response?.data.dataQuality,
              quality.hasAnyActivity == true else { return false }
        return (quality.chargingCost.missingCostCount ?? 0) == 0
            && (quality.parkingCost.missingCostCount ?? 0) == 0
    }

    public func select(_ range: CostReviewRange, carId: Int) async {
        guard state.range != range, !state.isRefreshing else { return }
        if let cached = responsesByRange[range] {
            state.range = range
            state.response = cached
            state.hasLoadedData = true
            saveCachedState()
        }
        await load(carId: carId, requestedRange: range)
    }

    public func load(carId: Int) async {
        await load(carId: carId, requestedRange: state.range)
    }

    public func refresh() async {
        guard let carId else { return }
        await load(carId: carId, requestedRange: state.range)
    }

    private func load(carId: Int, requestedRange: CostReviewRange) async {
        guard !state.isRefreshing else { return }
        self.carId = carId
        let previousRange = state.range
        let previousResponse = state.response
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        let window = requestedRange.dateWindow(containing: now())

        switch await api.costReview(carId: carId, startDate: window.startDate, endDate: window.endDate) {
        case let .success(response):
            responsesByRange[requestedRange] = response
            state.range = requestedRange
            state.response = response
            state.hasLoadedData = true
            saveCachedState()
        case let .failure(error):
            if let cached = responsesByRange[requestedRange] {
                state.range = requestedRange
                state.response = cached
                state.hasLoadedData = true
            } else {
                state.range = previousRange
                state.response = previousResponse
            }
            state.errorMessage = error.analyticsMessage
        }
    }

    private func saveCachedState() {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(
            CostReviewPageSnapshot(
                state: snapshot,
                responsesByRange: responsesByRange
            ),
            for: cacheKey
        )
    }
}

public enum CostReviewPresentation {
    public static func money(_ value: Double?, currencySymbol: String) -> String {
        value.map { currencySymbol + String(format: "%.2f", $0) } ?? "--"
    }

    public static func moneyDelta(_ value: Double, currencySymbol: String) -> String {
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        return sign + money(abs(value), currencySymbol: currencySymbol)
    }

    public static func coverage(recorded: Int, total: Int, language: AppLanguage) -> String {
        MateDriveUnitFormatter.usesChineseLabels(language: language)
            ? "已记录 \(recorded)/\(total) 条"
            : "Recorded \(recorded)/\(total)"
    }

    public static func rangeTitle(_ range: CostReviewRange, language: AppLanguage) -> String {
        let chinese = MateDriveUnitFormatter.usesChineseLabels(language: language)
        if range == .oneYear {
            return chinese ? "1 年" : "1 year"
        }
        return chinese ? "\(range.rawValue) 天" : "\(range.rawValue) days"
    }
}
