import XCTest
@testable import MateDriveApp

@MainActor
final class AnalyticalViewModelTests: XCTestCase {
    func testSoftwareUpdatesRestorePersistedHistoryWhenAPIIsOffline() async throws {
        let storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("software-updates-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let settings = StaticAnalyticsSettingsStore(
            settings: AppSettings(serverURL: "https://teslamate.example.com")
        )
        let expected = [
            UpdateData(
                updateId: 7,
                version: "2026.20.3 release",
                startDate: "2026-07-01T08:00:00Z"
            )
        ]
        let writer = SoftwareUpdatesViewModel(
            api: FakeAnalyticsAPI(updates: expected),
            settingsStore: settings,
            snapshotStore: SoftwareUpdateSnapshotStore(storageURL: storageURL)
        )

        await writer.load(carId: 1)

        let reader = SoftwareUpdatesViewModel(
            api: FakeAnalyticsAPI(updatesResult: .failure(.network("offline"))),
            settingsStore: settings,
            snapshotStore: SoftwareUpdateSnapshotStore(storageURL: storageURL)
        )
        await reader.load(carId: 1)

        XCTAssertFalse(reader.state.isLoading)
        XCTAssertNotNil(reader.state.errorMessage)
        XCTAssertEqual(reader.state.updates.map(\.id), [7])
        XCTAssertEqual(reader.state.updates.first?.version, "2026.20.3")
    }

    func testSoftwareUpdatesRepeatedEntryRestoresFilterAndFailedRefreshPreservesRows() async {
        let cache = VehiclePageStateCache<SoftwareUpdatesPageSnapshot>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let update = UpdateData(
            updateId: 7,
            version: "2026.20.3 release",
            startDate: "2026-07-01T08:00:00Z"
        )
        let initial = SoftwareUpdatesViewModel(
            api: FakeAnalyticsAPI(updates: [update]),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)
        initial.setFilter(months: 6)

        let reopened = SoftwareUpdatesViewModel(
            api: FakeAnalyticsAPI(updatesResult: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.filterMonths, 6)
        XCTAssertEqual(reopened.state.updates.map(\.id), [7])

        await reopened.load(carId: 1)

        XCTAssertEqual(reopened.state.updates.map(\.id), [7])
        XCTAssertNotNil(reopened.state.errorMessage)
    }

    func testSoftwareUpdatesOverlappingLoadsStartOneServerRequest() async {
        let api = SlowSoftwareUpdatesAPI()
        let viewModel = SoftwareUpdatesViewModel(api: api)

        async let first: Void = viewModel.load(carId: 1)
        async let second: Void = viewModel.load(carId: 1)
        _ = await (first, second)

        let updateRequestCount = await api.updateRequestCount
        XCTAssertEqual(updateRequestCount, 1)
    }

    func testSoftwareUpdatesCacheSuccessfulEmptyResultWithoutReopeningLoader() async {
        let cache = VehiclePageStateCache<SoftwareUpdatesPageSnapshot>()
        let key = VehiclePageCacheKey(
            serverURL: "https://teslamate.example.com",
            carId: 1
        )
        let initial = SoftwareUpdatesViewModel(
            api: FakeAnalyticsAPI(updates: []),
            cacheKey: key,
            stateCache: cache
        )

        await initial.load(carId: 1)

        let reopened = SoftwareUpdatesViewModel(
            api: FakeAnalyticsAPI(updatesResult: .failure(.network("offline"))),
            cacheKey: key,
            stateCache: cache
        )
        XCTAssertTrue(reopened.state.hasLoadedData)
        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertTrue(reopened.state.updates.isEmpty)
    }

    func testSoftwareUpdateSnapshotsAreIsolatedByServerAndVehicle() async {
        let store = SoftwareUpdateSnapshotStore()
        let snapshot = SoftwareUpdateSnapshot(updates: [UpdateData(updateId: 7, version: "2026.20.3")])

        await store.save(snapshot, serverURL: "https://one.example.com", carId: 1)

        let matching = await store.load(serverURL: "https://ONE.example.com ", carId: 1)
        let otherCar = await store.load(serverURL: "https://one.example.com", carId: 2)
        let otherServer = await store.load(serverURL: "https://two.example.com", carId: 1)
        XCTAssertEqual(matching, snapshot)
        XCTAssertNil(otherCar)
        XCTAssertNil(otherServer)
    }

    func testStatsUnitPresentationConvertsRatesWithoutRelabelingMetricValues() {
        XCTAssertEqual(StatsUnitPresentation.hardBrakingPer100(10, units: .metric), 10, accuracy: 0.0001)
        XCTAssertEqual(StatsUnitPresentation.hardBrakingPer100(10, units: .imperial), 16.09344, accuracy: 0.0001)
        XCTAssertEqual(StatsUnitPresentation.drainRate(10, units: .metric), "10.00 km/h")
        XCTAssertEqual(StatsUnitPresentation.drainRate(10, units: .imperial), "6.21 mi/h")
    }

    func testMileageViewModelBuildsYearMonthDayDrilldown() async throws {
        let api = FakeAnalyticsAPI(drives: [
            .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90),
            .fixture(id: 2, startDate: "2026-07-02T08:00:00Z", distance: 150, durationMin: 120)
        ])
        let viewModel = MileageViewModel(provider: APIMileageDataProvider(api: api))

        await viewModel.load(carId: 1)
        viewModel.selectYear(2026)
        viewModel.selectMonth("2026-07")

        XCTAssertEqual(viewModel.years.map(\.year), [2026])
        XCTAssertEqual(viewModel.years.first?.distance, 250)
        XCTAssertEqual(viewModel.state.months.first?.yearMonth, "2026-07")
        XCTAssertEqual(viewModel.state.days.map(\.date), ["2026-07-02", "2026-07-01"])
    }

    func testDatabaseMileageProviderUsesSyncedSummariesAndSkipsOpenCharges() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appending(path: "DatabaseMileageProviderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }
        let databaseProvider = LiveAppDatabaseProvider(applicationSupportBaseDirectory: baseDirectory)
        let database = try await databaseProvider.database()

        try await DriveSummaryStore(database: database).upsertAll([
            DriveSummaryRecord(
                driveId: 1,
                carId: 7,
                startDate: "2026-07-01T08:00:00Z",
                endDate: "2026-07-01T09:00:00Z",
                distance: 42,
                durationMin: 60,
                energyConsumedNet: 7.5,
                startBatteryLevel: 80,
                endBatteryLevel: 65
            )
        ])
        try await ChargeSummaryStore(database: database).upsertAll([
            ChargeSummaryRecord(
                chargeId: 10,
                carId: 7,
                startDate: "2026-07-01T10:00:00Z",
                endDate: "2026-07-01T11:00:00Z",
                chargeEnergyAdded: 18,
                cost: 9,
                startBatteryLevel: 65,
                endBatteryLevel: 80
            ),
            ChargeSummaryRecord(
                chargeId: 11,
                carId: 7,
                startDate: "2026-07-01T12:00:00Z",
                endDate: nil,
                chargeEnergyAdded: 2,
                cost: nil
            )
        ])

        let provider = DatabaseMileageDataProvider(
            databaseProvider: databaseProvider,
            settingsStore: StaticAnalyticsSettingsStore(settings: AppSettings()),
            snapshotStore: EmptyDashboardSnapshotStore()
        )

        guard case let .success(drives) = await provider.mileageDrives(carId: 7),
              case let .success(charges) = await provider.mileageCharges(carId: 7)
        else {
            return XCTFail("Expected local mileage summaries")
        }
        XCTAssertEqual(drives.count, 1)
        XCTAssertEqual(drives.first?.distance, 42)
        XCTAssertEqual(drives.first?.usableEnergyConsumedNet, 7.5)
        XCTAssertEqual(charges.map(\.id), [10])
        XCTAssertEqual(charges.first?.chargeEnergyAdded, 18)
    }

