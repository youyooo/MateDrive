import XCTest
@testable import MateDroidIOS

@MainActor
final class DriveDetailViewModelTests: XCTestCase {
    func testDriveStatsPreserveMissingTelemetryInsteadOfInventingZeros() {
        let missing = DriveStatsCalculator.calculateStats(DriveDetail(driveId: 1))

        XCTAssertNil(missing.speedMax)
        XCTAssertNil(missing.speedAvg)
        XCTAssertNil(missing.powerMax)
        XCTAssertNil(missing.elevationMax)
        XCTAssertNil(missing.elevationGain)
        XCTAssertNil(missing.batteryStart)
        XCTAssertNil(missing.batteryEnd)
        XCTAssertNil(missing.distance)
        XCTAssertNil(missing.durationMin)
        XCTAssertNil(missing.avgSpeedFromDistance)

        let zero = DriveStatsCalculator.calculateStats(DriveDetail(
            driveId: 2,
            distance: 0,
            durationMin: 0,
            speedMax: 0,
            speedAvg: 0,
            powerMax: 0,
            powerMin: 0,
            batteryDetails: DriveBatteryDetails(startBatteryLevel: 0, endBatteryLevel: 0),
            positions: [DrivePosition(speed: 0, power: 0, batteryLevel: 0, elevation: 0)]
        ))

        XCTAssertEqual(zero.speedMax, 0)
        XCTAssertEqual(zero.powerMax, 0)
        XCTAssertEqual(zero.elevationMax, 0)
        XCTAssertEqual(zero.batteryStart, 0)
        XCTAssertEqual(zero.distance, 0)
        XCTAssertEqual(zero.durationMin, 0)

        XCTAssertEqual(DriveDetailPresentation.distanceText(nil, units: .metric), "--")
        XCTAssertEqual(DriveDetailPresentation.distanceText(0, units: .metric), "0.0 km")
        XCTAssertEqual(DriveDetailPresentation.speedText(nil, units: .metric), "--")
        XCTAssertEqual(DriveDetailPresentation.speedText(0, units: .metric), "0 km/h")
        XCTAssertEqual(DriveDetailPresentation.batteryText(start: nil, end: nil), "--")
        XCTAssertEqual(DriveDetailPresentation.batteryText(start: 0, end: 0), "0% -> 0%")
        XCTAssertEqual(DriveDetailPresentation.elevationText(gain: nil, loss: nil, units: .metric), "--")
        XCTAssertEqual(DriveDetailPresentation.durationText(nil, language: .chinese), "--")
        XCTAssertEqual(DriveDetailPresentation.durationText(0, language: .chinese), "0分钟")

        let annotation = DriveAnnotation(classification: .unclassified)
        let missingCSV = DriveCSVExporter.csv(detail: DriveDetail(driveId: 1), stats: missing, annotation: annotation, units: .metric)
        let zeroCSV = DriveCSVExporter.csv(detail: DriveDetail(driveId: 2, distance: 0, durationMin: 0, speedMax: 0, speedAvg: 0), stats: zero, annotation: annotation, units: .metric)
        XCTAssertTrue(missingCSV.contains("\"distance_km\",\"\""))
        XCTAssertTrue(missingCSV.contains("\"duration_min\",\"\""))
        XCTAssertTrue(zeroCSV.contains("\"distance_km\",\"0.000000\""))
        XCTAssertTrue(zeroCSV.contains("\"duration_min\",\"0\""))
    }

