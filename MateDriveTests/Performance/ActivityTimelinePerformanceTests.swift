import XCTest
@testable import MateDriveApp

@MainActor
final class ActivityTimelinePerformanceTests: XCTestCase {
    func testLoadingFiveHundredCachedSessionsStaysWithinBudget() async throws {
        let warmupStore = PerformanceSmartActivitySessionStore(sessions: [Self.session(0)])
        let warmupViewModel = ActivityTimelineViewModel(sessionStore: warmupStore)
        await warmupViewModel.load(carId: 1)

        let sessions = (0..<500).reversed().map(Self.session)
        let store = PerformanceSmartActivitySessionStore(sessions: sessions)
        let viewModel = ActivityTimelineViewModel(sessionStore: store)
        let clock = ContinuousClock()

        let duration = await clock.measure {
            await viewModel.load(carId: 1)
        }
        let networkRequestCount = await store.networkRequestCount()

        XCTAssertLessThan(duration, .milliseconds(100))
        XCTAssertEqual(viewModel.state.sessions.count, 500)
        XCTAssertEqual(networkRequestCount, 0)
    }

    private static func session(_ index: Int) -> SmartActivitySession {
        let start = Date(timeIntervalSince1970: 1_720_000_000 + Double(index * 300))
        return SmartActivitySession(
            id: "performance-session-\(index)",
            carId: 1,
            startDate: start,
            endDate: start.addingTimeInterval(180),
            placeKey: "place-\(index % 10)",
            latitude: SyntheticCoordinates.point(latitudeOffset: 0.2282).northing,
            longitude: SyntheticCoordinates.point(longitudeOffset: 0.9388).easting,
            geofenceID: nil,
            provisionalKind: .parking,
            classification: nil,
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: [],
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "source-\(index)",
            derivationFingerprint: "performance-fixture"
        )
    }
}

private actor PerformanceSmartActivitySessionStore: SmartActivitySessionStoring {
    private let values: [SmartActivitySession]
    private var requestCount = 0

    init(sessions: [SmartActivitySession]) {
        values = sessions
    }

    func sessions(carId: Int) async throws -> [SmartActivitySession] {
        guard carId == 1 else { return [] }
        return values
    }

    func session(carId: Int, sessionId: String) async throws -> SmartActivitySession? {
        values.first { $0.carId == carId && $0.id == sessionId }
    }

    func replace(carId _: Int, sessions _: [SmartActivitySession]) async throws {}
    func removeDerivedSessions() async throws {}

    func networkRequestCount() -> Int { requestCount }
}
