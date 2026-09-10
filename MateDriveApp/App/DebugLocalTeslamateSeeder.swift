import Foundation

#if DEBUG
enum DebugLocalTeslamateSeeder {
    struct IntegrationConfig: Equatable {
        let baseURL: String
        let token: String?
        let basicUsername: String?
        let basicPassword: String?
    }

    static func seedIfNeeded(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        databaseProvider: (any AppDatabaseProviding)? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        await seedLaunchConfigurationIfNeeded(
            settingsStore: settingsStore,
            secretStore: secretStore,
            environment: environment
        )
        await seedDatabaseFixtureIfNeeded(
            databaseProvider: databaseProvider,
            environment: environment
        )
    }

    static func seedLaunchConfigurationIfNeeded(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        if environment["MATEDRIVE_UI_TEST_MODE"] == "1" {
            if environment["MATEDRIVE_UI_TEST_FRESH_SETUP"] == "1" {
                var settings = AppSettings()
                settings.appLanguage = uiTestLanguage(from: environment)
                await settingsStore.save(settings)
                for key in authenticationSecretKeys {
                    try? await secretStore.remove(key)
                }
                await DashboardSnapshotStore.shared.clearAll()
                return
            }
            if environment["MATEDRIVE_UI_TEST_PRESERVE_SETTINGS"] == "1" {
                return
            }
            await seedUITestLaunchFixture(
                settingsStore: settingsStore,
                environment: environment
            )
            return
        }
        guard let config = integrationConfig(from: environment) else {
            return
        }

        var settings = await settingsStore.load()
        settings.serverURL = config.baseURL
        if config.token != nil {
            settings.authenticationMode = .bearerToken
        } else if config.basicUsername != nil, config.basicPassword != nil {
            settings.authenticationMode = .basic
        } else {
            settings.authenticationMode = .none
        }
        await settingsStore.save(settings)
        if let token = config.token {
            try? await secretStore.set(token, for: "apiToken")
        }
        if let username = config.basicUsername {
            try? await secretStore.set(username, for: "httpBasicAuthUsername")
        }
        if let password = config.basicPassword {
            try? await secretStore.set(password, for: "httpBasicAuthPassword")
        }
    }

    private static let authenticationSecretKeys = [
        "apiToken",
        "httpBasicAuthUsername",
        "httpBasicAuthPassword",
        "apiAccessKey",
        "apiSecretKey",
        "cloudflareAccessClientID",
        "cloudflareAccessClientSecret"
    ]

    static func seedDatabaseFixtureIfNeeded(
        databaseProvider: (any AppDatabaseProviding)?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async {
        guard environment["MATEDRIVE_UI_TEST_MODE"] == "1" else { return }
        await seedUITestDatabaseFixture(
            databaseProvider: databaseProvider,
            includeScreenshotSessions: environment["MATEDRIVE_STORE_SCREENSHOT_MODE"] == "1"
        )
    }

    private static func seedUITestLaunchFixture(
        settingsStore: any SettingsStoring,
        environment: [String: String]
    ) async {
        let serverURL = "https://ui-test.invalid"
        var settings = await settingsStore.load()
        settings.serverURL = serverURL
        settings.authenticationMode = .none
        settings.lastSelectedCarId = 1
        settings.appLanguage = uiTestLanguage(from: environment)
        settings.displayUnitSystem = .metric
        settings.currencyCode = "CNY"
        await settingsStore.save(settings)

        let latestDriveWindow = fixtureDriveWindow()
        let latestDrive = DashboardLatestDrive(
            driveId: 101,
            startedAt: latestDriveWindow.start,
            endedAt: latestDriveWindow.end,
            distanceKm: 24.8,
            durationMinutes: 32,
            energyConsumedNet: 3.7,
            consumptionNet: 149,
            startRatedRangeKm: 410,
            endRatedRangeKm: 382
        )
        let latestCharge = DashboardLatestCharge(
            chargeId: 201,
            startedAt: DomainDateParser.date(from: "2026-07-22T16:00:00Z"),
            endedAt: DomainDateParser.date(from: "2026-07-22T17:12:00Z"),
            energyAddedKWh: 22.4,
            cost: 11.2,
            durationMinutes: 72,
            address: "测试充电站",
            startBatteryLevel: 38,
            endBatteryLevel: 80,
            odometerKm: 118_859,
            isCostEstimated: false
        )
        let state = DashboardState(
            isLoading: false,
            cars: [DashboardCarOption(id: 1, name: "Model 3 Performance")],
            selectedCarId: 1,
            carName: "Model 3 Performance",
            vehicleModelName: "Model 3",
            batteryLevel: 72,
            isCharging: false,
            isLocked: true,
            outsideTemperature: 31,
            insideTemperature: 25,
            ratedRange: 382,
            odometer: 118_859,
            locationText: "测试车库",
            softwareVersion: "2026.20.3",
            units: .metric,
            currencyCode: "CNY",
            totalCharges: 86,
            totalDrives: 428,
            totalUpdates: 12,
            vehicleState: "asleep",
            latestDrive: latestDrive,
            latestCharge: latestCharge
        )
        if let snapshot = DashboardSnapshot(state: state) {
            await DashboardSnapshotStore.shared.save(snapshot, serverURL: serverURL)
        }
    }

    private static func uiTestLanguage(from environment: [String: String]) -> AppLanguage {
        switch environment["MATEDRIVE_UI_TEST_LANGUAGE"]?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "en", "english":
            return .english
        case "zh-Hant", "traditionalChinese":
            return .traditionalChinese
        case "zh-Hans", "chinese", "simplifiedChinese":
            return .chinese
        default:
            return .chinese
        }
    }

