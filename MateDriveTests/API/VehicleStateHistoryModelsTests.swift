import XCTest
@testable import MateDriveApp

final class VehicleStateHistoryModelsTests: XCTestCase {
    func testDecodesStateHistoryEnvelope() throws {
        let json = #"{"data":{"states":[{"state":"asleep","start_date":"2026-07-17T00:00:00Z","end_date":"2026-07-17T02:00:00Z"}]}}"#

        let result = try JSONDecoder.teslamate.decode(
            VehicleStateHistoryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(result.intervals.count, 1)
        XCTAssertEqual(result.intervals[0].state, "asleep")
    }

    func testDecodesTopLevelStateHistoryArray() throws {
        let json = #"[{"state":"online","start_date":"2026-07-17T00:00:00Z","end_date":null}]"#

        let result = try JSONDecoder.teslamate.decode(
            VehicleStateHistoryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(result.intervals.map(\.state), ["online"])
        XCTAssertNil(result.intervals[0].endDate)
    }

    func testRejectsObjectEnvelopesWithoutStatesArray() {
        for json in [#"{}"#, #"{"data":{}}"#] {
            XCTAssertThrowsError(
                try JSONDecoder.teslamate.decode(
                    VehicleStateHistoryResponse.self,
                    from: Data(json.utf8)
                ),
                "JSON: \(json)"
            )
        }
    }

    func testConvertsOnlyValidAsleepIntervalsToSleepIntervals() throws {
        let json = #"[{"state":"asleep","start_date":"2026-07-17T00:00:00Z","end_date":null},{"state":"online","start_date":"2026-07-17T00:00:00Z","end_date":"2026-07-17T01:00:00Z"},{"state":"asleep","start_date":"not-a-date","end_date":"2026-07-17T01:00:00Z"}]"#
        let result = try JSONDecoder.teslamate.decode(
            VehicleStateHistoryResponse.self,
            from: Data(json.utf8)
        )
        let now = Date(timeIntervalSince1970: 1_784_253_600)

        XCTAssertEqual(
            result.intervals[0].sleepInterval(now: now),
            SleepInterval(start: Date(timeIntervalSince1970: 1_784_246_400), end: now)
        )
        XCTAssertNil(result.intervals[1].sleepInterval(now: now))
        XCTAssertNil(result.intervals[2].sleepInterval(now: now))
    }
}
