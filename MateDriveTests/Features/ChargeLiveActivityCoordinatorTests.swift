import ActivityKit
import Foundation
import XCTest
@testable import MateDriveApp

final class ChargeLiveActivityCoordinatorTests: XCTestCase {
    func testAllowStartUsesStartOrUpdate() async {
        let manager = RecordingLiveActivityManager()
        let coordinator = ChargeLiveActivityCoordinator(manager: manager)

        await coordinator.reconcile(
            carId: 7,
            event: .charging(.fixture()),
            policy: .allowStart
        )

        let calls = await manager.recordedCalls()
        XCTAssertEqual(calls, [.startOrUpdate(carId: 7)])
    }

    func testExistingOnlyNeverStartsANewActivity() async {
        let manager = RecordingLiveActivityManager()
        let coordinator = ChargeLiveActivityCoordinator(manager: manager)

        await coordinator.reconcile(
            carId: 7,
            event: .charging(.fixture()),
            policy: .existingOnly
        )

        let calls = await manager.recordedCalls()
        XCTAssertEqual(calls, [.updateExisting(carId: 7)])
    }

    func testIdleEndsForBothPolicies() async {
        let manager = RecordingLiveActivityManager()
        let coordinator = ChargeLiveActivityCoordinator(manager: manager)
        let identifier = String(repeating: "a", count: 64)

        await coordinator.reconcile(
            carId: 7,
            event: .idle(vehicleIdentifier: identifier),
            policy: .allowStart
        )
        await coordinator.reconcile(
            carId: 7,
            event: .idle(vehicleIdentifier: nil),
            policy: .existingOnly
        )

        let calls = await manager.recordedCalls()
        XCTAssertEqual(calls, [
            .end(carId: 7, vehicleIdentifier: identifier),
            .end(carId: 7, vehicleIdentifier: nil)
        ])
    }

    func testIndeterminateDoesNothing() async {
        let manager = RecordingLiveActivityManager()
        let coordinator = ChargeLiveActivityCoordinator(manager: manager)

        await coordinator.reconcile(
            carId: 7,
            event: .indeterminate,
            policy: .allowStart
        )
        await coordinator.reconcile(
            carId: 7,
            event: .indeterminate,
            policy: .existingOnly
        )

        let calls = await manager.recordedCalls()
        XCTAssertEqual(calls, [])
    }
}

final class SystemChargeLiveActivityManagerTests: XCTestCase {
    private let firstIdentifier = String(repeating: "a", count: 64)
    private let secondIdentifier = String(repeating: "b", count: 64)

    func testExistingOnlyWithNoMatchingActivityDoesNotRequestOrUpdate() async {
        let gateway = RecordingChargeLiveActivityGateway()
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.updateExisting(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: firstIdentifier)
        )

