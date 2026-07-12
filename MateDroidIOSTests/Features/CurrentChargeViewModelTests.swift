import XCTest
@testable import MateDroidIOS

@MainActor
final class CurrentChargeViewModelTests: XCTestCase {
    func testCurrentChargeLoadsActiveChargeAndStats() async throws {
        let api = FakeChargeAPI(
            currentChargeResult: .success(.active(.activeFixture)),
            statusResult: .success(.chargingStatus)
        )
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.chargeDetail?.chargeId, 9)
        XCTAssertEqual(viewModel.state.stats?.powerMax, 120)
        XCTAssertEqual(viewModel.state.stats?.batteryAdded, 30)
        XCTAssertTrue(viewModel.state.isDcCharge)
        XCTAssertEqual(viewModel.state.chronologicalPoints.map(\.batteryLevel), [40, 70])
        XCTAssertEqual(viewModel.state.chargeLimitSoc, 80)
        XCTAssertNotNil(viewModel.state.lastUpdatedAt)
        XCTAssertFalse(viewModel.state.isRefreshing)
    }

    func testCurrentChargeShowsNotChargingWhenNoActiveChargeAndStatusIdle() async throws {
        let api = FakeChargeAPI(
            currentChargeResult: .success(.noActiveCharge),
            statusResult: .success(.idleStatus)
        )
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertTrue(viewModel.state.isNotCharging)
        XCTAssertFalse(viewModel.state.isChargeStarting)
    }

    func testRefreshFromActiveToIdleClearsStaleChargeSession() async {
        let api = SequencedChargeAPI(
            currentChargeResults: [.success(.active(.activeFixture)), .success(.noActiveCharge)],
            statusResults: [.success(.chargingStatus), .success(.idleStatus)]
        )
        let viewModel = CurrentChargeViewModel(api: api)

        await viewModel.load(carId: 1)
        XCTAssertNotNil(viewModel.state.chargeDetail)

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.isNotCharging)
        XCTAssertNil(viewModel.state.chargeDetail)
        XCTAssertNil(viewModel.state.stats)
        XCTAssertTrue(viewModel.state.chronologicalPoints.isEmpty)
        XCTAssertNil(viewModel.state.timeToFullCharge)
        XCTAssertFalse(viewModel.state.isDcCharge)
    }

    func testDisconnectedStatusDoesNotExposeChargingOrSentinelLocationValues() {
        let status = CarStatus(
            carGeodata: CarGeodata(geofence: "", latitude: SyntheticCoordinates.zero.latitude, longitude: SyntheticCoordinates.zero.longitude),
            chargingDetails: ChargingDetails(pluggedIn: false, chargingState: "disconnected", chargerPhases: 0, chargerPower: 0)
        )

        XCTAssertFalse(status.isCharging)
        XCTAssertFalse(status.isDcCharging)
        XCTAssertNil(status.chargerPower)
        XCTAssertNil(status.geofence)
        XCTAssertNil(status.latitude)
        XCTAssertNil(status.longitude)
    }

    func testChronologicalSortUsesTimestampsInsteadOfBlindlyReversingSamples() {
        let early = ChargePoint(date: "2026-07-01T09:00:00Z", batteryLevel: 40)
        let middle = ChargePoint(date: "2026-07-01T09:10:00Z", batteryLevel: 55)
        let late = ChargePoint(date: "2026-07-01T09:20:00Z", batteryLevel: 70)

        XCTAssertEqual(
            CurrentChargeViewModel.chronological([early, middle, late]).map(\.batteryLevel),
            [40, 55, 70]
        )
        XCTAssertEqual(
            CurrentChargeViewModel.chronological([late, middle, early]).map(\.batteryLevel),
            [40, 55, 70]
        )
    }
}

private actor SequencedChargeAPI: ChargeAPIProviding {
    private var currentChargeResults: [APIResult<CurrentChargeOutcome>]
    private var statusResults: [APIResult<CarStatusPayload>]

    init(currentChargeResults: [APIResult<CurrentChargeOutcome>], statusResults: [APIResult<CarStatusPayload>]) {
        self.currentChargeResults = currentChargeResults
        self.statusResults = statusResults
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> { currentChargeResults.removeFirst() }
    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> { .failure(.emptyBody) }
    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> { statusResults.removeFirst() }
}

private final class FakeChargeAPI: ChargeAPIProviding, @unchecked Sendable {
    private let currentChargeResult: APIResult<CurrentChargeOutcome>
    private let statusResult: APIResult<CarStatusPayload>

    init(currentChargeResult: APIResult<CurrentChargeOutcome>, statusResult: APIResult<CarStatusPayload>) {
        self.currentChargeResult = currentChargeResult
        self.statusResult = statusResult
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func currentCharge(carId _: Int) async -> APIResult<CurrentChargeOutcome> {
        currentChargeResult
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        statusResult
    }
}

private extension ChargeDetail {
    static let activeFixture = ChargeDetail(
        chargeId: 9,
        startDate: "2026-07-01T09:00:00Z",
        chargeEnergyAdded: 28,
        chargeEnergyUsed: 28,
        durationMin: 20,
        batteryDetails: ChargeBatteryDetails(startBatteryLevel: 40, endBatteryLevel: 70),
        chargePoints: [
            ChargePoint(batteryLevel: 70, chargerDetails: ChargerDetails(chargerPower: 80, chargerVoltage: 390, chargerActualCurrent: 205, chargerPhases: 0), outsideTemp: 18),
            ChargePoint(batteryLevel: 40, chargerDetails: ChargerDetails(chargerPower: 120, chargerVoltage: 400, chargerActualCurrent: 300, chargerPhases: 0), outsideTemp: 17)
        ],
        isCharging: true
    )
}

private extension CarStatusPayload {
    static let chargingStatus = CarStatusPayload(
        status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: true, chargingState: "Charging", chargeLimitSoc: 80, chargerPhases: 0, timeToFullCharge: 0.5)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let idleStatus = CarStatusPayload(
        status: CarStatus(
            chargingDetails: ChargingDetails(pluggedIn: false, chargingState: "Disconnected")
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )
}
