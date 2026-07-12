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
    public let efficiency: Double?
    public let durationMin: Int?
    public let cost: Double?
}

public enum ChargeStatsCalculator {
    public static let dcAveragePowerThresholdKW = 20.0

    public static func calculateStats(_ detail: ChargeDetail) -> ChargeDetailStats {
        let points = detail.chargePoints ?? []

        let powers = points.compactMap(\.chargerPower)
        let voltages = points.compactMap(\.chargerVoltage)
        let currents = points.compactMap(\.chargerCurrent)
        let temps = points.compactMap(\.outsideTemp)
        let batteryLevels = points.compactMap(\.batteryLevel)

        let energyAdded = detail.chargeEnergyAdded
        let energyUsed = detail.chargeEnergyUsed ?? energyAdded
        let efficiency = energyAdded.flatMap { added in
            energyUsed.flatMap { used in used > 0 ? (added / used) * 100 : nil }
        }
        let batteryStart = batteryLevels.first ?? detail.startBatteryLevel
        let batteryEnd = batteryLevels.last ?? detail.currentOrEndBatteryLevel

        return ChargeDetailStats(
            powerMax: powers.max(),
            powerMin: powers.filter { $0 > 0 }.min() ?? powers.min(),
            powerAvg: average(powers.map(Double.init)),
            voltageMax: voltages.max(),
            voltageMin: voltages.filter { $0 > 0 }.min() ?? voltages.min(),
            voltageAvg: average(voltages.map(Double.init)),
            currentMax: currents.max(),
            currentMin: currents.filter { $0 > 0 }.min() ?? currents.min(),
            currentAvg: average(currents.map(Double.init)),
            tempMax: temps.max() ?? detail.outsideTempAvg,
            tempMin: temps.min() ?? detail.outsideTempAvg,
            tempAvg: temps.isEmpty ? detail.outsideTempAvg : average(temps),
            batteryStart: batteryStart,
            batteryEnd: batteryEnd,
            batteryAdded: batteryStart.flatMap { start in batteryEnd.map { $0 - start } },
            energyAdded: energyAdded,
            energyUsed: energyUsed,
            efficiency: efficiency,
            durationMin: detail.durationMin,
            cost: detail.cost
        )
    }

    public static func detectDcCharge(_ detail: ChargeDetail) -> Bool {
        guard let points = detail.chargePoints else {
            return false
        }
        let phaseVotes = points
            .compactMap { $0.chargerDetails?.chargerPhases }
        guard !phaseVotes.isEmpty else {
            return false
        }
        let modePhases = phaseVotes.reduce(into: [Int: Int]()) { counts, phase in
            counts[phase, default: 0] += 1
        }
        .max { lhs, rhs in lhs.value < rhs.value }?
        .key
        return modePhases == 0
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
        let averagePower = energyAddedKwh / (Double(durationMin) / 60.0)
        return averagePower > dcAveragePowerThresholdKW
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
