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

public struct DriveInsightsState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var routes: [DriveInsightRouteItem] = []
    public var evaluations: [DriveEvaluationItem] = []
    public var filter: DriveInsightFilter = .repeated
    public var units: UnitPreferences?
    public init() {}
}

@MainActor
public final class DriveInsightsViewModel: ObservableObject {
    @Published public private(set) var state: DriveInsightsState
    private let api: any DriveInsightsAPIProviding

    public init(api: any DriveInsightsAPIProviding, initialState: DriveInsightsState = DriveInsightsState()) {
        self.api = api
        state = initialState
    }

    public var visibleRoutes: [DriveInsightRouteItem] {
        switch state.filter {
        case .all: state.routes
        case .repeated: state.routes.filter { ($0.insight.driveCount ?? 0) >= 2 }
        }
    }

    public func setFilter(_ filter: DriveInsightFilter) { state.filter = filter }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        async let insightResult = api.driveInsights(carId: carId)
        async let driveResult = api.drives(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000)
        async let activityResult = api.activities(carId: carId, page: 1, show: 20)
        let (resolvedInsights, resolvedDrives, resolvedActivities) = await (insightResult, driveResult, activityResult)

        guard case let .success(data) = resolvedInsights else {
            if case let .failure(error) = resolvedInsights { state.errorMessage = error.analyticsMessage }
            state.isLoading = false
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
            state.evaluations = response.data
                .filter { $0.kind == .drive }
                .flatMap { activity in
                    (activity.stats?.evaluations ?? []).map {
                        DriveEvaluationItem(driveId: activity.id, date: activity.startDate, evaluation: $0)
                    }
                }
                .sorted { ($0.evaluation.priority ?? 0) > ($1.evaluation.priority ?? 0) }
        } else {
            state.evaluations = []
        }
        state.isLoading = false
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
