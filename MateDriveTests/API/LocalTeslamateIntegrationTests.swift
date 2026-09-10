import Foundation
import XCTest
@testable import MateDriveApp

final class LocalTeslamateIntegrationTests: XCTestCase {
    func testPhysicalDeviceCanReachLocalTeslaMateEndpointWithoutCredentials() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["MATEDRIVE_INTEGRATION_LAN_PROBE_BASE_URL"],
              let baseURL = URL(string: rawURL)
        else {
            throw XCTSkip("Set MATEDRIVE_INTEGRATION_LAN_PROBE_BASE_URL for the physical-device LAN probe.")
        }

        var request = URLRequest(url: baseURL.appending(path: "api/v1/cars"))
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
            print("Physical-device LAN probe \(baseURL) returned HTTP \(statusCode).")
            XCTAssertTrue(
                (200...299).contains(statusCode) || statusCode == 401 || statusCode == 403,
                "Expected a TeslaMate success or authentication response from \(baseURL.host ?? "the LAN host"), got HTTP \(statusCode)."
            )
        } catch {
            XCTFail("The physical device could not reach the LAN TeslaMate endpoint \(baseURL): \(error)")
        }
    }

    func testLocalTeslaMateTripRoutesPopulatePersistentCache() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let drives = try await requireSuccess(api.drives(carId: car.carId, startDate: nil, endDate: nil, page: 1, show: 10))
        let driveIds = Array(drives.compactMap(\.driveId).prefix(5))
        XCTAssertFalse(driveIds.isEmpty)

        let database = try SQLiteDatabase.inMemory()
        try await Migrations.applyAll(to: database)
        let cache = DatabaseBackedTripRouteCache(databaseProvider: IntegrationDatabaseProvider(database: database))
        let provider = APITripDataProvider(api: api, routeCache: cache)

        let segments = await provider.routeSegments(carId: car.carId, driveIds: driveIds)

        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            let cached = try await cache.points(carId: car.carId, driveId: segment.driveId)
            XCTAssertEqual(cached, segment.points)
            XCTAssertGreaterThanOrEqual(segment.points.count, 2)
        }
        let cachedCount = try await database.intValues("SELECT COUNT(*) FROM trip_route_cache;").first
        XCTAssertEqual(cachedCount, segments.count)
    }

    func testLocalTeslaMateDriveDetailProvidesTripTirePressureSamples() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let drives = try await requireSuccess(api.drives(carId: car.carId, startDate: nil, endDate: nil, page: 1, show: 10))
        let driveIds = Array(drives.compactMap(\.driveId).prefix(5))

        var pressureSamples: [DriveChartSample] = []
        for driveId in driveIds {
            let detail = try await requireSuccess(api.driveDetail(carId: car.carId, driveId: driveId))
            pressureSamples = DriveChartSampleBuilder.samples(
                kind: .tirePressure,
                positions: detail.positions ?? [],
                units: .metric,
                sourcePressureUnit: detail.sourceUnits?.unitOfPressure
            )
            if !pressureSamples.isEmpty { break }
        }

        XCTAssertFalse(pressureSamples.isEmpty)
        XCTAssertTrue(pressureSamples.allSatisfy { $0.value > 0 })
        XCTAssertTrue(Set(pressureSamples.map(\.series)).isSubset(of: ["frontLeft", "frontRight", "rearLeft", "rearRight"]))
    }

    func testLocalTeslaMateAPIDecodesEnvironmentAndTireHistory() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.environmentHistory(carId: car.carId, range: "30d", grain: "day"))

        XCTAssertFalse(response.data.series.isEmpty)
        XCTAssertTrue(response.data.series.contains { $0.timestamp != nil })
        XCTAssertTrue(response.data.series.contains { $0.outsideTemp != nil || $0.insideTemp != nil })
        XCTAssertTrue(response.data.series.contains { $0.tpmsPressureFl != nil || $0.tpmsPressureFr != nil || $0.tpmsPressureRl != nil || $0.tpmsPressureRr != nil })
        XCTAssertGreaterThan(response.data.summary?.sampleCount ?? 0, 0)
        XCTAssertNotNil(response.units?.unitOfTemperature)
        XCTAssertNotNil(response.units?.unitOfPressure)
    }

    func testLocalTeslaMateAPI251AKSKAuthenticationAndRejectionRules() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["MATEDRIVE_INTEGRATION_AKSK_BASE_URL"],
              let baseURL = URL(string: rawURL),
              let accessKey = environment["MATEDRIVE_INTEGRATION_ACCESS_KEY"],
              let secretKey = environment["MATEDRIVE_INTEGRATION_SECRET_KEY"]
        else {
            throw XCTSkip("Set the MATEDRIVE_INTEGRATION_AKSK_* variables for AK/SK integration tests.")
        }
        let credentials = AKSKCredentials(accessKey: accessKey, secretKey: secretKey)
        let api = TeslamateAPI(baseURL: baseURL, aksk: credentials)

        let version = try await requireSuccess(api.version())
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(version.resolvedVersion), TeslaMateAPIVersion(major: 2, minor: 5, patch: 1))

        let rejectedAPI = TeslamateAPI(
            baseURL: baseURL,
            aksk: AKSKCredentials(accessKey: accessKey, secretKey: secretKey + "-wrong")
        )
        switch await rejectedAPI.version() {
        case .success:
            XCTFail("Expected the wrong secret key to be rejected")
        case let .failure(error):
            XCTAssertEqual(error, .httpStatus(401))
        }

        let versionURL = baseURL.appending(path: "api/v1/version")
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let signed = try AKSKRequestSigner.authenticated(
            URLRequest(url: versionURL),
            credentials: credentials,
            timestamp: Int64(Date().timeIntervalSince1970),
            nonce: nonce
        )
        let (_, firstResponse) = try await URLSession.shared.data(for: signed)
        let (_, replayResponse) = try await URLSession.shared.data(for: signed)
        XCTAssertEqual((firstResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((replayResponse as? HTTPURLResponse)?.statusCode, 401)

        let stale = try AKSKRequestSigner.authenticated(
            URLRequest(url: versionURL),
            credentials: credentials,
            timestamp: Int64(Date().timeIntervalSince1970) - 3_600,
            nonce: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        )
        let (_, staleResponse) = try await URLSession.shared.data(for: stale)
        XCTAssertEqual((staleResponse as? HTTPURLResponse)?.statusCode, 401)
    }

    func testLocalTeslaMateMileageReconstructsCompleteEnergyTotals() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let viewModel = await MainActor.run { MileageViewModel(provider: APIMileageDataProvider(api: api)) }

        await viewModel.load(carId: car.carId)
        let state = await MainActor.run { viewModel.state }

        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.years.isEmpty)
        XCTAssertTrue(state.years.allSatisfy { $0.energy != nil })
        XCTAssertGreaterThan(state.years.compactMap(\.energy).reduce(0, +), 0)
        XCTAssertTrue(state.years.allSatisfy(\.energyCostIsComplete))
        XCTAssertEqual(
            state.years.reduce(0) { $0 + $1.pricedChargeCount },
            state.years.reduce(0) { $0 + $1.chargeCount }
        )
        XCTAssertGreaterThan(state.years.compactMap(\.energyCost).reduce(0, +), 0)
    }

    func testLocalTeslaMateDriveListPreservesReconstructedEnergySources() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let provider = APIDriveSummaryProvider(api: api)
        let summaries = try await requireSuccess(provider.driveSummaries(carId: car.carId))
        let items = await provider.enrichDriveSummaries(summaries, carId: car.carId)
        let valuesWithEfficiency = items.filter { $0.efficiency != nil }

        XCTAssertFalse(valuesWithEfficiency.isEmpty)
        XCTAssertTrue(valuesWithEfficiency.allSatisfy { $0.efficiencySource != .unavailable })
        XCTAssertTrue(valuesWithEfficiency.contains { $0.efficiencySource == .powerSamples })
    }

    func testLocalTeslaMateChargeSummaryReportsCompleteAPICostCoverage() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let viewModel = await MainActor.run {
            ChargesViewModel(store: APIChargeSummaryProvider(api: api), showShortEntries: true)
        }

        await viewModel.load(carId: car.carId)
        let summary = await MainActor.run { viewModel.state.summary }

        XCTAssertGreaterThan(summary.totalCharges, 0)
        XCTAssertEqual(summary.pricedChargeCount, summary.totalCharges)
        XCTAssertEqual(summary.missingCostCount, 0)
        XCTAssertEqual(summary.apiCostCount, summary.totalCharges)
        XCTAssertEqual(summary.pricingRuleCostCount, 0)
        XCTAssertEqual(summary.manualCostCount, 0)
    }

    func testLocalTeslaMateDiagnosticReportsHistoricalDataQuality() async throws {
        let config = try Self.localConfig()
        let report = await TeslaMateConnectionDiagnostic().run(
            settings: AppSettings(serverURL: config.baseURL.absoluteString),
            token: config.token,
            basicAuth: config.basicAuth,
            language: .chinese
        )

        let quality = try XCTUnwrap(report.checks.first { $0.checkID == .historyDataQuality })
        let environment = try XCTUnwrap(report.checks.first { $0.checkID == .environmentHistory })
        let vehicle = try XCTUnwrap(report.checks.first { $0.checkID == .vehicleInfo })
        XCTAssertEqual(vehicle.status, .passed)
        XCTAssertTrue(vehicle.message.contains("2022 Model 3 Performance"))
        XCTAssertTrue(vehicle.message.contains("Pinwheel18CapKit"))
        XCTAssertEqual(quality.status, .warning)
        XCTAssertTrue(quality.message.contains("全部"))
        XCTAssertTrue(quality.message.contains("条行程"))
        XCTAssertTrue(quality.message.contains("可重建"))
        XCTAssertTrue(quality.message.contains("条充电"))
        XCTAssertTrue(quality.message.contains("缺核心采样"))
        XCTAssertEqual(environment.status, .passed)
        XCTAssertTrue(environment.message.contains("温度覆盖"))
        XCTAssertTrue(environment.message.contains("胎压覆盖"))

        let export = TeslaMateDiagnosticExport.render(
            report: report,
            metadata: TeslaMateDiagnosticExportMetadata(
                appVersion: "integration",
                appBuild: "test",
                languageCode: "zh-Hans",
                unitSystem: "teslamate",
                currencyCode: "CNY"
            )
        )
        XCTAssertTrue(export.contains("api_version:"))
        XCTAssertTrue(export.contains("historyDataQuality"))
        XCTAssertFalse(export.contains(config.baseURL.absoluteString))
        if let token = config.token {
            XCTAssertFalse(export.contains(token))
        }
        if let basicAuth = config.basicAuth {
            XCTAssertFalse(export.contains(basicAuth.username))
            XCTAssertFalse(export.contains(basicAuth.password))
        }
    }

    func testLocalTeslaMateAPIDiscoversEnhancedCapabilities() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(
            baseURL: config.baseURL,
            bearerToken: config.token,
            basicAuth: config.basicAuth
        )
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let reportedVersion = try await requireSuccess(api.version())
        let profile = await TeslaMateCapabilityService().discover(api: api, carId: car.carId, force: true)

        XCTAssertEqual(profile.version.resolvedVersion, reportedVersion.resolvedVersion)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(profile.version.resolvedVersion),
            TeslaMateCapabilityPresentation.enhancedFeatureMinimumVersion
        )
        for capability in [
            TeslaMateCapability.serverStats,
            .costReview,
            .unifiedActivities,
            .batteryHealthHistory,
            .driveInsights,
            .environmentHistory,
            .topDrainLocations,
            .commuteRoutes,
            .statsExtremes,
            .drivingCoordinates,
            .serverPlaces
        ] {
            let state = try XCTUnwrap(profile.status(for: capability)?.state)
            XCTAssertTrue(
                state == .available || state == .degraded,
                "Expected \(capability.rawValue) on the configured local API, got \(state)"
            )
        }
    }

    func testLocalTeslaMateAPIDecodesServerStatsWithMeasuredUnits() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.serverStats(carId: car.carId))
        let summary = try XCTUnwrap(response.summary)

        XCTAssertGreaterThan(summary.totalDistanceKm ?? 0, 0)
        XCTAssertGreaterThan(summary.avgConsumptionNet ?? 0, 0)
        XCTAssertLessThan(summary.avgConsumptionNet ?? .greatestFiniteMagnitude, 1_000)
        XCTAssertGreaterThanOrEqual(summary.avgRegenCaptureRate ?? -1, 0)
        XCTAssertLessThanOrEqual(summary.avgRegenCaptureRate ?? 2, 1)
        XCTAssertEqual(response.units?.unitOfLength, "km")
        XCTAssertFalse(response.data.isEmpty)
    }

    func testLocalTeslaMateAPI26DecodesCostReviewAndPreservesMissingCostSemantics() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let endDate = Date()
        let startDate = endDate.addingTimeInterval(-30 * 24 * 60 * 60)

        let response = try await requireSuccess(api.costReview(carId: car.carId, startDate: startDate, endDate: endDate))

        XCTAssertEqual(response.contractVersion, 1)
        XCTAssertEqual(response.data.range.period, "day")
        XCTAssertEqual(response.data.dataQuality.hasAnyActivity, true)
        XCTAssertFalse(response.data.buckets.isEmpty)
        XCTAssertNotNil(response.data.comparison?.previousRange)
        XCTAssertEqual(
            response.data.summary.missingChargeCostCount,
            response.data.dataQuality.chargingCost.missingCostCount
        )
        XCTAssertEqual(
            response.data.summary.missingParkingCostCount,
            response.data.dataQuality.parkingCost.missingCostCount
        )
        XCTAssertEqual(response.units?.unitOfLength, "km")
        if (response.data.summary.missingParkingCostCount ?? 0) > 0 {
            XCTAssertNil(response.data.summary.parkingCost)
        }
    }

    func testLocalTeslaMateAPI26ChargeCostUpdateSurfacesBusinessErrors() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let missingChargeId = 999_999_999

        switch await api.updateChargeCost(chargeId: missingChargeId, cost: 12.34) {
        case .success:
            XCTFail("Expected the nonexistent charging process to be rejected")
        case let .failure(error):
            XCTAssertEqual(error, .invalidResponse("Charging process not found"))
        }
    }

    func testLocalTeslaMateAnnualHeatmapMatchesRawHistoryTotals() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        async let drivesResult = VehicleHistoryPaginator.drives(loadPage: { page, show in
            await api.drives(carId: car.carId, page: page, show: show)
        })
        async let chargesResult = VehicleHistoryPaginator.charges(loadPage: { page, show in
            await api.charges(carId: car.carId, page: page, show: show)
        })
        let rawDrives = await drivesResult
        let rawCharges = await chargesResult
        let drives = try await requireSuccess(rawDrives)
        let charges = try await requireSuccess(rawCharges)
        let calendar = Calendar.current
        let years = (drives.compactMap { $0.startDate.flatMap(DomainDateParser.date(from:)) } +
            charges.compactMap { $0.startDate.flatMap(DomainDateParser.date(from:)) })
            .map { calendar.component(.year, from: $0) }
        let year = try XCTUnwrap(years.max())

        let days = await StatsViewModel.dailyActivity(year: year, drives: drives, charges: charges, calendar: calendar)
        let expectedDrives = drives.filter { $0.startDate.flatMap(DomainDateParser.date(from:)).map { calendar.component(.year, from: $0) == year } == true }
        let expectedCharges = charges.filter { $0.startDate.flatMap(DomainDateParser.date(from:)).map { calendar.component(.year, from: $0) == year } == true }

        XCTAssertTrue(days.count == 365 || days.count == 366)
        XCTAssertEqual(days.reduce(0) { $0 + $1.driveCount }, expectedDrives.count)
        XCTAssertEqual(days.reduce(0) { $0 + $1.chargeCount }, expectedCharges.count)
        XCTAssertEqual(days.reduce(0) { $0 + $1.distanceKm }, expectedDrives.reduce(0) { $0 + ($1.distance ?? 0) }, accuracy: 0.001)
        XCTAssertEqual(days.reduce(0) { $0 + $1.chargeEnergyKWh }, expectedCharges.reduce(0) { $0 + ($1.chargeEnergyAdded ?? 0) }, accuracy: 0.001)
    }

    func testLocalTeslaMateAPIDecodesUnifiedActivitiesAndKnownPaginationAnomaly() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.activities(carId: car.carId, page: 1, show: 20))

        XCTAssertFalse(response.data.isEmpty)
        XCTAssertTrue(response.data.allSatisfy { $0.kind != .unknown })
        XCTAssertEqual(response.pagination?.totalRecords, 0)
        XCTAssertEqual(response.pagination?.totalPages, 9_999)
        XCTAssertEqual(response.pagination?.limit, 20)
    }

    func testLocalTeslaMateLoadsCompleteActivityHistoryFromActualPages() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let viewModel = await MainActor.run { ActivitiesViewModel(api: api) }

        await viewModel.load(carId: car.carId)
        await viewModel.loadCompleteHistory(maximumPages: 50)
        let state = await MainActor.run { viewModel.state }
        let summary = await MainActor.run { viewModel.periodSummary }

        XCTAssertTrue(state.historyFullyLoaded)
        XCTAssertFalse(state.historyLoadCapped)
        XCTAssertGreaterThan(state.loadedPageCount, 1)
        XCTAssertEqual(summary.activityCount, state.items.count)
        XCTAssertGreaterThan(summary.driveCount, 0)
        XCTAssertGreaterThan(summary.chargeCount, 0)
        XCTAssertGreaterThan(summary.parkingCount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(summary.distanceKm), 0)
        XCTAssertGreaterThan(try XCTUnwrap(summary.chargedEnergyKWh), 0)
        XCTAssertGreaterThan(summary.knownChargeCost ?? 0, 0)
        XCTAssertEqual(summary.pricedChargeCount, summary.chargeCount)
        XCTAssertEqual(summary.missingChargeCostCount, 0)
        XCTAssertTrue(summary.chargeCostIsComplete)
        let places = PlaceInsightsViewModel.aggregate(state.items)
        XCTAssertGreaterThan(places.count, 1)
        XCTAssertTrue(places.contains { $0.chargeCount > 0 })
        XCTAssertTrue(places.contains { $0.parkingCount > 0 })
        XCTAssertTrue(places.contains {
            GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) != nil
        })
        let pricedParking = try XCTUnwrap(state.items.first {
            $0.kind == .park && ($0.durationMin ?? 0) > 0 && $0.startAddress?.isEmpty == false
        })
        let parkingRule = ParkingFeeRule(
            name: "Integration Parking",
            addressKeyword: pricedParking.startAddress,
            freeMinutes: 0,
            billingIncrementMinutes: 60,
            hourlyRate: 1
        )
        let parkingSummary = ParkingFeeRuleEngine.summarize(
            state.items.filter { $0.kind == .park }.map {
                ParkingFeeInput(startDate: $0.startDate, address: $0.startAddress, latitude: $0.startLatitude, longitude: $0.startLongitude, durationMinutes: $0.durationMin)
            },
            rules: [parkingRule]
        )
        XCTAssertGreaterThan(parkingSummary.matchedParkingCount, 0)
        XCTAssertGreaterThan(parkingSummary.totalCost, 0)
    }

    func testLocalTeslaMateStatsCombinesCompleteParkingAndChargeCosts() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let settings = AppSettings(currencyCode: "CNY", parkingFeeRules: [
            ParkingFeeRule(name: "Integration All Parking", monthlyFee: 100)
        ])
        let viewModel = await MainActor.run {
            StatsViewModel(api: api, settingsStore: IntegrationSettingsStore(settings: settings), activityAPI: api)
        }

        await viewModel.load(carId: car.carId)
        let state = await MainActor.run { viewModel.state }
        let total = await MainActor.run { viewModel.displayedTotalVehicleCost }
        let chargeCostIsComplete = await MainActor.run { viewModel.chargeCostIsComplete }

        XCTAssertTrue(state.parkingCostAvailable)
        XCTAssertTrue(state.parkingHistoryComplete)
        XCTAssertGreaterThan(state.parkingCost.matchedParkingCount, 0)
        XCTAssertEqual(state.parkingCost.unmatchedParkingCount, 0)
        XCTAssertGreaterThan(state.parkingCost.totalCost, 0)
        XCTAssertEqual(state.summary.pricedChargeCount, state.summary.totalCharges)
        XCTAssertEqual(state.summary.missingChargeCostCount, 0)
        XCTAssertTrue(chargeCostIsComplete)
        XCTAssertNotNil(total)
    }

    func testLocalTeslaMateAPIDecodesLocationStandbyDrain() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let status = try await requireSuccess(api.carStatus(carId: car.carId))
        let latitude = try XCTUnwrap(status.status?.latitude)
        let longitude = try XCTUnwrap(status.status?.longitude)

        let response = try await requireSuccess(api.standbyDrain(carId: car.carId, latitude: latitude, longitude: longitude))
        let data = try XCTUnwrap(response.data)

        XCTAssertEqual(data.periodDays, 30)
        XCTAssertGreaterThan(data.radiusMeters ?? 0, 0)
        XCTAssertGreaterThanOrEqual(data.totalParkingEvents ?? 0, 0)
        XCTAssertGreaterThanOrEqual(data.totalRangeLossKm ?? 0, 0)
        XCTAssertLessThanOrEqual(data.averageDrainPercent24H ?? 0, 0)
        XCTAssertEqual(response.units?.length, "km")
    }

    func testLocalTeslaMateAPIDecodesTopStandbyDrainLocations() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.topDrainLocations(carId: car.carId))

        XCTAssertFalse(response.locations.isEmpty)
        XCTAssertTrue(response.locations.allSatisfy { GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) != nil })
        XCTAssertTrue(response.locations.contains { ($0.totalRangeLossKm ?? 0) > 0 })
        XCTAssertTrue(response.locations.contains { ($0.parkingCount ?? 0) > 0 })
        XCTAssertNotNil(response.units?.unitOfLength)
    }

    func testLocalTeslaMateAPIDecodesCommuteRoutesAndMeasuredInsights() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.commuteRoutes(carId: car.carId))

        XCTAssertFalse(response.routes.isEmpty)
        XCTAssertGreaterThan(response.summary?.totalCommuteDrives ?? 0, 0)
        XCTAssertTrue(response.routes.contains { ($0.tripCount ?? 0) > 0 })
        XCTAssertTrue(response.routes.contains { ($0.totalDistanceKm ?? 0) > 0 })
        XCTAssertTrue(response.routes.contains { ($0.averageRegenCaptureRate ?? 0) > 0 })
        XCTAssertTrue(response.routes.contains { ($0.averagePercentSpeed0To20 ?? 0) > 0 })
        XCTAssertEqual(response.units?.unitOfLength, "km")
    }

    func testLocalTeslaMateAPIDecodesDrivingRecordsAndLinksDrives() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.statsExtremes(carId: car.carId))

        XCTAssertGreaterThanOrEqual(response.extremes.count, 8)
        XCTAssertTrue(response.extremes.contains { $0.type == "longest_distance" && ($0.value ?? 0) > 0 && $0.driveId != nil })
        XCTAssertTrue(response.extremes.contains { $0.type == "highest_speed" && ($0.value ?? 0) > 0 && $0.driveId != nil })
        XCTAssertTrue(response.extremes.contains { $0.type == "daily_most_drives" && $0.driveId == nil })
        XCTAssertEqual(response.units?.unitOfLength, "km")
    }

    func testLocalTeslaMateAPIDecodesRecentDrivingCoordinates() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let response = try await requireSuccess(api.drivingCoordinates(carId: car.carId))
        let points = response.data.coordinates

        XCTAssertGreaterThan(points.count, 100)
        XCTAssertGreaterThan(Set(points.compactMap(\.driveId)).count, 1)
        XCTAssertTrue(points.allSatisfy { GeoCoordinateValidator.location(latitude: $0.latitude, longitude: $0.longitude) != nil })
        XCTAssertTrue(points.contains { $0.type == "start" })
        XCTAssertTrue(points.contains { $0.type == "end" })
        XCTAssertEqual(response.data.simplifiedPoints, points.count)
        XCTAssertEqual(response.data.units?.length, "km")
    }

    func testLocalTeslaMateAPIDecodesAllSmartPlacePages() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        let first = try await requireSuccess(api.places(carId: car.carId, page: 1, show: 20))
        let second = try await requireSuccess(api.places(carId: car.carId, page: 2, show: 20))
        let places = first.data + second.data

        XCTAssertEqual(places.count, first.pagination?.totalRecords)
        XCTAssertTrue(places.contains { ($0.visitCount ?? 0) > 0 && $0.role != nil })
        XCTAssertTrue(places.contains { ($0.chargeCount ?? 0) > 0 && ($0.totalChargeKwh ?? 0) > 0 })
        XCTAssertTrue(places.contains { ($0.parkCount ?? 0) > 0 && ($0.totalParkingDurationMin ?? 0) > 0 })
        XCTAssertTrue(places.contains { ($0.missingChargeCostCount ?? 0) > 0 })
        XCTAssertEqual(first.units?.unitOfLength, "km")
    }

    func testLocalTeslaMateAPIDecodesAchievementsAndSummary() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let payload = try await requireSuccess(api.achievements(carId: car.carId))

        XCTAssertEqual(payload.summary?.total, payload.achievements.count)
        XCTAssertEqual(payload.summary?.unlocked, payload.achievements.filter { $0.tiers.contains(where: \.unlocked) }.count)
        XCTAssertFalse(payload.achievements.isEmpty)
        XCTAssertTrue(payload.achievements.allSatisfy { !$0.tiers.isEmpty })
        XCTAssertEqual(payload.units?.unitOfLength, "km")
    }

    func testLocalTeslaMateAPIDecodesBatteryHistoryAndDerivedEfficiency() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let history = try await requireSuccess(api.batteryHistory(carId: car.carId))
        let charts = try XCTUnwrap(history.charts)

        XCTAssertFalse(charts.capacity.isEmpty)
        XCTAssertFalse(charts.range.isEmpty)
        XCTAssertGreaterThan(charts.capacity.first?.odometer ?? 0, 100_000)
        XCTAssertGreaterThan(history.efficiency?.qualifyingChargeCount ?? 0, 0)
        XCTAssertEqual(history.efficiency?.whPerKm ?? 0, 146, accuracy: 0.01)
        XCTAssertEqual(history.units?.unitOfLength, "km")
        let resolvedSummary = await BatteryViewModel.historySummary(from: history)
        let summary = try XCTUnwrap(resolvedSummary)
        XCTAssertTrue(summary.capacityUsesMedian)
        XCTAssertGreaterThan(summary.rangeSmoothingSampleCount, 1)
        XCTAssertGreaterThan(summary.capacityCurrentKWh ?? 0, 60)
        XCTAssertGreaterThan(summary.rangeCurrentKm ?? 0, 400)
        XCTAssertGreaterThan(summary.quality.score, 0)
        XCTAssertLessThanOrEqual(summary.quality.score, 100)
        XCTAssertGreaterThan(summary.quality.capacitySampleCount, 0)
        XCTAssertGreaterThan(summary.quality.rangeSampleCount, 0)
        XCTAssertGreaterThan(summary.quality.recordedDistanceKm, 1_000)

        let health = try await requireSuccess(api.batteryHealth(carId: car.carId))
        let status = try await requireSuccess(api.carStatus(carId: car.carId))
        let recordingStart = try XCTUnwrap(charts.range.first?.odometer)
        let stats = await BatteryViewModel.computeStats(
            health: health,
            status: status.status,
            ratedEfficiencyFallback: history.efficiency?.whPerKm,
            batteryRecordingStartOdometerKm: recordingStart
        )
        XCTAssertEqual(stats.healthSource, .recordedPeriod)
        XCTAssertFalse(stats.showsAbsoluteHealth)
        XCTAssertFalse(stats.hasOriginalCapacityData)
        XCTAssertGreaterThan(stats.maxRangeNow ?? -.infinity, 400)
        XCTAssertLessThan(stats.maxRangeNow ?? .infinity, 550)
    }

    func testLocalTeslaMateAPIDecodesDriveInsightsAndServerEvaluations() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)

        let insights = try await requireSuccess(api.driveInsights(carId: car.carId))
        let route = try XCTUnwrap(insights.driveStats.first)
        let activities = try await requireSuccess(api.activities(carId: car.carId, page: 1, show: 20))
        let evaluations = activities.data.flatMap { $0.stats?.evaluations ?? [] }

        XCTAssertGreaterThan(route.driveCount ?? 0, 1)
        XCTAssertGreaterThan(route.avgDistanceKm ?? 0, 0)
        XCTAssertLessThan(route.avgEnergyKwh ?? 0, 0)
        XCTAssertGreaterThan(route.consumptionWhKm ?? 0, 50)
        XCTAssertFalse(evaluations.isEmpty)
        XCTAssertTrue(evaluations.allSatisfy { !$0.type.isEmpty })
    }

    func testLocalTeslaMateAPIDecodesCoreFeatureData() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(baseURL: config.baseURL, bearerToken: config.token, basicAuth: config.basicAuth)

        let cars = try await requireSuccess(api.cars())
        XCTAssertFalse(cars.isEmpty)
        let car = try XCTUnwrap(cars.first)
        XCTAssertGreaterThan(car.carId, 0)
        XCTAssertEqual(car.modelYear, 2022)
        XCTAssertEqual(car.vehicleModelDescription, "2022 Model 3 Performance")
        XCTAssertGreaterThan(car.teslamateStats?.totalUpdates ?? 0, 0)

        let status = try await requireSuccess(api.carStatus(carId: car.carId))
        XCTAssertNotNil(status.status)
        XCTAssertNotNil(status.units?.unitOfLength)
        XCTAssertGreaterThan(status.status?.odometer ?? 0, 100_000)
        XCTAssertNotNil(status.status?.locationSummary)
        XCTAssertNotNil(status.status?.version)
        let tpms = try XCTUnwrap(status.status?.tpmsDetails)
        XCTAssertTrue(tpms.hasAnyData)
        XCTAssertGreaterThan(tpms.pressureFl ?? 0, 2)
        XCTAssertGreaterThan(tpms.pressureFr ?? 0, 2)
        XCTAssertGreaterThan(tpms.pressureRl ?? 0, 2)
        XCTAssertGreaterThan(tpms.pressureRr ?? 0, 2)

        let dashboardState = DashboardState(
            isLoading: false,
            cars: cars.map { DashboardCarOption(id: $0.carId, name: $0.dashboardDisplayName) },
            selectedCarId: car.carId,
            carName: status.status?.displayName ?? car.dashboardPrimaryName,
            vehicleModelName: car.vehicleModelDescription,
            batteryLevel: status.status?.batteryLevel,
            isCharging: status.status?.isCharging ?? false,
            isLocked: status.status?.locked,
            sentryModeActive: status.status?.sentryMode ?? false,
            outsideTemperature: status.status?.outsideTemp,
            insideTemperature: status.status?.insideTemp,
            ratedRange: status.status?.ratedBatteryRangeKm,
            odometer: status.status?.odometer,
            locationText: status.status?.locationSummary,
            softwareVersion: status.status?.version,
            tpmsDetails: tpms,
            units: UnitPreferences(unitOfLength: status.units?.unitOfLength, unitOfTemperature: status.units?.unitOfTemperature, unitOfPressure: status.units?.unitOfPressure)
        )
        let suiteName = "LocalTeslaMateDashboardSnapshot.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let snapshotStore = DashboardSnapshotStore(defaults: defaults)
        let snapshot = try XCTUnwrap(DashboardSnapshot(state: dashboardState))
        await snapshotStore.save(snapshot, serverURL: config.baseURL.absoluteString)
        let restoredValue = await snapshotStore.load(serverURL: config.baseURL.absoluteString, carId: car.carId, now: Date())
        let restored = try XCTUnwrap(restoredValue)
        XCTAssertEqual(restored.batteryLevel, status.status?.batteryLevel)
        XCTAssertEqual(restored.odometer, status.status?.odometer)
        XCTAssertEqual(restored.locationText, status.status?.locationSummary)
        XCTAssertEqual(restored.softwareVersion, status.status?.version)
        XCTAssertEqual(restored.tpms?.pressureFl, tpms.pressureFl)

        let drives = try await requireSuccess(api.drives(carId: car.carId, page: 1, show: 5))
        XCTAssertFalse(drives.isEmpty)
        if let driveId = drives.first?.driveId {
            let detail = try await requireSuccess(api.driveDetail(carId: car.carId, driveId: driveId))
            XCTAssertEqual(detail.driveId, driveId)
            XCTAssertFalse((detail.positions ?? []).isEmpty)
            let replaySamples = DriveReplayBuilder.samples(from: detail.positions ?? [])
            XCTAssertGreaterThan(replaySamples.count, 1)
            XCTAssertLessThanOrEqual(replaySamples.count, detail.positions?.count ?? 0)
            XCTAssertTrue(replaySamples.contains { $0.position.speed != nil && $0.position.power != nil })
            let stats = DriveStatsCalculator.calculateStats(detail)
            XCTAssertEqual(stats.energySource, .powerSamples)
            XCTAssertGreaterThan(stats.energySampleCoverage ?? 0, 0.8)
            XCTAssertGreaterThan(stats.energyUsed ?? 0, 0)
            XCTAssertGreaterThan(stats.tractionEnergyKWh ?? 0, stats.regeneratedEnergyKWh ?? 0)
            XCTAssertGreaterThan(stats.efficiency ?? 0, 50)
            XCTAssertLessThan(stats.efficiency ?? .greatestFiniteMagnitude, 500)
            let chartPositions = detail.positions ?? []
            let speedChart = DriveChartSampleBuilder.samples(kind: .speed, positions: chartPositions, units: .metric)
            let powerChart = DriveChartSampleBuilder.samples(kind: .power, positions: chartPositions, units: .metric)
            let batteryChart = DriveChartSampleBuilder.samples(kind: .battery, positions: chartPositions, units: .metric)
            let elevationChart = DriveChartSampleBuilder.samples(kind: .elevation, positions: chartPositions, units: .metric)
            let temperatureChart = DriveChartSampleBuilder.samples(kind: .temperature, positions: chartPositions, units: .metric)
            XCTAssertGreaterThan(speedChart.count, 1)
            XCTAssertGreaterThan(powerChart.count, 1)
            XCTAssertGreaterThan(batteryChart.count, 1)
            XCTAssertGreaterThan(elevationChart.count, 1)
            XCTAssertGreaterThan(temperatureChart.count, 1)
            XCTAssertLessThan(try XCTUnwrap(speedChart.first?.date), try XCTUnwrap(speedChart.last?.date))

            let annotation = DriveAnnotation(classification: .business, note: "Local integration export")
            let csv = DriveCSVExporter.csv(
                detail: detail,
                stats: stats,
                annotation: annotation,
                units: UnitPreferences(unitOfLength: status.units?.unitOfLength)
            )
            XCTAssertTrue(csv.contains("\"drive_id\",\"\(driveId)\""))
            XCTAssertTrue(csv.contains("\"start_date\","))
            XCTAssertTrue(csv.contains("\"end_date\","))
            XCTAssertTrue(csv.contains("\"start_address\","))
            XCTAssertTrue(csv.contains("\"end_address\","))
            XCTAssertTrue(csv.contains("\"energy_kwh\","))
            XCTAssertTrue(csv.contains("\"efficiency_wh_km\","))
            XCTAssertTrue(csv.contains("\"classification\",\"business\""))
            if let token = config.token {
                XCTAssertFalse(csv.contains(token))
            }
        }

        let charges = try await requireSuccess(api.charges(carId: car.carId, page: 1, show: 5))
        XCTAssertFalse(charges.isEmpty)
        if let chargeId = charges.first?.chargeId {
            let detail = try await requireSuccess(api.chargeDetail(carId: car.carId, chargeId: chargeId))
            XCTAssertEqual(detail.chargeId, chargeId)
            XCTAssertFalse((detail.chargePoints ?? []).isEmpty)
            XCTAssertTrue(detail.chargePoints?.contains(where: { $0.connectorType?.isEmpty == false }) == true)
            XCTAssertTrue(detail.chargePoints?.contains(where: { $0.chargerDetails?.fastChargerPresent == true }) == true)
            XCTAssertNotEqual(ChargingSessionAnalyzer.chargerIdentity(detail), .ac)

            let chargeDate = try XCTUnwrap(detail.startDate.flatMap(ChargePricingDate.localDate(from:)))
            let energy = try XCTUnwrap(detail.chargeEnergyAdded)
            XCTAssertGreaterThan(energy, 0)
            let historicalRule = ChargePricingRule(
                id: "historical-real-charge",
                name: "Historical Real Charge",
                effectiveFromDate: chargeDate,
                effectiveToDate: chargeDate,
                pricePerKWh: 0.5,
                priority: 1
            )
            let futureRule = ChargePricingRule(
                id: "future-price",
                name: "Future Price",
                effectiveFromDate: "9999-01-01",
                pricePerKWh: 9,
                priority: 999
            )
            let estimate = ChargePricingRuleEngine.estimateCost(
                for: ChargePricingInput(
                    startDate: detail.startDate,
                    endDate: detail.endDate,
                    address: detail.address,
                    latitude: detail.latitude,
                    longitude: detail.longitude,
                    energyAddedKWh: energy,
                    isDc: ChargingSessionAnalyzer.detectDcCharge(detail),
                    chargerIdentity: ChargingSessionAnalyzer.chargerIdentity(detail)
                ),
                rules: [futureRule, historicalRule]
            )
            XCTAssertEqual(estimate?.rule.id, historicalRule.id)
            XCTAssertEqual(estimate?.cost ?? 0, energy * 0.5, accuracy: 0.001)
        }

        let batteryHealth = try await requireSuccess(api.batteryHealth(carId: car.carId))
        XCTAssertGreaterThan(batteryHealth.batteryHealthPercentage ?? 0, 0)
        XCTAssertGreaterThan(batteryHealth.currentRange ?? 0, 0)
        let currentCapacity = try XCTUnwrap(batteryHealth.currentCapacity)
        XCTAssertGreaterThan(currentCapacity, 0)
        let verifiedNewCapacity = currentCapacity + 8
        let capacityCalibrated = await MainActor.run {
            BatteryViewModel.computeStats(
                health: batteryHealth,
                status: status.status,
                ratedEfficiencyFallback: nil,
                batteryReferenceCapacityKWh: verifiedNewCapacity,
                batteryRecordingStartOdometerKm: status.status?.odometer
            )
        }
        XCTAssertEqual(capacityCalibrated.healthSource, .manualCapacityReference)
        XCTAssertEqual(capacityCalibrated.originalCapacity ?? .nan, verifiedNewCapacity, accuracy: 0.001)
        XCTAssertEqual(capacityCalibrated.currentCapacity ?? .nan, currentCapacity, accuracy: 0.001)
        XCTAssertEqual(capacityCalibrated.healthPercent ?? .nan, currentCapacity / verifiedNewCapacity * 100, accuracy: 0.1)
        XCTAssertTrue(capacityCalibrated.showsAbsoluteHealth)

        let globalSettings = try await requireSuccess(api.globalSettings())
        XCTAssertNotNil(globalSettings?.unitOfLength)
        XCTAssertNotNil(globalSettings?.unitOfTemperature)
        XCTAssertNotNil(globalSettings?.preferredRange)
        _ = try await requireSuccess(api.updates(carId: car.carId, page: 1, show: 5))

        switch await api.currentCharge(carId: car.carId) {
        case .success(.active), .success(.noActiveCharge):
            break
        case let .failure(error):
            XCTFail("Current charge endpoint failed: \(error)")
        }
    }

    func testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN() async throws {
        let config = try Self.localConfig()
        let api = TeslamateAPI(
            baseURL: config.baseURL,
            bearerToken: config.token,
            basicAuth: config.basicAuth
        )

        let version = try await requireSuccess(api.version())
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(version.resolvedVersion),
            TeslaMateCapabilityPresentation.enhancedFeatureMinimumVersion
        )
        let cars = try await requireSuccess(api.cars())
        let car = try XCTUnwrap(cars.first)
        XCTAssertNil(car.carDetails?.vin)
        XCTAssertNil(car.modelYear)
        XCTAssertEqual(car.vehicleModelDescription, "Model 3 Performance")

        let status = try await requireSuccess(api.carStatus(carId: car.carId))
        XCTAssertNotNil(status.status)
        XCTAssertNotNil(status.units)

        let drives = try await requireSuccess(
            api.drives(carId: car.carId, page: 1, show: 200)
        )
        let drive = try XCTUnwrap(drives.first)
        let driveID = try XCTUnwrap(drive.driveId)
        let driveDetail = try await requireSuccess(
            api.driveDetail(carId: car.carId, driveId: driveID)
        )
        XCTAssertFalse((driveDetail.positions ?? []).isEmpty)

        let charges = try await requireSuccess(
            api.charges(carId: car.carId, page: 1, show: 200)
        )
        let charge = try XCTUnwrap(charges.first)
        let chargeID = try XCTUnwrap(charge.chargeId)
        let chargeDetail = try await requireSuccess(
            api.chargeDetail(carId: car.carId, chargeId: chargeID)
        )
        XCTAssertFalse((chargeDetail.chargePoints ?? []).isEmpty)

        let start = "2026-07-01T00:00:00Z"
        let end = "2026-07-31T23:59:59Z"
        let stateHistory = try await requireSuccess(
            api.vehicleStateHistory(
                carId: car.carId,
                startDate: start,
                endDate: end
            )
        )
        XCTAssertFalse(stateHistory.isEmpty)
        let battery = try await requireSuccess(api.battery(carId: car.carId))
        XCTAssertNotNil(battery)
        _ = try await requireSuccess(api.batteryHealth(carId: car.carId))
        _ = try await requireSuccess(api.batteryHistory(carId: car.carId))
        _ = try await requireSuccess(api.serverStats(carId: car.carId))
        _ = try await requireSuccess(
            api.costReview(
                carId: car.carId,
                startDate: Date(timeIntervalSince1970: 1_774_915_200),
                endDate: Date(timeIntervalSince1970: 1_777_593_599)
            )
        )
        _ = try await requireSuccess(api.activities(carId: car.carId, page: 1))
        _ = try await requireSuccess(api.driveInsights(carId: car.carId))
        _ = try await requireSuccess(
            api.environmentHistory(carId: car.carId, range: "30d", grain: "day")
        )
        let reviewLocation = SyntheticCoordinates.point()
        _ = try await requireSuccess(
            api.standbyDrain(
                carId: car.carId,
                latitude: reviewLocation.northing,
                longitude: reviewLocation.easting
            )
        )
        _ = try await requireSuccess(api.topDrainLocations(carId: car.carId))
        _ = try await requireSuccess(api.commuteRoutes(carId: car.carId))
        _ = try await requireSuccess(api.statsExtremes(carId: car.carId))
        _ = try await requireSuccess(api.drivingCoordinates(carId: car.carId))
        _ = try await requireSuccess(api.places(carId: car.carId))
        _ = try await requireSuccess(api.achievements(carId: car.carId))
        let updates = try await requireSuccess(
            api.updates(carId: car.carId, page: 1, show: 200)
        )
        XCTAssertFalse(updates.isEmpty)
        let globalSettings = try await requireSuccess(api.globalSettings())
        XCTAssertNotNil(globalSettings)

        switch await api.currentCharge(carId: car.carId) {
        case .success(.noActiveCharge):
            break
        case .success(.active):
            XCTFail("Synthetic review data should not expose an active charge")
        case let .failure(error):
            XCTFail("Current charge endpoint failed: \(error)")
        }

        switch await api.updateChargeCost(chargeId: chargeID, cost: 1) {
        case .success:
            XCTFail("The static review endpoint must reject write requests")
        case .failure:
            break
        }
    }

    private static func localConfig() throws -> (baseURL: URL, token: String?, basicAuth: BasicAuth?) {
        let environment = ProcessInfo.processInfo.environment
        let token = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_API_TOKEN"])
        let username = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_BASIC_USERNAME"])
        let password = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_BASIC_PASSWORD"])
        let explicitBaseURL = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_BASE_URL"])
        guard token != nil || username != nil || explicitBaseURL != nil else {
            throw XCTSkip("Set MATEDRIVE_INTEGRATION_BASE_URL for local no-auth tests, or provide MATEDRIVE_INTEGRATION_API_TOKEN / MATEDRIVE_INTEGRATION_BASIC_USERNAME.")
        }
        guard (username == nil && password == nil) || (username != nil && password != nil) else {
            XCTFail("Set both MATEDRIVE_INTEGRATION_BASIC_USERNAME and MATEDRIVE_INTEGRATION_BASIC_PASSWORD for Basic Auth.")
            throw IntegrationTestError.invalidBasicAuth
        }
        let rawBaseURL = explicitBaseURL ?? "http://127.0.0.1:3030"
        guard let baseURL = URL(string: rawBaseURL) else {
            XCTFail("Invalid MATEDRIVE_INTEGRATION_BASE_URL: \(rawBaseURL)")
            throw IntegrationTestError.invalidBaseURL
        }
        let basicAuth = username.flatMap { username in
            password.map { BasicAuth(username: username, password: $0) }
        }
        return (baseURL, token, basicAuth)
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func requireSuccess<Value>(
        _ result: APIResult<Value>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Value {
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            XCTFail("Expected API success, got \(error)", file: file, line: line)
            throw IntegrationTestError.apiFailure
        }
    }
}

private struct IntegrationSettingsStore: SettingsStoring {
    let settings: AppSettings
    func load() async -> AppSettings { settings }
    func save(_: AppSettings) async {}
}

private struct IntegrationDatabaseProvider: AppDatabaseProviding {
    let database: SQLiteDatabase
    func database() async throws -> SQLiteDatabase { database }
}

private enum IntegrationTestError: Error {
    case apiFailure
    case invalidBasicAuth
    case invalidBaseURL
}
