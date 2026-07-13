import Foundation

public enum DriveEnergySource: Equatable, Sendable {
    case api
    case powerSamples
    case unavailable
}

public struct DriveEnergyEstimate: Equatable, Sendable {
    public let tractionKWh: Double
    public let regeneratedKWh: Double
    public let netKWh: Double
    public let coverage: Double
    public let integratedDuration: TimeInterval
    public let sampleDuration: TimeInterval

    public var isReliable: Bool { coverage >= 0.8 }
}

public struct DriveDetailStats: Equatable, Sendable {
    public let speedMax: Int?
    public let speedAvg: Double?
    public let speedMin: Int?
    public let powerMax: Int?
    public let powerMin: Int?
    public let powerAvg: Double?
    public let elevationMax: Int?
    public let elevationMin: Int?
    public let elevationGain: Int?
    public let elevationLoss: Int?
    public let batteryStart: Int?
    public let batteryEnd: Int?
    public let batteryUsed: Int?
    public let energyUsed: Double?
    public let energySource: DriveEnergySource
    public let tractionEnergyKWh: Double?
    public let regeneratedEnergyKWh: Double?
    public let energySampleCoverage: Double?
    public let efficiency: Double?
    public let distance: Double?
    public let durationMin: Int?
    public let avgSpeedFromDistance: Double?
    public let outsideTempAvg: Double?
    public let insideTempAvg: Double?
}

public enum DriveStatsCalculator {
    public static func calculateStats(_ detail: DriveDetail) -> DriveDetailStats {
        let positions = detail.positions ?? []

        let speeds = positions.compactMap(\.speed)
        let speedMax = speeds.max() ?? detail.speedMax
        let speedMin = speeds.filter { $0 > 0 }.min() ?? speeds.min()
        let speedAvg = speeds.isEmpty ? detail.speedAvg : Double(speeds.reduce(0, +)) / Double(speeds.count)

        let powers = positions.compactMap(\.power)
        let powerMax = powers.max() ?? detail.powerMax
        let powerMin = powers.min() ?? detail.powerMin
        let powerAvg = powers.isEmpty ? nil : Double(powers.reduce(0, +)) / Double(powers.count)

        let elevations = positions.compactMap(\.elevation)
        let elevationMax = elevations.max()
        let elevationMin = elevations.min()
        let (elevationGain, elevationLoss) = elevationChange(elevations)

        let batteryLevels = positions.compactMap(\.batteryLevel)
        let batteryStart = batteryLevels.first ?? detail.startBatteryLevel
        let batteryEnd = batteryLevels.last ?? detail.endBatteryLevel
        let batteryUsed = batteryStart.flatMap { start in batteryEnd.map { start - $0 } }

        let distance = detail.distance
        let sampleEstimate = estimateEnergy(from: positions)
        let reliableSampleEstimate = sampleEstimate?.isReliable == true ? sampleEstimate : nil
        let energyUsed = detail.usableEnergyConsumedNet ?? reliableSampleEstimate?.netKWh
        let energySource: DriveEnergySource = detail.usableEnergyConsumedNet != nil
            ? .api
            : reliableSampleEstimate != nil ? .powerSamples
            : detail.usableConsumptionNet != nil ? .api : .unavailable
        let efficiency: Double?
        if let energyUsed, let distance, distance > 0 {
            efficiency = energyUsed * 1000 / distance
        } else {
            efficiency = detail.usableConsumptionNet
        }
        let durationMin = detail.durationMin
        let avgSpeedFromDistance: Double? = durationMin.flatMap { duration in
            guard duration > 0, let distance else { return nil }
            return distance / Double(duration) * 60
        }

        return DriveDetailStats(
            speedMax: speedMax,
            speedAvg: speedAvg,
            speedMin: speedMin,
            powerMax: powerMax,
            powerMin: powerMin,
            powerAvg: powerAvg,
            elevationMax: elevationMax,
            elevationMin: elevationMin,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            batteryStart: batteryStart,
            batteryEnd: batteryEnd,
            batteryUsed: batteryUsed,
            energyUsed: energyUsed,
            energySource: energySource,
            tractionEnergyKWh: reliableSampleEstimate?.tractionKWh,
            regeneratedEnergyKWh: reliableSampleEstimate?.regeneratedKWh,
            energySampleCoverage: sampleEstimate?.coverage,
            efficiency: efficiency,
            distance: distance,
            durationMin: durationMin,
            avgSpeedFromDistance: avgSpeedFromDistance,
            outsideTempAvg: detail.outsideTempAvg,
            insideTempAvg: detail.insideTempAvg
        )
    }

