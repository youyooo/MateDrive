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

    func testPeriodCasesAndCalendarBoundaries() {
        XCTAssertEqual(SleepDurationPeriod.allCases, [.sinceCharge, .today, .week, .month])
        XCTAssertEqual(SleepDurationPeriod.today.id, "today")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-01-14T15:45:00Z")
        XCTAssertEqual(calendar.startOfDay(for: now), date("2026-01-14T00:00:00Z"))
        XCTAssertEqual(calendar.dateInterval(of: .weekOfYear, for: now)?.start, date("2026-01-11T00:00:00Z"))
        XCTAssertEqual(calendar.dateInterval(of: .month, for: now)?.start, date("2026-01-01T00:00:00Z"))
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
