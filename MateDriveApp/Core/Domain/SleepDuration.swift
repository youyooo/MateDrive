import Foundation

public struct SleepInterval: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
}

public enum SleepDurationPeriod: String, CaseIterable, Identifiable, Sendable {
    case sinceCharge, today, week, month

    public var id: String { rawValue }
}

public struct SleepDurationSummary: Equatable, Sendable {
    public let period: SleepDurationPeriod
    public let duration: TimeInterval?
    public let isAvailable: Bool
}

public enum SleepDurationCalculator {
    public static func currentDuration(state: String?, stateSince: Date?, now: Date) -> TimeInterval? {
        guard state?.lowercased() == "asleep", let stateSince, stateSince <= now else { return nil }
        return now.timeIntervalSince(stateSince)
    }

    public static func total(intervals: [SleepInterval], from start: Date, to end: Date) -> TimeInterval {
        guard start < end else { return 0 }

        let clipped = intervals.compactMap { interval -> SleepInterval? in
            let lower = max(interval.start, start)
            let upper = min(interval.end, end)
            return lower < upper ? SleepInterval(start: lower, end: upper) : nil
        }.sorted { $0.start < $1.start }

        var merged: [SleepInterval] = []
        for interval in clipped {
            guard let last = merged.last, interval.start <= last.end else {
                merged.append(interval)
                continue
            }
            merged[merged.count - 1] = SleepInterval(
                start: last.start,
                end: max(last.end, interval.end)
            )
        }

        return merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
}
