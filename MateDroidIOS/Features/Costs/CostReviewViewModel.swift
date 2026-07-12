import Combine
import Foundation

public enum CostReviewRange: Int, CaseIterable, Identifiable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30
    case ninetyDays = 90
    case oneYear = 365

    public var id: Int { rawValue }
}

public struct CostReviewState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var response: CostReviewResponse?
    public var range: CostReviewRange = .thirtyDays

    public init() {}
}

@MainActor
public final class CostReviewViewModel: ObservableObject {
    @Published public private(set) var state: CostReviewState

    private let api: any CostReviewAPIProviding
    private let now: @Sendable () -> Date

    public init(
        api: any CostReviewAPIProviding,
        initialState: CostReviewState = CostReviewState(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.state = initialState
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
        guard state.range != range else { return }
        let previousRange = state.range
        state.range = range
        await load(carId: carId)
        if state.errorMessage != nil, state.response != nil {
            state.range = previousRange
        }
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        let endDate = now()
        let startDate = endDate.addingTimeInterval(-Double(state.range.rawValue) * 24 * 60 * 60)

        switch await api.costReview(carId: carId, startDate: startDate, endDate: endDate) {
        case let .success(response):
            state.response = response
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
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
        MateDroidUnitFormatter.usesChineseLabels(language: language)
            ? "已记录 \(recorded)/\(total) 条"
            : "Recorded \(recorded)/\(total)"
    }

    public static func rangeTitle(_ range: CostReviewRange, language: AppLanguage) -> String {
        let chinese = MateDroidUnitFormatter.usesChineseLabels(language: language)
        if range == .oneYear {
            return chinese ? "1 年" : "1 year"
        }
        return chinese ? "\(range.rawValue) 天" : "\(range.rawValue) days"
    }
}