        XCTAssertEqual(gateway.requestCount, 0)
        XCTAssertEqual(gateway.updatedActivityIDs, [])
    }

    func testExistingOnlyUpdatesTheExactCompositeIdentityWithoutRequesting() async {
        let gateway = RecordingChargeLiveActivityGateway(activities: [
            .init(id: "first", carID: 99, vehicleIdentifier: firstIdentifier),
            .init(id: "second", carID: 7, vehicleIdentifier: secondIdentifier),
            .init(id: "legacy", carID: 7, vehicleIdentifier: nil)
        ])
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.updateExisting(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: secondIdentifier)
        )
        await manager.updateExisting(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: nil)
        )
        await manager.updateExisting(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: String(repeating: "c", count: 64))
        )

        XCTAssertEqual(gateway.updatedActivityIDs, ["second", "legacy"])
        XCTAssertEqual(gateway.requestCount, 0)
    }

    func testBothUpdatePathsUseExactlyTwoMinuteStaleDate() async {
        let existingDate = Date(timeIntervalSince1970: 1_786_320_000)
        let requestedDate = Date(timeIntervalSince1970: 1_786_320_500)
        let gateway = RecordingChargeLiveActivityGateway(activities: [
            .init(id: "existing", carID: 7, vehicleIdentifier: firstIdentifier)
        ])
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.update(
            carId: 7,
            snapshot: makeSnapshot(
                vehicleIdentifier: firstIdentifier,
                updatedAt: existingDate
            )
        )
        await manager.update(
            carId: 7,
            snapshot: makeSnapshot(
                vehicleIdentifier: secondIdentifier,
                updatedAt: requestedDate
            )
        )

        XCTAssertEqual(
            gateway.updatedContents.map(\.staleDate),
            [existingDate.addingTimeInterval(120)]
        )
        XCTAssertEqual(
            gateway.requestedContents.map(\.staleDate),
            [requestedDate.addingTimeInterval(120)]
        )
    }

    func testUpdateExistingUsesExactlyTwoMinuteStaleDateForExactCompositeIdentity() async {
        let updatedAt = Date(timeIntervalSince1970: 1_786_321_234)
        let gateway = RecordingChargeLiveActivityGateway(activities: [
            .init(id: "exact", carID: 99, vehicleIdentifier: firstIdentifier),
            .init(id: "other-identity", carID: 7, vehicleIdentifier: secondIdentifier),
            .init(id: "other-car", carID: 8, vehicleIdentifier: String(repeating: "c", count: 64))
        ])
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.updateExisting(
            carId: 7,
            snapshot: makeSnapshot(
                vehicleIdentifier: firstIdentifier,
                updatedAt: updatedAt
            )
        )

        XCTAssertEqual(gateway.requestCount, 0)
        XCTAssertEqual(gateway.updatedActivityIDs, ["exact"])
        XCTAssertEqual(
            gateway.updatedContents.map(\.staleDate),
            [Date(timeIntervalSince1970: 1_786_321_354)]
        )
    }

    func testConcurrentStartOrUpdateRequestsOnceForTheSameCompositeIdentity() async {
        let gateway = RecordingChargeLiveActivityGateway()
        let manager = SystemChargeLiveActivityManager(gateway: gateway)
        let snapshot = makeSnapshot(vehicleIdentifier: firstIdentifier)

        async let first: Void = manager.update(carId: 7, snapshot: snapshot)
        async let second: Void = manager.update(carId: 7, snapshot: snapshot)
        _ = await (first, second)

        XCTAssertEqual(gateway.requestCount, 1)
        XCTAssertEqual(gateway.requestedVehicleIdentifiers, [firstIdentifier])
    }

    // Production break caught: a newly requested ActivityKit attribute payload persists the raw TeslaMate car ID.
    func testNewRequestEncodesOpaqueIdentityWithoutRawCarID() async throws {
        let gateway = RecordingChargeLiveActivityGateway()
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.update(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: firstIdentifier)
        )

        let attributes = try XCTUnwrap(gateway.requestedAttributes.first)
        let encoded = try JSONEncoder().encode(attributes)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["vehicleIdentifier"] as? String, firstIdentifier)
        XCTAssertNil(object["carID"])
    }

    func testStartOrUpdateKeepsDifferentCompositeIdentitiesIsolated() async {
        let gateway = RecordingChargeLiveActivityGateway(activities: [
            .init(id: "first", carID: 7, vehicleIdentifier: firstIdentifier)
        ])
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.update(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: secondIdentifier)
        )

        XCTAssertEqual(gateway.updatedActivityIDs, [])
        XCTAssertEqual(gateway.requestedVehicleIdentifiers, [secondIdentifier])
    }

    func testIdentityAwareEndOnlyEndsTheExactIdentityAndLegacyConvenienceEndsNil() async {
        let gateway = RecordingChargeLiveActivityGateway(activities: [
            .init(id: "first", carID: 7, vehicleIdentifier: firstIdentifier),
            .init(id: "second", carID: 99, vehicleIdentifier: secondIdentifier),
            .init(id: "legacy", carID: 7, vehicleIdentifier: nil),
            .init(id: "other-car", carID: 7, vehicleIdentifier: firstIdentifier)
        ])
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.end(carId: 7, vehicleIdentifier: secondIdentifier)
        await manager.end(carId: 7)

        XCTAssertEqual(gateway.endedActivityIDs, ["second", "legacy"])
    }

    func testStartWithoutOpaqueIdentityDoesNotRequestANewActivity() async {
        let gateway = RecordingChargeLiveActivityGateway()
        let manager = SystemChargeLiveActivityManager(gateway: gateway)

        await manager.update(
            carId: 7,
            snapshot: makeSnapshot(vehicleIdentifier: nil)
        )

        XCTAssertEqual(gateway.requestCount, 0)
    }

    // Production break caught: the request path treats any nonnil string as an opaque vehicle identity.
    func testNewRequestRejectsEveryNoncanonicalVehicleIdentifier() async {
        let invalidIdentifiers = [
            "7",
            String(repeating: "g", count: 64),
            "https://teslamate.example",
            String(repeating: "A", count: 64)
        ]

        for invalidIdentifier in invalidIdentifiers {
            let gateway = RecordingChargeLiveActivityGateway()
            let manager = SystemChargeLiveActivityManager(gateway: gateway)

            await manager.update(
                carId: 7,
                snapshot: makeSnapshot(vehicleIdentifier: invalidIdentifier)
            )

            XCTAssertEqual(
                gateway.requestCount,
                0,
                "Requested an activity for a noncanonical identifier: \(invalidIdentifier)"
            )
        }
    }

    private func makeSnapshot(
        vehicleIdentifier: String?,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> ChargeLiveActivitySnapshot {
        ChargeLiveActivitySnapshot(
            carName: "Model 3",
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: false,
            isCharging: true,
            vehicleIdentifier: vehicleIdentifier,
            displayLanguage: .english,
            quality: .complete,
            updatedAt: updatedAt
        )
    }
}