    private static func seedUITestDatabaseFixture(
        databaseProvider: (any AppDatabaseProviding)?,
        includeScreenshotSessions: Bool
    ) async {
        guard let databaseProvider,
              let database = try? await databaseProvider.database()
        else { return }
        let driveWindow = fixtureDriveWindow()
        let driveStartDate = fixtureISO8601(driveWindow.start)
        let driveEndDate = fixtureISO8601(driveWindow.end)
        try? await DriveSummaryStore(database: database).upsertAll([
            DriveSummaryRecord(
                driveId: 101,
                carId: 1,
                startDate: driveStartDate,
                endDate: driveEndDate,
                distance: 24.8,
                durationMin: 32,
                energyConsumedNet: 3.7,
                consumptionNet: 149,
                energySource: "teslamate",
                startBatteryLevel: 80,
                endBatteryLevel: 72,
                startRatedRangeKm: 410,
                endRatedRangeKm: 382,
                startAddress: "测试住宅, 湖南, 中国",
                endAddress: "测试公司, 湖南, 中国",
                speedAvg: 46,
                outsideTempAvg: 31
            )
        ])
        try? await ChargeSummaryStore(database: database).upsertAll([
            ChargeSummaryRecord(
                chargeId: 201,
                carId: 1,
                startDate: "2026-07-22T16:00:00Z",
                endDate: "2026-07-22T17:12:00Z",
                chargeEnergyAdded: 22.4,
                cost: 11.2,
                durationMin: 72,
                address: "测试充电站, 湖南, 中国",
                startBatteryLevel: 38,
                endBatteryLevel: 80,
                odometerKm: 118_859
            )
        ])
        let tripStore = TripStore(database: database)
        if let savedTrips = try? await tripStore.savedTrips(carId: 1),
           let savedTrip = savedTrips.first(where: { trip in
               trip.legs.contains { leg in
                   if case let .drive(driveID) = leg { return driveID == 101 }
                   return false
               }
           }) {
            try? await tripStore.updateTrip(
                tripId: savedTrip.tripId,
                name: "测试通勤",
                startDate: driveStartDate,
                endDate: driveEndDate,
                legs: [.drive(101)],
                consumedFingerprints: [TripFingerprint.fingerprint(driveIds: [101])]
            )
        } else {
            _ = try? await tripStore.saveTrip(
                carId: 1,
                name: "测试通勤",
                startDate: driveStartDate,
                endDate: driveEndDate,
                legs: [.drive(101)],
                consumedFingerprints: [TripFingerprint.fingerprint(driveIds: [101])]
            )
        }
        let driveActivity = TeslaMateActivity(
            id: 101,
            type: TeslaMateActivityKind.drive.rawValue,
            startDate: driveStartDate,
            endDate: driveEndDate,
            durationMin: 32,
            startAddress: "测试住宅, 湖南, 中国",
            endAddress: "测试公司, 湖南, 中国",
            startLatitude: UITestCoordinate.originNorthing,
            startLongitude: UITestCoordinate.originEasting,
            endLatitude: UITestCoordinate.destinationNorthing,
            endLongitude: UITestCoordinate.destinationEasting,
            kwhUsed: 3.7,
            rangeDiffKm: 28,
            soc: 80,
            socDiff: -8,
            odometerKm: 118_859,
            distanceKm: 24.8,
            endRangeKm: 382
        )
        let sessionStart = driveWindow.start
        let sessionEnd = driveWindow.end
        let session = SmartActivitySession(
            id: "ui-session-1",
            carId: 1,
            startDate: sessionStart,
            endDate: sessionEnd,
            placeKey: "ui-test-company",
            latitude: UITestCoordinate.destinationNorthing,
            longitude: UITestCoordinate.destinationEasting,
            geofenceID: nil,
            provisionalKind: .commute,
            classification: ActivityClassificationResult(
                purpose: .commute,
                confidence: 0.92,
                source: .learnedPattern,
                reasons: [.weekdayTimeWindow, .repeatedRoute],
                classifierVersion: 1
            ),
            parkingMetrics: nil,
            chargeCost: nil,
            eventReferences: [SmartActivityEventReference(sourceActivity: driveActivity)],
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "ui-test-drive-101",
            derivationFingerprint: "ui-test-activity-v1"
        )
        let screenshotSessions = includeScreenshotSessions
            ? makeScreenshotActivitySessions()
            : []
        try? await SmartActivityStore(database: database).replace(
            carId: 1,
            sessions: [session] + screenshotSessions,
            derivationFingerprint: "ui-test-activity-v1"
        )
    }

