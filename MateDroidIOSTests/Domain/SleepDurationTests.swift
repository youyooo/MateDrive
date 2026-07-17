import Foundation
import XCTest
@testable import MateDroidIOS

final class SleepDurationTests: XCTestCase {
    func testCurrentSleepRequiresAsleepState() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            SleepDurationCalculator.currentDuration(
                state: "asleep",
                stateSince: Date(timeIntervalSince1970: 6_400),
                now: now
            ),
            3_600
        )
        XCTAssertNil(SleepDurationCalculator.currentDuration(
            state: "offline",
            stateSince: now.addingTimeInterval(-600),
            now: now
        ))
        XCTAssertNil(SleepDurationCalculator.currentDuration(
            state: "unknown",
            stateSince: now.addingTimeInterval(-600),
            now: now
        ))
        XCTAssertNil(SleepDurationCalculator.currentDuration(
            state: "parking",
            stateSince: now.addingTimeInterval(-600),
            now: now
        ))
    }

    func testFutureSleepStartIsRejected() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertNil(SleepDurationCalculator.currentDuration(
            state: "asleep",
            stateSince: now.addingTimeInterval(1),
            now: now
        ))
    }

    func testTotalClipsIntervalsAndDoesNotDoubleCountOverlaps() {
        let intervals = [
            SleepInterval(start: date("2026-01-01T23:30:00Z"), end: date("2026-01-02T01:30:00Z")),
            SleepInterval(start: date("2026-01-02T00:30:00Z"), end: date("2026-01-02T02:00:00Z"))
        ]

        XCTAssertEqual(
            SleepDurationCalculator.total(
                intervals: intervals,
                from: date("2026-01-02T00:00:00Z"),
                to: date("2026-01-02T01:00:00Z")
            ),
            3_600
        )
    }

    func testTotalRejectsEmptyAndBackwardsRanges() {
        let interval = SleepInterval(start: date("2026-01-01T00:00:00Z"), end: date("2026-01-01T01:00:00Z"))

        XCTAssertEqual(SleepDurationCalculator.total(intervals: [interval], from: interval.start, to: interval.start), 0)
        XCTAssertEqual(SleepDurationCalculator.total(intervals: [interval], from: interval.end, to: interval.start), 0)
    }

    func testPeriodCases() {
        XCTAssertEqual(SleepDurationPeriod.allCases, [.sinceCharge, .today, .week, .month])
        XCTAssertEqual(SleepDurationPeriod.today.id, "today")
    }

    func testTotalUsesLocalDayBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = date("2026-01-14T20:00:00Z")
        let start = calendar.startOfDay(for: now)
        let end = date("2026-01-15T08:00:00Z")
        let intervals = [
            SleepInterval(start: date("2026-01-14T07:00:00Z"), end: date("2026-01-14T09:00:00Z")),
            SleepInterval(start: date("2026-01-14T10:00:00Z"), end: date("2026-01-14T11:00:00Z"))
        ]

        XCTAssertEqual(SleepDurationCalculator.total(intervals: intervals, from: start, to: end), 7_200)
    }

    func testTotalUsesISO8601MondayWeekBoundary() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date("2026-01-14T12:00:00Z"))!.start
        let intervals = [
            SleepInterval(start: date("2026-01-11T23:00:00Z"), end: date("2026-01-12T01:00:00Z")),
            SleepInterval(start: date("2026-01-12T02:00:00Z"), end: date("2026-01-12T04:00:00Z"))
        ]

        XCTAssertEqual(SleepDurationCalculator.total(
            intervals: intervals,
            from: weekStart,
            to: date("2026-01-19T00:00:00Z")
        ), 10_800)
    }

    func testTotalUsesMonthBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthStart = calendar.dateInterval(of: .month, for: date("2026-01-14T12:00:00Z"))!.start
        let intervals = [
            SleepInterval(start: date("2025-12-31T23:00:00Z"), end: date("2026-01-01T01:00:00Z")),
            SleepInterval(start: date("2026-01-02T02:00:00Z"), end: date("2026-01-02T04:00:00Z"))
        ]

        XCTAssertEqual(SleepDurationCalculator.total(
            intervals: intervals,
            from: monthStart,
            to: date("2026-02-01T00:00:00Z")
        ), 10_800)
    }

    func testTotalUsesSinceChargeBoundary() {
        let sinceCharge = date("2026-01-10T12:00:00Z")
        let intervals = [
            SleepInterval(start: date("2026-01-10T11:00:00Z"), end: date("2026-01-10T13:00:00Z")),
            SleepInterval(start: date("2026-01-10T14:00:00Z"), end: date("2026-01-10T15:00:00Z"))
        ]

        XCTAssertEqual(SleepDurationCalculator.total(
            intervals: intervals,
            from: sinceCharge,
            to: date("2026-01-10T16:00:00Z")
        ), 7_200)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
