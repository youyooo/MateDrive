import Combine
import Foundation

public enum DriveInsightFilter: Hashable, Sendable { case all, repeated }

public struct DriveInsightRouteItem: Equatable, Identifiable, Sendable {
    public var id: String { insight.id }
    public let insight: TeslaMateRouteInsight
    public let latestDriveId: Int?
}

public struct DriveEvaluationItem: Equatable, Identifiable, Sendable {
    public var id: String { "\(driveId)-\(evaluation.id)" }
    public let driveId: Int
    public let date: String?
    public let evaluation: TeslaMateDriveEvaluation
}

public enum DriveInsightScoreComponentKind: Hashable, Sendable {
    case safety
    case regeneration
}

public struct DriveInsightScoreComponent: Equatable, Sendable {
    public let kind: DriveInsightScoreComponentKind
    public let score: Int
    public let averageValue: Double
    public let observedDriveCount: Int
}

public enum DriveInsightRecommendation: Hashable, Sendable {
    case smootherBraking
    case increaseRegeneration
    case preconditionBattery
    case checkTirePressure
    case improveCoverage
    case keepSteady
}

public enum DriveInsightConfidenceLevel: Equatable, Sendable {
    case low
    case medium
    case high
}

public struct DriveInsightDrivingScore: Equatable, Sendable {
    public let overall: Int
    public let confidence: Int
    public let totalDriveCount: Int
    public let components: [DriveInsightScoreComponent]
    public let recommendations: [DriveInsightRecommendation]

    public var confidenceLevel: DriveInsightConfidenceLevel {
        confidence >= 75 ? .high : confidence >= 40 ? .medium : .low
    }
}

public struct DriveInsightsState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var errorMessage: String?
    public var routes: [DriveInsightRouteItem] = []
    public var evaluations: [DriveEvaluationItem] = []
    public var drivingScore: DriveInsightDrivingScore?
    public var filter: DriveInsightFilter = .repeated
    public var units: UnitPreferences?
    public init() {}
}

