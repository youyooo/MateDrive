import SwiftUI
import XCTest
@testable import MateDriveApp

@MainActor
final class DriveDetailViewModelTests: XCTestCase {
    func testDriveShareCardDefaultsHideEverySensitiveField() {
        let firstPoint = SyntheticCoordinates.point()
        let secondPoint = SyntheticCoordinates.point(latitudeOffset: 0.001, longitudeOffset: 0.001)
        let detail = DriveDetail(
            driveId: 42,
            startDate: "2026-07-01T08:00:00Z",
            startAddress: "Home, Changsha",
            endAddress: "Office, Changsha",
            distance: 26.5,
            durationMin: 40,
            speedAvg: 40,
            batteryDetails: DriveBatteryDetails(startBatteryLevel: 45, endBatteryLevel: 39),
            energyConsumedNet: 5.3,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", latitude: firstPoint.latitude, longitude: firstPoint.longitude),
                DrivePosition(date: "2026-07-01T08:40:00Z", latitude: secondPoint.latitude, longitude: secondPoint.longitude)
            ]
        )
        let stats = DriveStatsCalculator.calculateStats(detail)

        let content = DriveShareCardBuilder.content(
            detail: detail,
            stats: stats,
            annotation: DriveAnnotation(classification: .commute, note: "Private note"),
            units: .metric,
            language: .chinese,
            options: DriveShareCardOptions()
        )

