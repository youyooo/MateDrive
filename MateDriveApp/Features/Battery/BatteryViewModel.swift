import Combine
import Foundation

public struct BatteryStats: Equatable, Sendable {
    public let healthSource: BatteryHealthSource
    public let confidence: BatteryHealthConfidence
    public let currentCapacity: Double?
    public let originalCapacity: Double?
    public let healthPercent: Double?
    public let showsAbsoluteHealth: Bool
    public let lossKwh: Double?
    public let lossPercent: Double?
    public let maxRangeNew: Double?
    public let maxRangeNow: Double?
    public let rangeLoss: Double?
    public let ratedEfficiency: Double?
    public let batteryLevel: Int?
    public let usableBatteryLevel: Int?
    public let estimatedRange: Double?
    public let ratedRange: Double?
    public let idealRange: Double?
    public let rangeAt100: Double?
    public let recordingStartOdometerKm: Double?
    public let hasCurrentCapacityData: Bool
    public let hasOriginalCapacityData: Bool
    public let hasCurrentRangeData: Bool
    public let hasSOCData: Bool
    public let hasRatedRangeData: Bool
    public let hasEfficiencyData: Bool
}

public struct BatteryHistorySummary: Equatable, Sendable {
    public let startDate: String?
    public let endDate: String?
    public let startOdometerKm: Double?
    public let endOdometerKm: Double?
    public let capacityStartKWh: Double?
    public let capacityCurrentKWh: Double?
    public let capacityChangeKWh: Double?
    public let rangeStartKm: Double?
    public let rangeCurrentKm: Double?
    public let rangeChangeKm: Double?
    public let efficiencyWhKm: Double?
    public let qualifyingChargeCount: Int?
    public let capacityUsesMedian: Bool
    public let rangeSmoothingSampleCount: Int
    public let quality: BatteryHistoryQuality

    public var recordedCapacityRetentionPercent: Double? {
        guard let capacityStartKWh, let capacityCurrentKWh, capacityStartKWh > 0 else { return nil }
        return capacityCurrentKWh / capacityStartKWh * 100
    }

    public var recordedRangeRetentionPercent: Double? {
        guard let rangeStartKm, let rangeCurrentKm, rangeStartKm > 0 else { return nil }
        return rangeCurrentKm / rangeStartKm * 100
    }

    public var recordedDistanceKm: Double? {
        guard let startOdometerKm, let endOdometerKm else { return nil }
        return max(endOdometerKm - startOdometerKm, 0)
    }
}

public struct BatteryHistoryQuality: Equatable, Sendable {
    public enum Level: Equatable, Sendable {
        case low, medium, high

        public func title(language: AppLanguage) -> String {
            let chinese = MateDriveUnitFormatter.usesChineseLabels(language: language)
            switch self {
            case .low: return chinese ? "较低" : "Low"
            case .medium: return chinese ? "中等" : "Medium"
            case .high: return chinese ? "较高" : "High"
            }
        }
    }

    public let score: Int
    public let capacitySampleCount: Int
    public let rangeSampleCount: Int
    public let qualifyingChargeCount: Int
    public let requiredChargeCount: Int
    public let recordedDays: Int
    public let recordedDistanceKm: Double

    public var level: Level {
        score >= 75 ? .high : score >= 45 ? .medium : .low
    }
}

public enum BatteryHealthConfidence: Equatable, Sendable {
    case calibratedLateHistory
    case lateHistoryNeedsReference
    case recordingStartUnknown
    case normal

    public var needsReference: Bool {
        self == .lateHistoryNeedsReference || self == .recordingStartUnknown
    }

    public func title(language: AppLanguage) -> String {
        switch self {
        case .calibratedLateHistory:
            return localized("Calibrated", "已校准", language: language)
        case .lateHistoryNeedsReference:
            return localized("Needs reference", "需要参考值", language: language)
        case .recordingStartUnknown:
            return localized("Recording start unknown", "记录起点未知", language: language)
        case .normal:
            return localized("Normal", "正常", language: language)
        }
    }

