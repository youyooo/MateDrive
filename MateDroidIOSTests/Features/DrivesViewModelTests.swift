import XCTest
@testable import MateDroidIOS

@MainActor
final class DrivesViewModelTests: XCTestCase {
    func testDriveFiltersUseAppLanguageForDisplayTitles() {
        XCTAssertEqual(DriveDateFilter.allTime.title(language: .chinese), "全部")
        XCTAssertEqual(DriveDateFilter.today.title(language: .chinese), "今天")
        XCTAssertEqual(DriveDateFilter.lastYear.title(language: .chinese), "一年")
        XCTAssertEqual(DriveDistanceFilter.all.title(language: .chinese), "全部")
        XCTAssertEqual(DriveDistanceFilter.commute.title(language: .chinese), "通勤")
        XCTAssertEqual(DriveDistanceFilter.dayTrip.title(language: .chinese), "短途")
        XCTAssertEqual(DriveDistanceFilter.roadTrip.title(language: .chinese), "长途")

        XCTAssertEqual(DriveDateFilter.allTime.title(language: .english), "All Time")
        XCTAssertEqual(DriveDistanceFilter.roadTrip.title(language: .english), "Road Trip")
        XCTAssertEqual(DriveDateFilter.lastYear.title(language: .german), "Jahr")
        XCTAssertEqual(DriveDistanceFilter.commute.title(language: .spanish), "Trayecto diario")
        XCTAssertEqual(DriveDistanceFilter.dayTrip.title(language: .italian), "Gita giornaliera")
        XCTAssertEqual(DriveDistanceFilter.roadTrip.title(language: .catalan), "Viatge per carretera")
    }

    func testDrivesViewModelHidesShortDrivesWhenSettingIsOff() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(driveId: 1, distance: 0.9, durationMin: 10),
            .fixture(driveId: 2, distance: 14.0, durationMin: 20)
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: false,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [2])
        XCTAssertEqual(viewModel.state.summary.totalDrives, 2)
    }

    func testDistanceFilterUsesAndroidDriveCategories() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(driveId: 1, distance: 9.9, durationMin: 10),
            .fixture(driveId: 2, distance: 10.0, durationMin: 15),
            .fixture(driveId: 3, distance: 100.0, durationMin: 60)
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)
        viewModel.setDistanceFilter(.dayTrip)

        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [2])
        XCTAssertEqual(viewModel.state.summary.totalDistanceKm, 10.0)

        viewModel.setDistanceFilter(.roadTrip)
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [3])
    }

    func testSummaryCalculatesDistanceDurationSpeedAndEfficiency() async throws {
        let store = FakeDriveSummaryProvider(items: [
            .fixture(driveId: 1, distance: 20, durationMin: 30, speedMax: 80, efficiency: 180, efficiencySource: .api),
            .fixture(driveId: 2, distance: 40, durationMin: 60, speedMax: 100, efficiency: 220, efficiencySource: .powerSamples)
        ])
        let viewModel = DrivesViewModel(
            store: store,
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalDistanceKm, 60)
        XCTAssertEqual(viewModel.state.summary.totalDurationMin, 90)
        XCTAssertEqual(viewModel.state.summary.maxSpeedKmh, 100)
        XCTAssertEqual(viewModel.state.summary.avgEfficiencyWhKm, 200)
        XCTAssertEqual(viewModel.state.summary.reconstructedEfficiencyCount, 1)
    }

    func testAPISummaryProviderEnrichesZeroEnergyFromDriveDetails() async throws {
        let provider = APIDriveSummaryProvider(api: MissingEnergyDriveAPI())

        let result = await provider.driveSummaries(carId: 1)
        let items = try result.successValue()
        let item = try XCTUnwrap(items.first)

        XCTAssertEqual(try XCTUnwrap(item.energyConsumedNet), 0.05, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(item.efficiency), 100, accuracy: 0.1)
        XCTAssertEqual(item.efficiencySource, .powerSamples)
    }

    func testAPISummaryProviderFallsBackToVehicleScopedCacheWhenAPIIsOffline() async throws {
        let cached = DriveSummaryItem(
            driveId: 42,
            carId: 1,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            distance: 21,
            durationMin: 30,
            startAddress: nil,
            endAddress: nil,
            speedMax: nil,
            speedAvg: nil,
            energyConsumedNet: 4.2,
            efficiency: 200,
            efficiencySource: .api,
            outsideTempAvg: nil
        )
        let provider = APIDriveSummaryProvider(
            api: OfflineDriveAPI(),
            cache: FakeDriveSummaryCache(items: [cached])
        )

        let result = await provider.driveSummaries(carId: 1)
        let items = try result.successValue()

        XCTAssertEqual(items.map(\.driveId), [42])
        XCTAssertEqual(items.first?.energyConsumedNet, 4.2)
        XCTAssertEqual(items.first?.isCached, true)

        let viewModel = DrivesViewModel(store: provider, showShortEntries: true, initialState: DrivesState(dateFilter: .allTime))
        await viewModel.load(carId: 1)
        XCTAssertTrue(viewModel.state.isUsingCachedData)
    }

    func testSummaryItemMarksServerEfficiencyAsDirectData() {
        let item = DriveSummaryItem(
            data: DriveData(driveId: 1, distance: 10, durationMin: 20, consumptionNet: 168),
            carId: 1
        )

        XCTAssertEqual(item.efficiency, 168)
        XCTAssertEqual(item.efficiencySource, .api)
    }

    func testDriveSummaryPreservesMissingDistanceAndDurationAndReportsCoverage() async {
        let items = [
            DriveSummaryItem(data: DriveData(driveId: 1, startDate: "2026-07-01T08:00:00Z", distance: 20, durationMin: 30), carId: 1),
            DriveSummaryItem(data: DriveData(driveId: 2, startDate: "2026-07-02T08:00:00Z", distance: nil, durationMin: nil), carId: 1)
        ]
        let viewModel = DrivesViewModel(
            store: FakeDriveSummaryProvider(items: items),
            showShortEntries: true,
            initialState: DrivesState(dateFilter: .allTime)
        )

        await viewModel.load(carId: 1)

        XCTAssertNil(items[1].distance)
        XCTAssertNil(items[1].durationMin)
        XCTAssertEqual(viewModel.state.summary.totalDistanceKm, 20)
        XCTAssertEqual(viewModel.state.summary.distanceRecordCount, 1)
        XCTAssertFalse(viewModel.state.summary.distanceIsComplete)
        XCTAssertEqual(viewModel.state.summary.totalDurationMin, 30)
        XCTAssertEqual(viewModel.state.summary.durationRecordCount, 1)
        XCTAssertFalse(viewModel.state.summary.durationIsComplete)
        XCTAssertEqual(DrivesPresentation.distanceText(nil, isComplete: false, units: .metric), "--")
        XCTAssertEqual(DrivesPresentation.distanceText(20, isComplete: false, units: .metric), "≥20.0 km")
        XCTAssertEqual(DrivesPresentation.durationText(30, isComplete: false, language: .chinese), "≥30分钟")
        XCTAssertEqual(viewModel.state.rows.map(\.driveId), [2, 1])

        viewModel.setDistanceFilter(.commute)
        XCTAssertTrue(viewModel.state.rows.isEmpty)
    }
}

