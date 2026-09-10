import Combine
import Foundation

public protocol EnergyCycleDataProviding: Sendable {
    func dataSet(carId: Int) async throws -> EnergyCycleDataSet
}

public struct DatabaseBackedEnergyCycleDataProvider: EnergyCycleDataProviding {
    private let databaseProvider: any AppDatabaseProviding

    public init(databaseProvider: any AppDatabaseProviding) {
        self.databaseProvider = databaseProvider
    }

    public func dataSet(carId: Int) async throws -> EnergyCycleDataSet {
        let database = try await databaseProvider.database()
        async let charges = ChargeSummaryStore(database: database).records(carId: carId)
        async let drives = DriveSummaryStore(database: database).records(carId: carId)
        let records = try await (charges, drives)
        return EnergyCycleDataSet(charges: records.0, drives: records.1)
    }
}

public struct EnergyCyclesState: Equatable, Sendable {
    public var isLoading: Bool
    public var selectedPeriod: EnergyCyclePeriod
    public var analysis: EnergyCycleAnalysis?
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        selectedPeriod: EnergyCyclePeriod = .today,
        analysis: EnergyCycleAnalysis? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.selectedPeriod = selectedPeriod
        self.analysis = analysis
        self.errorMessage = errorMessage
    }
}

@MainActor
public final class EnergyCyclesViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<EnergyCyclesState>()

    @Published public private(set) var state: EnergyCyclesState

    private let provider: any EnergyCycleDataProviding
    private let referenceDate: Date?
    private let calendar: Calendar
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<EnergyCyclesState>
    private var dataSet = EnergyCycleDataSet.empty
    private var carId: Int?
    private var isRefreshing = false

    public init(
        provider: any EnergyCycleDataProviding,
        referenceDate: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<EnergyCyclesState>? = nil,
        initialState: EnergyCyclesState = EnergyCyclesState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.provider = provider
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        self.carId = carId
        state.isLoading = state.analysis == nil
        state.errorMessage = nil
        do {
            dataSet = try await provider.dataSet(carId: carId)
            await recalculate()
        } catch {
            state.isLoading = false
            state.errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        guard let carId else { return }
        await load(carId: carId)
    }

    public func selectPeriod(_ period: EnergyCyclePeriod) {
        guard state.selectedPeriod != period else { return }
        state.selectedPeriod = period
        Task { await recalculate() }
    }

    private func recalculate() async {
        let dataSet = dataSet
        let period = state.selectedPeriod
        let now = referenceDate ?? Date()
        let calendar = calendar
        let analysis = await Task.detached(priority: .userInitiated) {
            EnergyCycleAnalyzer.analyze(
                dataSet: dataSet,
                period: period,
                now: now,
                calendar: calendar
            )
        }.value
        guard state.selectedPeriod == period else { return }
        state.analysis = analysis
        state.isLoading = false
        state.errorMessage = nil
        if let cacheKey {
            stateCache.save(state, for: cacheKey)
        }
    }
}