@MainActor
public final class DriveInsightsViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<DriveInsightsState>()

    @Published public private(set) var state: DriveInsightsState
    private let api: any DriveInsightsAPIProviding
    private let historyProvider: (any MileageDataProviding)?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<DriveInsightsState>

    public init(
        api: any DriveInsightsAPIProviding,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<DriveInsightsState>? = nil,
        initialState: DriveInsightsState = DriveInsightsState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public var visibleRoutes: [DriveInsightRouteItem] {
        switch state.filter {
        case .all: state.routes
        case .repeated: state.routes.filter { ($0.insight.driveCount ?? 0) >= 2 }
        }
    }

    public func setFilter(_ filter: DriveInsightFilter) {
        state.filter = filter
        saveCachedState()
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = !hasContent
        state.errorMessage = nil
        async let insightResult = api.driveInsights(carId: carId)
        async let driveResult = loadDrives(carId: carId)
        async let activityResult = api.activities(carId: carId, page: 1, show: 200)
        let (resolvedInsights, resolvedDrives, resolvedActivities) = await (insightResult, driveResult, activityResult)

        guard case let .success(data) = resolvedInsights else {
            if case let .failure(error) = resolvedInsights { state.errorMessage = error.analyticsMessage }
            state.isLoading = false
            state.isRefreshing = false
            return
        }
        let drives = (try? resolvedDrives.value) ?? []
        state.routes = data.driveStats
            .map { insight in DriveInsightRouteItem(insight: insight, latestDriveId: Self.matchDrive(insight.lastDriveDate, in: drives)) }
            .sorted { ($0.insight.driveCount ?? 0) > ($1.insight.driveCount ?? 0) }
        state.units = UnitPreferences(
            unitOfLength: data.units?.unitOfLength,
            unitOfTemperature: data.units?.unitOfTemperature,
            unitOfPressure: data.units?.unitOfPressure
        )
        if case let .success(response) = resolvedActivities {
            let driveActivities = response.data.filter { $0.kind == .drive }
            state.drivingScore = DriveInsightScoreCalculator.calculate(driveActivities)
            state.evaluations = driveActivities
                .flatMap { activity in
                    (activity.stats?.evaluations ?? []).map {
                        DriveEvaluationItem(driveId: activity.id, date: activity.startDate, evaluation: $0)
                    }
                }
                .sorted { ($0.evaluation.priority ?? 0) > ($1.evaluation.priority ?? 0) }
        } else {
            state.drivingScore = nil
            state.evaluations = []
        }
        state.isLoading = false
        state.isRefreshing = false
        saveCachedState()
    }

    private var hasContent: Bool {
        !state.routes.isEmpty || !state.evaluations.isEmpty || state.drivingScore != nil
    }

    private func saveCachedState() {
        guard let cacheKey else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }

    private func loadDrives(carId: Int) async -> APIResult<[DriveData]> {
        if let historyProvider {
            return await historyProvider.mileageDrives(carId: carId)
        }
        return await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private static func matchDrive(_ dateText: String?, in drives: [DriveData]) -> Int? {
        guard let target = dateText.flatMap(DomainDateParser.date(from:)) else { return nil }
        return drives.compactMap { drive -> (Int, TimeInterval)? in
            guard let id = drive.driveId,
                  let date = drive.startDate.flatMap(DomainDateParser.date(from:))
            else { return nil }
            return (id, abs(date.timeIntervalSince(target)))
        }
        .filter { $0.1 <= 1 }
        .min { $0.1 < $1.1 }?.0
    }
}

private enum DriveInsightScoreCalculator {
    private static let componentWeights: [DriveInsightScoreComponentKind: Double] = [
        .safety: 0.6,
        .regeneration: 0.4
    ]

    static func calculate(_ drives: [TeslaMateActivity]) -> DriveInsightDrivingScore? {
        guard !drives.isEmpty else { return nil }

        let brakingRates = drives.compactMap { validNonnegative($0.stats?.hardBrakingPer100Km) }
        let regenerationRates = drives.compactMap { normalizedPercentage($0.stats?.regenUtilization) }
        var components: [DriveInsightScoreComponent] = []

        if let average = average(brakingRates) {
            components.append(DriveInsightScoreComponent(
                kind: .safety,
                score: roundedScore(100 - average * 15),
                averageValue: average,
                observedDriveCount: brakingRates.count
            ))
        }
        if let average = average(regenerationRates) {
            components.append(DriveInsightScoreComponent(
                kind: .regeneration,
                score: roundedScore(average),
                averageValue: average,
                observedDriveCount: regenerationRates.count
            ))
        }
        guard !components.isEmpty else { return nil }

        let availableWeight = components.reduce(0.0) { $0 + (componentWeights[$1.kind] ?? 0) }
        let weightedScore = components.reduce(0.0) {
            $0 + Double($1.score) * (componentWeights[$1.kind] ?? 0)
        } / max(availableWeight, 0.001)
        let observedMetricCount = components.reduce(0) { $0 + $1.observedDriveCount }
        let coverage = Double(observedMetricCount) / Double(drives.count * 2)
        let sampleRatio = min(Double(drives.count) / 20, 1)
        let confidence = roundedScore((coverage * 0.7 + sampleRatio * 0.3) * 100)

        return DriveInsightDrivingScore(
            overall: roundedScore(weightedScore),
            confidence: confidence,
            totalDriveCount: drives.count,
            components: components,
            recommendations: recommendations(
                drives: drives,
                brakingRate: average(brakingRates),
                regenerationRate: average(regenerationRates),
                coverage: coverage
            )
        )
    }

    private static func recommendations(
        drives: [TeslaMateActivity],
        brakingRate: Double?,
        regenerationRate: Double?,
        coverage: Double
    ) -> [DriveInsightRecommendation] {
        var values: [DriveInsightRecommendation] = []
        if let brakingRate, brakingRate >= 1 { values.append(.smootherBraking) }
        if let regenerationRate, regenerationRate <= 70 { values.append(.increaseRegeneration) }

        let regenLimitedCount = drives.filter { $0.stats?.isRegenLimited == true }.count
        let hasColdLimitedDrive = drives.contains {
            $0.stats?.isRegenLimited == true && ($0.stats?.avgOutsideTemp).map { $0 < 10 } == true
        }
        if hasColdLimitedDrive,
           Double(regenLimitedCount) / Double(drives.count) >= 0.25 {
            values.append(.preconditionBattery)
        }
        if drives.compactMap({ validNonnegative($0.stats?.tirePressureGapBar) }).max().map({ $0 >= 0.25 }) == true {
            values.append(.checkTirePressure)
        }
        if coverage < 0.75 { values.append(.improveCoverage) }
        return values.isEmpty ? [.keepSteady] : values
    }

    private static func validNonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func normalizedPercentage(_ value: Double?) -> Double? {
        guard let value = validNonnegative(value) else { return nil }
        if value <= 1 { return value * 100 }
        guard value <= 100 else { return nil }
        return value
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func roundedScore(_ value: Double) -> Int {
        Int(min(max(value, 0), 100).rounded())
    }
}

private extension APIResult {
    var value: Value {
        get throws {
            switch self {
            case let .success(value): return value
            case let .failure(error): throw error
            }
        }
    }
}