private struct MissingEnergyDriveAPI: DriveAPIProviding {
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success([
            DriveData(
                driveId: 10,
                carId: 1,
                startDate: "2026-07-01T08:00:00Z",
                endDate: "2026-07-01T08:00:20Z",
                distance: 0.5,
                durationMin: 1,
                energyConsumedNet: 0,
                consumptionNet: 0
            )
        ])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .success(DriveDetail(
            driveId: 10,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:00:20Z",
            odometerDetails: DriveOdometerDetails(distance: 0.5),
            durationMin: 1,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", power: 18),
                DrivePosition(date: "2026-07-01T08:00:10Z", power: 18),
                DrivePosition(date: "2026-07-01T08:00:20Z", power: -18)
            ]
        ))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }
}

private struct OfflineDriveAPI: DriveAPIProviding {
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .failure(.network("offline"))
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .failure(.network("offline"))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .failure(.network("offline"))
    }
}

private struct FakeDriveSummaryCache: DriveSummaryCaching {
    let items: [DriveSummaryItem]

    func load(carId: Int) async -> [DriveSummaryItem] {
        items.filter { $0.carId == carId }
    }

    func save(_: [DriveSummaryItem], carId _: Int) async {}
}

private extension APIResult {
    func successValue() throws -> Value {
        switch self {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}

private struct FakeDriveSummaryProvider: DriveSummaryProviding {
    let items: [DriveSummaryItem]

    func driveSummaries(carId _: Int) async -> APIResult<[DriveSummaryItem]> {
        .success(items)
    }

    func driveUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(.metric)
    }
}

private extension DriveSummaryItem {
    static func fixture(
        driveId: Int,
        distance: Double,
        durationMin: Int,
        speedMax: Int? = nil,
        efficiency: Double? = nil,
        efficiencySource: DriveEnergySource = .unavailable
    ) -> DriveSummaryItem {
        DriveSummaryItem(
            driveId: driveId,
            carId: 1,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            distance: distance,
            durationMin: durationMin,
            startAddress: "Home",
            endAddress: "Work",
            speedMax: speedMax,
            speedAvg: nil,
            energyConsumedNet: nil,
            efficiency: efficiency,
            efficiencySource: efficiencySource,
            outsideTempAvg: nil
        )
    }
}
