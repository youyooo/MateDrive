import Combine
import Foundation

public protocol CommuteRoutesAPIProviding: Sendable {
    func commuteRoutes(carId: Int) async -> APIResult<CommuteRoutesResponse>
}

extension TeslamateAPI: CommuteRoutesAPIProviding {}

public struct SettingsBackedCommuteRoutesAPI: CommuteRoutesAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }

    public func commuteRoutes(carId: Int) async -> APIResult<CommuteRoutesResponse> {
        await factory.request { await $0.commuteRoutes(carId: carId) }
    }
}

public struct CommuteRoutesState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var routes: [CommuteRoute] = []
    public var summary: CommuteRoutesSummary?
    public var units: TeslaMateServerStatsUnits?

    public init() {}
}

@MainActor
public final class CommuteRoutesViewModel: ObservableObject {
    @Published public private(set) var state: CommuteRoutesState
    private let api: any CommuteRoutesAPIProviding

    public init(api: any CommuteRoutesAPIProviding, initialState: CommuteRoutesState = CommuteRoutesState()) {
        self.api = api
        state = initialState
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        switch await api.commuteRoutes(carId: carId) {
        case let .success(response):
            state.routes = response.routes.sorted { ($0.tripCount ?? 0) > ($1.tripCount ?? 0) }
            state.summary = response.summary
            state.units = response.units
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
    }
}
