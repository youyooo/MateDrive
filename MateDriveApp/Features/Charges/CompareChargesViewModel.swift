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

    public init(isLoading: Bool = true, rows: [ComparableChargeRow] = [], curves: [SessionCurve] = [], sort: CompareChargeSort = .peak, currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol(), errorMessage: String? = nil) {
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

public struct CompareChargesCacheKey: Hashable, Sendable {
    public let serverURL: String
    public let carId: Int
    public let baseChargeId: Int

    public init(serverURL: String, carId: Int, baseChargeId: Int) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.carId = carId
        self.baseChargeId = baseChargeId
    }
}

public final class CompareChargesStateCache: @unchecked Sendable {
    public static let shared = CompareChargesStateCache()

    private let lock = NSLock()
    private let maximumEntryCount: Int
    private var states: [CompareChargesCacheKey: CompareChargesState] = [:]
    private var recency: [CompareChargesCacheKey] = []

    public init(maximumEntryCount: Int = 16) {
        self.maximumEntryCount = max(maximumEntryCount, 1)
    }

    public func state(for key: CompareChargesCacheKey) -> CompareChargesState? {
        lock.withLock {
            guard let state = states[key] else { return nil }
            markRecentlyUsed(key)
            return state
        }
    }

    public func save(_ state: CompareChargesState, for key: CompareChargesCacheKey) {
        var snapshot = state
        snapshot.isLoading = false
        snapshot.errorMessage = nil
        lock.withLock {
            states[key] = snapshot
            markRecentlyUsed(key)
            while recency.count > maximumEntryCount, let oldest = recency.first {
                recency.removeFirst()
                states.removeValue(forKey: oldest)
            }
        }
    }

    public func removeAll() {
        lock.withLock {
            states.removeAll()
            recency.removeAll()
        }
    }

