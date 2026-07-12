import XCTest
@testable import MateDroidIOS

@MainActor
final class AnalyticalViewModelTests: XCTestCase {
    func testAnalyticalDynamicLabelsUseSelectedEuropeanLanguage() {
        XCTAssertEqual(CountrySortOrder.firstVisit.title(language: .german), "Erster Besuch")
        XCTAssertEqual(CountrySortOrder.distance.title(language: .spanish), "Distancia")
        XCTAssertEqual(RegionSortOrder.energy.title(language: .italian), "Energia")
        XCTAssertEqual(RegionSortOrder.charges.title(language: .catalan), "Càrregues")
        XCTAssertEqual(SoftwareUpdateTextFormatter.unknownInstallDate(language: .german), "Installationsdatum unbekannt")
        XCTAssertEqual(SoftwareUpdateTextFormatter.days(12, language: .spanish), "12 días")
        XCTAssertEqual(SoftwareUpdateTextFormatter.daysInstalled(8, language: .italian), "Installato da 8 giorni")
        XCTAssertEqual(SoftwareUpdateTextFormatter.daysInstalled(3, language: .catalan), "Instal·lada durant 3 dies")
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

        XCTAssertEqual(viewModel.state.years.first?.energyCost ?? 0, 14, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.months.first?.energyCost ?? 0, 14, accuracy: 0.001)
        XCTAssertEqual(viewModel.state.days.first?.energyCost ?? 0, 14, accuracy: 0.001)
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
        XCTAssertEqual(
            StatsCoveragePresentation.coverageText(known: 1, total: 2, nounKey: "drives", language: .german),
            "Datenabdeckung: 1/2 Fahrten"
        )
        XCTAssertEqual(
            StatsCoveragePresentation.coverageText(known: 1, total: 2, nounKey: "Charges", language: .spanish),
            "Cobertura de datos: 1/2 Cargas"
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

        XCTAssertEqual(viewModel.state.summary.totalChargeCost, 30)
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

        XCTAssertEqual(viewModel.state.summary.totalChargeCost, 20, accuracy: 0.001)
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
        let detail = DriveDetail(
            driveId: 7,
            startDate: drive.startDate,
            endDate: drive.endDate,
            odometerDetails: DriveOdometerDetails(distance: 20),
            durationMin: 60,
            positions: [
                DrivePosition(date: "2026-07-01T08:05:00Z", latitude: 1, longitude: 1, speed: 10),
                DrivePosition(date: "2026-07-01T08:40:00Z", latitude: 2, longitude: 2, speed: 70)
            ]
        )
        let api = FakeAnalyticsAPI(drives: [drive], driveDetails: [7: detail])
        let viewModel = WhereWasIViewModel(api: api)

        await viewModel.load(carId: 1, timestamp: "2026-07-01T08:42:00Z")

        XCTAssertEqual(viewModel.state.carState, .driving)
        XCTAssertEqual(viewModel.state.driveId, 7)
        XCTAssertEqual(viewModel.state.speed, 70)
        XCTAssertEqual(viewModel.state.latitude, 2)
    }

    func testBatteryStatsUseHealthAPIAndCurrentStatus() {
        let health = BatteryHealth(maxRange: 500, currentRange: 450, maxCapacity: 82, currentCapacity: 74, ratedEfficiency: 155, batteryHealthPercentage: 90)
        let status = CarStatus(
            batteryDetails: BatteryDetails(batteryLevel: 50, usableBatteryLevel: 48, estBatteryRange: 210, ratedBatteryRange: 225, idealBatteryRange: 240)
        )

        let stats = BatteryViewModel.computeStats(health: health, status: status)

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

    func testBatteryStatsNormalizeFractionalTeslaMateHealth() {
        let health = BatteryHealth(maxRange: 500, currentRange: 450, maxCapacity: 82, currentCapacity: 74, ratedEfficiency: 155, batteryHealthPercentage: 0.912)

        let stats = BatteryViewModel.computeStats(health: health, status: nil)

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

        let stats = BatteryViewModel.computeStats(health: health, status: nil)

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
        drives: [DriveData] = [],
        charges: [ChargeData] = [],
        driveDetails: [Int: DriveDetail] = [:],
        chargeDetails: [Int: ChargeDetail] = [:],
        status: APIResult<CarStatusPayload> = .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar"))),
        serverStats: APIResult<TeslaMateServerStatsResponse> = .failure(.httpStatus(404)),
        batteryHistory: APIResult<BatteryHistoryData> = .failure(.httpStatus(404))
    ) {
        self.health = health
        self.updatesResult = .success(updates)
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

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        drivesResult
    }

    func charges(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[ChargeData]> {
        chargesResult
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
            cost: cost,
            durationMin: durationMin
        )
    }
}
