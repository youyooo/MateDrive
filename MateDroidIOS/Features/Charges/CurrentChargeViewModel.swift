import Combine
import Foundation

public struct CurrentChargeState: Equatable, Sendable {
    public var isLoading: Bool
    public var errorMessage: String?
    public var chargeDetail: ChargeDetail?
    public var units: UnitPreferences?
    public var stats: ChargeDetailStats?
    public var isDcCharge: Bool
    public var isNotCharging: Bool
    public var isChargeStarting: Bool
    public var timeToFullCharge: Double?
    public var chargeLimitSoc: Int?
    public var chronologicalPoints: [ChargePoint]
    public var isRefreshing: Bool
    public var lastUpdatedAt: Date?

    public init(
        isLoading: Bool = true,
        errorMessage: String? = nil,
        chargeDetail: ChargeDetail? = nil,
        units: UnitPreferences? = nil,
        stats: ChargeDetailStats? = nil,
        isDcCharge: Bool = false,
        isNotCharging: Bool = false,
        isChargeStarting: Bool = false,
        timeToFullCharge: Double? = nil,
        chargeLimitSoc: Int? = nil,
        chronologicalPoints: [ChargePoint] = [],
        isRefreshing: Bool = false,
        lastUpdatedAt: Date? = nil
    ) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.chargeDetail = chargeDetail
        self.units = units
        self.stats = stats
        self.isDcCharge = isDcCharge
        self.isNotCharging = isNotCharging
        self.isChargeStarting = isChargeStarting
        self.timeToFullCharge = timeToFullCharge
        self.chargeLimitSoc = chargeLimitSoc
        self.chronologicalPoints = chronologicalPoints
        self.isRefreshing = isRefreshing
        self.lastUpdatedAt = lastUpdatedAt
    }
}

@MainActor
public final class CurrentChargeViewModel: ObservableObject {
    @Published public private(set) var state: CurrentChargeState

    private let api: any ChargeAPIProviding
    private var requestIsRunning = false

    public init(api: any ChargeAPIProviding, initialState: CurrentChargeState = CurrentChargeState()) {
        self.api = api
        self.state = initialState
    }

    public func load(carId: Int) async {
        guard !requestIsRunning else { return }
        requestIsRunning = true
        state.isRefreshing = state.chargeDetail != nil
        defer {
            requestIsRunning = false
            state.isRefreshing = false
            state.lastUpdatedAt = Date()
        }
        if state.chargeDetail == nil {
            state.isLoading = true
        }
        state.errorMessage = nil

        let statusResult = await api.carStatus(carId: carId)
        let statusPayload: CarStatusPayload?
        switch statusResult {
        case let .success(payload):
            statusPayload = payload
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
            state.timeToFullCharge = payload.status?.chargingDetails?.timeToFullCharge
            state.chargeLimitSoc = payload.status?.chargeLimitSoc
        case .failure:
            statusPayload = nil
        }

        switch await api.currentCharge(carId: carId) {
        case let .success(.active(detail)):
            let chronological = Self.chronological(detail.chargePoints ?? [])
            let normalized = ChargeDetail(
                chargeId: detail.chargeId,
                startDate: detail.startDate,
                endDate: detail.endDate,
                address: detail.address,
                chargeEnergyAdded: detail.chargeEnergyAdded,
                chargeEnergyUsed: detail.chargeEnergyUsed,
                cost: detail.cost,
                durationMin: detail.durationMin,
                durationStr: detail.durationStr,
                batteryDetails: detail.batteryDetails,
                rangeIdeal: detail.rangeIdeal,
                rangeRated: detail.rangeRated,
                outsideTempAvg: detail.outsideTempAvg,
                odometer: detail.odometer,
                latitude: detail.latitude,
                longitude: detail.longitude,
                chargePoints: chronological,
                isCharging: detail.isCharging
            )
            state.chargeDetail = normalized
            state.stats = ChargeStatsCalculator.calculateStats(normalized)
            state.isDcCharge = statusPayload?.status?.isDcCharging ?? ChargeStatsCalculator.detectDcCharge(normalized)
            state.isNotCharging = normalized.isCharging == false
            state.isChargeStarting = false
            state.chronologicalPoints = normalized.chargePoints ?? []
            state.isLoading = false

        case .success(.noActiveCharge):
            state.chargeDetail = nil
            state.stats = nil
            state.isDcCharge = false
            state.chronologicalPoints = []
            if statusPayload?.status?.isCharging == true {
                state.isChargeStarting = true
                state.isNotCharging = false
            } else {
                state.isChargeStarting = false
                state.isNotCharging = true
                state.timeToFullCharge = nil
            }
            state.isLoading = false

        case let .failure(error):
            state.isLoading = false
            state.errorMessage = error.chargeMessage
        }
    }

    public static func chronological(_ points: [ChargePoint]) -> [ChargePoint] {
        let dated = points.compactMap { point -> (ChargePoint, Date)? in
            guard let date = point.date.flatMap(DomainDateParser.date(from:)) else { return nil }
            return (point, date)
        }
        guard dated.count == points.count, points.count > 1 else {
            return Array(points.reversed())
        }
        return dated.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