private actor RecordingLiveActivityManager: ChargeLiveActivityManaging {
    enum Call: Equatable, Sendable {
        case startOrUpdate(carId: Int)
        case updateExisting(carId: Int)
        case end(carId: Int, vehicleIdentifier: String?)
    }

    private var calls: [Call] = []

    func update(carId: Int, snapshot _: ChargeLiveActivitySnapshot) async {
        calls.append(.startOrUpdate(carId: carId))
    }

    func updateExisting(carId: Int, snapshot _: ChargeLiveActivitySnapshot) async {
        calls.append(.updateExisting(carId: carId))
    }

    func end(carId: Int) async {
        calls.append(.end(carId: carId, vehicleIdentifier: nil))
    }

    func end(carId: Int, vehicleIdentifier: String?) async {
        calls.append(.end(carId: carId, vehicleIdentifier: vehicleIdentifier))
    }

    func recordedCalls() -> [Call] {
        calls
    }
}

private final class RecordingChargeLiveActivityGateway: ChargeLiveActivityGateway, @unchecked Sendable {
    struct RecordedContent: Equatable, Sendable {
        let state: ChargeLiveActivityAttributes.ContentState
        let staleDate: Date?
    }

    private struct State {
        var activities: [ChargeLiveActivityReference]
        var requestedVehicleIdentifiers: [String?] = []
        var requestedAttributes: [ChargeLiveActivityAttributes] = []
        var requestedContents: [RecordedContent] = []
        var updatedActivityIDs: [String] = []
        var updatedContents: [RecordedContent] = []
        var endedActivityIDs: [String] = []
    }

    private let lock = NSLock()
    private var state: State
    let areActivitiesEnabled = true

    init(activities: [ChargeLiveActivityReference] = []) {
        state = State(activities: activities)
    }

    var requestCount: Int {
        lock.withLock { state.requestedContents.count }
    }

    var requestedVehicleIdentifiers: [String?] {
        lock.withLock { state.requestedVehicleIdentifiers }
    }

    var requestedAttributes: [ChargeLiveActivityAttributes] {
        lock.withLock { state.requestedAttributes }
    }

    var requestedContents: [RecordedContent] {
        lock.withLock { state.requestedContents }
    }

    var updatedActivityIDs: [String] {
        lock.withLock { state.updatedActivityIDs }
    }

    var updatedContents: [RecordedContent] {
        lock.withLock { state.updatedContents }
    }

    var endedActivityIDs: [String] {
        lock.withLock { state.endedActivityIDs }
    }

    func activityReferences() -> [ChargeLiveActivityReference] {
        lock.withLock { state.activities }
    }

    func request(
        attributes: ChargeLiveActivityAttributes,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) throws {
        lock.withLock {
            state.requestedVehicleIdentifiers.append(attributes.vehicleIdentifier)
            state.requestedAttributes.append(attributes)
            state.requestedContents.append(.init(
                state: content.state,
                staleDate: content.staleDate
            ))
            state.activities.append(.init(
                id: "requested-\(state.requestedContents.count)",
                carID: attributes.carID,
                vehicleIdentifier: attributes.vehicleIdentifier
            ))
        }
    }

    func update(
        activityID: String,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) async {
        lock.withLock {
            state.updatedActivityIDs.append(activityID)
            state.updatedContents.append(.init(
                state: content.state,
                staleDate: content.staleDate
            ))
        }
    }

    func end(
        activityID: String,
        content _: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) async {
        lock.withLock {
            state.endedActivityIDs.append(activityID)
            state.activities.removeAll { $0.id == activityID }
        }
    }
}
