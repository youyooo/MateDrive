import Combine
import Foundation

public enum DriveCompareSort: String, CaseIterable, Sendable {
    case efficiency = "Efficiency"
    case duration = "Duration"
    case speed = "Speed"
}

public struct ComparableDriveRow: Equatable, Identifiable, Sendable {
    public var id: Int { driveId }

    public let driveId: Int
    public let isBase: Bool
    public let startDate: String
    public let startAddress: String?
    public let endAddress: String?
    public let distance: Double?
    public let durationMin: Int?
    public let efficiency: Double?
    public let speedAvg: Double?
    public let outsideTempAvg: Double?
}

public struct DriveComparisonAverage: Equatable, Sendable {
    public let efficiency: Double?
    public let durationMin: Int?
    public let speedAvg: Double?
    public let count: Int

    public static let empty = DriveComparisonAverage(efficiency: nil, durationMin: nil, speedAvg: nil, count: 0)
}

public struct CompareDrivesState: Equatable, Sendable {
    public var isLoading: Bool
    public var rows: [ComparableDriveRow]
    public var average: DriveComparisonAverage
    public var sort: DriveCompareSort
    public var units: UnitPreferences?
    public var errorMessage: String?

    public init(
        isLoading: Bool = true,
        rows: [ComparableDriveRow] = [],
        average: DriveComparisonAverage = .empty,
        sort: DriveCompareSort = .efficiency,
        units: UnitPreferences? = nil,
        errorMessage: String? = nil
    ) {
        self.isLoading = isLoading
        self.rows = rows
        self.average = average
        self.sort = sort
        self.units = units
        self.errorMessage = errorMessage
    }
}

@MainActor
public final class CompareDrivesViewModel: ObservableObject {
    private static let distanceTolerance = 0.25

    @Published public private(set) var state: CompareDrivesState

    private let api: any DriveAPIProviding
    private var baseDriveId: Int?
    private var comparableRows: [ComparableDriveRow] = []

    public init(api: any DriveAPIProviding, initialState: CompareDrivesState = CompareDrivesState()) {
        self.api = api
        self.state = initialState
    }

    public func load(carId: Int, baseDriveId: Int) async {
        self.baseDriveId = baseDriveId
        state.isLoading = true
        state.errorMessage = nil

        async let baseResult = api.driveDetail(carId: carId, driveId: baseDriveId)
        async let drivesResult = api.drives(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000)
        async let statusResult = api.carStatus(carId: carId)

        if case let .success(payload) = await statusResult {
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
        }

        switch await (baseResult, drivesResult) {
        case let (.success(baseDetail), .success(drives)):
            let baseRow = Self.row(detail: baseDetail, isBase: true)
            let others = drives
                .filter { $0.driveId != baseDriveId }
                .filter { Self.isComparable($0, to: baseDetail) }
                .map { Self.row(data: $0, isBase: false) }
            comparableRows = others + [baseRow]
            rebuildRows()
            state.isLoading = false
        case let (.failure(error), _), let (_, .failure(error)):
            state.isLoading = false
            state.errorMessage = error.driveMessage
        }
    }

    public func setSort(_ sort: DriveCompareSort) {
        state.sort = sort
        rebuildRows()
    }

    private func rebuildRows() {
        state.rows = sorted(comparableRows)
        state.average = Self.average(for: comparableRows)
    }

    private func sorted(_ rows: [ComparableDriveRow]) -> [ComparableDriveRow] {
        switch state.sort {
        case .efficiency:
            return rows.sorted { ($0.efficiency ?? .greatestFiniteMagnitude) < ($1.efficiency ?? .greatestFiniteMagnitude) }
        case .duration:
            return rows.sorted { ($0.durationMin ?? .max) < ($1.durationMin ?? .max) }
        case .speed:
            return rows.sorted { ($0.speedAvg ?? -.greatestFiniteMagnitude) > ($1.speedAvg ?? -.greatestFiniteMagnitude) }
        }
    }

    private static func isComparable(_ drive: DriveData, to base: DriveDetail) -> Bool {
        let sameStart = normalized(drive.startAddress) == normalized(base.startAddress)
        let sameEnd = normalized(drive.endAddress) == normalized(base.endAddress)
        guard sameStart, sameEnd else {
            return false
        }

        let baseDistance = base.distance ?? 0
        guard baseDistance > 0 else {
            return true
        }
        let distance = drive.distance ?? 0
        return abs(distance - baseDistance) / baseDistance <= distanceTolerance
    }

    private static func normalized(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    }

    private static func row(detail: DriveDetail, isBase: Bool) -> ComparableDriveRow {
        let stats = DriveStatsCalculator.calculateStats(detail)
        return ComparableDriveRow(
            driveId: detail.driveId,
            isBase: isBase,
            startDate: detail.startDate ?? "",
            startAddress: detail.startAddress,
            endAddress: detail.endAddress,
            distance: stats.distance,
            durationMin: stats.durationMin,
            efficiency: stats.efficiency.flatMap { $0 > 0 ? $0 : nil },
            speedAvg: stats.speedAvg.flatMap { $0 > 0 ? $0 : nil } ?? stats.avgSpeedFromDistance,
            outsideTempAvg: detail.outsideTempAvg
        )
    }

    private static func row(data: DriveData, isBase: Bool) -> ComparableDriveRow {
        let distance = data.distance
        let durationMin = data.durationMin
        let calculatedSpeed: Double? = durationMin.flatMap { duration in
            guard duration > 0, let distance else { return nil }
            return distance / Double(duration) * 60
        }
        return ComparableDriveRow(
            driveId: data.driveId ?? -1,
            isBase: isBase,
            startDate: data.startDate ?? "",
            startAddress: data.startAddress,
            endAddress: data.endAddress,
            distance: distance,
            durationMin: durationMin,
            efficiency: data.efficiencyWhKm,
            speedAvg: data.speedAvg ?? data.averageSpeed ?? calculatedSpeed,
            outsideTempAvg: data.outsideTempAvg
        )
    }

    private static func average(for rows: [ComparableDriveRow]) -> DriveComparisonAverage {
        guard !rows.isEmpty else {
            return .empty
        }
        let efficiencies = rows.compactMap(\.efficiency)
        return DriveComparisonAverage(
            efficiency: efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count),
            durationMin: averageInt(rows.compactMap(\.durationMin)),
            speedAvg: averageDouble(rows.compactMap(\.speedAvg)),
            count: rows.count
        )
    }

    private static func averageInt(_ values: [Int]) -> Int? {
        values.isEmpty ? nil : values.reduce(0, +) / values.count
    }

    private static func averageDouble(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
