import Combine
import Foundation

public enum EnvironmentHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case ninetyDays = "90d"
    case oneYear = "1y"
    public var id: String { rawValue }
    public var grain: String { self == .sevenDays ? "hour" : "day" }
}

public struct EnvironmentHistoryState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var response: EnvironmentHistoryResponse?
    public var range: EnvironmentHistoryRange = .thirtyDays
    public init() {}
}

@MainActor
public final class EnvironmentHistoryViewModel: ObservableObject {
    @Published public private(set) var state: EnvironmentHistoryState
    private let api: any EnvironmentHistoryAPIProviding

    public init(api: any EnvironmentHistoryAPIProviding, initialState: EnvironmentHistoryState = EnvironmentHistoryState()) {
        self.api = api
        state = initialState
    }

    public var datedPoints: [EnvironmentHistoryPoint] {
        (state.response?.data.series ?? []).filter { $0.timestamp != nil }.sorted { $0.timestamp! < $1.timestamp! }
    }

    public func select(_ range: EnvironmentHistoryRange, carId: Int) async {
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
        let result = await api.environmentHistory(carId: carId, range: state.range.rawValue, grain: state.range.grain)
        switch result {
        case let .success(response):
            state.response = response
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
    }
}
