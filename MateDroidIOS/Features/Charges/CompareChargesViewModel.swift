import Combine
import Foundation

public enum CompareChargeSort: String, CaseIterable, Sendable {
    case peak = "Peak"
    case duration = "Duration"
    case cost = "Cost"

    public func title(language: AppLanguage) -> String {
        let chinese: String
        switch self {
        case .peak:
            chinese = "峰值"
        case .duration:
            chinese = "时长"
        case .cost:
            chinese = "费用"
        }
        return AppText.localized(rawValue, chinese, language: language)
    }
}

public struct ComparableChargeRow: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let isBase: Bool
    public let startDate: String?
    public let address: String?
    public let energyAdded: Double?
    public let totalCost: Double?
    public let peakKW: Int?
    public let durationMin: Int?
    public let costPerKwh: Double?
    public let batteryStart: Int?
    public let batteryEnd: Int?
    public let isDc: Bool
}

public struct SessionCurvePoint: Equatable, Sendable {
    public let soc: Double
    public let power: Double
}

public struct SessionCurve: Equatable, Identifiable, Sendable {
    public var id: Int { chargeId }

    public let chargeId: Int
    public let isBase: Bool
    public let points: [SessionCurvePoint]
}

public struct CompareChargesState: Equatable, Sendable {
    public var isLoading: Bool
    public var rows: [ComparableChargeRow]
    public var curves: [SessionCurve]
    public var sort: CompareChargeSort
    public var currencySymbol: String
    public var errorMessage: String?

    public init(isLoading: Bool = true, rows: [ComparableChargeRow] = [], curves: [SessionCurve] = [], sort: CompareChargeSort = .peak, currencySymbol: String = "€", errorMessage: String? = nil) {
        self.isLoading = isLoading
        self.rows = rows
        self.curves = curves
        self.sort = sort
        self.currencySymbol = currencySymbol
        self.errorMessage = errorMessage
    }

    public var baseRow: ComparableChargeRow? {
        rows.first { $0.isBase }
    }

    public var comparisonRows: [ComparableChargeRow] {
        rows.filter { !$0.isBase }
    }
}

@MainActor
public final class CompareChargesViewModel: ObservableObject {
    @Published public private(set) var state: CompareChargesState

    private let api: any ChargeAPIProviding
    private let costOverrideStore: any ChargeCostOverriding
    private let settingsStore: (any SettingsStoring)?
    private var carId: Int?
    private var baseChargeId: Int?
    private var details: [ChargeDetail] = []
    private var costOverrides: [Int: Double] = [:]
    private var pricingRules: [ChargePricingRule] = []

    public init(
        api: any ChargeAPIProviding,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        settingsStore: (any SettingsStoring)? = nil,
        initialState: CompareChargesState = CompareChargesState()
    ) {
        self.api = api
        self.costOverrideStore = costOverrideStore
        self.settingsStore = settingsStore
        self.state = initialState
    }

    public func load(carId: Int, baseChargeId: Int) async {
        self.carId = carId
        self.baseChargeId = baseChargeId
        state.isLoading = true
        state.errorMessage = nil
        state.currencySymbol = "€"
        pricingRules = []

        async let baseResult = api.chargeDetail(carId: carId, chargeId: baseChargeId)
        async let chargesResult = api.charges(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000)

        switch await (baseResult, chargesResult) {
        case let (.success(baseDetail), .success(charges)):
            guard baseDetail.chargeId == baseChargeId else {
                details = []
                state.isLoading = false
                state.rows = []
                state.curves = []
                state.errorMessage = "TeslaMate returned no charge data."
                return
            }

            do {
                costOverrides = try await costOverrideStore.costOverrides(carId: carId)
            } catch {
                costOverrides = [:]
            }
            if let settingsStore {
                let settings = await settingsStore.load()
                pricingRules = settings.chargePricingRules
                state.currencySymbol = MateDroidCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())
            }
            let nearbyIds = charges
                .compactMap(\.chargeId)
                .filter { $0 != baseChargeId }
                .prefix(4)
            var loaded = [baseDetail]
            for id in nearbyIds {
                if case let .success(detail) = await api.chargeDetail(carId: carId, chargeId: id) {
                    loaded.append(detail)
                }
            }
            details = loaded
            rebuildRows()
            if state.baseRow == nil {
                state.errorMessage = "TeslaMate returned no charge data."
            }
            state.isLoading = false

        case let (.failure(error), _), let (_, .failure(error)):
            state.isLoading = false
            state.errorMessage = error.chargeMessage
        }
    }

    public func setSort(_ sort: CompareChargeSort) {
        state.sort = sort
        rebuildRows()
    }

    private func rebuildRows() {
        guard let baseChargeId else {
            return
        }
        let rows = details.map { detail in
            let stats = ChargeStatsCalculator.calculateStats(detail)
            let isDc = ChargeStatsCalculator.detectDcCharge(detail)
                || ChargeStatsCalculator.isDcCharge(
                    chargeId: detail.chargeId,
                    energyAddedKwh: stats.energyAdded,
                    durationMin: stats.durationMin,
                    dcChargeIds: [],
                    processedChargeIds: []
                )
            let pricingEstimate = ChargePricingRuleEngine.estimateCost(
                for: ChargePricingInput(
                    startDate: detail.startDate,
                    endDate: detail.endDate,
                    address: detail.address,
                    latitude: detail.latitude,
                    longitude: detail.longitude,
                    energyAddedKWh: stats.energyAdded,
                    energySamples: (detail.chargePoints ?? []).map {
                        ChargePricingEnergySample(date: $0.date, cumulativeEnergyAddedKWh: $0.chargeEnergyAdded)
                    },
                    isDc: isDc
                ),
                rules: pricingRules
            )
            let effectiveCost = costOverrides[detail.chargeId] ?? pricingEstimate?.cost ?? detail.cost
            let costPerKwh: Double?
            if let cost = effectiveCost, let energyAdded = stats.energyAdded, energyAdded > 0 {
                costPerKwh = cost / energyAdded
            } else {
                costPerKwh = nil
            }
            return ComparableChargeRow(
                chargeId: detail.chargeId,
                isBase: detail.chargeId == baseChargeId,
                startDate: detail.startDate,
                address: detail.address,
                energyAdded: stats.energyAdded,
                totalCost: effectiveCost,
                peakKW: stats.powerMax,
                durationMin: stats.durationMin,
                costPerKwh: costPerKwh,
                batteryStart: stats.batteryStart,
                batteryEnd: stats.batteryEnd,
                isDc: isDc
            )
        }
        state.rows = sorted(rows)
        state.curves = details.compactMap { detail in
            let points = (detail.chargePoints ?? []).compactMap { point -> SessionCurvePoint? in
                guard let soc = point.batteryLevel, let power = point.chargerPower, power > 0 else {
                    return nil
                }
                return SessionCurvePoint(soc: Double(soc), power: Double(power))
            }
            return points.count >= 2 ? SessionCurve(chargeId: detail.chargeId, isBase: detail.chargeId == baseChargeId, points: points) : nil
        }
    }

    private func sorted(_ rows: [ComparableChargeRow]) -> [ComparableChargeRow] {
        switch state.sort {
        case .peak:
            return rows.sorted { ($0.peakKW ?? -1) > ($1.peakKW ?? -1) }
        case .duration:
            return rows.sorted { ($0.durationMin ?? .max) < ($1.durationMin ?? .max) }
        case .cost:
            return rows.sorted { ($0.costPerKwh ?? .greatestFiniteMagnitude) < ($1.costPerKwh ?? .greatestFiniteMagnitude) }
        }
    }

}