    public func detail(recordingStartOdometerKm: Double?, units: UnitPreferences?, language: AppLanguage) -> String {
        let odometer = recordingStartOdometerKm.map { MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0) }
        switch self {
        case .calibratedLateHistory:
            if let odometer {
                return localized(
                    "TeslaMate history starts around \(odometer); health is calculated from your new-car capacity or range reference.",
                    "TeslaMate 记录约从 \(odometer) 开始，健康度已按你填写的新车容量或续航参考值计算。",
                    language: language
                )
            }
            return localized(
                "Health is calculated from your new-car capacity or range reference.",
                "健康度已按你填写的新车容量或续航参考值计算。",
                language: language
            )
        case .lateHistoryNeedsReference:
            if let odometer {
                return localized(
                    "TeslaMate history starts around \(odometer). Enter the verified new-car usable capacity or rated range for a more accurate estimate.",
                    "TeslaMate 记录约从 \(odometer) 才开始。请填写已确认的新车可用容量或额定续航，电池健康度会更准确。",
                    language: language
                )
            }
            return localized(
                "Enter the verified new-car usable capacity or rated range for a more accurate health estimate.",
                "请填写已确认的新车可用容量或额定续航，电池健康度会更准确。",
                language: language
            )
        case .recordingStartUnknown:
            return localized(
                "TeslaMate's recording start odometer is unknown. Recording-period retention is not shown as lifetime health until you add a verified new-car capacity or rated-range reference.",
                "TeslaMate 的开始记录里程未知。在填写已确认的新车可用容量或额定续航前，记录期保持率不会作为整车寿命健康度显示。",
                language: language
            )
        case .normal:
            return localized(
                "No late-history calibration warning is active.",
                "当前没有晚开始记录的校准警告。",
                language: language
            )
        }
    }

    private func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public enum BatteryHealthSource: Equatable, Sendable {
    case manualCapacityReference
    case manualReference
    case teslaMateHealth
    case recordedPeriod
    case rangeRatio
    case fallback

    public func title(language: AppLanguage) -> String {
        switch self {
        case .manualCapacityReference:
            return localized("Manual capacity", "手动容量基线", language: language)
        case .manualReference:
            return localized("Manual reference", "手动参考值", language: language)
        case .teslaMateHealth:
            return localized("TeslaMate health", "TeslaMate 健康度", language: language)
        case .recordedPeriod:
            return localized("Recording-period retention", "记录期保持率", language: language)
        case .rangeRatio:
            return localized("Range estimate", "续航估算", language: language)
        case .fallback:
            return localized("Unavailable", "不可用", language: language)
        }
    }

    public func detail(language: AppLanguage) -> String {
        switch self {
        case .manualCapacityReference:
            return localized(
                "Calculated from current usable capacity and your verified new-car usable capacity.",
                "按当前可用容量和你确认的新车可用容量计算。",
                language: language
            )
        case .manualReference:
            return localized(
                "Calculated from current 100% rated range and your new-car reference range.",
                "按当前满电额定续航和你填写的新车参考续航计算。",
                language: language
            )
        case .teslaMateHealth:
            return localized(
                "Using TeslaMate API battery health percentage.",
                "使用 TeslaMate API 返回的电池健康百分比。",
                language: language
            )
        case .recordedPeriod:
            return localized(
                "TeslaMate compares the current value with the best value observed since recording began; this is not lifetime battery health.",
                "TeslaMate 将当前值与开始记录后的观测最佳值比较；这不是车辆从新车至今的寿命健康度。",
                language: language
            )
        case .rangeRatio:
            return localized(
                "Calculated from current and baseline rated range.",
                "按当前续航和基准续航比例估算。",
                language: language
            )
        case .fallback:
            return localized("No reliable data", "暂无可靠数据", language: language)
        }
    }

    private func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct BatteryState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var errorMessage: String?
    public var batteryHealth: BatteryHealth?
    public var carStatus: CarStatus?
    public var units: UnitPreferences?
    public var stats: BatteryStats?
    public var history: BatteryHistoryData?
    public var historySummary: BatteryHistorySummary?

    public init(isLoading: Bool = true, isRefreshing: Bool = false, errorMessage: String? = nil, batteryHealth: BatteryHealth? = nil, carStatus: CarStatus? = nil, units: UnitPreferences? = nil, stats: BatteryStats? = nil, history: BatteryHistoryData? = nil, historySummary: BatteryHistorySummary? = nil) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.errorMessage = errorMessage
        self.batteryHealth = batteryHealth
        self.carStatus = carStatus
        self.units = units
        self.stats = stats
        self.history = history
        self.historySummary = historySummary
    }
}