    private func markRecentlyUsed(_ key: CompareChargesCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

@MainActor
public final class CompareChargesViewModel: ObservableObject {
    @Published public private(set) var state: CompareChargesState

    private let api: any ChargeAPIProviding
    private let costOverrideStore: any ChargeCostOverriding
    private let settingsStore: (any SettingsStoring)?
    private let historyProvider: (any MileageDataProviding)?
    private let cacheKey: CompareChargesCacheKey?
    private let stateCache: CompareChargesStateCache
    private var carId: Int?
    private var baseChargeId: Int?
    private var details: [ChargeDetail] = []
    private var summaryRows: [ComparableChargeRow] = []
    private var costOverrides: [Int: Double] = [:]
    private var pricingRules: [ChargePricingRule] = []

    public init(
        api: any ChargeAPIProviding,
        costOverrideStore: any ChargeCostOverriding = EmptyChargeCostOverrideStore(),
        settingsStore: (any SettingsStoring)? = nil,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: CompareChargesCacheKey? = nil,
        stateCache: CompareChargesStateCache = .shared,
        initialState: CompareChargesState = CompareChargesState()
    ) {
        self.api = api
        self.costOverrideStore = costOverrideStore
        self.settingsStore = settingsStore
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = stateCache
        let restoredState = cacheKey.flatMap { stateCache.state(for: $0) } ?? initialState
        self.state = restoredState
        self.summaryRows = restoredState.rows
    }

    public func load(carId: Int, baseChargeId: Int) async {
        self.carId = carId
        self.baseChargeId = baseChargeId
        state.isLoading = state.baseRow == nil
        state.errorMessage = nil
        if state.rows.isEmpty {
            state.currencySymbol = MateDriveCurrencyFormatter.automaticSymbol()
        }
        pricingRules = []
        details = []
        summaryRows = []

        if historyProvider != nil {
            await loadLocalFirst(carId: carId, baseChargeId: baseChargeId)
            return
        }

        async let baseResult = api.chargeDetail(carId: carId, chargeId: baseChargeId)
        async let chargesResult = loadCharges(carId: carId)

        let baseDetail: ChargeDetail
        switch await baseResult {
        case let .success(detail) where detail.chargeId == baseChargeId:
            baseDetail = detail
            details = [detail]
            rebuildRows()
            state.isLoading = false
            saveCachedState()
        case .success:
            details = []
            state.isLoading = false
            if state.baseRow == nil {
                state.rows = []
                state.curves = []
            }
            state.errorMessage = "TeslaMate returned no charge data."
            _ = await chargesResult
            return
        case let .failure(error):
            state.isLoading = false
            state.errorMessage = error.chargeMessage
            _ = await chargesResult
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
            state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())
        }
        rebuildRows()
        saveCachedState()

        switch await chargesResult {
        case let .success(charges):
            let nearbyIds = charges
                .compactMap(\.chargeId)
                .filter { $0 != baseChargeId }
                .prefix(4)
            var loaded = [baseDetail]
            let api = self.api
            await withTaskGroup(of: ChargeDetail?.self) { group in
                for id in nearbyIds {
                    group.addTask {
                        guard case let .success(detail) = await api.chargeDetail(carId: carId, chargeId: id) else {
                            return nil
                        }
                        return detail
                    }
                }
                for await detail in group {
                    if let detail {
                        loaded.append(detail)
                    }
                }
            }
            details = loaded
            rebuildRows()
            if state.baseRow == nil {
                state.errorMessage = "TeslaMate returned no charge data."
            }
            state.isLoading = false
            saveCachedState()

        case let .failure(error):
            state.errorMessage = error.chargeMessage
        }
    }

    private func loadLocalFirst(carId: Int, baseChargeId: Int) async {
        async let baseResult = api.chargeDetail(carId: carId, chargeId: baseChargeId)
        async let chargesResult = loadCharges(carId: carId)

        await loadPricingContext(carId: carId)

        let selectedCharges: [ChargeData]
        switch await chargesResult {
        case let .success(charges):
            guard let base = charges.first(where: { $0.chargeId == baseChargeId }) else {
                selectedCharges = []
                state.errorMessage = "TeslaMate returned no charge data."
                state.isLoading = false
                _ = await baseResult
                return
            }
            selectedCharges = [base] + charges
                .filter { $0.chargeId != baseChargeId }
                .prefix(4)
            summaryRows = selectedCharges.compactMap {
                summaryRow(from: $0, baseChargeId: baseChargeId)
            }
            rebuildRows()
            state.isLoading = false
            saveCachedState()
        case let .failure(error):
            selectedCharges = []
            state.isLoading = false
            state.errorMessage = error.chargeMessage
        }

        var loaded: [ChargeDetail] = []
        if case let .success(detail) = await baseResult, detail.chargeId == baseChargeId {
            loaded.append(detail)
            details = loaded
            rebuildRows()
            state.errorMessage = nil
            saveCachedState()
        }

        let candidateIds = selectedCharges
            .compactMap(\.chargeId)
            .filter { $0 != baseChargeId }
        let api = self.api
        await withTaskGroup(of: ChargeDetail?.self) { group in
            for id in candidateIds {
                group.addTask {
                    guard case let .success(detail) = await api.chargeDetail(carId: carId, chargeId: id) else {
                        return nil
                    }
                    return detail
                }
            }
            for await detail in group {
                if let detail {
                    loaded.append(detail)
                    details = loaded
                    rebuildRows()
                    saveCachedState()
                }
            }
        }
    }

    private func loadPricingContext(carId: Int) async {
        do {
            costOverrides = try await costOverrideStore.costOverrides(carId: carId)
        } catch {
            costOverrides = [:]
        }
        if let settingsStore {
            let settings = await settingsStore.load()
            pricingRules = settings.chargePricingRules
            state.currencySymbol = MateDriveCurrencyFormatter.symbol(for: settings.resolvedCurrencyCode())
        }
    }

    private func loadCharges(carId: Int) async -> APIResult<[ChargeData]> {
        if let historyProvider {
            return await historyProvider.mileageCharges(carId: carId)
        }
        return await VehicleHistoryPaginator.charges(loadPage: { page, show in
            await self.api.charges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    public func setSort(_ sort: CompareChargeSort) {
        state.sort = sort
        state.rows = sorted(state.rows)
        saveCachedState()
    }

    private func rebuildRows() {
        guard let baseChargeId else {
            return
        }
        let detailRows = details.map { detail in
            let stats = ChargingSessionAnalyzer.calculateStats(detail)
            let isDc = ChargingSessionAnalyzer.detectDcCharge(detail)
                || ChargingSessionAnalyzer.isDcCharge(
                    chargeId: detail.chargeId,
                    energyAddedKwh: stats.energyAdded,
                    durationMin: stats.durationMin,
                    dcChargeIds: [],
                    processedChargeIds: []
                )
            let billing = ChargeBillingEvidence.energyAndSamples(
                wallEnergy: stats.energyUsed,
                batteryEnergy: stats.energyAdded,
                samples: (detail.chargePoints ?? []).map {
                    ChargePricingEnergySample(date: $0.date, cumulativeEnergyAddedKWh: $0.chargeEnergyAdded)
                }
            )
            let pricingEstimate = ChargePricingRuleEngine.estimateCost(
                for: ChargePricingInput(
                    startDate: detail.startDate,
                    endDate: detail.endDate,
                    address: detail.address,
                    latitude: detail.latitude,
                    longitude: detail.longitude,
                    energyAddedKWh: billing.energy,
                    energySamples: billing.samples,
                    isDc: isDc
                ),
                rules: pricingRules
            )
            let effectiveCost = costOverrides[detail.chargeId]
                ?? ChargeBillingEvidence.recordedCost(detail.cost)
                ?? pricingEstimate?.cost
            let costPerKwh: Double?
            if let cost = effectiveCost, let energy = billing.energy, energy > 0 {
                costPerKwh = cost / energy
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
        var merged = Dictionary(uniqueKeysWithValues: summaryRows.map { ($0.chargeId, $0) })
        detailRows.forEach { merged[$0.chargeId] = $0 }
        state.rows = sorted(Array(merged.values))
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

    private func summaryRow(from charge: ChargeData, baseChargeId: Int) -> ComparableChargeRow? {
        guard let chargeId = charge.chargeId else { return nil }
        let isDc = ChargingSessionAnalyzer.isDcCharge(
            chargeId: chargeId,
            energyAddedKwh: charge.chargeEnergyAdded,
            durationMin: charge.durationMin,
            dcChargeIds: [],
            processedChargeIds: []
        )
        let billing = ChargeBillingEvidence.energyAndSamples(
            wallEnergy: charge.chargeEnergyUsed,
            batteryEnergy: charge.chargeEnergyAdded,
            samples: []
        )
        let pricingEstimate = ChargePricingRuleEngine.estimateCost(
            for: ChargePricingInput(
                startDate: charge.startDate,
                endDate: charge.endDate,
                address: charge.address,
                latitude: charge.latitude,
                longitude: charge.longitude,
                energyAddedKWh: billing.energy,
                energySamples: billing.samples,
                isDc: isDc
            ),
            rules: pricingRules
        )
        let effectiveCost = costOverrides[chargeId]
            ?? ChargeBillingEvidence.recordedCost(charge.cost)
            ?? pricingEstimate?.cost
        let costPerKwh: Double?
        if let effectiveCost, let energy = billing.energy, energy > 0 {
            costPerKwh = effectiveCost / energy
        } else {
            costPerKwh = nil
        }
        return ComparableChargeRow(
            chargeId: chargeId,
            isBase: chargeId == baseChargeId,
            startDate: charge.startDate,
            address: charge.address,
            energyAdded: charge.chargeEnergyAdded,
            totalCost: effectiveCost,
            peakKW: charge.chargerPower.map { Int($0.rounded()) },
            durationMin: charge.durationMin,
            costPerKwh: costPerKwh,
            batteryStart: charge.startBatteryLevel,
            batteryEnd: charge.endBatteryLevel,
            isDc: isDc
        )
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

    private func saveCachedState() {
        guard let cacheKey, state.baseRow != nil else { return }
        stateCache.save(state, for: cacheKey)
    }
}