        XCTAssertEqual(content.routeTitle, "隐私行程")
        XCTAssertEqual(content.hiddenLocationsLabel, "地点已隐藏")
        XCTAssertNil(content.dateText)
        XCTAssertNil(content.classificationText)
        XCTAssertTrue(content.routePoints.isEmpty)
        XCTAssertFalse(content.routeTitle.contains("Home"))
        XCTAssertFalse(content.routeTitle.contains("Office"))
        XCTAssertFalse(String(describing: content).contains("Private note"))
        XCTAssertEqual(content.metrics.first(where: { $0.id == "energy" })?.value, "5.3 kWh")
    }

    func testDriveShareCardOnlyIncludesDetailsExplicitlySelected() {
        let firstPoint = SyntheticCoordinates.point()
        let secondPoint = SyntheticCoordinates.point(latitudeOffset: 0.001, longitudeOffset: 0.001)
        let thirdPoint = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        let detail = DriveDetail(
            driveId: 43,
            startDate: "2026-07-01T08:00:00Z",
            startAddress: "Start place",
            endAddress: "End place",
            distance: 7.3,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", latitude: firstPoint.latitude, longitude: firstPoint.longitude),
                DrivePosition(date: "2026-07-01T08:10:00Z", latitude: secondPoint.latitude, longitude: secondPoint.longitude),
                DrivePosition(date: "2026-07-01T08:20:00Z", latitude: thirdPoint.latitude, longitude: thirdPoint.longitude)
            ]
        )
        let options = DriveShareCardOptions(
            includesDateAndTime: true,
            includesLocations: true,
            includesRouteShape: true,
            includesClassification: true
        )

        let content = DriveShareCardBuilder.content(
            detail: detail,
            stats: DriveStatsCalculator.calculateStats(detail),
            annotation: DriveAnnotation(classification: .business),
            units: .metric,
            language: .english,
            options: options
        )

        XCTAssertTrue(options.includesSensitiveDetails)
        XCTAssertEqual(content.routeTitle, "Start place → End place")
        XCTAssertNil(content.hiddenLocationsLabel)
        XCTAssertNotNil(content.dateText)
        XCTAssertEqual(content.classificationText, "Business")
        XCTAssertEqual(content.routePoints.count, 3)
        XCTAssertTrue(content.routePoints.allSatisfy { (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y) })
    }

    func testDriveShareCardPreservesMissingValuesInsteadOfInventingZero() {
        let content = DriveShareCardBuilder.content(
            detail: DriveDetail(driveId: 44),
            stats: DriveStatsCalculator.calculateStats(DriveDetail(driveId: 44)),
            annotation: DriveAnnotation(),
            units: .metric,
            language: .english,
            options: DriveShareCardOptions()
        )

        XCTAssertEqual(content.metrics.map(\.value), ["--", "--", "--", "--", "--", "--"])
    }

    func testDriveShareCardRendersAsHighResolutionNonblankImage() throws {
        let firstPoint = SyntheticCoordinates.point()
        let secondPoint = SyntheticCoordinates.point(latitudeOffset: 0.001, longitudeOffset: 0.001)
        let thirdPoint = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        let detail = DriveDetail(
            driveId: 45,
            startAddress: "Sample Start",
            endAddress: "Sample End",
            distance: 26.5,
            durationMin: 40,
            speedAvg: 40,
            batteryDetails: DriveBatteryDetails(startBatteryLevel: 45, endBatteryLevel: 39),
            energyConsumedNet: 5.3,
            positions: [
                DrivePosition(latitude: firstPoint.latitude, longitude: firstPoint.longitude),
                DrivePosition(latitude: secondPoint.latitude, longitude: secondPoint.longitude),
                DrivePosition(latitude: thirdPoint.latitude, longitude: thirdPoint.longitude)
            ]
        )
        let content = DriveShareCardBuilder.content(
            detail: detail,
            stats: DriveStatsCalculator.calculateStats(detail),
            annotation: DriveAnnotation(classification: .commute),
            units: .metric,
            language: .chinese,
            options: DriveShareCardOptions(
                includesLocations: true,
                includesRouteShape: true,
                includesClassification: true
            )
        )
        let renderer = ImageRenderer(content: DriveShareCardView(content: content))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let cgImage = try XCTUnwrap(image.cgImage)

        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1350)
        XCTAssertTrue(imageHasVisibleVariation(cgImage))

        let attachment = XCTAttachment(image: image)
        attachment.name = "MateDrive Drive Share Card"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func imageHasVisibleVariation(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel >= 32
        else { return false }

        let bytesPerPixel = image.bitsPerPixel / 8
        var sampledColors = Set<UInt32>()
        let xStep = max(image.width / 20, 1)
        let yStep = max(image.height / 20, 1)
        for y in stride(from: 0, to: image.height, by: yStep) {
            for x in stride(from: 0, to: image.width, by: xStep) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                let color = UInt32(bytes[offset]) << 24
                    | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8
                    | UInt32(bytes[offset + 3])
                sampledColors.insert(color)
            }
        }
        return sampledColors.count >= 4
    }

    func testDriveEnergyValidatorRejectsPlaceholderAndInvalidValues() {
        XCTAssertEqual(DriveEnergyValueValidator.positiveFinite(12.5), 12.5)
        XCTAssertNil(DriveEnergyValueValidator.positiveFinite(nil))
        XCTAssertNil(DriveEnergyValueValidator.positiveFinite(0))
        XCTAssertNil(DriveEnergyValueValidator.positiveFinite(-1))
        XCTAssertNil(DriveEnergyValueValidator.positiveFinite(.infinity))
        XCTAssertNil(DriveEnergyValueValidator.positiveFinite(.nan))
    }

    func testRatedRangeUsePrefersStartAndEndRangeAndNormalizesFallback() {
        XCTAssertEqual(DriveRange(startRange: 380, endRange: 342, rangeDiff: 38).usedDistance, 38)
        XCTAssertEqual(DriveRange(rangeDiff: -12).usedDistance, 12)
        XCTAssertEqual(DriveRange(startRange: 320, endRange: 340).usedDistance, 0)
    }

    func testCabinTelemetryUsesRecordedClimateSamples() {
        let telemetry = DriveCabinTelemetry(positions: [
            DrivePosition(climateInfo: DriveClimateInfo(isClimateOn: true, fanStatus: 3, driverTempSetting: 22, passengerTempSetting: 21)),
            DrivePosition(climateInfo: DriveClimateInfo(isClimateOn: true, fanStatus: 3, driverTempSetting: 22, passengerTempSetting: 21)),
            DrivePosition(climateInfo: DriveClimateInfo(isClimateOn: false, fanStatus: 1, driverTempSetting: 23, passengerTempSetting: 21))
        ])

        XCTAssertTrue(telemetry.hasClimateTelemetry)
        XCTAssertTrue(telemetry.wasClimateOn)
        XCTAssertEqual(telemetry.climateSampleCount, 3)
        XCTAssertEqual(telemetry.climateOnSampleCount, 2)
        XCTAssertEqual(telemetry.fanStatus, 3)
        XCTAssertEqual(telemetry.driverTemperatureSetting, 22)
        XCTAssertEqual(telemetry.passengerTemperatureSetting, 21)
    }

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
        XCTAssertEqual(DriveDetailPresentation.batteryText(start: 0, end: 0), "0% → 0%")
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
    }

    func testReplayBuilderKeepsMetricsAlignedWithValidRoutePoints() {
        let firstPoint = SyntheticCoordinates.point()
        let secondPoint = SyntheticCoordinates.point(latitudeOffset: 0.001, longitudeOffset: 0.001)
        let implausiblePoint = SyntheticCoordinates.point(latitudeOffset: 40, longitudeOffset: 80)
        let finalPoint = SyntheticCoordinates.point(latitudeOffset: 0.002, longitudeOffset: 0.002)
        let positions = [
            DrivePosition(date: "2026-07-01T08:00:00Z", latitude: SyntheticCoordinates.zero.latitude, longitude: SyntheticCoordinates.zero.longitude, speed: 1),
            DrivePosition(date: "2026-07-01T08:00:00Z", latitude: firstPoint.latitude, longitude: firstPoint.longitude, speed: 20),
            DrivePosition(date: "2026-07-01T08:00:10Z", latitude: secondPoint.latitude, longitude: secondPoint.longitude, speed: 30, power: 8),
            DrivePosition(date: "2026-07-01T08:00:11Z", latitude: implausiblePoint.latitude, longitude: implausiblePoint.longitude, speed: 99),
            DrivePosition(date: "2026-07-01T08:00:20Z", latitude: finalPoint.latitude, longitude: finalPoint.longitude, speed: 40, batteryLevel: 78)
        ]

        let samples = DriveReplayBuilder.samples(from: positions)

        XCTAssertEqual(samples.count, 3)
        XCTAssertEqual(samples.map(\.position.speed), [20, 30, 40])
        XCTAssertEqual(samples.last?.position.batteryLevel, 78)
        XCTAssertEqual(samples.map(\.latitude), [firstPoint.latitude, secondPoint.latitude, finalPoint.latitude])
    }

    func testReplayBuilderReturnsEmptyForMissingCoordinates() {
        XCTAssertTrue(DriveReplayBuilder.samples(from: [
            DrivePosition(speed: 20),
            DrivePosition(latitude: SyntheticCoordinates.invalidLatitude, longitude: SyntheticCoordinates.point().longitude)
        ]).isEmpty)
    }

    func testReplayTrailRefreshPolicyCapsMapOverlayRebuildsForDenseRoutes() {
        let sampleCount = 439
        var lastRenderedIndex: Int?
        var renderedIndices: [Int] = []

        for index in 0..<sampleCount {
            guard DriveReplayRenderPolicy.shouldRefreshTrail(
                lastRenderedIndex: lastRenderedIndex,
                currentIndex: index,
                sampleCount: sampleCount
            ) else {
                continue
            }
            renderedIndices.append(index)
            lastRenderedIndex = index
        }

        XCTAssertEqual(renderedIndices.first, 0)
        XCTAssertEqual(renderedIndices.last, sampleCount - 1)
        XCTAssertLessThanOrEqual(renderedIndices.count, 120)
    }

    func testDriveDetailStatsUsePositionDataBeforeSummaryFallbacks() async throws {
        let detail = DriveDetail.fixture()
        let api = FakeDriveAPI(detail: detail)
        let weatherLocation = SyntheticCoordinates.point()
        let weatherService = FakeDriveWeatherService(points: [
            WeatherPoint(latitude: weatherLocation.latitude, longitude: weatherLocation.longitude, temperatureCelsius: 17, weatherCode: 1)
        ])
        let settingsStore = DriveAnnotationSettingsStore(
            AppSettings(allowsThirdPartyRouteWeather: true)
        )
        let viewModel = DriveDetailViewModel(
            api: api,
            weatherService: weatherService,
            settingsStore: settingsStore
        )

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

    func testRouteWeatherRequiresConsentAndLoadsImmediatelyAfterPermissionIsSaved() async {
        let weatherLocation = SyntheticCoordinates.point()
        let weatherService = CountingDriveWeatherService(points: [
            WeatherPoint(
                latitude: weatherLocation.latitude,
                longitude: weatherLocation.longitude,
                temperatureCelsius: 18,
                weatherCode: 2
            )
        ])
        let settingsStore = DriveAnnotationSettingsStore()
        let viewModel = DriveDetailViewModel(
            api: FakeDriveAPI(detail: .fixture()),
            weatherService: weatherService,
            settingsStore: settingsStore
        )

        await viewModel.load(carId: 1, driveId: 10)

        let requestsBeforeConsent = await weatherService.requestCount()
        XCTAssertEqual(requestsBeforeConsent, 0)
        XCTAssertFalse(viewModel.state.allowsThirdPartyRouteWeather)
        XCTAssertTrue(viewModel.state.weatherPoints.isEmpty)

        await viewModel.enableRouteWeather()

        let requestsAfterConsent = await weatherService.requestCount()
        let storedSettings = await settingsStore.load()
        XCTAssertEqual(requestsAfterConsent, 1)
        XCTAssertTrue(storedSettings.allowsThirdPartyRouteWeather)
        XCTAssertTrue(viewModel.state.allowsThirdPartyRouteWeather)
        XCTAssertEqual(viewModel.state.weatherPoints.map(\.temperatureCelsius), [18])
    }

    func testDriveDetailAppearsBeforeSlowVehicleStatusFinishes() async {
        let api = DelayedDriveStatusAPI(detail: .fixture())
        let viewModel = DriveDetailViewModel(api: api)

        let loadTask = Task { await viewModel.load(carId: 1, driveId: 10) }
        await api.waitUntilStatusRequested()
        await waitUntil { viewModel.state.driveDetail != nil }

        XCTAssertNotNil(viewModel.state.driveDetail)
        XCTAssertFalse(viewModel.state.isLoading)

        await api.releaseStatus()
        await loadTask.value
    }

    func testRepeatedDriveDetailShowsExistingStateWhileFreshDetailLoads() async {
        let cache = DriveDetailStateCache()
        let key = DriveDetailCacheKey(serverURL: "https://teslamate.example", carId: 1, driveId: 10)
        let cachedDetail = DriveDetail(
            driveId: 10,
            startAddress: "Cached start",
            endAddress: "Cached end",
            distance: 12
        )
        let firstViewModel = DriveDetailViewModel(
            api: FakeDriveAPI(detail: cachedDetail),
            cacheKey: key,
            stateCache: cache
        )
        await firstViewModel.load(carId: 1, driveId: 10)

        let freshDetail = DriveDetail(
            driveId: 10,
            startAddress: "Fresh start",
            endAddress: "Fresh end",
            distance: 13
        )
        let delayedAPI = DelayedDriveDetailAPI(detail: freshDetail)
        let repeatedViewModel = DriveDetailViewModel(
            api: delayedAPI,
            cacheKey: key,
            stateCache: cache
        )

        XCTAssertEqual(repeatedViewModel.state.driveDetail?.startAddress, "Cached start")
        XCTAssertFalse(repeatedViewModel.state.isLoading)

        let refreshTask = Task { await repeatedViewModel.load(carId: 1, driveId: 10) }
        await delayedAPI.waitUntilDetailRequested()

        XCTAssertEqual(repeatedViewModel.state.driveDetail?.startAddress, "Cached start")
        XCTAssertFalse(repeatedViewModel.state.isLoading)

        await delayedAPI.releaseDetail()
        await refreshTask.value

        XCTAssertEqual(repeatedViewModel.state.driveDetail?.startAddress, "Fresh start")
        XCTAssertEqual(repeatedViewModel.state.driveDetail?.distance, 13)
        XCTAssertFalse(repeatedViewModel.state.isLoading)
    }

    func testCachedDriveSummaryAppearsWhileFreshDetailLoads() async {
        let summary = DriveSummaryItem(
            driveId: 10,
            carId: 1,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:30:00Z",
            distance: 24,
            durationMin: 30,
            energyConsumedNet: 4.8,
            efficiency: 200,
            efficiencySource: .api,
            startBatteryLevel: 81,
            endBatteryLevel: 71,
            isCached: true
        )
        let api = DelayedDriveDetailAPI(detail: .fixture())
        let viewModel = DriveDetailViewModel(
            api: api,
            summaryCache: DriveDetailSummaryCache(items: [summary])
        )

        let loadTask = Task { await viewModel.load(carId: 1, driveId: 10) }
        await api.waitUntilDetailRequested()
        await waitUntil { viewModel.state.isShowingSummary }

        XCTAssertEqual(viewModel.state.driveDetail?.distance, 24)
        XCTAssertEqual(viewModel.state.stats?.energyUsed, 4.8)
        XCTAssertFalse(viewModel.state.isLoading)
        XCTAssertTrue(viewModel.state.isRefreshing)

        await api.releaseDetail()
        await loadTask.value

        XCTAssertFalse(viewModel.state.isShowingSummary)
        XCTAssertFalse(viewModel.state.isRefreshing)
        XCTAssertEqual(viewModel.state.driveDetail?.startAddress, "Home")
    }

    func testDriveMetricDetailAppearsBeforeSlowVehicleStatusFinishes() async {
        let api = DelayedDriveStatusAPI(detail: .fixture())
        let viewModel = DriveMetricDetailViewModel(api: api)

        let loadTask = Task { await viewModel.load(carId: 1, driveId: 10) }
        await api.waitUntilStatusRequested()
        await waitUntil { viewModel.state.driveDetail != nil }

        XCTAssertNotNil(viewModel.state.driveDetail)
        XCTAssertFalse(viewModel.state.isLoading)

        await api.releaseStatus()
        await loadTask.value
    }

    func testDriveMetricDetailKeepsCachedSummaryWhenRefreshFails() async {
        let detail = DriveDetail.fixture(energyConsumedNet: 4.8)
        let stats = DriveStatsCalculator.calculateStats(detail)
        let viewModel = DriveMetricDetailViewModel(
            api: FakeDriveAPI(
                detailResult: .failure(.network("offline")),
                statusResult: .failure(.network("offline"))
            ),
            initialState: DriveMetricDetailState(
                isLoading: false,
                driveDetail: detail,
                stats: stats,
                units: .metric
            )
        )

        await viewModel.load(carId: 1, driveId: 10)

        XCTAssertEqual(viewModel.state.driveDetail, detail)
        XCTAssertEqual(viewModel.state.stats, stats)
        XCTAssertEqual(viewModel.state.errorMessage, APIError.network("offline").driveMessage)
        XCTAssertFalse(viewModel.state.isLoading)
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

    func testDriveDetailTreatsZeroAPIEnergyAsMissingAndUsesPowerSamples() throws {
        let detail = DriveDetail(
            driveId: 10,
            startDate: "2026-07-01T08:00:00Z",
            endDate: "2026-07-01T08:00:20Z",
            odometerDetails: DriveOdometerDetails(distance: 0.5),
            durationMin: 1,
            energyConsumedNet: 0,
            positions: [
                DrivePosition(date: "2026-07-01T08:00:00Z", power: 18),
                DrivePosition(date: "2026-07-01T08:00:10Z", power: 18),
                DrivePosition(date: "2026-07-01T08:00:20Z", power: -18)
            ]
        )

        let stats = DriveStatsCalculator.calculateStats(detail)

        XCTAssertEqual(try XCTUnwrap(stats.energyUsed), 0.05, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(stats.efficiency), 100, accuracy: 0.1)
        XCTAssertEqual(stats.energySource, .powerSamples)
    }

    func testDriveDetailTreatsZeroEnergyAsMissingAndUsesPositiveConsumptionFallback() throws {
        let detail = DriveDetail.fixture(energyConsumedNet: 0, consumptionNet: 165)

        let stats = DriveStatsCalculator.calculateStats(detail)

        XCTAssertNil(stats.energyUsed)
        XCTAssertEqual(stats.efficiency, 165)
        XCTAssertEqual(stats.energySource, .api)
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

    private func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        if !condition() {
            XCTFail("Timed out waiting for the expected drive-detail state", file: file, line: line)
        }
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

    func testRouteLabelRulePersistsThroughSettingsRoundTripAndOldSettingsDecode() throws {
        let route = DriveRouteFingerprint(points: (0..<4).map { index in
            let point = SyntheticCoordinates.point(
                latitudeOffset: Double(index) * 0.01,
                longitudeOffset: Double(index) * 0.01
            )
            return DriveRoutePoint(latitude: point.latitude, longitude: point.longitude)
        })
        let rule = DriveRouteLabelRule(
            carId: 7,
            name: "接送",
            iconName: "figure.2.and.child.holdinghands",
            colorHex: "AF52DE",
            typicalDistanceKm: 12.3,
            fingerprint: route
        )
        let settings = AppSettings(driveRouteLabelRules: [rule])

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        let oldSettings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(decoded.driveRouteLabelRules, [rule])
        XCTAssertTrue(oldSettings.driveRouteLabelRules.isEmpty)
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

    func testDriveChartSamplesLimitLongTripsWhilePreservingEndpointsAndPeak() throws {
        var positions: [DrivePosition] = []
        for index in 0..<1_000 {
            let date = String(
                format: "2026-07-01T%02d:%02d:%02dZ",
                8 + index / 3_600,
                (index / 60) % 60,
                index % 60
            )
            positions.append(DrivePosition(date: date, speed: index == 517 ? 180 : index % 90))
        }

        let samples = DriveChartSampleBuilder.samples(kind: .speed, positions: positions, units: .metric)

        XCTAssertLessThanOrEqual(samples.count, DriveChartSampleBuilder.maximumSamplesPerSeries)
        XCTAssertEqual(samples.first?.date, DomainDateParser.date(from: positions.first?.date ?? ""))
        XCTAssertEqual(samples.last?.date, DomainDateParser.date(from: positions.last?.date ?? ""))
        XCTAssertEqual(samples.map { $0.value }.max(), 180)
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

private actor DelayedDriveStatusAPI: DriveAPIProviding {
    private let detail: DriveDetail
    private var statusRequested = false
    private var statusWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(detail: DriveDetail) {
        self.detail = detail
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .success(detail)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        statusRequested = true
        statusWaiters.forEach { $0.resume() }
        statusWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km")))
    }

    func waitUntilStatusRequested() async {
        guard !statusRequested else { return }
        await withCheckedContinuation { statusWaiters.append($0) }
    }

    func releaseStatus() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor DelayedDriveDetailAPI: DriveAPIProviding {
    private let detail: DriveDetail
    private var detailRequested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(detail: DriveDetail) {
        self.detail = detail
    }

    func drives(carId _: Int, startDate _: String?, endDate _: String?, page _: Int?, show _: Int?) async -> APIResult<[DriveData]> {
        .success([])
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        detailRequested = true
        requestWaiters.forEach { $0.resume() }
        requestWaiters.removeAll()
        await withCheckedContinuation { releaseWaiters.append($0) }
        return .success(detail)
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: Units(unitOfLength: "km")))
    }

    func waitUntilDetailRequested() async {
        guard !detailRequested else { return }
        await withCheckedContinuation { requestWaiters.append($0) }
    }

    func releaseDetail() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private struct FakeDriveWeatherService: DriveWeatherServicing {
    let points: [WeatherPoint]

    func weatherAlongDrive(positions _: [WeatherRoutePosition], totalDistanceKm _: Double) async -> [WeatherPoint] {
        points
    }
}

private actor CountingDriveWeatherService: DriveWeatherServicing {
    private let points: [WeatherPoint]
    private var calls = 0

    init(points: [WeatherPoint]) {
        self.points = points
    }

    func weatherAlongDrive(
        positions _: [WeatherRoutePosition],
        totalDistanceKm _: Double
    ) async -> [WeatherPoint] {
        calls += 1
        return points
    }

    func requestCount() -> Int {
        calls
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

private actor DriveDetailSummaryCache: DriveSummaryCaching {
    private var items: [DriveSummaryItem]

    init(items: [DriveSummaryItem]) {
        self.items = items
    }

    func load(carId: Int) async -> [DriveSummaryItem] {
        items.filter { $0.carId == carId }
    }

    func save(_ items: [DriveSummaryItem], carId _: Int) async {
        self.items = items
    }
}

private extension DriveDetail {
    static func fixture(energyConsumedNet: Double? = 4.8, consumptionNet: Double? = nil) -> DriveDetail {
        let firstPoint = SyntheticCoordinates.point()
        let secondPoint = SyntheticCoordinates.point(latitudeOffset: 0.1, longitudeOffset: 0.1)
        let finalPoint = SyntheticCoordinates.point(latitudeOffset: 0.2, longitudeOffset: 0.2)
        return DriveDetail(
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
                DrivePosition(date: "2026-07-01T08:00:00Z", latitude: firstPoint.latitude, longitude: firstPoint.longitude, speed: 20, power: 10, batteryLevel: 80, elevation: 100),
                DrivePosition(date: "2026-07-01T08:15:00Z", latitude: secondPoint.latitude, longitude: secondPoint.longitude, speed: 80, power: 30, batteryLevel: 75, elevation: 125),
                DrivePosition(date: "2026-07-01T08:30:00Z", latitude: finalPoint.latitude, longitude: finalPoint.longitude, speed: 50, power: -12, batteryLevel: 72, elevation: 115)
            ]
        )
    }
}