    public static func estimatedNetEnergyKWh(
        from positions: [DrivePosition],
        maximumSampleGap: TimeInterval = 30
    ) -> Double? {
        let estimate = estimateEnergy(from: positions, maximumSampleGap: maximumSampleGap)
        return estimate?.isReliable == true ? estimate?.netKWh : nil
    }

    public static func estimateEnergy(
        from positions: [DrivePosition],
        maximumSampleGap: TimeInterval = 30
    ) -> DriveEnergyEstimate? {
        let samples = positions.compactMap { position -> (date: Date, power: Double)? in
            guard let date = position.date.flatMap(DomainDateParser.date(from:)),
                  let power = position.power
            else {
                return nil
            }
            return (date, Double(power))
        }
        .sorted { $0.date < $1.date }

        guard samples.count >= 2 else {
            return nil
        }

        let sampleDuration = samples.last!.date.timeIntervalSince(samples.first!.date)
        guard sampleDuration > 0 else { return nil }

        var tractionKWh = 0.0
        var regeneratedKWh = 0.0
        var integratedDuration: TimeInterval = 0
        var integratedSegmentCount = 0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let seconds = current.date.timeIntervalSince(previous.date)
            guard seconds > 0, seconds <= maximumSampleGap else {
                continue
            }
            let areas = energyAreas(startPower: previous.power, endPower: current.power, seconds: seconds)
            tractionKWh += areas.traction / 3600
            regeneratedKWh += areas.regenerated / 3600
            integratedDuration += seconds
            integratedSegmentCount += 1
        }

        let netKWh = tractionKWh - regeneratedKWh
        guard integratedSegmentCount > 0,
              tractionKWh.isFinite,
              regeneratedKWh.isFinite,
              netKWh.isFinite
        else {
            return nil
        }
        return DriveEnergyEstimate(
            tractionKWh: tractionKWh,
            regeneratedKWh: regeneratedKWh,
            netKWh: netKWh,
            coverage: min(max(integratedDuration / sampleDuration, 0), 1),
            integratedDuration: integratedDuration,
            sampleDuration: sampleDuration
        )
    }

    private static func energyAreas(startPower: Double, endPower: Double, seconds: TimeInterval) -> (traction: Double, regenerated: Double) {
        if startPower >= 0, endPower >= 0 {
            return ((startPower + endPower) / 2 * seconds, 0)
        }
        if startPower <= 0, endPower <= 0 {
            return (0, -(startPower + endPower) / 2 * seconds)
        }

        let zeroFraction = abs(startPower) / (abs(startPower) + abs(endPower))
        let firstDuration = seconds * zeroFraction
        let secondDuration = seconds - firstDuration
        if startPower > 0 {
            return (startPower * firstDuration / 2, -endPower * secondDuration / 2)
        }
        return (endPower * secondDuration / 2, -startPower * firstDuration / 2)
    }

    private static func elevationChange(_ elevations: [Int]) -> (gain: Int?, loss: Int?) {
        guard elevations.count >= 2 else {
            return (nil, nil)
        }

        var gain = 0
        var loss = 0
        for index in 1..<elevations.count {
            let diff = elevations[index] - elevations[index - 1]
            if diff > 0 {
                gain += diff
            } else {
                loss += -diff
            }
        }
        return (gain, loss)
    }
}
