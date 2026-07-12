import Foundation

public enum DriveChartHeaderPresentation {
    public static func valueText(
        kind: DriveChartKind,
        positions: [DrivePosition],
        units: UnitPreferences?,
        sourcePressureUnit: String? = nil
    ) -> String? {
        let samples = DriveChartSampleBuilder.samples(
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: sourcePressureUnit
        )
        guard !samples.isEmpty else { return nil }

        let value: Double
        switch kind {
        case .battery:
            guard let latest = samples.max(by: { $0.date < $1.date }) else { return nil }
            value = latest.value
        case .power:
            value = samples.map { abs($0.value) }.max() ?? 0
        default:
            value = samples.map(\.value).max() ?? 0
        }

        switch kind {
        case .speed:
            return "\(whole(value)) \(units?.isImperial == true ? "mph" : "km/h")"
        case .power:
            return "\(whole(value)) kW"
        case .battery:
            return "\(whole(value))%"
        case .elevation:
            return "\(whole(value)) \(units?.isImperial == true ? "ft" : "m")"
        case .temperature:
            return "\(compact(value))°\(units?.isImperial == true ? "F" : "C")"
        case .tirePressure:
            return "\(String(format: "%.2f", value)) \(MateDroidUnitFormatter.pressureUnit(units: units))"
        }
    }

    private static func whole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    private static func compact(_ value: Double) -> String {
        value.rounded() == value ? whole(value) : String(format: "%.1f", value)
    }
}

public enum DriveChartScale {
    public static func domain(kind: DriveChartKind, samples: [DriveChartSample]) -> ClosedRange<Double>? {
        guard let minimum = samples.map(\.value).min(), let maximum = samples.map(\.value).max() else {
            return nil
        }

        switch kind {
        case .battery:
            return 0...100
        case .speed:
            return 0...max(10, roundedUpperBound(maximum, step: 10))
        case .power:
            let lower = min(0, minimum)
            let upper = max(0, maximum)
            let padding = max((upper - lower) * 0.12, 5)
            return (lower - padding)...(upper + padding)
        case .elevation:
            return padded(minimum: minimum, maximum: maximum, minimumPadding: 5)
        case .temperature:
            return padded(minimum: minimum, maximum: maximum, minimumPadding: 2)
        case .tirePressure:
            return padded(minimum: minimum, maximum: maximum, minimumPadding: 0.05)
        }
    }

    private static func padded(minimum: Double, maximum: Double, minimumPadding: Double) -> ClosedRange<Double> {
        let padding = max((maximum - minimum) * 0.15, minimumPadding)
        return (minimum - padding)...(maximum + padding)
    }

    private static func roundedUpperBound(_ value: Double, step: Double) -> Double {
        (value * 1.1 / step).rounded(.up) * step
    }
}

public enum DriveChartAxisPresentation {
    public static func interiorDates(samples: [DriveChartSample]) -> [Date] {
        guard let first = samples.map(\.date).min(), let last = samples.map(\.date).max() else {
            return []
        }
        let duration = last.timeIntervalSince(first)
        guard duration > 0 else { return [first] }
        return [
            first.addingTimeInterval(duration / 3),
            first.addingTimeInterval(duration * 2 / 3)
        ]
    }
}