    private static func fixtureISO8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func fixtureDriveWindow() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -2, to: dayStart)?
            .addingTimeInterval(8 * 60 * 60)
            ?? Date().addingTimeInterval(-2 * 24 * 60 * 60)
        return (start, start.addingTimeInterval(32 * 60))
    }

    private static func makeScreenshotActivitySessions() -> [SmartActivitySession] {
        let chargeStart = DomainDateParser.date(from: "2026-07-23T04:10:00Z")
            ?? Date(timeIntervalSince1970: 1_774_411_800)
        let chargeEnd = DomainDateParser.date(from: "2026-07-23T05:05:00Z")
            ?? chargeStart.addingTimeInterval(55 * 60)
        let chargeActivity = TeslaMateActivity(
            id: 201,
            type: TeslaMateActivityKind.charge.rawValue,
            startDate: "2026-07-23T04:10:00Z",
            endDate: "2026-07-23T05:05:00Z",
            durationMin: 55,
            startAddress: "测试家庭车位, 湖南, 中国",
            endAddress: "测试家庭车位, 湖南, 中国",
            startLatitude: UITestCoordinate.originNorthing,
            startLongitude: UITestCoordinate.originEasting,
            endLatitude: UITestCoordinate.originNorthing,
            endLongitude: UITestCoordinate.originEasting,
            kwh: 22.4,
            cost: 11.2,
            rangeDiffKm: 102,
            soc: 80,
            socDiff: 28,
            odometerKm: 118_834
        )
        let chargeSession = SmartActivitySession(
            id: "screenshot-session-charge",
            carId: 1,
            startDate: chargeStart,
            endDate: chargeEnd,
            placeKey: "screenshot-home",
            latitude: UITestCoordinate.originNorthing,
            longitude: UITestCoordinate.originEasting,
            geofenceID: "screenshot-home-geofence",
            provisionalKind: .homeCharging,
            classification: ActivityClassificationResult(
                purpose: .homeCharging,
                confidence: 0.97,
                source: .geofence,
                reasons: [.homeGeofence, .acCharging],
                classifierVersion: 1
            ),
            parkingMetrics: ParkingIntervalMetrics(
                startDate: chargeStart,
                endDate: chargeEnd,
                duration: 55 * 60,
                startBatteryPercent: 52,
                endBatteryPercent: 80,
                netBatteryChangePercent: 28,
                chargeGainPercent: 28,
                standbyBatteryChangePercent: nil,
                startRatedRangeKm: nil,
                endRatedRangeKm: nil,
                ratedRangeChangeKm: nil,
                vehicleReportedChargeEnergyKWh: 22.4,
                sleepDuration: 0,
                awakeDuration: 55 * 60,
                wakeCount: 1,
                quality: .complete,
                missingReasonCodes: []
            ),
            chargeCost: SmartActivityChargeCost(
                amount: 11.2,
                currencyCode: "CNY",
                source: .homeRule,
                ruleID: "screenshot-home-rule",
                isEstimated: true,
                isExplicitlyFree: false,
                components: []
            ),
            eventReferences: [SmartActivityEventReference(sourceActivity: chargeActivity)],
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "screenshot-charge-201",
            derivationFingerprint: "ui-test-activity-v1"
        )

        let parkingStart = DomainDateParser.date(from: "2026-07-22T10:30:00Z")
            ?? chargeStart.addingTimeInterval(-17 * 60 * 60)
        let parkingEnd = DomainDateParser.date(from: "2026-07-22T12:10:00Z")
            ?? parkingStart.addingTimeInterval(100 * 60)
        let parkingActivity = TeslaMateActivity(
            id: 301,
            type: TeslaMateActivityKind.park.rawValue,
            startDate: "2026-07-22T10:30:00Z",
            endDate: "2026-07-22T12:10:00Z",
            durationMin: 100,
            startAddress: "测试商场, 湖南, 中国",
            endAddress: "测试商场, 湖南, 中国",
            startLatitude: UITestCoordinate.destinationNorthing,
            startLongitude: UITestCoordinate.destinationEasting,
            endLatitude: UITestCoordinate.destinationNorthing,
            endLongitude: UITestCoordinate.destinationEasting,
            rangeDiffKm: -4,
            soc: 71,
            socDiff: -1,
            odometerKm: 118_810
        )
        let parkingSession = SmartActivitySession(
            id: "screenshot-session-shopping",
            carId: 1,
            startDate: parkingStart,
            endDate: parkingEnd,
            placeKey: "screenshot-shopping",
            latitude: UITestCoordinate.destinationNorthing,
            longitude: UITestCoordinate.destinationEasting,
            geofenceID: "screenshot-shopping-geofence",
            provisionalKind: .shopping,
            classification: ActivityClassificationResult(
                purpose: .shopping,
                confidence: 0.89,
                source: .geofence,
                reasons: [.shoppingGeofence, .dwellPattern],
                classifierVersion: 1
            ),
            parkingMetrics: ParkingIntervalMetrics(
                startDate: parkingStart,
                endDate: parkingEnd,
                duration: 100 * 60,
                startBatteryPercent: 72,
                endBatteryPercent: 71,
                netBatteryChangePercent: -1,
                chargeGainPercent: nil,
                standbyBatteryChangePercent: -1,
                startRatedRangeKm: 386,
                endRatedRangeKm: 382,
                ratedRangeChangeKm: -4,
                vehicleReportedChargeEnergyKWh: nil,
                sleepDuration: 74 * 60,
                awakeDuration: 26 * 60,
                wakeCount: 1,
                quality: .complete,
                missingReasonCodes: []
            ),
            chargeCost: nil,
            eventReferences: [SmartActivityEventReference(sourceActivity: parkingActivity)],
            isOpen: false,
            quality: .complete,
            derivationVersion: 1,
            sourceFingerprint: "screenshot-park-301",
            derivationFingerprint: "ui-test-activity-v1"
        )

        return [chargeSession, parkingSession]
    }

    static func integrationConfig(from environment: [String: String]) -> IntegrationConfig? {
        let baseURL = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_BASE_URL"])
        let token = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_API_TOKEN"])
        let basicUsername = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_BASIC_USERNAME"])
        let basicPassword = firstNonEmpty(environment["MATEDRIVE_INTEGRATION_BASIC_PASSWORD"])

        guard let baseURL else {
            return nil
        }
        return IntegrationConfig(
            baseURL: baseURL,
            token: token,
            basicUsername: basicUsername,
            basicPassword: basicPassword
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct DebugUITestAnalyticsAPI: AnalyticsAPIProviding {
    func serverStats(carId _: Int) async -> APIResult<TeslaMateServerStatsResponse> {
        .failure(.httpStatus(404))
    }

    func batteryHealth(carId _: Int) async -> APIResult<BatteryHealth> {
        .success(BatteryHealth(
            maxRange: 476,
            currentRange: 471,
            maxCapacity: 69.5,
            currentCapacity: 69,
            ratedEfficiency: 146,
            batteryHealthPercentage: 99.3
        ))
    }

    func batteryHistory(carId _: Int) async -> APIResult<BatteryHistoryData> {
        .failure(.httpStatus(404))
    }

    func updates(carId _: Int, page _: Int?, show _: Int?) async -> APIResult<[UpdateData]> {
        .failure(.httpStatus(404))
    }

    func drives(
        carId _: Int,
        startDate _: String?,
        endDate _: String?,
        page _: Int?,
        show _: Int?
    ) async -> APIResult<[DriveData]> {
        .success([])
    }

    func charges(
        carId _: Int,
        startDate _: String?,
        endDate _: String?,
        page _: Int?,
        show _: Int?
    ) async -> APIResult<[ChargeData]> {
        .failure(.httpStatus(404))
    }

    func driveDetail(carId _: Int, driveId _: Int) async -> APIResult<DriveDetail> {
        .failure(.httpStatus(404))
    }

    func chargeDetail(carId _: Int, chargeId _: Int) async -> APIResult<ChargeDetail> {
        .failure(.httpStatus(404))
    }

    func carStatus(carId _: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(
            status: CarStatus(
                displayName: "Model 3 Performance",
                odometer: 118_859,
                batteryDetails: BatteryDetails(
                    batteryLevel: 72,
                    usableBatteryLevel: 71,
                    estBatteryRange: 360,
                    ratedBatteryRange: 339,
                    idealBatteryRange: 370
                )
            ),
            units: Units(
                unitOfLength: "km",
                unitOfTemperature: "C",
                unitOfPressure: "bar"
            )
        ))
    }
}

struct DebugUITestStandbyAPI: ActivityAPIProviding, TopDrainLocationsAPIProviding {
    func activities(carId _: Int, page _: Int, show _: Int) async -> APIResult<TeslaMateActivitiesResponse> {
        .failure(.emptyBody)
    }

    func drives(
        carId _: Int,
        startDate _: String?,
        endDate _: String?,
        page _: Int?,
        show _: Int?
    ) async -> APIResult<[DriveData]> {
        .success([])
    }

    func charges(
        carId _: Int,
        startDate _: String?,
        endDate _: String?,
        page _: Int?,
        show _: Int?
    ) async -> APIResult<[ChargeData]> {
        .success([])
    }

    func standbyDrain(
        carId _: Int,
        latitude _: Double,
        longitude _: Double
    ) async -> APIResult<StandbyDrainResponse> {
        decode(
            StandbyDrainResponse.self,
            json: #"{"data":{"latitude":28.3116,"longitude":112.822,"radius_meters":100,"period_days":30,"total_parking_events":12,"total_parking_days":10,"avg_drain_rate_km_h":1.49,"avg_drain_rate_pct_24h":-6.87,"total_range_loss_km":38.17,"min_drain_rate_km_h":0.08,"max_drain_rate_km_h":2.41},"units":{"length":"km"}}"#
        )
    }

    func topDrainLocations(carId _: Int) async -> APIResult<TopDrainLocationsResponse> {
        decode(
            TopDrainLocationsResponse.self,
            json: #"{"locations":[{"address":"测试车库, 湖南, 中国","latitude":28.3116,"longitude":112.822,"totalRangeLossKm":38.17,"avgDrainRatePct24h":-6.87,"avgDrainRateKmH":1.49,"parkingCount":12,"totalDurationMin":7236.6}],"units":{"unit_of_length":"km","unit_of_pressure":"bar","unit_of_temperature":"C"}}"#
        )
    }

    private func decode<Value: Decodable & Sendable>(
        _ type: Value.Type,
        json: String
    ) -> APIResult<Value> {
        do {
            return .success(
                try JSONDecoder.teslamate.decode(type, from: Data(json.utf8))
            )
        } catch {
            return .failure(.invalidResponse(error.localizedDescription))
        }
    }
}

private enum UITestCoordinate {
    static let originNorthing = 0.50
    static let originEasting = 0.50
    static let destinationNorthing = 0.51
    static let destinationEasting = 0.51
}
#endif