    func testMileageViewModelReconstructsMissingEnergyAndDoesNotPresentPartialTotal() async throws {
        let reconstructable = DriveDetail(
            driveId: 1,
            distance: 10,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", power: 10),
                DrivePosition(date: "2026-07-01T08:00:10Z", power: 10),
                DrivePosition(date: "2026-07-01T08:00:20Z", power: 10)
            ]
        )
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 10, durationMin: 1),
                .fixture(id: 2, startDate: "2026-07-02T08:00:00Z", distance: 10, durationMin: 1)
            ],
            driveDetails: [1: reconstructable]
        )
        let viewModel = MileageViewModel(provider: APIMileageDataProvider(api: api))

        await viewModel.load(carId: 1)
        viewModel.selectYear(2026)
        viewModel.selectMonth("2026-07")

        XCTAssertEqual(viewModel.state.years.first?.energy ?? 0, 10.0 / 180, accuracy: 0.0001)
        XCTAssertEqual(viewModel.state.years.first?.energyIsComplete, false)
        XCTAssertEqual(viewModel.state.months.first?.energyIsComplete, false)
        XCTAssertEqual(viewModel.state.days.first(where: { $0.date == "2026-07-01" })?.energy ?? 0, 10.0 / 180, accuracy: 0.0001)
        XCTAssertEqual(viewModel.state.days.first(where: { $0.date == "2026-07-01" })?.energyIsComplete, true)
        XCTAssertNil(viewModel.state.days.first(where: { $0.date == "2026-07-02" })?.energy)
    }

    func testAPIMileageProviderBoundsForegroundEnergyEnrichment() async {
        let drives = (1 ... 3).map { (id: Int) in
            DriveData(
                driveId: id,
                startDate: "2026-07-0\(id)T08:00:00Z",
                distance: 10,
                durationMin: 10
            )
        }
        let details = Dictionary(uniqueKeysWithValues: (1 ... 3).map { (id: Int) in
            (id, DriveDetail(driveId: id, energyConsumedNet: Double(id)))
        })
        let provider = APIMileageDataProvider(
            api: FakeAnalyticsAPI(drives: drives, driveDetails: details),
            maximumEnergyEnrichmentCount: 2
        )

        guard case let .success(enriched) = await provider.mileageDrives(carId: 1) else {
            return XCTFail("Expected mileage history")
        }

        XCTAssertEqual(enriched[0].usableEnergyConsumedNet, 1)
        XCTAssertEqual(enriched[1].usableEnergyConsumedNet, 2)
        XCTAssertNil(enriched[2].usableEnergyConsumedNet)
    }

    func testAPIMileageProviderSkipsMissingDriveIdentifierDuringEnergyEnrichment() async {
        let provider = APIMileageDataProvider(
            api: FakeAnalyticsAPI(
                drives: [
                    DriveData(
                        driveId: nil,
                        startDate: "2026-07-01T08:00:00Z",
                        distance: 10,
                        durationMin: 10
                    ),
                    DriveData(
                        driveId: 2,
                        startDate: "2026-07-02T08:00:00Z",
                        distance: 10,
                        durationMin: 10
                    )
                ],
                driveDetails: [2: DriveDetail(driveId: 2, energyConsumedNet: 2)]
            )
        )

        guard case let .success(enriched) = await provider.mileageDrives(carId: 1) else {
            return XCTFail("Expected mileage history")
        }

        XCTAssertNil(enriched[0].usableEnergyConsumedNet)
        XCTAssertEqual(enriched[1].usableEnergyConsumedNet, 2)
    }

    func testMileageDistanceTotalsMarkMissingRecordsInsteadOfTreatingThemAsZero() async {
        let api = FakeAnalyticsAPI(drives: [
            DriveData(driveId: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 60),
            DriveData(driveId: 2, startDate: "2026-07-02T08:00:00Z", distance: nil, durationMin: 60)
        ])
        let viewModel = MileageViewModel(provider: APIMileageDataProvider(api: api))

        await viewModel.load(carId: 1)
        viewModel.selectYear(2026)
        viewModel.selectMonth("2026-07")

        XCTAssertEqual(viewModel.state.years.first?.distance, 100)
        XCTAssertEqual(viewModel.state.years.first?.distanceIsComplete, false)
        XCTAssertEqual(viewModel.state.months.first?.distanceIsComplete, false)
        XCTAssertEqual(viewModel.state.days.first(where: { $0.date == "2026-07-01" })?.distanceIsComplete, true)
        XCTAssertEqual(viewModel.state.days.first(where: { $0.date == "2026-07-02" })?.distanceIsComplete, false)
        XCTAssertEqual(MileagePresentation.distanceText(100, isComplete: false, units: .metric), "≥100.0 km")
        XCTAssertEqual(MileagePresentation.distanceText(nil, isComplete: false, units: .metric), "--")
    }

    func testMileageViewModelUsesManualChargeCostOverridesInDrilldownTotals() async throws {
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90),
                .fixture(id: 2, startDate: "2026-07-02T08:00:00Z", distance: 150, durationMin: 120)
            ],
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 20, durationMin: 60, cost: 8),
                .fixture(id: 11, startDate: "2026-07-02T10:00:00Z", energy: 30, durationMin: 80, cost: nil)
            ]
        )
        let overrides = InMemoryAnalyticsChargeCostOverrideStore(overrides: [10: 12.5, 11: 9.75])
        let viewModel = MileageViewModel(provider: APIMileageDataProvider(api: api), costOverrideStore: overrides)

        await viewModel.load(carId: 1)
        viewModel.selectYear(2026)
        viewModel.selectMonth("2026-07")

        XCTAssertEqual(viewModel.state.years.first?.energyCost, 22.25)
        XCTAssertEqual(viewModel.state.years.first?.energyCostIsComplete, true)
        XCTAssertEqual(viewModel.state.years.first?.pricedChargeCount, 2)
        XCTAssertEqual(viewModel.state.years.first?.chargeCount, 2)
        XCTAssertEqual(viewModel.state.months.first?.energyCost, 22.25)
        XCTAssertEqual(viewModel.state.days.map(\.energyCost), [9.75, 12.5])
    }

    func testMileageCostTotalsMarkPartialCoverageInsteadOfTreatingMissingAsZero() async throws {
        let api = FakeAnalyticsAPI(
            drives: [.fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90)],
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 20, durationMin: 60, cost: 8),
                .fixture(id: 11, startDate: "2026-07-01T12:00:00Z", energy: 10, durationMin: 30, cost: nil)
            ]
        )
        let viewModel = MileageViewModel(provider: APIMileageDataProvider(api: api))

        await viewModel.load(carId: 1)
        viewModel.selectYear(2026)
        viewModel.selectMonth("2026-07")

        XCTAssertEqual(viewModel.state.years.first?.energyCost, 8)
        XCTAssertEqual(viewModel.state.years.first?.energyCostIsComplete, false)
        XCTAssertEqual(viewModel.state.years.first?.pricedChargeCount, 1)
        XCTAssertEqual(viewModel.state.years.first?.chargeCount, 2)
        XCTAssertEqual(viewModel.state.days.first?.energyCostIsComplete, false)
    }

    func testMileageViewModelUsesPricingRulesWhenManualCostIsMissing() async throws {
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90)
            ],
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 20, durationMin: 60, cost: nil, address: "Home Garage")
            ]
        )
        let settingsStore = StaticAnalyticsSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", chargeType: .ac, addressKeyword: "Home", pricePerKWh: 0.6)
        ]))
        let viewModel = MileageViewModel(provider: APIMileageDataProvider(api: api), settingsStore: settingsStore)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.years.first?.energyCost, 12)
    }

    func testMileageViewModelUsesCachedChargeSamplesForSegmentedPricing() async throws {
        let api = FakeAnalyticsAPI(
            drives: [.fixture(id: 1, startDate: "2026-07-01T08:00:00+08:00", distance: 100, durationMin: 90)],
            charges: [
                .fixture(
                    id: 10,
                    startDate: "2026-07-01T18:30:00+08:00",
                    endDate: "2026-07-01T19:30:00+08:00",
                    energy: 10,
                    energyUsed: 12,
                    durationMin: 60,
                    cost: nil,
                    address: "Home Garage"
                )
            ]
        )
        let settingsStore = StaticAnalyticsSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(
                id: "home",
                name: "Home",
                chargeType: .ac,
                addressKeyword: "Home",
                pricePerKWh: 9,
                timeSegments: [
                    ChargePricingTimeSegment(startMinuteOfDay: 18 * 60, endMinuteOfDay: 18 * 60 + 59, pricePerKWh: 1),
                    ChargePricingTimeSegment(startMinuteOfDay: 19 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 3)
                ]
            )
        ]))
        let aggregateStore = StaticChargePricingAggregateStore(aggregates: [
            10: ChargeDetailPricingAggregate(
                chargeId: 10,
                isDc: false,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T18:30:00+08:00", cumulativeEnergyAddedKWh: 0),
                    ChargePricingEnergySample(date: "2026-07-01T19:00:00+08:00", cumulativeEnergyAddedKWh: 8),
                    ChargePricingEnergySample(date: "2026-07-01T19:30:00+08:00", cumulativeEnergyAddedKWh: 10)
                ]
            )
        ])
        let viewModel = MileageViewModel(
            provider: APIMileageDataProvider(api: api),
            settingsStore: settingsStore,
            chargePricingAggregateStore: aggregateStore
        )

        await viewModel.load(carId: 1)
        viewModel.selectYear(2026)
        viewModel.selectMonth("2026-07")

        XCTAssertEqual(viewModel.state.years.first?.energyCost ?? 0, 16.8, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.months.first?.energyCost ?? 0, 16.8, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.days.first?.energyCost ?? 0, 16.8, accuracy: 0.001)
    }

    func testStatsViewModelBuildsDriveChargeAndACDCSummary() async throws {
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90, energyConsumedNet: 18),
                .fixture(id: 2, startDate: "2026-07-02T08:00:00Z", distance: 50, durationMin: 60, energyConsumedNet: 12)
            ],
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 8, durationMin: 120, cost: 3),
                .fixture(id: 11, startDate: "2026-07-02T10:00:00Z", energy: 40, durationMin: 30, cost: 12)
            ]
        )
        let viewModel = StatsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.availableYears, [2026])
        XCTAssertEqual(viewModel.state.summary.totalDistance, 150)
        XCTAssertEqual(viewModel.state.summary.totalChargeEnergy, 48)
        XCTAssertEqual(viewModel.state.summary.acCharges, 1)
        XCTAssertEqual(viewModel.state.summary.dcCharges, 1)
        XCTAssertEqual(viewModel.state.heatmapYear, 2026)
        XCTAssertEqual(viewModel.state.dailyActivity.count, 365)
        let activeDays = viewModel.state.dailyActivity.filter { $0.driveCount > 0 || $0.chargeCount > 0 }
        XCTAssertEqual(activeDays.count, 2)
        XCTAssertEqual(activeDays.map(\.distanceKm), [100, 50])
        XCTAssertEqual(activeDays.map(\.chargeEnergyKWh), [8, 40])
    }

    func testStatsUsesLocalHistoryProviderInsteadOfBlockingOnHistoryAPI() async {
        let api = FakeAnalyticsAPI(
            drives: [],
            charges: [],
            status: .failure(.network("status unavailable"))
        )
        let localHistory = StaticMileageDataProvider(
            drives: [.fixture(
                id: 1,
                startDate: "2026-07-01T08:00:00Z",
                distance: 42,
                durationMin: 60,
                energyConsumedNet: 7.5
            )],
            charges: [.fixture(
                id: 10,
                startDate: "2026-07-01T10:00:00Z",
                energy: 18,
                durationMin: 60,
                cost: 9
            )],
            units: UnitPreferences(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
        )
        let viewModel = StatsViewModel(api: api, historyProvider: localHistory)

        await viewModel.load(carId: 1)

        XCTAssertNil(viewModel.state.errorMessage)
        XCTAssertEqual(viewModel.state.summary.totalDistance, 42)
        XCTAssertEqual(viewModel.state.summary.totalChargeEnergy, 18)
        XCTAssertEqual(viewModel.state.units?.unitOfLength, "km")
    }

    func testStatsSummaryReportsIncompleteDistanceDurationAndChargeEnergyCoverage() {
        let summary = StatsViewModel.summary(
            drives: [
                DriveData(driveId: 1, distance: 100, durationMin: 60),
                DriveData(driveId: 2, distance: nil, durationMin: nil)
            ],
            charges: [
                ChargeData(chargeId: 10, chargeEnergyAdded: 8),
                ChargeData(chargeId: 11, chargeEnergyAdded: nil)
            ]
        )

        XCTAssertEqual(summary.totalDistance, 100)
        XCTAssertEqual(summary.totalDrivingMin, 60)
        XCTAssertEqual(summary.totalChargeEnergy, 8)
        XCTAssertEqual(summary.missingDriveDistanceCount, 1)
        XCTAssertEqual(summary.missingDriveDurationCount, 1)
        XCTAssertEqual(summary.missingChargeEnergyCount, 1)
        XCTAssertEqual(summary.longestDrive?.driveId, 1)
        XCTAssertEqual(StatsCoveragePresentation.valuePrefix(missingCount: 1), "≥")
        XCTAssertEqual(
            StatsCoveragePresentation.coverageText(known: 1, total: 2, nounKey: "drives", language: .chinese),
            "数据覆盖：1/2 次行程"
        )
    }

    func testStatsDailyActivityIncludesLeapDayAndAggregatesSameDayRecords() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let days = StatsViewModel.dailyActivity(
            year: 2024,
            drives: [
                .fixture(id: 1, startDate: "2024-02-29T08:00:00Z", distance: 10, durationMin: 10),
                .fixture(id: 2, startDate: "2024-02-29T18:00:00Z", distance: 15, durationMin: 15)
            ],
            charges: [.fixture(id: 3, startDate: "2024-02-29T20:00:00Z", energy: 22, durationMin: 60, cost: nil)],
            calendar: calendar
        )

        XCTAssertEqual(days.count, 366)
        let leapDay = try XCTUnwrap(days.first { calendar.component(.month, from: $0.date) == 2 && calendar.component(.day, from: $0.date) == 29 })
        XCTAssertEqual(leapDay.driveCount, 2)
        XCTAssertEqual(leapDay.distanceKm, 25)
        XCTAssertEqual(leapDay.chargeCount, 1)
        XCTAssertEqual(leapDay.chargeEnergyKWh, 22)
    }

    func testStatsViewModelPrefersServerTotalsAndKeepsLocalFallbackMetrics() async throws {
        let serverResponse = try JSONDecoder.teslamate.decode(
            TeslaMateServerStatsResponse.self,
            from: #"{"summary":{"totalDistanceKm":1010.08,"totalChargingCost":27.83,"avgConsumptionNet":188.73,"avgRegenCaptureRate":0.942,"totalHardBrakingCount":62}}"#.data(using: .utf8)!
        )
        let api = FakeAnalyticsAPI(
            drives: [.fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90)],
            charges: [.fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 8, durationMin: 120, cost: 3)],
            serverStats: .success(serverResponse)
        )
        let viewModel = StatsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.usesServerAllTimeSummary)
        XCTAssertEqual(viewModel.displayedTotalDistance, 1010.08)
        XCTAssertEqual(viewModel.displayedTotalChargeCost, 27.83)
        XCTAssertEqual(viewModel.state.summary.totalChargeEnergy, 8)
        XCTAssertEqual(viewModel.state.serverStats?.avgConsumptionNet, 188.73)

        viewModel.setFilter(.year(2026))
        XCTAssertFalse(viewModel.usesServerAllTimeSummary)
        XCTAssertEqual(viewModel.displayedTotalDistance, 100)
        XCTAssertEqual(viewModel.displayedTotalChargeCost, 3)
    }

    func testStatsViewModelUsesManualChargeCostOverridesInTotalCost() async throws {
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90)
            ],
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 8, durationMin: 120, cost: 3),
                .fixture(id: 11, startDate: "2026-07-02T10:00:00Z", energy: 40, durationMin: 30, cost: nil)
            ]
        )
        let overrides = InMemoryAnalyticsChargeCostOverrideStore(overrides: [10: 6.25, 11: 14])
        let viewModel = StatsViewModel(api: api, costOverrideStore: overrides)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalChargeCost, 20.25)
        XCTAssertEqual(viewModel.state.summary.pricedChargeCount, 2)
        XCTAssertEqual(viewModel.state.summary.manualChargeCostCount, 2)
        XCTAssertEqual(viewModel.state.summary.missingChargeCostCount, 0)
    }

    func testStatsLocalCostCoverageDoesNotTreatMissingChargeCostAsZero() async throws {
        let api = FakeAnalyticsAPI(charges: [
            .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 8, durationMin: 60, cost: 6),
            .fixture(id: 11, startDate: "2026-07-02T10:00:00Z", energy: 10, durationMin: 60, cost: nil)
        ])
        let viewModel = StatsViewModel(api: api)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalChargeCost, 6)
        XCTAssertEqual(viewModel.state.summary.pricedChargeCount, 1)
        XCTAssertEqual(viewModel.state.summary.missingChargeCostCount, 1)
        XCTAssertFalse(viewModel.chargeCostIsComplete)
    }

    func testStatsViewModelLocalOverridesTakePriorityOverServerAllTimeCost() async throws {
        let serverResponse = try JSONDecoder.teslamate.decode(
            TeslaMateServerStatsResponse.self,
            from: #"{"summary":{"totalDistanceKm":1010.08,"totalChargingCost":27.83}}"#.data(using: .utf8)!
        )
        let api = FakeAnalyticsAPI(
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 8, durationMin: 120, cost: 3),
                .fixture(id: 11, startDate: "2026-07-02T10:00:00Z", energy: 40, durationMin: 30, cost: 12)
            ],
            serverStats: .success(serverResponse)
        )
        let viewModel = StatsViewModel(
            api: api,
            costOverrideStore: InMemoryAnalyticsChargeCostOverrideStore(overrides: [10: 6.25])
        )

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.usesServerAllTimeSummary)
        XCTAssertTrue(viewModel.usesLocalChargeCostTotal)
        XCTAssertEqual(viewModel.displayedTotalChargeCost, 18.25)
        XCTAssertEqual(viewModel.displayedTotalDistance, 1010.08)
    }

    func testStatsViewModelUsesPricingRulesWhenManualCostIsMissing() async throws {
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90)
            ],
            charges: [
                .fixture(id: 10, startDate: "2026-07-01T10:00:00Z", energy: 20, durationMin: 60, cost: nil, address: "Home Garage"),
                .fixture(id: 11, startDate: "2026-07-02T10:00:00Z", energy: 10, durationMin: 30, cost: 4, address: "Mall Supercharger")
            ]
        )
        let settingsStore = StaticAnalyticsSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "home", name: "Home", chargeType: .ac, addressKeyword: "Home", pricePerKWh: 0.5),
            ChargePricingRule(id: "supercharger", name: "Supercharger", addressKeyword: "Supercharger", pricePerKWh: 2)
        ]))
        let viewModel = StatsViewModel(api: api, settingsStore: settingsStore)

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalChargeCost, 14)
        XCTAssertEqual(viewModel.state.summary.apiChargeCostCount, 1)
        XCTAssertEqual(viewModel.state.summary.pricingRuleChargeCostCount, 1)
    }

    func testStatsViewModelUsesCachedChargeSamplesForSegmentedPricing() async throws {
        let api = FakeAnalyticsAPI(
            drives: [
                .fixture(id: 1, startDate: "2026-07-01T08:00:00Z", distance: 100, durationMin: 90)
            ],
            charges: [
                .fixture(
                    id: 10,
                    startDate: "2026-07-01T18:30:00+08:00",
                    endDate: "2026-07-01T19:30:00+08:00",
                    energy: 10,
                    energyUsed: 12,
                    durationMin: 60,
                    cost: nil,
                    address: "Home Garage"
                )
            ]
        )
        let settingsStore = StaticAnalyticsSettingsStore(settings: AppSettings(chargePricingRules: [
            ChargePricingRule(
                id: "home",
                name: "Home",
                chargeType: .ac,
                addressKeyword: "Home",
                pricePerKWh: 9,
                timeSegments: [
                    ChargePricingTimeSegment(startMinuteOfDay: 18 * 60, endMinuteOfDay: 18 * 60 + 59, pricePerKWh: 1),
                    ChargePricingTimeSegment(startMinuteOfDay: 19 * 60, endMinuteOfDay: 23 * 60 + 59, pricePerKWh: 3)
                ]
            )
        ]))
        let aggregateStore = StaticChargePricingAggregateStore(aggregates: [
            10: ChargeDetailPricingAggregate(
                chargeId: 10,
                isDc: false,
                energySamples: [
                    ChargePricingEnergySample(date: "2026-07-01T18:30:00+08:00", cumulativeEnergyAddedKWh: 0),
                    ChargePricingEnergySample(date: "2026-07-01T19:30:00+08:00", cumulativeEnergyAddedKWh: 10)
                ]
            )
        ])
        let viewModel = StatsViewModel(
            api: api,
            settingsStore: settingsStore,
            chargePricingAggregateStore: aggregateStore
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.summary.totalChargeCost, 24, accuracy: 0.001)
    }

    func testStatsCombinesCompleteChargeAndParkingCosts() async throws {
        let charge = ChargeData(chargeId: 1, startDate: "2026-07-01T10:00:00Z", address: "Charger", chargeEnergyAdded: 10, cost: 12)
        let parkingResponse = try JSONDecoder.teslamate.decode(
            TeslaMateActivitiesResponse.self,
            from: Data(#"{"data":[{"id":1,"type":"park","startDate":"2026-07-01T12:00:00Z","startAddress":"Mall","durationMin":90}],"pagination":{"page":1,"limit":20}}"#.utf8)
        )
        let settings = AppSettings(currencyCode: "CNY", parkingFeeRules: [
            ParkingFeeRule(name: "Mall", addressKeyword: "Mall", billingIncrementMinutes: 60, hourlyRate: 5)
        ])
        let viewModel = StatsViewModel(
            api: FakeAnalyticsAPI(charges: [charge]),
            settingsStore: StaticAnalyticsSettingsStore(settings: settings),
            activityAPI: StatsActivityTestAPI(results: [.success(parkingResponse)])
        )

        await viewModel.load(carId: 1)

        XCTAssertTrue(viewModel.state.parkingCostAvailable)
        XCTAssertTrue(viewModel.state.parkingHistoryComplete)
        XCTAssertEqual(viewModel.state.parkingCost.totalCost, 10)
        XCTAssertEqual(viewModel.displayedTotalChargeCost, 12)
        XCTAssertEqual(viewModel.displayedTotalVehicleCost, 22)
        XCTAssertTrue(viewModel.chargeCostIsComplete)
    }

    func testStatsDoesNotClaimVehicleTotalWhenParkingIsUnmatched() async throws {
        let parkingResponse = try JSONDecoder.teslamate.decode(
            TeslaMateActivitiesResponse.self,
            from: Data(#"{"data":[{"id":1,"type":"park","startDate":"2026-07-01T12:00:00Z","startAddress":"Street","durationMin":90}],"pagination":{"page":1,"limit":20}}"#.utf8)
        )
        let settings = AppSettings(parkingFeeRules: [ParkingFeeRule(name: "Mall", addressKeyword: "Mall", hourlyRate: 5)])
        let viewModel = StatsViewModel(
            api: FakeAnalyticsAPI(),
            settingsStore: StaticAnalyticsSettingsStore(settings: settings),
            activityAPI: StatsActivityTestAPI(results: [.success(parkingResponse)])
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.parkingCost.unmatchedParkingCount, 1)
        XCTAssertNil(viewModel.displayedTotalVehicleCost)
    }

    func testWhereWasISelectsActiveDrivePositionNearestTarget() async throws {
        let drive = DriveData.fixture(id: 7, startDate: "2026-07-01T08:00:00Z", endDate: "2026-07-01T09:00:00Z", distance: 20, durationMin: 60)
        let earlyPoint = SyntheticCoordinates.point()
        let activePoint = SyntheticCoordinates.point(latitudeOffset: 1, longitudeOffset: 1)
        let detail = DriveDetail(
            driveId: 7,
            startDate: drive.startDate,
            endDate: drive.endDate,
            odometerDetails: DriveOdometerDetails(distance: 20),
            durationMin: 60,
            positions: [
                DrivePosition(date: "2026-07-01T08:05:00Z", latitude: earlyPoint.latitude, longitude: earlyPoint.longitude, speed: 10),
                DrivePosition(date: "2026-07-01T08:40:00Z", latitude: activePoint.latitude, longitude: activePoint.longitude, speed: 70)
            ]
        )
        let api = FakeAnalyticsAPI(drives: [drive], driveDetails: [7: detail])
        let viewModel = WhereWasIViewModel(api: api)

        await viewModel.load(carId: 1, timestamp: "2026-07-01T08:42:00Z")

        XCTAssertEqual(viewModel.state.carState, .driving)
        XCTAssertEqual(viewModel.state.driveId, 7)
        XCTAssertEqual(viewModel.state.speed, 70)
        XCTAssertEqual(viewModel.state.latitude, activePoint.latitude)
    }

    func testBatteryStatsUseHealthAPIAndCurrentStatus() {
        let health = BatteryHealth(maxRange: 500, currentRange: 450, maxCapacity: 82, currentCapacity: 74, ratedEfficiency: 155, batteryHealthPercentage: 90)
        let status = CarStatus(
            batteryDetails: BatteryDetails(batteryLevel: 50, usableBatteryLevel: 48, estBatteryRange: 210, ratedBatteryRange: 225, idealBatteryRange: 240)
        )

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: status,
            batteryRecordingStartOdometerKm: 10_000
        )

        XCTAssertEqual(stats.healthSource, .teslaMateHealth)
        XCTAssertTrue(stats.showsAbsoluteHealth)
        XCTAssertEqual(stats.lossKwh, 8)
        XCTAssertEqual(stats.lossPercent, 10)
        XCTAssertEqual(stats.rangeLoss, 50)
        XCTAssertEqual(stats.rangeAt100, 450)
    }

    func testBatteryHistorySeparatesLateRecordingChangeFromAbsoluteHealth() async throws {
        let history = try JSONDecoder.teslamate.decode(
            BatteryHistoryResponse.self,
            from: #"{"data":{"charts":{"capacity":[{"date":"2026-06-25","odometer":117512.8,"capacity":69.5274},{"date":"2026-07-10","odometer":118608.6,"capacity":69.0277}],"range":[{"date":"2026-06-25","odometer":117500.2,"range":476.9461},{"date":"2026-07-11","odometer":118651.3,"range":471.7621}]},"efficiency":{"value":14.6,"ready":true,"qualifying_charge_count":7}}}"#.data(using: .utf8)!
        ).data!
        let api = FakeAnalyticsAPI(
            health: .success(BatteryHealth(currentRange: 471.76, currentCapacity: 69.03, batteryHealthPercentage: 99)),
            status: .success(CarStatusPayload(status: CarStatus(batteryDetails: BatteryDetails(batteryLevel: 63, usableBatteryLevel: 62, ratedBatteryRange: 292.5)), units: Units(unitOfLength: "km"))),
            batteryHistory: .success(history)
        )
        let viewModel = BatteryViewModel(api: api)

        await viewModel.load(carId: 1)

        let summary = try XCTUnwrap(viewModel.state.historySummary)
        XCTAssertEqual(summary.startOdometerKm ?? 0, 117_500.2, accuracy: 0.01)
        XCTAssertEqual(summary.recordedDistanceKm ?? 0, 1_151.1, accuracy: 0.1)
        XCTAssertEqual(summary.capacityChangeKWh ?? 0, -0.4997, accuracy: 0.001)
        XCTAssertEqual(summary.rangeChangeKm ?? 0, -5.184, accuracy: 0.001)
        XCTAssertEqual(summary.recordedCapacityRetentionPercent ?? 0, 99.281, accuracy: 0.001)
        XCTAssertEqual(summary.recordedRangeRetentionPercent ?? 0, 98.913, accuracy: 0.001)
        XCTAssertEqual(summary.efficiencyWhKm, 146)
        XCTAssertEqual(viewModel.state.stats?.recordingStartOdometerKm ?? 0, 117_500.2, accuracy: 0.01)
        XCTAssertEqual(viewModel.state.stats?.confidence, .lateHistoryNeedsReference)
    }

    func testBatteryHistorySummaryUsesCapacityMedianAndRangeEndpointWindows() throws {
        let history = try JSONDecoder.teslamate.decode(
            BatteryHistoryResponse.self,
            from: #"{"data":{"charts":{"capacity":[{"date":"1","odometer":100,"capacity":80},{"date":"2","odometer":200,"capacity":60}],"capacity_median":[{"date":"1","odometer":100,"capacity":75},{"date":"2","odometer":200,"capacity":72}],"range":[{"date":"1","odometer":100,"range":500},{"date":"2","odometer":110,"range":480},{"date":"3","odometer":120,"range":490},{"date":"4","odometer":130,"range":470},{"date":"5","odometer":140,"range":460},{"date":"6","odometer":150,"range":450}]}}}"#.data(using: .utf8)!
        ).data!

        let summary = try XCTUnwrap(BatteryViewModel.historySummary(from: history))

        XCTAssertTrue(summary.capacityUsesMedian)
        XCTAssertEqual(summary.capacityStartKWh, 75)
        XCTAssertEqual(summary.capacityCurrentKWh, 72)
        XCTAssertEqual(summary.capacityChangeKWh, -3)
        XCTAssertEqual(summary.rangeSmoothingSampleCount, 2)
        XCTAssertEqual(summary.rangeStartKm, 490)
        XCTAssertEqual(summary.rangeCurrentKm, 455)
        XCTAssertEqual(summary.rangeChangeKm, -35)
        XCTAssertEqual(summary.quality.score, 25)
        XCTAssertEqual(summary.quality.level, .low)
        XCTAssertEqual(summary.quality.level.title(language: .chinese), "较低")
    }

    func testBatteryHistoryQualityRequiresBroadStableEvidenceForHighLevel() throws {
        let capacity = (0..<8).map { index in
            "{\"date\":\"2026-0\(index < 6 ? index + 1 : 6)-01\",\"odometer\":\(1000 + index * 900),\"capacity\":\(75.0 - Double(index) * 0.1)}"
        }.joined(separator: ",")
        let ranges = (0..<20).map { index in
            let month = index < 9 ? "0\(index + 1)" : "10"
            return "{\"date\":\"2026-\(month)-01\",\"odometer\":\(1000 + index * 400),\"range\":\(500 - index)}"
        }.joined(separator: ",")
        let json = """
        {"data":{"charts":{"capacity_median":[\(capacity)],"range":[\(ranges)]},"efficiency":{"ready":true,"qualifying_charge_count":5,"required_charge_count":2}}}
        """
        let history = try JSONDecoder.teslamate.decode(BatteryHistoryResponse.self, from: Data(json.utf8)).data!

        let summary = try XCTUnwrap(BatteryViewModel.historySummary(from: history))

        XCTAssertEqual(summary.quality.capacitySampleCount, 8)
        XCTAssertEqual(summary.quality.rangeSampleCount, 20)
        XCTAssertEqual(summary.startOdometerKm, 1_000)
        XCTAssertEqual(summary.endOdometerKm, 8_600)
        XCTAssertGreaterThanOrEqual(summary.quality.recordedDistanceKm, 5_000)
        XCTAssertGreaterThanOrEqual(summary.quality.recordedDays, 90)
        XCTAssertEqual(summary.quality.score, 100)
        XCTAssertEqual(summary.quality.level, .high)
        XCTAssertEqual(summary.quality.level.title(language: .chinese), "较高")
    }

    func testBatteryViewModelDetectsLateRecordingStartFromEarliestDrive() async throws {
        let health = BatteryHealth(
            maxRange: 476,
            currentRange: 471,
            maxCapacity: 69.5,
            currentCapacity: 68.9,
            ratedEfficiency: 146,
            batteryHealthPercentage: 99.1
        )
        let drive = DriveData(
            driveId: 1,
            carId: 1,
            startDate: "2026-06-25T08:00:00Z",
            endDate: "2026-06-25T08:30:00Z",
            durationMin: 30,
            odometerDetails: DriveOdometerDetails(odometerStart: 110_500, odometerEnd: 110_520, distance: 20)
        )
        let viewModel = BatteryViewModel(api: FakeAnalyticsAPI(health: .success(health), drives: [drive]))

        await viewModel.load(carId: 1)

        let stats = try XCTUnwrap(viewModel.state.stats)
        XCTAssertEqual(stats.recordingStartOdometerKm, 110_500)
        XCTAssertEqual(stats.confidence, .lateHistoryNeedsReference)
    }

    func testBatteryViewModelUsesLocalDriveHistoryForRecordingStart() async {
        let apiDrive = DriveData(
            driveId: 999,
            odometerDetails: DriveOdometerDetails(odometerStart: 200_000)
        )
        let localDrive = DriveData(
            driveId: 1,
            odometerDetails: DriveOdometerDetails(odometerStart: 110_500)
        )
        let viewModel = BatteryViewModel(
            api: FakeAnalyticsAPI(
                health: .success(BatteryHealth(currentRange: 471)),
                drives: [apiDrive]
            ),
            historyProvider: StaticMileageDataProvider(
                drives: [localDrive],
                charges: [],
                units: .metric
            )
        )

        await viewModel.load(carId: 1)

        XCTAssertEqual(viewModel.state.stats?.recordingStartOdometerKm, 110_500)
    }

    func testBatteryViewModelUsesOnlySelectedVehicleCalibration() async throws {
        let settingsStore = StaticAnalyticsSettingsStore(settings: AppSettings(
            lastSelectedCarId: 1,
            batteryCalibrations: [
                "1": BatteryCalibration(referenceRangeKm: 500, recordingStartOdometerKm: 110_000),
                "2": BatteryCalibration(referenceRangeKm: 430, recordingStartOdometerKm: 20_000)
            ]
        ))
        let health = BatteryHealth(currentRange: 400, ratedEfficiency: 150, batteryHealthPercentage: 99)
        let viewModel = BatteryViewModel(api: FakeAnalyticsAPI(health: .success(health)), settingsStore: settingsStore)

        await viewModel.load(carId: 2)

        XCTAssertEqual(viewModel.state.stats?.maxRangeNew, 430)
        XCTAssertEqual(viewModel.state.stats?.healthPercent, 93)
        XCTAssertEqual(viewModel.state.stats?.recordingStartOdometerKm, 20_000)
    }

    func testBatteryViewModelMovesAutomaticRecordingStartBackWhenEarlierHistoryAppears() async throws {
        let store = MutableAnalyticsSettingsStore(settings: AppSettings(
            batteryCalibrations: ["1": BatteryCalibration(recordingStartOdometerKm: 117_500)]
        ))
        let earlierDrive = DriveData(
            driveId: 1,
            carId: 1,
            odometerDetails: DriveOdometerDetails(odometerStart: 110_250, odometerEnd: 110_270, distance: 20)
        )
        let viewModel = BatteryViewModel(
            api: FakeAnalyticsAPI(health: .success(BatteryHealth(currentRange: 470)), drives: [earlierDrive]),
            settingsStore: store
        )

        await viewModel.load(carId: 1)
        let saved = await store.load()

        XCTAssertEqual(viewModel.state.stats?.recordingStartOdometerKm, 110_250)
        XCTAssertEqual(saved.batteryCalibration(for: 1).recordingStartOdometerKm, 110_250)
    }

    func testBatteryViewModelKeepsEarlierManualRecordingStartWhenDetectedHistoryIsLater() async throws {
        let store = MutableAnalyticsSettingsStore(settings: AppSettings(
            batteryCalibrations: ["1": BatteryCalibration(recordingStartOdometerKm: 110_000)]
        ))
        let laterDrive = DriveData(
            driveId: 1,
            carId: 1,
            odometerDetails: DriveOdometerDetails(odometerStart: 117_500, odometerEnd: 117_520, distance: 20)
        )
        let viewModel = BatteryViewModel(
            api: FakeAnalyticsAPI(health: .success(BatteryHealth(currentRange: 470)), drives: [laterDrive]),
            settingsStore: store
        )

        await viewModel.load(carId: 1)
        let saved = await store.load()

        XCTAssertEqual(viewModel.state.stats?.recordingStartOdometerKm, 110_000)
        XCTAssertEqual(saved.batteryCalibration(for: 1).recordingStartOdometerKm, 110_000)
    }

    func testBatteryRepeatedEntryRestoresStateAndFailedRefreshPreservesIt() async throws {
        let cache = VehiclePageStateCache<BatteryState>()
        let key = VehiclePageCacheKey(serverURL: "https://battery.example", carId: 1)
        let history = try JSONDecoder.teslamate.decode(
            BatteryHistoryResponse.self,
            from: Data(#"{"data":{"charts":{"capacity":[{"date":"2026-01-01","odometer":110000,"capacity":70},{"date":"2026-07-01","odometer":118000,"capacity":69}]}}}"#.utf8)
        ).data!
        let initial = BatteryViewModel(
            api: FakeAnalyticsAPI(
                health: .success(BatteryHealth(currentRange: 470, currentCapacity: 69)),
                batteryHistory: .success(history)
            ),
            cacheKey: key,
            stateCache: cache
        )
        await initial.load(carId: 1)
        let expectedStats = try XCTUnwrap(initial.state.stats)
        let expectedHistory = try XCTUnwrap(initial.state.historySummary)

        let reopened = BatteryViewModel(
            api: FakeAnalyticsAPI(
                health: .failure(.network("offline")),
                batteryHistory: .failure(.network("offline"))
            ),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertFalse(reopened.state.isLoading)
        XCTAssertEqual(reopened.state.stats, expectedStats)
        XCTAssertEqual(reopened.state.historySummary, expectedHistory)

        await reopened.load(carId: 1)

        XCTAssertEqual(reopened.state.stats, expectedStats)
        XCTAssertEqual(reopened.state.historySummary, expectedHistory)
        XCTAssertNotNil(reopened.state.errorMessage)
        XCTAssertFalse(reopened.state.isLoading)
    }

    func testBatteryOptionalHistoryFailureKeepsCachedTrendWhileRefreshingHealth() async throws {
        let cache = VehiclePageStateCache<BatteryState>()
        let key = VehiclePageCacheKey(serverURL: "https://battery.example", carId: 1)
        let history = try JSONDecoder.teslamate.decode(
            BatteryHistoryResponse.self,
            from: Data(#"{"data":{"charts":{"range":[{"date":"2026-01-01","odometer":110000,"range":480},{"date":"2026-07-01","odometer":118000,"range":470}]}}}"#.utf8)
        ).data!
        let initial = BatteryViewModel(
            api: FakeAnalyticsAPI(
                health: .success(BatteryHealth(currentRange: 470)),
                batteryHistory: .success(history)
            ),
            cacheKey: key,
            stateCache: cache
        )
        await initial.load(carId: 1)
        let expectedHistory = try XCTUnwrap(initial.state.historySummary)

        let refreshed = BatteryViewModel(
            api: FakeAnalyticsAPI(
                health: .success(BatteryHealth(currentRange: 468)),
                batteryHistory: .failure(.network("history offline"))
            ),
            cacheKey: key,
            stateCache: cache
        )
        await refreshed.load(carId: 1)

        XCTAssertEqual(refreshed.state.historySummary, expectedHistory)
        XCTAssertEqual(refreshed.state.stats?.maxRangeNow, 468)
        XCTAssertNil(refreshed.state.errorMessage)
    }

    func testBatteryOverlappingLoadsStartOneRefresh() async {
        let api = SlowBatteryAnalyticsAPI()
        let viewModel = BatteryViewModel(
            api: api,
            historyProvider: StaticMileageDataProvider(drives: [], charges: [], units: .metric)
        )

        async let first: Void = viewModel.load(carId: 1)
        async let second: Void = viewModel.load(carId: 1)
        _ = await (first, second)

        let counts = await api.requestCounts
        XCTAssertEqual(counts.health, 1)
        XCTAssertEqual(counts.status, 1)
        XCTAssertEqual(counts.history, 1)
    }

    func testBatteryDetectedRecordingStartUsesAtomicSettingsUpdate() async {
        let store = AtomicBatterySettingsStore(settings: AppSettings(
            appLanguage: .english,
            batteryCalibrations: ["1": BatteryCalibration(recordingStartOdometerKm: 117_500)]
        ))
        let earlierDrive = DriveData(
            driveId: 1,
            carId: 1,
            odometerDetails: DriveOdometerDetails(odometerStart: 110_250)
        )
        let viewModel = BatteryViewModel(
            api: FakeAnalyticsAPI(
                health: .success(BatteryHealth(currentRange: 470)),
                drives: [earlierDrive]
            ),
            settingsStore: store
        )

        await viewModel.load(carId: 1)

        let snapshot = await store.snapshot
        XCTAssertEqual(snapshot.settings.appLanguage, .english)
        XCTAssertEqual(
            snapshot.settings.batteryCalibration(for: 1).recordingStartOdometerKm,
            110_250
        )
        XCTAssertEqual(snapshot.atomicUpdateCount, 1)
        XCTAssertEqual(snapshot.wholeSaveCount, 0)
    }

    func testBatteryStatsNormalizeFractionalTeslaMateHealth() {
        let health = BatteryHealth(maxRange: 500, currentRange: 450, maxCapacity: 82, currentCapacity: 74, ratedEfficiency: 155, batteryHealthPercentage: 0.912)

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: nil,
            batteryRecordingStartOdometerKm: 10_000
        )

        XCTAssertEqual(stats.healthSource, .teslaMateHealth)
        XCTAssertEqual(stats.healthPercent, 91.2)
        XCTAssertEqual(stats.lossPercent ?? .nan, 8.8, accuracy: 0.001)
    }

    func testBatteryStatsUseManualReferenceRangeForLateTeslaMateHistory() {
        let health = BatteryHealth(maxRange: 448, currentRange: 440, maxCapacity: nil, currentCapacity: nil, ratedEfficiency: 155, batteryHealthPercentage: 98)
        let status = CarStatus(
            batteryDetails: BatteryDetails(batteryLevel: 50, usableBatteryLevel: 48, estBatteryRange: 205, ratedBatteryRange: 220, idealBatteryRange: 230)
        )

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: status,
            batteryReferenceRangeKm: 500,
            batteryRecordingStartOdometerKm: 110_000
        )

        XCTAssertEqual(stats.maxRangeNew, 500)
        XCTAssertEqual(stats.maxRangeNow, 440)
        XCTAssertEqual(stats.healthSource, .manualReference)
        XCTAssertEqual(stats.confidence, .calibratedLateHistory)
        XCTAssertEqual(stats.recordingStartOdometerKm, 110_000)
        XCTAssertEqual(stats.healthPercent, 88)
        XCTAssertEqual(stats.rangeLoss, 60)
        XCTAssertEqual(stats.originalCapacity, 77.5)
        XCTAssertEqual(stats.currentCapacity, 68.2)
    }

    func testBatteryStatsManualReferenceOverridesLateBaselineCapacities() {
        let health = BatteryHealth(
            maxRange: 448,
            currentRange: 440,
            maxCapacity: 70,
            currentCapacity: 69,
            ratedEfficiency: 155,
            batteryHealthPercentage: 98
        )
        let status = CarStatus(
            batteryDetails: BatteryDetails(batteryLevel: 50, usableBatteryLevel: 48, estBatteryRange: 205, ratedBatteryRange: 220, idealBatteryRange: 230)
        )

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: status,
            batteryReferenceRangeKm: 500
        )

        XCTAssertEqual(stats.healthPercent, 88)
        XCTAssertEqual(stats.healthSource, .manualReference)
        XCTAssertEqual(stats.originalCapacity, 77.5)
        XCTAssertEqual(stats.currentCapacity, 68.2)
        XCTAssertEqual(stats.lossKwh ?? .nan, 9.3, accuracy: 0.001)
        XCTAssertEqual(stats.lossPercent ?? .nan, 12, accuracy: 0.001)
    }

    func testBatteryStatsPreferVerifiedCapacityReferenceOverRangeAndTeslaMatePercentage() {
        let health = BatteryHealth(
            maxRange: 500,
            currentRange: 440,
            maxCapacity: 72,
            currentCapacity: 68.5,
            ratedEfficiency: 155,
            batteryHealthPercentage: 99
        )

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: nil,
            batteryReferenceRangeKm: 520,
            batteryReferenceCapacityKWh: 78.8,
            batteryRecordingStartOdometerKm: 110_000
        )

        XCTAssertEqual(stats.healthSource, .manualCapacityReference)
        XCTAssertEqual(stats.healthPercent, 86.9)
        XCTAssertEqual(stats.originalCapacity, 78.8)
        XCTAssertEqual(stats.currentCapacity, 68.5)
        XCTAssertEqual(stats.lossKwh ?? .nan, 10.3, accuracy: 0.001)
        XCTAssertEqual(stats.lossPercent ?? .nan, 13.1, accuracy: 0.001)
        XCTAssertEqual(stats.confidence, .calibratedLateHistory)
        XCTAssertEqual(stats.healthSource.title(language: .chinese), "手动容量基线")
    }

    func testBatteryStatsDoNotClaimCapacityCalibrationWithoutCurrentCapacity() {
        let health = BatteryHealth(currentRange: 440, batteryHealthPercentage: 98)

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: nil,
            batteryReferenceCapacityKWh: 78.8,
            batteryRecordingStartOdometerKm: 110_000
        )

        XCTAssertEqual(stats.healthSource, .recordedPeriod)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertEqual(stats.originalCapacity, 78.8)
        XCTAssertFalse(stats.hasCurrentCapacityData)
        XCTAssertEqual(stats.confidence, .lateHistoryNeedsReference)
    }

    func testBatteryStatsWarnWhenTeslaMateHistoryStartsLateWithoutReferenceRange() {
        let health = BatteryHealth(maxRange: 448, currentRange: 440, maxCapacity: 70, currentCapacity: 69, ratedEfficiency: 155, batteryHealthPercentage: 98)

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: nil,
            batteryRecordingStartOdometerKm: 110_000
        )

        XCTAssertEqual(stats.healthSource, .recordedPeriod)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertEqual(stats.confidence, .lateHistoryNeedsReference)
        XCTAssertEqual(stats.confidence.title(language: .chinese), "需要参考值")
        XCTAssertTrue(stats.confidence.detail(recordingStartOdometerKm: 110_000, units: .metric, language: .chinese).contains("110,000 km"))
    }

    func testBatteryStatsExposeRangeRatioSourceWhenHealthPercentIsMissing() {
        let health = BatteryHealth(maxRange: 500, currentRange: 450, ratedEfficiency: 155)

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: nil,
            batteryRecordingStartOdometerKm: 10_000
        )

        XCTAssertEqual(stats.healthSource, .rangeRatio)
        XCTAssertEqual(stats.healthPercent, 90)
        XCTAssertEqual(stats.rangeLoss, 50)
    }

    func testBatteryStatsDoNotTreatLateRecordingRangeRatioAsLifetimeHealth() {
        let health = BatteryHealth(maxRange: 476.08, currentRange: 474.90, ratedEfficiency: 146)

        let stats = BatteryViewModel.computeStats(
            health: health,
            status: nil,
            batteryRecordingStartOdometerKm: 118_704
        )

        XCTAssertEqual(stats.healthSource, .recordedPeriod)
        XCTAssertEqual(stats.healthPercent, 99.8)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertEqual(stats.confidence, .lateHistoryNeedsReference)
        XCTAssertFalse(stats.hasOriginalCapacityData)
    }

    func testBatteryStatsDoNotTreatUnknownRecordingStartAsLifetimeHealth() {
        let health = BatteryHealth(
            maxRange: 476,
            currentRange: 471,
            maxCapacity: 69.5,
            currentCapacity: 69,
            ratedEfficiency: 146,
            batteryHealthPercentage: 99.3
        )

        let stats = BatteryViewModel.computeStats(health: health, status: nil)

        XCTAssertEqual(stats.healthSource, .recordedPeriod)
        XCTAssertEqual(stats.healthPercent, 99.3)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertFalse(stats.hasOriginalCapacityData)
        XCTAssertEqual(stats.confidence, .recordingStartUnknown)
        XCTAssertTrue(stats.confidence.needsReference)
        XCTAssertEqual(stats.confidence.title(language: .chinese), "记录起点未知")
    }

    func testBatteryStatsExposeFallbackSourceWhenCoreValuesAreMissing() {
        let stats = BatteryViewModel.computeStats(health: BatteryHealth(), status: nil)

        XCTAssertEqual(stats.healthSource, .fallback)
        XCTAssertNil(stats.healthPercent)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertNil(stats.originalCapacity)
        XCTAssertNil(stats.currentCapacity)
        XCTAssertNil(stats.maxRangeNew)
        XCTAssertNil(stats.maxRangeNow)
        XCTAssertNil(stats.ratedEfficiency)
        XCTAssertNil(stats.batteryLevel)
        XCTAssertNil(stats.usableBatteryLevel)
        XCTAssertEqual(BatteryHealthPresentation.percentText(stats.healthPercent), "--")
        XCTAssertFalse(stats.hasOriginalCapacityData)
        XCTAssertFalse(stats.hasCurrentCapacityData)
        XCTAssertFalse(stats.hasCurrentRangeData)
        XCTAssertFalse(stats.hasSOCData)
        XCTAssertFalse(stats.hasRatedRangeData)
        XCTAssertFalse(stats.hasEfficiencyData)
    }

    func testBatteryStatsKeepLateTeslaMateCurrentValuesWithoutClaimingOriginalCapacity() {
        let health = BatteryHealth(maxRange: 476.08, currentRange: 474.90, maxCapacity: 69.56, currentCapacity: 68.95, ratedEfficiency: 146, batteryHealthPercentage: 99.12)
        let status = CarStatus(batteryDetails: BatteryDetails(batteryLevel: 52, usableBatteryLevel: 52, estBatteryRange: 230.06, ratedBatteryRange: 246.13, idealBatteryRange: 246.13))

        let stats = BatteryViewModel.computeStats(health: health, status: status, batteryRecordingStartOdometerKm: 118_704)

        XCTAssertFalse(stats.hasOriginalCapacityData)
        XCTAssertTrue(stats.hasCurrentCapacityData)
        XCTAssertTrue(stats.hasCurrentRangeData)
        XCTAssertTrue(stats.hasSOCData)
        XCTAssertTrue(stats.hasRatedRangeData)
        XCTAssertTrue(stats.hasEfficiencyData)
        XCTAssertEqual(stats.ratedEfficiency, 146)
        XCTAssertEqual(stats.healthSource, .recordedPeriod)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertEqual(stats.confidence, .lateHistoryNeedsReference)
    }

    func testBatteryHealthSourceTextLocalizesReason() {
        XCTAssertEqual(BatteryHealthSource.manualReference.title(language: .chinese), "手动参考值")
        XCTAssertEqual(
            BatteryHealthSource.manualReference.detail(language: .chinese),
            "按当前满电额定续航和你填写的新车参考续航计算。"
        )
        XCTAssertEqual(BatteryHealthSource.teslaMateHealth.title(language: .english), "TeslaMate health")
    }

    func testMileageRepeatedEntryRestoresDrilldownAndFailedRefreshPreservesIt() async throws {
        let cache = VehiclePageStateCache<MileagePageSnapshot>()
        let key = VehiclePageCacheKey(serverURL: "https://mileage-cache.test", carId: 41)
        let drive = DriveData.fixture(
            id: 1,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            distance: 20,
            durationMin: 30
        )
        let initial = MileageViewModel(
            provider: StaticMileageDataProvider(drives: [drive], charges: [], units: nil),
            cacheKey: key,
            stateCache: cache
        )
        await initial.load(carId: 41)
        initial.selectYear(2026)
        initial.selectMonth("2026-07")

        let repeated = MileageViewModel(
            provider: FailingMileageDataProvider(),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertEqual(repeated.state.years, initial.state.years)
        XCTAssertEqual(repeated.state.months, initial.state.months)
        XCTAssertEqual(repeated.state.days, initial.state.days)
        XCTAssertFalse(repeated.state.isLoading)

        await repeated.load(carId: 41)

        XCTAssertEqual(repeated.state.years, initial.state.years)
        XCTAssertEqual(repeated.state.months, initial.state.months)
        XCTAssertNotNil(repeated.state.errorMessage)
        XCTAssertFalse(repeated.state.isLoading)
    }

    func testStatsRepeatedEntryRestoresFilterContextAndFailedRefreshPreservesIt() async throws {
        let cache = VehiclePageStateCache<StatsPageSnapshot>()
        let key = VehiclePageCacheKey(serverURL: "https://stats-cache.test", carId: 42)
        let drive = DriveData.fixture(
            id: 2,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            distance: 22,
            durationMin: 30
        )
        let serverStats = try JSONDecoder.teslamate.decode(
            TeslaMateServerStatsResponse.self,
            from: Data(#"{"summary":{"total_distance_km":123.4}}"#.utf8)
        )
        let initial = StatsViewModel(
            api: FakeAnalyticsAPI(serverStats: .success(serverStats)),
            historyProvider: StaticMileageDataProvider(drives: [drive], charges: [], units: nil),
            cacheKey: key,
            stateCache: cache
        )
        await initial.load(carId: 42)
        initial.setFilter(.year(2026))

        let repeated = StatsViewModel(
            api: FakeAnalyticsAPI(),
            historyProvider: FailingMileageDataProvider(),
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertEqual(repeated.state.selectedFilter, .year(2026))
        XCTAssertEqual(repeated.state.summary, initial.state.summary)
        XCTAssertEqual(repeated.state.serverStats, initial.state.serverStats)
        XCTAssertFalse(repeated.state.isLoading)

        await repeated.load(carId: 42)

        XCTAssertEqual(repeated.state.selectedFilter, .year(2026))
        XCTAssertEqual(repeated.state.summary, initial.state.summary)
        XCTAssertEqual(repeated.state.serverStats, initial.state.serverStats)
        XCTAssertNotNil(repeated.state.errorMessage)
        XCTAssertFalse(repeated.state.isLoading)
    }

    func testMileageConcurrentLoadsReadHistoryOnce() async {
        let provider = CountingMileageDataProvider()
        let viewModel = MileageViewModel(provider: provider)

        async let first: Void = viewModel.load(carId: 43)
        async let second: Void = viewModel.load(carId: 43)
        _ = await (first, second)

        let driveRequestCount = await provider.driveRequestCount
        let chargeRequestCount = await provider.chargeRequestCount
        XCTAssertEqual(driveRequestCount, 1)
        XCTAssertEqual(chargeRequestCount, 1)
    }
}

private struct FakeAnalyticsAPI: AnalyticsAPIProviding {
    let health: APIResult<BatteryHealth>
    let updatesResult: APIResult<[UpdateData]>
    let drivesResult: APIResult<[DriveData]>
    let chargesResult: APIResult<[ChargeData]>
    let driveDetails: [Int: DriveDetail]
    let chargeDetails: [Int: ChargeDetail]
    let status: APIResult<CarStatusPayload>
    let serverStatsResult: APIResult<TeslaMateServerStatsResponse>
    let batteryHistoryResult: APIResult<BatteryHistoryData>

    init(
        health: APIResult<BatteryHealth> = .success(BatteryHealth()),
        updates: [UpdateData] = [],
        updatesResult: APIResult<[UpdateData]>? = nil,
        drives: [DriveData] = [],
        charges: [ChargeData] = [],
        driveDetails: [Int: DriveDetail] = [:],
        chargeDetails: [Int: ChargeDetail] = [:],
        status: APIResult<CarStatusPayload> = .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar"))),
        serverStats: APIResult<TeslaMateServerStatsResponse> = .failure(.httpStatus(404)),
        batteryHistory: APIResult<BatteryHistoryData> = .failure(.httpStatus(404))
    ) {
        self.health = health
        self.updatesResult = updatesResult ?? .success(updates)
        self.drivesResult = .success(drives)
        self.chargesResult = .success(charges)
        self.driveDetails = driveDetails
        self.chargeDetails = chargeDetails
        self.status = status
        self.serverStatsResult = serverStats
        self.batteryHistoryResult = batteryHistory
    }

    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> { serverStatsResult }
    func batteryHistory(carId _: Int) async -> APIResult<BatteryHistoryData> { batteryHistoryResult }

    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> {
        health
    }

    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> {
        updatesResult
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        (page ?? 1) == 1 ? drivesResult : .success([])
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        (page ?? 1) == 1 ? chargesResult : .success([])
    }

    func driveDetail(carId _: Int, driveId: Int) async -> APIResult<DriveDetail> {
        driveDetails[driveId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId: Int) async -> APIResult<ChargeDetail> {
        chargeDetails[chargeId].map(APIResult.success) ?? .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        status
    }
}

private actor SlowSoftwareUpdatesAPI: AnalyticsAPIProviding {
    private var updateRequests = 0

    var updateRequestCount: Int {
        updateRequests
    }

    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> {
        updateRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success([UpdateData(updateId: 7, version: "2026.20.3")])
    }

    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> {
        .failure(.emptyBody)
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success([])
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .failure(.emptyBody)
    }
}

private actor SlowBatteryAnalyticsAPI: AnalyticsAPIProviding {
    private var healthRequests = 0
    private var statusRequests = 0
    private var historyRequests = 0

    var requestCounts: (health: Int, status: Int, history: Int) {
        (healthRequests, statusRequests, historyRequests)
    }

    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> {
        .failure(.emptyBody)
    }

    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> {
        healthRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success(BatteryHealth(currentRange: 470))
    }

    func batteryHistory(carId _: Int) async -> APIResult<BatteryHistoryData> {
        historyRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .failure(.emptyBody)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        statusRequests += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km")))
    }

    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> {
        .success([])
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success([])
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .failure(.emptyBody)
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.emptyBody)
    }
}

private actor AtomicBatterySettingsStore: SettingsStoring, AtomicSettingsUpdating {
    private var settings: AppSettings
    private var atomicUpdateCount = 0
    private var wholeSaveCount = 0

    init(settings: AppSettings) {
        self.settings = settings
    }

    var snapshot: (settings: AppSettings, atomicUpdateCount: Int, wholeSaveCount: Int) {
        (settings, atomicUpdateCount, wholeSaveCount)
    }

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {
        wholeSaveCount += 1
        self.settings = settings
    }

    func updateAtomically(
        _ transform: @Sendable (AppSettings) -> AppSettings
    ) async throws -> AppSettings {
        atomicUpdateCount += 1
        settings = transform(settings)
        return settings
    }
}

private actor InMemoryAnalyticsChargeCostOverrideStore: ChargeCostOverriding {
    private var overrides: [Int: Double]

    init(overrides: [Int: Double] = [:]) {
        self.overrides = overrides
    }

    func costOverrides(carId _: Int) async throws -> [Int: Double] {
        overrides
    }

    func costOverride(carId _: Int, chargeId: Int) async throws -> Double? {
        overrides[chargeId]
    }

    func saveCostOverride(carId _: Int, chargeId: Int, cost: Double?) async throws {
        overrides[chargeId] = cost
    }
}

private actor StatsActivityTestAPI: ActivityAPIProviding {
    private var results: [APIResult<TeslaMateActivitiesResponse>]
    init(results: [APIResult<TeslaMateActivitiesResponse>]) { self.results = results }
    func activities(carId _: Int, page _: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        results.isEmpty ? .failure(.emptyBody) : results.removeFirst()
    }
    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> { .success([]) }
    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> { .success([]) }
    func standbyDrain(carId _: Int, latitude _: Double, longitude _: Double) async -> APIResult<StandbyDrainResponse> { .failure(.httpStatus(404)) }
}

private struct StaticMileageDataProvider: MileageDataProviding {
    let drives: [DriveData]
    let charges: [ChargeData]
    let units: UnitPreferences?

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> { .success(drives) }
    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> { .success(charges) }
    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> { .success(units) }
}

private struct FailingMileageDataProvider: MileageDataProviding {
    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> { .failure(.network("offline")) }
    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> { .failure(.network("offline")) }
    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> { .failure(.network("offline")) }
}

private actor CountingMileageDataProvider: MileageDataProviding {
    private(set) var driveRequestCount = 0
    private(set) var chargeRequestCount = 0

    func mileageDrives(carId _: Int) async -> APIResult<[DriveData]> {
        driveRequestCount += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success([])
    }

    func mileageCharges(carId _: Int) async -> APIResult<[ChargeData]> {
        chargeRequestCount += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .success([])
    }

    func mileageUnits(carId _: Int) async -> APIResult<UnitPreferences?> {
        .success(nil)
    }
}

private struct StaticAnalyticsSettingsStore: SettingsStoring {
    let settings: AppSettings

    func load() async -> AppSettings {
        settings
    }

    func save(_: AppSettings) async {}
}

private actor MutableAnalyticsSettingsStore: SettingsStoring {
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings { settings }
    func save(_ settings: AppSettings) async { self.settings = settings }
}

private struct StaticChargePricingAggregateStore: ChargePricingAggregateProviding {
    let aggregates: [Int: ChargeDetailPricingAggregate]

    func chargePricingAggregates(carId _: Int) async throws -> [Int: ChargeDetailPricingAggregate] {
        aggregates
    }
}

private extension DriveData {
    static func fixture(
        id: Int,
        startDate: String,
        endDate: String = "2026-07-01T09:00:00Z",
        distance: Double,
        durationMin: Int,
        energyConsumedNet: Double? = nil
    ) -> DriveData {
        DriveData(
            driveId: id,
            carId: 1,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            durationMin: durationMin,
            startAddress: "Home, Region, Country",
            endAddress: "Work, Region, Country",
            speedAvg: durationMin > 0 ? distance / Double(durationMin) * 60 : nil,
            odometerDetails: DriveOdometerDetails(distance: distance),
            batteryDetails: DriveBatteryDetails(startBatteryLevel: 80, endBatteryLevel: 70),
            energyConsumedNet: energyConsumedNet
        )
    }
}

private extension ChargeData {
    static func fixture(
        id: Int,
        startDate: String,
        endDate: String = "2026-07-01T11:00:00Z",
        energy: Double,
        energyUsed: Double? = nil,
        durationMin: Int,
        cost: Double?,
        address: String = "Charger, Region, Country"
    ) -> ChargeData {
        ChargeData(
            chargeId: id,
            carId: 1,
            startDate: startDate,
            endDate: endDate,
            address: address,
            chargeEnergyAdded: energy,
            chargeEnergyUsed: energyUsed,
            cost: cost,
            durationMin: durationMin
        )
    }
}
