import Foundation

public struct ChargeDetailStats: Equatable, Sendable {
    public let powerMax: Int?
    public let powerMin: Int?
    public let powerAvg: Double?
    public let voltageMax: Int?
    public let voltageMin: Int?
    public let voltageAvg: Double?
    public let currentMax: Int?
    public let currentMin: Int?
    public let currentAvg: Double?
    public let tempMax: Double?
    public let tempMin: Double?
    public let tempAvg: Double?
    public let batteryStart: Int?
    public let batteryEnd: Int?
    public let batteryAdded: Int?
    public let energyAdded: Double?
    public let energyUsed: Double?
    public let energyLoss: Double?
    public let efficiency: Double?
    public let durationMin: Int?
    public let cost: Double?
}

public enum ChargingSessionAnalyzer {
    // A normal three-phase AC session tops out near 22 kW. This fallback is only
    // used when TeslaMate has not supplied connector metadata.
    public static let dcPowerFallbackThresholdKW = 24.0

    public static func calculateStats(_ detail: ChargeDetail) -> ChargeDetailStats {
        let points = detail.chargePoints ?? []

        let power = IntegerSeries(points.compactMap(\.chargerPower))
        let voltage = IntegerSeries(points.compactMap(\.chargerVoltage))
        let current = IntegerSeries(points.compactMap(\.chargerCurrent))
        let temperature = DecimalSeries(points.compactMap(\.outsideTemp))
        let batteryLevels = points.compactMap(\.batteryLevel)

        let energyAdded = nonnegativeFinite(detail.chargeEnergyAdded)
        let energyUsed = nonnegativeFinite(detail.chargeEnergyUsed)
        let energyLoss = energyUsed.flatMap { used in
            energyAdded.map { used - $0 }
        }
        let efficiency = energyAdded.flatMap { added in
            energyUsed.flatMap { used in used > 0 ? (added / used) * 100 : nil }
        }
        let batteryStart = batteryLevels.first ?? detail.startBatteryLevel
        let batteryEnd = batteryLevels.last ?? detail.currentOrEndBatteryLevel

        return ChargeDetailStats(
            powerMax: power.maximum,
            powerMin: power.minimumWhileActive,
            powerAvg: power.mean,
            voltageMax: voltage.maximum,
            voltageMin: voltage.minimumWhileActive,
            voltageAvg: voltage.mean,
            currentMax: current.maximum,
            currentMin: current.minimumWhileActive,
            currentAvg: current.mean,
            tempMax: temperature.maximum ?? detail.outsideTempAvg,
            tempMin: temperature.minimum ?? detail.outsideTempAvg,
            tempAvg: temperature.mean ?? detail.outsideTempAvg,
            batteryStart: batteryStart,
            batteryEnd: batteryEnd,
            batteryAdded: batteryStart.flatMap { start in batteryEnd.map { $0 - start } },
            energyAdded: energyAdded,
            energyUsed: energyUsed,
            energyLoss: energyLoss,
            efficiency: efficiency,
            durationMin: detail.durationMin,
            cost: detail.cost
        )
    }

    public static func detectDcCharge(_ detail: ChargeDetail) -> Bool {
        let points = detail.chargePoints ?? []
        if points.contains(where: { $0.chargerDetails?.fastChargerPresent == true }) {
            return true
        }

        let reportedPhases = points.compactMap { $0.chargerDetails?.chargerPhases }
        if reportedPhases.contains(0) {
            return true
        }
        if reportedPhases.contains(where: { $0 > 0 }) {
            return false
        }

        let measuredPower = IntegerSeries(points.compactMap(\.chargerPower)).mean
        return measuredPower.map { $0 > dcPowerFallbackThresholdKW } ?? false
    }

    public static func chargerIdentity(_ detail: ChargeDetail) -> ChargePricingChargerIdentity {
        let brands = detail.chargePoints?
            .compactMap { normalizedChargerValue($0.chargerDetails?.fastChargerBrand) } ?? []
        let isDc = detectDcCharge(detail) || detail.chargePoints?.contains(where: { $0.chargerDetails?.fastChargerPresent == true }) == true
        if isDc, brands.contains(where: { $0.localizedCaseInsensitiveContains("tesla") }) {
            return .teslaSupercharger
        }
        return chargerIdentity(isDc: isDc, fastChargerBrand: brands.first, address: detail.address)
    }

    public static func chargerIdentity(
        isDc: Bool,
        fastChargerBrand: String?,
        address: String? = nil
    ) -> ChargePricingChargerIdentity {
        guard isDc else { return .ac }
        let brand = normalizedChargerValue(fastChargerBrand)
        let address = address?.lowercased() ?? ""
        if brand?.localizedCaseInsensitiveContains("tesla") == true ||
            address.localizedCaseInsensitiveContains("tesla supercharger") ||
            address.contains("特斯拉超级充电") || address.contains("特斯拉超充")
        {
            return .teslaSupercharger
        }
        return brand == nil ? .unknownDC : .otherDC
    }

    private static func normalizedChargerValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "<invalid>",
              value.lowercased() != "unknown"
        else {
            return nil
        }
        return value
    }

    public static func isDcCharge(
        chargeId: Int,
        energyAddedKwh: Double?,
        durationMin: Int?,
        dcChargeIds: Set<Int>,
        processedChargeIds: Set<Int>
    ) -> Bool {
        if processedChargeIds.contains(chargeId) {
            return dcChargeIds.contains(chargeId)
        }
        guard let durationMin, let energyAddedKwh, durationMin > 0 else {
            return false
        }
        let averagePower = energyAddedKwh * 60.0 / Double(durationMin)
        return averagePower > dcPowerFallbackThresholdKW
    }

    private static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private struct IntegerSeries {
        let values: [Int]

        init(_ values: [Int]) {
            self.values = values
        }

        var maximum: Int? { values.max() }
        var minimumWhileActive: Int? {
            let active = values.filter { $0 > 0 }
            return active.min() ?? values.min()
        }
        var mean: Double? {
            guard !values.isEmpty else { return nil }
            return Double(values.reduce(0, +)) / Double(values.count)
        }
    }

    private struct DecimalSeries {
        let values: [Double]

        init(_ values: [Double]) {
            self.values = values.filter(\.isFinite)
        }

        var maximum: Double? { values.max() }
        var minimum: Double? { values.min() }
        var mean: Double? {
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
    }
}