    func testEnergySourcePresentationExplainsDirectReconstructedAndUnavailableValues() {
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .api, language: .chinese), "TeslaMate 原始数据")
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .powerSamples, language: .chinese), "由功率采样重建")
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .unavailable, language: .chinese), "暂无可靠数据")
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .powerSamples, language: .english), "Reconstructed from power samples")
        XCTAssertEqual(
            DriveEnergySourcePresentation.efficiencySubtitle(energySource: .unavailable, hasEfficiency: true, language: .chinese),
            "TeslaMate 原始数据"
        )
        XCTAssertEqual(
            DriveEnergySourcePresentation.efficiencySubtitle(energySource: .unavailable, hasEfficiency: false, language: .chinese),
            "暂无可靠数据"
        )
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .api, language: .german), "Direkte TeslaMate-Daten")
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .powerSamples, language: .spanish), "Reconstruido a partir de muestras de potencia")
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .unavailable, language: .italian), "Nessun dato affidabile")
        XCTAssertEqual(DriveEnergySourcePresentation.subtitle(for: .powerSamples, language: .catalan), "Reconstruït a partir de mostres de potència")
    }

    func testDriveClassificationTitlesUseSelectedEuropeanLanguage() {
        XCTAssertEqual(DriveClassification.unclassified.title(language: .german), "Nicht klassifiziert")
        XCTAssertEqual(DriveClassification.commute.title(language: .spanish), "Trayecto diario")
        XCTAssertEqual(DriveClassification.personal.title(language: .italian), "Personale")
        XCTAssertEqual(DriveClassification.business.title(language: .catalan), "Feina")
        XCTAssertEqual(DriveClassification.roadTrip.title(language: .german), "Roadtrip")
        XCTAssertEqual(DriveClassification.custom.title(language: .spanish), "Personalizado")
    }

    func testReplayBuilderKeepsMetricsAlignedWithValidRoutePoints() {
        let positions = [
            DrivePosition(date: "2026-07-01T08:00:00Z", latitude: 0, longitude: 0, speed: 1),
            DrivePosition(date: "2026-07-01T08:00:00Z", latitude: 28.10, longitude: 112.90, speed: 20),
            DrivePosition(date: "2026-07-01T08:00:10Z", latitude: 28.101, longitude: 112.901, speed: 30, power: 8),
            DrivePosition(date: "2026-07-01T08:00:11Z", latitude: 39.90, longitude: 116.40, speed: 99),
            DrivePosition(date: "2026-07-01T08:00:20Z", latitude: 28.102, longitude: 112.902, speed: 40, batteryLevel: 78)
        ]

        let samples = DriveReplayBuilder.samples(from: positions)

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.position.speed), [20, 30, 40])
        XCTAssertEqual(samples.last?.position.batteryLevel, 78)
        XCTAssertEqual(samples.map(\.latitude), [28.10, 28.101, 28.102])
    }

    func testReplayBuilderReturnsEmptyForMissingCoordinates() {
        XCTAssertTrue(DriveReplayBuilder.samples(from: [
            DrivePosition(speed: 20),
            DrivePosition(latitude: 91, longitude: 10)
        ]).isEmpty)
    }

    func testDriveDetailStatsUsePositionDataBeforeSummaryFallbacks() async throws {
        let detail = DriveDetail.fixture()
        let api = FakeDriveAPI(detail: detail)
        let weatherService = FakeDriveWeatherService(points: [
            WeatherPoint(latitude: 48.0, longitude: 2.0, temperatureCelsius: 17, weatherCode: 1)
        ])
        let viewModel = DriveDetailViewModel(api: api, weatherService: weatherService)

        await viewModel.load(carId: 1, driveId: 10)

        let stats = try XCTUnwrap(viewModel.state.stats)
        XCTAssertEqual(stats.speedMax, 80)
        XCTAssertEqual(stats.speedMin, 20)
        XCTAssertEqual(stats.powerMax, 30)
        XCTAssertEqual(stats.powerMin, -12)
        XCTAssertEqual(stats.elevationGain, 25)
        XCTAssertEqual(stats.elevationLoss, 10)
        XCTAssertEqual(stats.batteryStart, 80)
        XCTAssertEqual(stats.batteryEnd, 72)
        XCTAssertEqual(stats.batteryUsed, 8)
        XCTAssertEqual(stats.efficiency, 200)
        XCTAssertEqual(stats.energyUsed, 4.8)
        XCTAssertEqual(stats.energySource, .api)
        XCTAssertEqual(viewModel.state.weatherPoints.map(\.temperatureCelsius), [17])
    }

    func testDriveDetailStatsUseConsumptionWhenEnergyIsMissing() async throws {
        let detail = DriveDetail.fixture(energyConsumedNet: nil, consumptionNet: 155)
        let api = FakeDriveAPI(detail: detail)
        let viewModel = DriveDetailViewModel(api: api)

        await viewModel.load(carId: 1, driveId: 10)

        let stats = try XCTUnwrap(viewModel.state.stats)
        XCTAssertEqual(stats.efficiency, 155)
        XCTAssertNil(stats.energyUsed)
    }

    func testDriveDetailStatsEstimateNetEnergyFromPowerSamplesWhenAPIFieldsAreMissing() async throws {
        let detail = DriveDetail(
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
        )
        let api = FakeDriveAPI(detail: detail)
        let viewModel = DriveDetailViewModel(api: api)

        await viewModel.load(carId: 1, driveId: 10)

        let stats = try XCTUnwrap(viewModel.state.stats)
        XCTAssertEqual(try XCTUnwrap(stats.energyUsed), 0.05, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.efficiency), 100, accuracy: 0.1)
        XCTAssertEqual(stats.energySource, .powerSamples)
        XCTAssertEqual(try XCTUnwrap(stats.energySampleCoverage), 1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.tractionEnergyKWh), 0.0625, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.regeneratedEnergyKWh), 0.0125, accuracy: 0.001)
    }

    func testDriveDetailRejectsLowCoveragePowerEstimate() throws {
        let detail = DriveDetail(
            driveId: 10,
            odometerDetails: DriveOdometerDetails(distance: 10),
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", power: 20),
                DrivePosition(date: "2026-07-01T08:00:10Z", power: 20),
                DrivePosition(date: "2026-07-01T08:10:00Z", power: 20)
            ]
        )

        let stats = DriveStatsCalculator.calculateStats(detail)

        XCTAssertNil(stats.energyUsed)
        XCTAssertNil(stats.efficiency)
        XCTAssertEqual(stats.energySource, .unavailable)
        XCTAssertLessThan(try XCTUnwrap(stats.energySampleCoverage), 0.8)
    }

    func testDriveDetailHandlesAPIFailure() async throws {
        let api = FakeDriveAPI(detailResult: .failure(.httpStatus(500)))
        let viewModel = DriveDetailViewModel(api: api)

        await viewModel.load(carId: 1, driveId: 10)

        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertEqual(viewModel.state.errorMessage, "TeslaMate returned HTTP 500.")
        XCTAssertNil(viewModel.state.driveDetail)
    }

    func testDriveAnnotationsAreIsolatedByCarAndDriveAndRemoveWhenEmpty() {
        var settings = AppSettings()
        let first = DriveAnnotation(classification: .commute, note: "Morning")
        let second = DriveAnnotation(classification: .business, note: "Client")

        settings.setDriveAnnotation(first, carId: 1, driveId: 10)
        settings.setDriveAnnotation(second, carId: 2, driveId: 10)

        XCTAssertEqual(settings.driveAnnotation(carId: 1, driveId: 10), first)
        XCTAssertEqual(settings.driveAnnotation(carId: 2, driveId: 10), second)
        XCTAssertEqual(settings.driveAnnotation(carId: 1, driveId: 11), DriveAnnotation())

        settings.setDriveAnnotation(DriveAnnotation(), carId: 1, driveId: 10)

        XCTAssertEqual(settings.driveAnnotation(carId: 1, driveId: 10), DriveAnnotation())
        XCTAssertEqual(settings.driveAnnotations.count, 1)
    }

    func testDriveAnnotationPersistsThroughSettingsRoundTripAndOldSettingsDecode() throws {
        var settings = AppSettings(appLanguage: .chinese)
        let annotation = DriveAnnotation(classification: .custom, customLabel: "接客户", note: "机场二号航站楼")
        settings.setDriveAnnotation(annotation, carId: 7, driveId: 42)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        let oldSettings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(decoded.driveAnnotation(carId: 7, driveId: 42), annotation)
        XCTAssertTrue(oldSettings.driveAnnotations.isEmpty)
    }

    func testCSVExporterEscapesFieldsAndIncludesAnnotation() {
        let detail = DriveDetail(
            driveId: 7,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            startAddress: "Home, \"North\"",
            endAddress: "Work\nGarage",
            odometerDetails: DriveOdometerDetails(distance: 24),
            durationMin: 30,
            speedMax: 80,
            speedAvg: 48,
            energyConsumedNet: 4.8
        )
        let annotation = DriveAnnotation(classification: .custom, customLabel: "Client, A", note: "Line 1\n\"Line 2\"")

        let csv = DriveCSVExporter.csv(
            detail: detail,
            stats: DriveStatsCalculator.calculateStats(detail),
            annotation: annotation,
            units: UnitPreferences(unitOfLength: "km")
        )

        XCTAssertTrue(csv.contains("\"drive_id\",\"7\""))
        XCTAssertTrue(csv.contains("\"Home, \"\"North\"\"\""))
        XCTAssertTrue(csv.contains("\"Work\nGarage\""))
        XCTAssertTrue(csv.contains("\"classification\",\"custom\""))
        XCTAssertTrue(csv.contains("\"Client, A\""))
        XCTAssertTrue(csv.contains("\"Line 1\n\"\"Line 2\"\"\""))
    }

    func testDriveDetailViewModelLoadsAndSavesAnnotation() async {
        var initialSettings = AppSettings()
        let initial = DriveAnnotation(classification: .personal, note: "Initial")
        initialSettings.setDriveAnnotation(initial, carId: 1, driveId: 10)
        let store = DriveAnnotationSettingsStore(initialSettings)
        let viewModel = DriveDetailViewModel(api: FakeDriveAPI(detail: .fixture()), settingsStore: store)

        await viewModel.load(carId: 1, driveId: 10)
        XCTAssertEqual(viewModel.state.annotation, initial)

        let updated = DriveAnnotation(classification: .business, note: "Expense report")
        await viewModel.saveAnnotation(carId: 1, driveId: 10, annotation: updated)

        let stored = await store.load().driveAnnotation(carId: 1, driveId: 10)
        XCTAssertEqual(viewModel.state.annotation, updated)
        XCTAssertEqual(stored, updated)
    }

    func testDriveChartSamplesUseActualTimestampsSortAndSkipUndatedValues() throws {
        let positions = [
            DrivePosition(date: "2026-07-01T08:00:20Z", speed: 80, power: -12, batteryLevel: 72, elevation: 115, climateInfo: DriveClimateInfo(insideTemp: 21, outsideTemp: 12)),
            DrivePosition(date: nil, speed: 999, power: 999),
            DrivePosition(date: "2026-07-01T08:00:00Z", speed: 20, power: 10, batteryLevel: 80, elevation: 100, climateInfo: DriveClimateInfo(insideTemp: 22, outsideTemp: 11), batteryInfo: DriveBatteryInfo(batteryHeater: true))
        ]

        let speed = DriveChartSampleBuilder.samples(kind: .speed, positions: positions, units: .metric)
        let power = DriveChartSampleBuilder.samples(kind: .power, positions: positions, units: .metric)
        let battery = DriveChartSampleBuilder.samples(kind: .battery, positions: positions, units: .metric)
        let temperature = DriveChartSampleBuilder.samples(kind: .temperature, positions: positions, units: .metric)

        XCTAssertEqual(speed.map(\.value), [20, 80])
        XCTAssertLessThan(try XCTUnwrap(speed.first?.date), try XCTUnwrap(speed.last?.date))
        XCTAssertEqual(power.map(\.series), ["traction", "regeneration"])
        XCTAssertEqual(power.map(\.isHighlighted), [false, true])
        XCTAssertEqual(battery.map(\.isHighlighted), [true, false])
        XCTAssertEqual(temperature.map(\.series), ["outside", "inside", "outside", "inside"])
    }

    func testDriveChartSamplesConvertValuesForImperialUnits() {
        let position = DrivePosition(
            date: "2026-07-01T08:00:00Z",
            speed: 100,
            elevation: 100,
            climateInfo: DriveClimateInfo(outsideTemp: 20)
        )

        let speed = DriveChartSampleBuilder.samples(kind: .speed, positions: [position], units: .imperial)
        let elevation = DriveChartSampleBuilder.samples(kind: .elevation, positions: [position], units: .imperial)
        let temperature = DriveChartSampleBuilder.samples(kind: .temperature, positions: [position], units: .imperial)

        XCTAssertEqual(speed.first?.value ?? 0, 62.1371, accuracy: 0.001)
        XCTAssertEqual(elevation.first?.value ?? 0, 328.084, accuracy: 0.001)
        XCTAssertEqual(temperature.first?.value ?? 0, 68, accuracy: 0.001)
    }

    func testDriveChartSelectionChoosesNearestTimestampAndAllSeriesAtThatTime() throws {
        let positions = [
            DrivePosition(date: "2026-07-01T08:00:00Z", climateInfo: DriveClimateInfo(insideTemp: 22, outsideTemp: 18)),
            DrivePosition(date: "2026-07-01T08:00:20Z", climateInfo: DriveClimateInfo(insideTemp: 23, outsideTemp: 19))
        ]
        let samples = DriveChartSampleBuilder.samples(kind: .temperature, positions: positions, units: .metric)
        let requestedDate = try XCTUnwrap(DomainDateParser.date(from: "2026-07-01T08:00:16Z"))

        let selected = DriveChartSelection.samples(at: requestedDate, in: samples)

        XCTAssertEqual(selected.map(\.series), ["outside", "inside"])
        XCTAssertEqual(selected.map(\.value), [19, 23])
        XCTAssertEqual(Set(selected.map(\.date)).count, 1)
    }

    func testDriveChartSelectionHandlesEmptySamples() {
        XCTAssertNil(DriveChartSelection.nearestDate(to: Date(), in: []))
        XCTAssertTrue(DriveChartSelection.samples(at: Date(), in: []).isEmpty)
    }

    func testDriveChartHeaderSummariesUseTheRelevantTripMetric() {
        let positions = [
            DrivePosition(
                date: "2026-07-01T08:00:00Z",
                speed: 20,
                power: 10,
                batteryLevel: 80,
                elevation: 100,
                tpmsPressureFl: 2.85,
                climateInfo: DriveClimateInfo(insideTemp: 22, outsideTemp: 18)
            ),
            DrivePosition(
                date: "2026-07-01T08:00:20Z",
                speed: 80,
                power: -30,
                batteryLevel: 72,
                elevation: 115,
                tpmsPressureFl: 2.9,
                climateInfo: DriveClimateInfo(insideTemp: 23, outsideTemp: 19)
            )
        ]

        XCTAssertEqual(DriveChartHeaderPresentation.valueText(kind: .speed, positions: positions, units: .metric), "80 km/h")
        XCTAssertEqual(DriveChartHeaderPresentation.valueText(kind: .power, positions: positions, units: .metric), "30 kW")
        XCTAssertEqual(DriveChartHeaderPresentation.valueText(kind: .battery, positions: positions, units: .metric), "72%")
        XCTAssertEqual(DriveChartHeaderPresentation.valueText(kind: .elevation, positions: positions, units: .metric), "115 m")
        XCTAssertEqual(DriveChartHeaderPresentation.valueText(kind: .temperature, positions: positions, units: .metric), "23°C")
        XCTAssertEqual(DriveChartHeaderPresentation.valueText(kind: .tirePressure, positions: positions, units: .metric), "2.90 bar")
    }

    func testDriveChartScaleKeepsFlatEnvironmentalDataReadable() throws {
        let temperature = [
            DriveChartSample(date: Date(timeIntervalSince1970: 1), value: 22, series: "inside", isHighlighted: false),
            DriveChartSample(date: Date(timeIntervalSince1970: 2), value: 22, series: "inside", isHighlighted: false)
        ]
        let pressure = [
            DriveChartSample(date: Date(timeIntervalSince1970: 1), value: 2.85, series: "frontLeft", isHighlighted: false),
            DriveChartSample(date: Date(timeIntervalSince1970: 2), value: 2.86, series: "frontLeft", isHighlighted: false)
        ]

        let temperatureDomain = try XCTUnwrap(DriveChartScale.domain(kind: .temperature, samples: temperature))
        let pressureDomain = try XCTUnwrap(DriveChartScale.domain(kind: .tirePressure, samples: pressure))

        XCTAssertLessThan(temperatureDomain.lowerBound, 22)
        XCTAssertGreaterThan(temperatureDomain.upperBound, 22)
        XCTAssertLessThan(pressureDomain.lowerBound, 2.85)
        XCTAssertGreaterThan(pressureDomain.upperBound, 2.86)
        XCTAssertEqual(DriveChartScale.domain(kind: .battery, samples: temperature), 0...100)
    }

    func testDriveChartAxisUsesInteriorTimesSoEdgeLabelsAreNotClipped() throws {
        let start = try XCTUnwrap(DomainDateParser.date(from: "2026-07-01T08:00:00Z"))
        let end = try XCTUnwrap(DomainDateParser.date(from: "2026-07-01T08:30:00Z"))
        let samples = [
            DriveChartSample(date: start, value: 10, series: "speed", isHighlighted: false),
            DriveChartSample(date: end, value: 20, series: "speed", isHighlighted: false)
        ]

        let dates = DriveChartAxisPresentation.interiorDates(samples: samples)

        XCTAssertEqual(dates.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(dates.first), start)
        XCTAssertLessThan(try XCTUnwrap(dates.last), end)
    }
}

