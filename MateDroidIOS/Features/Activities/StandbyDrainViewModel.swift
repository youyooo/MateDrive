import Combine
import Foundation

public struct StandbyDrainState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var data: StandbyDrainData?
    public var units: StandbyDrainUnits?

    public init() {}
}

@MainActor
public final class StandbyDrainViewModel: ObservableObject {
    @Published public private(set) var state = StandbyDrainState()

    private let api: any ActivityAPIProviding

    public init(api: any ActivityAPIProviding) {
        self.api = api
    }

    public func load(carId: Int, latitude: Double, longitude: Double) async {
        state.isLoading = true
        state.errorMessage = nil
        switch await api.standbyDrain(carId: carId, latitude: latitude, longitude: longitude) {
        case let .success(response):
            state.data = response.data
            state.units = response.units
            if response.data == nil {
                state.errorMessage = response.error
            }
        case let .failure(error):
            state.data = nil
            state.errorMessage = error.analyticsMessage
        }
        state.isLoading = false
    }
}