@MainActor
public final class BatteryViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<BatteryState>(maximumEntryCount: 4)

    @Published public private(set) var state: BatteryState

    private let api: any AnalyticsAPIProviding
    private let ratedEfficiencyFallback: Double?
    private let settingsStore: (any SettingsStoring)?
    private let historyProvider: (any MileageDataProviding)?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<BatteryState>
    private var carId: Int?

    public init(
        api: any AnalyticsAPIProviding,
        ratedEfficiencyFallback: Double? = nil,
        settingsStore: (any SettingsStoring)? = nil,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<BatteryState>? = nil,
        initialState: BatteryState = BatteryState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.ratedEfficiencyFallback = ratedEfficiencyFallback
        self.settingsStore = settingsStore
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        self.carId = carId
        state.isRefreshing = true
        state.isLoading = state.stats == nil
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }

        async let healthResult = api.batteryHealth(carId: carId)
        async let statusResult = api.carStatus(carId: carId)
        async let drivesResult = loadDrives(carId: carId)
        async let historyResult = api.batteryHistory(carId: carId)

        let (resolvedHealth, resolvedStatus, resolvedDrives, resolvedHistory) = await (healthResult, statusResult, drivesResult, historyResult)

        switch (resolvedHealth, resolvedStatus) {
        case let (.success(health), .success(payload)):
            let units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
            state.batteryHealth = health
            state.carStatus = payload.status
            state.units = units
            let history: BatteryHistoryData?
            if case let .success(value) = resolvedHistory {
                history = value
                state.history = value
                state.historySummary = Self.historySummary(from: value)
            } else {
                history = state.history
            }
            let referenceRange: Double?
            let referenceCapacity: Double?
            let recordingStartOdometer: Double?
            let detectedRecordingStartOdometer = state.historySummary?.startOdometerKm
                ?? Self.recordingStartOdometer(from: resolvedDrives)
            if let settingsStore {
                let settings = await settingsStore.load()
                var calibration = settings.batteryCalibration(for: carId)
                referenceRange = calibration.referenceRangeKm
                referenceCapacity = calibration.referenceCapacityKWh
                recordingStartOdometer = Self.earliestValidOdometer(
                    calibration.recordingStartOdometerKm,
                    detectedRecordingStartOdometer
                )
                if calibration.recordingStartOdometerKm != recordingStartOdometer {
                    calibration.recordingStartOdometerKm = recordingStartOdometer
                    await saveDetectedRecordingStart(
                        calibration,
                        carId: carId,
                        fallbackSettings: settings,
                        settingsStore: settingsStore
                    )
                }
            } else {
                referenceRange = nil
                referenceCapacity = nil
                recordingStartOdometer = detectedRecordingStartOdometer
            }
            state.stats = Self.computeStats(
                health: health,
                status: payload.status,
                ratedEfficiencyFallback: history?.efficiency?.whPerKm ?? ratedEfficiencyFallback,
                batteryReferenceRangeKm: referenceRange,
                batteryReferenceCapacityKWh: referenceCapacity,
                batteryRecordingStartOdometerKm: recordingStartOdometer
            )
            saveCachedState()
        case let (.failure(error), _), let (_, .failure(error)):
            state.errorMessage = error.analyticsMessage
        }
    }

    private func loadDrives(carId: Int) async -> APIResult<[DriveData]> {
        if let historyProvider {
            return await historyProvider.mileageDrives(carId: carId)
        }
        return await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    public func refresh() async {
        guard let carId else {
            return
        }
        await load(carId: carId)
    }

    private func saveDetectedRecordingStart(
        _ calibration: BatteryCalibration,
        carId: Int,
        fallbackSettings: AppSettings,
        settingsStore: any SettingsStoring
    ) async {
        if let atomicStore = settingsStore as? any AtomicSettingsUpdating {
            _ = try? await atomicStore.updateAtomically { current in
                var updated = current
                var latest = updated.batteryCalibration(for: carId)
                latest.recordingStartOdometerKm = Self.earliestValidOdometer(
                    latest.recordingStartOdometerKm,
                    calibration.recordingStartOdometerKm
                )
                updated.setBatteryCalibration(latest, for: carId)
                return updated
            }
            return
        }
        var updated = fallbackSettings
        updated.setBatteryCalibration(calibration, for: carId)
        await settingsStore.save(updated)
    }

    private func saveCachedState() {
        guard let cacheKey, state.stats != nil else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }

    public static func computeStats(
        health: BatteryHealth,
        status: CarStatus?,
        ratedEfficiencyFallback: Double? = nil,
        batteryReferenceRangeKm: Double? = nil,
        batteryReferenceCapacityKWh: Double? = nil,
        batteryRecordingStartOdometerKm: Double? = nil
    ) -> BatteryStats {
        let measuredEfficiency = health.ratedEfficiency ?? ratedEfficiencyFallback
        let ratedEfficiency = measuredEfficiency
        let batteryLevel = status?.batteryLevel
        let usableBatteryLevel = status?.usableBatteryLevel ?? batteryLevel
        let estimatedRange = status?.estBatteryRangeKm
        let ratedRange = status?.ratedBatteryRangeKm
        let idealRange = status?.idealBatteryRangeKm
        let socBasis = usableBatteryLevel.flatMap { $0 > 0 ? $0 : nil } ?? batteryLevel.flatMap { $0 > 0 ? $0 : nil }
        let statusRangeAt100 = socBasis.flatMap { soc in
            ratedRange.flatMap { range in range > 0 ? rounded(range / Double(soc) * 100, places: 1) : nil }
        }
        // Charge-derived range is less sensitive to transient SOC rounding than a single status extrapolation.
        let maxRangeNow = health.currentRange ?? statusRangeAt100
        let maxRangeNew = batteryReferenceRangeKm ?? health.maxRange
        let rangeLoss = maxRangeNew.flatMap { newRange in maxRangeNow.map { rounded(max(newRange - $0, 0), places: 1) } }
        let healthPercent: Double?
        let healthSource: BatteryHealthSource
        let recordingStartIsKnown = batteryRecordingStartOdometerKm != nil
        let startsLate = (batteryRecordingStartOdometerKm ?? 0) >= 50_000
        let historyBaselineIsUnverified = !recordingStartIsKnown || startsLate
        if let batteryReferenceCapacityKWh, batteryReferenceCapacityKWh > 0,
           let currentCapacity = health.currentCapacity, currentCapacity > 0 {
            healthPercent = rounded(min(max(currentCapacity / batteryReferenceCapacityKWh * 100, 0), 100), places: 1)
            healthSource = .manualCapacityReference
        } else if let batteryReferenceRangeKm, batteryReferenceRangeKm > 0, let maxRangeNow, maxRangeNow > 0 {
            healthPercent = rounded(min(max(maxRangeNow / batteryReferenceRangeKm * 100, 0), 100), places: 1)
            healthSource = .manualReference
        } else if let batteryHealthPercentage = health.batteryHealthPercentage {
            healthPercent = batteryHealthPercentage
            healthSource = historyBaselineIsUnverified ? .recordedPeriod : .teslaMateHealth
        } else if let maxRangeNew, maxRangeNew > 0, let maxRangeNow, maxRangeNow > 0 {
            healthPercent = rounded(min(max(maxRangeNow / maxRangeNew * 100, 0), 100), places: 1)
            healthSource = historyBaselineIsUnverified ? .recordedPeriod : .rangeRatio
        } else {
            healthPercent = nil
            healthSource = .fallback
        }
        let hasManualCapacityReference = (batteryReferenceCapacityKWh ?? 0) > 0
        let hasManualRangeReference = (batteryReferenceRangeKm ?? 0) > 0
        let referenceOriginalCapacity = hasManualRangeReference && !hasManualCapacityReference
            ? measuredEfficiency.flatMap { estimatedCapacity(rangeKm: batteryReferenceRangeKm, ratedEfficiency: $0) }
            : nil
        let referenceCurrentCapacity = hasManualRangeReference && !hasManualCapacityReference
            ? measuredEfficiency.flatMap { efficiency in maxRangeNow.flatMap { estimatedCapacity(rangeKm: $0, ratedEfficiency: efficiency) } }
            : nil
        let verifiedOriginalCapacity = ((batteryReferenceCapacityKWh ?? 0) > 0 ? batteryReferenceCapacityKWh : nil)
            ?? referenceOriginalCapacity
        let observedBaselineCapacity = health.maxCapacity
            ?? measuredEfficiency.flatMap { estimatedCapacity(rangeKm: health.maxRange, ratedEfficiency: $0) }
        let resolvedOriginalCapacity = verifiedOriginalCapacity
            ?? ((healthSource != .recordedPeriod && healthSource != .fallback) ? observedBaselineCapacity : nil)
        let resolvedCurrentCapacity = referenceCurrentCapacity
            ?? health.currentCapacity
            ?? ((healthSource != .recordedPeriod && healthSource != .fallback)
                ? healthPercent.flatMap { percent in resolvedOriginalCapacity.map { $0 * percent / 100 } }
                : nil)
        let originalCapacity = resolvedOriginalCapacity
        let currentCapacity = resolvedCurrentCapacity
        let lossKwh = originalCapacity.flatMap { original in currentCapacity.map { max(original - $0, 0) } }
        let lossPercent = healthPercent.map { max(100 - $0, 0) }
        let rangeAt100 = maxRangeNow
        let confidence: BatteryHealthConfidence
        if (healthSource == .manualCapacityReference || healthSource == .manualReference) && historyBaselineIsUnverified {
            confidence = .calibratedLateHistory
        } else if !recordingStartIsKnown {
            confidence = .recordingStartUnknown
        } else if (batteryRecordingStartOdometerKm ?? 0) >= 50_000 {
            confidence = .lateHistoryNeedsReference
        } else {
            confidence = .normal
        }

        return BatteryStats(
            healthSource: healthSource,
            confidence: confidence,
            currentCapacity: currentCapacity,
            originalCapacity: originalCapacity,
            healthPercent: healthPercent,
            showsAbsoluteHealth: healthPercent != nil && healthSource != .recordedPeriod && healthSource != .fallback,
            lossKwh: lossKwh,
            lossPercent: lossPercent,
            maxRangeNew: maxRangeNew,
            maxRangeNow: maxRangeNow,
            rangeLoss: rangeLoss,
            ratedEfficiency: ratedEfficiency,
            batteryLevel: batteryLevel,
            usableBatteryLevel: usableBatteryLevel,
            estimatedRange: estimatedRange,
            ratedRange: ratedRange,
            idealRange: idealRange,
            rangeAt100: rangeAt100,
            recordingStartOdometerKm: batteryRecordingStartOdometerKm,
            hasCurrentCapacityData: resolvedCurrentCapacity != nil,
            hasOriginalCapacityData: resolvedOriginalCapacity != nil,
            hasCurrentRangeData: maxRangeNow != nil,
            hasSOCData: status?.batteryLevel != nil || status?.usableBatteryLevel != nil,
            hasRatedRangeData: ratedRange != nil,
            hasEfficiencyData: measuredEfficiency != nil
        )
    }

    public static func historySummary(from history: BatteryHistoryData) -> BatteryHistorySummary? {
        let rawCapacity = (history.charts?.capacity ?? []).filter { $0.capacity != nil }
            .sorted { ($0.odometer ?? 0) < ($1.odometer ?? 0) }
        let medianCapacity = (history.charts?.capacityMedian ?? []).filter { $0.capacity != nil }
            .sorted { ($0.odometer ?? 0) < ($1.odometer ?? 0) }
        let capacityUsesMedian = medianCapacity.count >= 2
        let capacity = capacityUsesMedian ? medianCapacity : rawCapacity
        let ranges = (history.charts?.range ?? []).filter { $0.range != nil }
            .sorted { ($0.odometer ?? 0) < ($1.odometer ?? 0) }
        guard !capacity.isEmpty || !ranges.isEmpty else { return nil }

        let odometers = (capacity.compactMap(\.odometer) + ranges.compactMap(\.odometer))
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        let dates = (capacity.compactMap(\.date) + ranges.compactMap(\.date)).sorted()
        let capacityStart = capacity.first?.capacity
        let capacityCurrent = capacity.last?.capacity
        let rangeValues = ranges.compactMap(\.range)
        let rangeSmoothingSampleCount = smoothingWindowCount(for: rangeValues.count)
        let rangeStart = median(Array(rangeValues.prefix(rangeSmoothingSampleCount)))
        let rangeCurrent = median(Array(rangeValues.suffix(rangeSmoothingSampleCount)))
        let quality = historyQuality(
            rawCapacityCount: rawCapacity.count,
            medianCapacityCount: medianCapacity.count,
            rangeCount: ranges.count,
            qualifyingChargeCount: history.efficiency?.qualifyingChargeCount,
            requiredChargeCount: history.efficiency?.requiredChargeCount,
            efficiencyReady: history.efficiency?.ready,
            startDate: dates.first,
            endDate: dates.last,
            startOdometerKm: odometers.first,
            endOdometerKm: odometers.last
        )
        return BatteryHistorySummary(
            startDate: dates.first,
            endDate: dates.last,
            startOdometerKm: odometers.first,
            endOdometerKm: odometers.last,
            capacityStartKWh: capacityStart,
            capacityCurrentKWh: capacityCurrent,
            capacityChangeKWh: difference(from: capacityStart, to: capacityCurrent),
            rangeStartKm: rangeStart,
            rangeCurrentKm: rangeCurrent,
            rangeChangeKm: difference(from: rangeStart, to: rangeCurrent),
            efficiencyWhKm: history.efficiency?.whPerKm,
            qualifyingChargeCount: history.efficiency?.qualifyingChargeCount,
            capacityUsesMedian: capacityUsesMedian,
            rangeSmoothingSampleCount: rangeSmoothingSampleCount,
            quality: quality
        )
    }

    private static func historyQuality(
        rawCapacityCount: Int,
        medianCapacityCount: Int,
        rangeCount: Int,
        qualifyingChargeCount: Int?,
        requiredChargeCount: Int?,
        efficiencyReady: Bool?,
        startDate: String?,
        endDate: String?,
        startOdometerKm: Double?,
        endOdometerKm: Double?
    ) -> BatteryHistoryQuality {
        let capacityCount = medianCapacityCount > 0 ? medianCapacityCount : rawCapacityCount
        let charges = max(qualifyingChargeCount ?? 0, 0)
        let required = max(requiredChargeCount ?? 2, 1)
        let distance = max((endOdometerKm ?? 0) - (startOdometerKm ?? 0), 0)
        let days = recordedDays(from: startDate, to: endDate)
        var score = 0
        score += capacityCount >= 8 ? 25 : capacityCount >= 3 ? 18 : capacityCount >= 2 ? 10 : 0
        score += rangeCount >= 20 ? 25 : rangeCount >= 8 ? 18 : rangeCount >= 3 ? 10 : 0
        score += distance >= 5_000 ? 20 : distance >= 1_000 ? 12 : distance > 0 ? 5 : 0
        score += days >= 90 ? 15 : days >= 30 ? 10 : days >= 7 ? 5 : 0
        if efficiencyReady == true, charges >= required {
            score += 15
        } else if charges > 0 {
            score += min(10, charges * 3)
        }
        return BatteryHistoryQuality(
            score: min(score, 100),
            capacitySampleCount: capacityCount,
            rangeSampleCount: rangeCount,
            qualifyingChargeCount: charges,
            requiredChargeCount: required,
            recordedDays: days,
            recordedDistanceKm: distance
        )
    }

    private static func recordedDays(from start: String?, to end: String?) -> Int {
        guard let start, let end else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let startDate = formatter.date(from: String(start.prefix(10))),
              let endDate = formatter.date(from: String(end.prefix(10))) else { return 0 }
        return max(Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day ?? 0, 0)
    }

    private static func smoothingWindowCount(for sampleCount: Int) -> Int {
        guard sampleCount > 0 else { return 0 }
        return min(5, max(1, sampleCount / 3))
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func difference(from start: Double?, to end: Double?) -> Double? {
        guard let start, let end else { return nil }
        return end - start
    }

    private static func rounded(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    private static func estimatedCapacity(rangeKm: Double?, ratedEfficiency: Double) -> Double? {
        guard let rangeKm, rangeKm > 0, ratedEfficiency > 0 else {
            return nil
        }
        return rounded(rangeKm * ratedEfficiency / 1000, places: 1)
    }

    private static func recordingStartOdometer(from result: APIResult<[DriveData]>) -> Double? {
        guard case let .success(drives) = result else {
            return nil
        }
        return drives.compactMap(\.odometerDetails?.odometerStart)
            .filter { $0.isFinite && $0 > 0 }
            .min()
    }

    nonisolated private static func earliestValidOdometer(_ values: Double?...) -> Double? {
        values.compactMap { $0 }
            .filter { $0.isFinite && $0 > 0 }
            .min()
    }
}