private struct FakeDriveAPI: DriveAPIProviding {
    let detailResult: APIResult<DriveDetail>
    let drivesResult: APIResult<[DriveData]>
    let statusResult: APIResult<CarStatusPayload>

    init(
        detail: DriveDetail,
        drives: [DriveData] = [],
        status: CarStatusPayload = CarStatusPayload(status: nil, units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar"))
    ) {
        self.detailResult = .success(detail)
        self.drivesResult = .success(drives)
        self.statusResult = .success(status)
    }

    init(
        detailResult: APIResult<DriveDetail>,
        drivesResult: APIResult<[DriveData]> = .success([]),
        statusResult: APIResult<CarStatusPayload> = .success(CarStatusPayload(status: nil, units: nil))
    ) {
        self.detailResult = detailResult
        self.drivesResult = drivesResult
        self.statusResult = statusResult
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        drivesResult
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        detailResult
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        statusResult
    }
}

private struct FakeDriveWeatherService: DriveWeatherServicing {
    let points: [WeatherPoint]

    func weatherAlongDrive(positions _: [WeatherRoutePosition], totalDistanceKm _: Double) async -> [WeatherPoint] {
        points
    }
}

private actor DriveAnnotationSettingsStore: SettingsStoring {
    private var value: AppSettings

    init(_ value: AppSettings = AppSettings()) {
        self.value = value
    }

    func load() async -> AppSettings { value }

    func save(_ settings: AppSettings) async { value = settings }
}

private extension DriveDetail {
    static func fixture(energyConsumedNet: Double? = 4.8, consumptionNet: Double? = nil) -> DriveDetail {
        DriveDetail(
            driveId: 10,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            startAddress: "Home",
            endAddress: "Work",
            odometerDetails: DriveOdometerDetails(odometerStart: 1000, odometerEnd: 1024, distance: 24),
            durationMin: 30,
            speedMax: 100,
            speedAvg: 60,
            powerMax: 99,
            powerMin: -99,
            batteryDetails: DriveBatteryDetails(startBatteryLevel: 81, endBatteryLevel: 71),
            outsideTempAvg: 12,
            insideTempAvg: 21,
            energyConsumedNet: energyConsumedNet,
            consumptionNet: consumptionNet,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", latitude: 48.0, longitude: 2.0, speed: 20, power: 10, batteryLevel: 80, elevation: 100),
                DrivePosition(date: "2026-07-01T08:15:00Z", latitude: 48.1, longitude: 2.1, speed: 80, power: 30, batteryLevel: 75, elevation: 125),
                DrivePosition(date: "2026-07-01T08:30:00Z", latitude: 48.2, longitude: 2.2, speed: 50, power: -12, batteryLevel: 72, elevation: 115)
            ]
        )
    }
}
