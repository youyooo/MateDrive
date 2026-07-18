import XCTest
@testable import MateDroidIOS

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testOldSettingsDecodeWithEmptyVehicleImageOverrides() throws {
        let data = """
        {
          "serverURL": "https://teslamate.example",
          "currencyCode": "CNY"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.serverURL, "https://teslamate.example")
        XCTAssertEqual(settings.currencyCode, "CNY")
        XCTAssertNil(settings.vehicleImageOverride(for: URL(string: "https://teslamate.example")!, carID: 1))
    }

    func testGeofenceKindsDecodeOldValuesAndExposeNewKinds() throws {
        XCTAssertEqual(try JSONDecoder().decode(GeofenceKind.self, from: Data("\"home\"".utf8)), .home)
        XCTAssertEqual(try JSONDecoder().decode(GeofenceKind.self, from: Data("\"work\"".utf8)), .work)
        XCTAssertEqual(GeofenceKind.shopping.title(language: .english), "Shopping")
        XCTAssertEqual(GeofenceKind.schoolPickup.title(language: .chinese), "学校或接送")
        XCTAssertEqual(GeofenceKind.shopping.systemImage, "cart.fill")
        XCTAssertEqual(GeofenceKind.schoolPickup.systemImage, "figure.2.and.child.holdinghands")
    }

    func testSavingHomeTariffRegionKeepsCurrencyAndCanonicalFieldInSync() async throws {
        let store = InMemorySettingsStore(initial: AppSettings(currencyCode: "HKD"))
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())
        await viewModel.load()

        await viewModel.saveHomeTariffRegionCode(" cn-43 ")

        let saved = try XCTUnwrap(store.saved)
        XCTAssertEqual(saved.homeTariffRegionCode, "CN-43")
        XCTAssertEqual(saved.residentialTariffRegionCode, "CN-43")
        XCTAssertEqual(saved.currencyCode, "HKD")

        await viewModel.saveResidentialTariffRegionCode(nil)
        XCTAssertNil(viewModel.settings.homeTariffRegionCode)
        XCTAssertEqual(viewModel.settings.currencyCode, "HKD")
    }

    nonisolated func testConcurrentSaveSurvivesLegacyOverrideMigrationLoad() async throws {
        let suiteName = "SettingsStoreMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let key = "settings"
        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "serverURL": "https://teslamate.example",
                "carImageVariants": ["7": "m3"],
                "carImageWheelCodes": ["7": "W32D"]
            ]),
            forKey: key
        )
        let gate = CatalogLoadGate()
        let catalog = try await MainActor.run {
            try BundledVehicleImageCatalogProvider(bundle: .main).catalog()
        }
        let store = UserDefaultsSettingsStore(defaults: defaults, key: key, vehicleImageCatalog: {
            await gate.waitForRelease()
            return catalog
        })

        let loadTask = Task { await store.load() }
        await gate.waitUntilLoadStarted()
        await store.save(AppSettings(serverURL: "https://teslamate.example", currencyCode: "HKD"))
        await gate.release()
        _ = await loadTask.value

        let persistedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let savedData = try XCTUnwrap(persistedDefaults.data(forKey: key))
        let saved = try JSONDecoder().decode(AppSettings.self, from: savedData)
        XCTAssertEqual(saved.currencyCode, "HKD")
        XCTAssertNil(saved.vehicleImageOverride(for: URL(string: "https://teslamate.example")!, carID: 7))
    }

    func testBatteryCalibrationIsStoredPerVehicleAndLegacyValueMigrates() throws {
        var settings = AppSettings(
            lastSelectedCarId: 1,
            batteryReferenceRangeKm: 500,
            batteryRecordingStartOdometerKm: 110_000
        )
        settings.setBatteryCalibration(BatteryCalibration(referenceRangeKm: 430, referenceCapacityKWh: 75, recordingStartOdometerKm: 20_000), for: 2)

        XCTAssertEqual(settings.batteryCalibration(for: 1).referenceRangeKm, 500)
        XCTAssertEqual(settings.batteryCalibration(for: 2).referenceRangeKm, 430)
        XCTAssertEqual(settings.batteryCalibration(for: 2).referenceCapacityKWh, 75)

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.batteryCalibration(for: 1).recordingStartOdometerKm, 110_000)
        XCTAssertEqual(decoded.batteryCalibration(for: 2).recordingStartOdometerKm, 20_000)
        XCTAssertEqual(decoded.batteryCalibration(for: 2).referenceCapacityKWh, 75)
    }

    func testDefaultSettingsFollowDeviceCurrencyAndTeslaMateUnits() {
        let settings = AppSettings()
        XCTAssertFalse(settings.isConfigured)
        XCTAssertFalse(settings.hasSecondaryServer)
        XCTAssertEqual(settings.currencyCode, MateDroidCurrencyFormatter.automaticCode)
        XCTAssertEqual(settings.displayUnitSystem, .teslamate)
        XCTAssertEqual(settings.appLanguage, .system)
        XCTAssertFalse(settings.forceChineseLanguage)
    }

    func testGeofenceRulesRoundTripAndOldSettingsKeepDefaults() throws {
        let coordinate = SyntheticCoordinates.point()
        let home = GeofenceRule(
            carId: 7,
            name: "Home",
            kind: .home,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 120
        )
        let settings = AppSettings(
            geofenceRules: [home],
            usesGeofencesForCommuteClassification: false
        )

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(restored.geofenceRules, [home])
        XCTAssertFalse(restored.usesGeofencesForCommuteClassification)
        XCTAssertTrue(legacy.geofenceRules.isEmpty)
        XCTAssertTrue(legacy.usesGeofencesForCommuteClassification)
    }

    func testGeofenceMatchingUsesVehicleScopeAndMostSpecificRadius() {
        let coordinate = SyntheticCoordinates.point()
        let nearbyCoordinate = SyntheticCoordinates.point(
            latitudeOffset: 0.0002,
            longitudeOffset: 0.0001
        )
        let broad = GeofenceRule(
            id: "broad",
            carId: 7,
            name: "Community",
            kind: .other,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 500
        )
        let home = GeofenceRule(
            id: "home",
            carId: 7,
            name: "Home",
            kind: .home,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 120
        )
        let anotherCar = GeofenceRule(
            id: "other-car",
            carId: 9,
            name: "Other car",
            kind: .work,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 50
        )

        let matched = GeofenceRuleEngine.matchingRule(
            latitude: nearbyCoordinate.latitude,
            longitude: nearbyCoordinate.longitude,
            carId: 7,
            rules: [broad, anotherCar, home]
        )

        XCTAssertEqual(matched?.id, "home")
        XCTAssertNil(GeofenceRuleEngine.matchingRule(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            carId: 7,
            rules: [anotherCar]
        ))
    }

    func testAppLanguageExposesEveryBundledLocalization() {
        XCTAssertEqual(
            AppLanguage.allCases,
            [.system, .english, .chinese, .traditionalChinese, .german, .spanish, .italian, .catalan]
        )
        XCTAssertEqual(AppLanguage.traditionalChinese.localeIdentifier, "zh-Hant")
        XCTAssertEqual(AppLanguage.german.localeIdentifier, "de")
        XCTAssertEqual(AppLanguage.spanish.localeIdentifier, "es")
        XCTAssertEqual(AppLanguage.italian.localeIdentifier, "it")
        XCTAssertEqual(AppLanguage.catalan.localeIdentifier, "ca")
    }

    func testLegacyEuroDefaultMigratesToAutomaticRegionalCurrency() throws {
        let data = """
        {
          "serverURL": "https://teslamate.example",
          "currencyCode": "EUR"
        }
        """.data(using: .utf8)!
        var settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.formatPreferencesVersion, 0)
        settings.migrateFormattingPreferences()

        XCTAssertEqual(settings.currencyCode, MateDroidCurrencyFormatter.automaticCode)
        XCTAssertEqual(settings.resolvedCurrencyCode(locale: Locale(identifier: "zh_CN")), "CNY")
        XCTAssertEqual(settings.displayUnitSystem, .teslamate)
        XCTAssertEqual(settings.formatPreferencesVersion, AppSettings.currentFormatPreferencesVersion)
    }

    func testLegacyExplicitCurrencySurvivesFormattingMigration() throws {
        let data = """
        {
          "serverURL": "https://teslamate.example",
          "currencyCode": "HKD"
        }
        """.data(using: .utf8)!
        var settings = try JSONDecoder().decode(AppSettings.self, from: data)

        settings.migrateFormattingPreferences()

        XCTAssertEqual(settings.currencyCode, "HKD")
        XCTAssertEqual(settings.resolvedCurrencyCode(locale: Locale(identifier: "zh_HK")), "HKD")
    }

    func testLegacySettingsDecodeDefaultsLanguageToSystem() throws {
        let data = """
        {
          "serverURL": "https://teslamate.example",
          "currencyCode": "CNY"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.serverURL, "https://teslamate.example")
        XCTAssertEqual(settings.currencyCode, "CNY")
        XCTAssertEqual(settings.appLanguage, .system)
        XCTAssertFalse(settings.forceChineseLanguage)
    }

    func testLegacyChineseSwitchDecodeMapsToChineseLanguage() throws {
        let data = """
        {
          "serverURL": "https://teslamate.example",
          "forceChineseLanguage": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.appLanguage, .chinese)
        XCTAssertTrue(settings.forceChineseLanguage)
    }

    func testSettingsEncodeAndDecodeBatteryLateHistoryCalibration() throws {
        let settings = AppSettings(
            batteryReferenceRangeKm: 500,
            batteryRecordingStartOdometerKm: 110_000
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.batteryReferenceRangeKm, 500)
        XCTAssertEqual(decoded.batteryRecordingStartOdometerKm, 110_000)
    }

    func testSavingSettingsSeparatesSecretsFromNonSecrets() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(
                showShortDrivesCharges: true,
                teslamateBaseURL: "https://grafana.example",
                lastSelectedCarId: 7,
                notificationPermissionAsked: true
            )
        )
        let secrets = InMemorySecretStore()
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets)
        await viewModel.load()

        await viewModel.save(
            serverURL: "https://teslamate.example",
            secondaryServerURL: "https://backup.example",
            apiToken: "token",
            basicUsername: "user",
            basicPassword: "pass",
            apiAccessKey: "access-key",
            apiSecretKey: "secret-key",
            acceptInvalidCerts: true,
            currencyCode: "hkd",
            displayUnitSystem: .metric,
            appLanguage: .chinese,
            batteryReferenceRangeKm: 500,
            batteryReferenceCapacityKWh: 78.8,
            batteryRecordingStartOdometerKm: 110_000
        )

        XCTAssertEqual(store.saved?.serverURL, "https://teslamate.example")
        XCTAssertEqual(store.saved?.secondaryServerURL, "https://backup.example")
        XCTAssertEqual(store.saved?.currencyCode, "HKD")
        XCTAssertEqual(store.saved?.displayUnitSystem, .metric)
        XCTAssertEqual(store.saved?.showShortDrivesCharges, true)
        XCTAssertEqual(store.saved?.teslamateBaseURL, "https://grafana.example")
        XCTAssertEqual(store.saved?.lastSelectedCarId, 7)
        XCTAssertEqual(store.saved?.notificationPermissionAsked, true)
        XCTAssertEqual(store.saved?.appLanguage, .chinese)
        XCTAssertEqual(store.saved?.batteryReferenceRangeKm, 500)
        XCTAssertEqual(store.saved?.batteryRecordingStartOdometerKm, 110_000)
        XCTAssertEqual(store.saved?.batteryCalibration(for: 7).referenceCapacityKWh, 78.8)
        XCTAssertEqual(store.saved?.forceChineseLanguage, true)
        XCTAssertEqual(secrets.values["apiToken"], "token")
        XCTAssertEqual(secrets.values["httpBasicAuthPassword"], "pass")
        XCTAssertEqual(secrets.values["apiAccessKey"], "access-key")
        XCTAssertEqual(secrets.values["apiSecretKey"], "secret-key")
    }

    func testSavingSettingsWithBlankSecretFieldsPreservesExistingSecrets() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(serverURL: "https://teslamate.example", currencyCode: "EUR")
        )
        let secrets = InMemorySecretStore()
        try await secrets.set("saved-token", for: "apiToken")
        try await secrets.set("saved-user", for: "httpBasicAuthUsername")
        try await secrets.set("saved-pass", for: "httpBasicAuthPassword")
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets)
        await viewModel.load()

        await viewModel.save(
            serverURL: "https://teslamate.example",
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: " ",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: 520,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertEqual(store.saved?.currencyCode, "CNY")
        XCTAssertEqual(store.saved?.appLanguage, .chinese)
        XCTAssertEqual(store.saved?.batteryReferenceRangeKm, 520)
        XCTAssertNil(store.saved?.batteryRecordingStartOdometerKm)
        XCTAssertEqual(secrets.values["apiToken"], "saved-token")
        XCTAssertEqual(secrets.values["httpBasicAuthUsername"], "saved-user")
        XCTAssertEqual(secrets.values["httpBasicAuthPassword"], "saved-pass")
    }

    func testSavingLanguageOnlyPreservesOtherSettingsAndSecrets() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(
                serverURL: "https://teslamate.example",
                secondaryServerURL: "https://backup.example",
                acceptInvalidCerts: true,
                currencyCode: "USD",
                teslamateBaseURL: "https://grafana.example",
                lastSelectedCarId: 7
            )
        )
        let secrets = InMemorySecretStore()
        try await secrets.set("token", for: "apiToken")
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets)
        await viewModel.load()

        await viewModel.saveAppLanguage(.english)

        XCTAssertEqual(store.saved?.serverURL, "https://teslamate.example")
        XCTAssertEqual(store.saved?.secondaryServerURL, "https://backup.example")
        XCTAssertEqual(store.saved?.acceptInvalidCerts, true)
        XCTAssertEqual(store.saved?.currencyCode, "USD")
        XCTAssertEqual(store.saved?.teslamateBaseURL, "https://grafana.example")
        XCTAssertEqual(store.saved?.lastSelectedCarId, 7)
        XCTAssertEqual(store.saved?.appLanguage, .english)
        XCTAssertEqual(secrets.values["apiToken"], "token")
    }

    func testSavingLanguageOnlyClearsStaleConnectionReport() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(serverURL: "https://teslamate.example", appLanguage: .chinese)
        )
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            connectionDiagnostic: CapturingConnectionDiagnostic()
        )
        await viewModel.load()
        await viewModel.testConnection()

        XCTAssertNotNil(viewModel.connectionReport)

        await viewModel.saveAppLanguage(.english)

        XCTAssertNil(viewModel.connectionReport)
    }

    func testSavingSettingsClearsStaleConnectionReportWhenLanguageChanges() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(serverURL: "https://teslamate.example", appLanguage: .chinese)
        )
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            connectionDiagnostic: CapturingConnectionDiagnostic()
        )
        await viewModel.load()
        await viewModel.testConnection()

        XCTAssertNotNil(viewModel.connectionReport)

        await viewModel.save(
            serverURL: "https://teslamate.example",
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .english,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertNil(viewModel.connectionReport)
    }

    func testSavingChargePricingRulesPreservesOtherSettings() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(
                serverURL: "https://teslamate.example",
                acceptInvalidCerts: true,
                currencyCode: "CNY",
                appLanguage: .chinese,
                batteryReferenceRangeKm: 500
            )
        )
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())
        await viewModel.load()

        await viewModel.saveChargePricingRules([
            ChargePricingRule(
                id: "home-valley",
                name: "Home Valley",
                chargeType: .ac,
                addressKeyword: "Home",
                startMinuteOfDay: 22 * 60,
                endMinuteOfDay: 7 * 60,
                pricePerKWh: 0.48,
                priority: 3
            )
        ])

        XCTAssertEqual(store.saved?.serverURL, "https://teslamate.example")
        XCTAssertEqual(store.saved?.acceptInvalidCerts, true)
        XCTAssertEqual(store.saved?.currencyCode, "CNY")
        XCTAssertEqual(store.saved?.appLanguage, .chinese)
        XCTAssertEqual(store.saved?.batteryReferenceRangeKm, 500)
        XCTAssertEqual(store.saved?.chargePricingRules.first?.id, "home-valley")
        XCTAssertEqual(store.saved?.chargePricingRules.first?.pricePerKWh, 0.48)
    }

    func testPricingRuleHealthSeparatesActiveDisabledAndInvalidRules() async {
        let store = InMemorySettingsStore(initial: AppSettings(chargePricingRules: [
            ChargePricingRule(id: "active", name: "Active", pricePerKWh: 1),
            ChargePricingRule(id: "disabled", name: "Disabled", isEnabled: false, pricePerKWh: 1),
            ChargePricingRule(id: "invalid", name: "Invalid", latitude: 28.1, pricePerKWh: 1)
        ]))
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        await viewModel.load()

        XCTAssertEqual(viewModel.chargePricingRulesHealth, ChargePricingRulesHealth(activeCount: 1, disabledCount: 1, invalidCount: 1))
        XCTAssertEqual(viewModel.chargePricingRulesHealth.totalCount, 3)
        XCTAssertTrue(viewModel.chargePricingRulesHealth.needsAttention)
    }

    func testSettingsLoadsHistorySyncHealthForSelectedVehicle() async {
        let expected = HistorySyncHealth(
            driveSummaryCount: 67,
            driveDetailCount: 66,
            pendingDriveCount: 1,
            chargeSummaryCount: 14,
            chargeDetailCount: 14,
            pendingChargeCount: 0,
            lastSyncAtMilliseconds: 2_000
        )
        let provider = CapturingHistorySyncHealthProvider(health: expected)
        let store = InMemorySettingsStore(initial: AppSettings(lastSelectedCarId: 7))
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            historySyncHealthProvider: provider
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.historySyncHealth, expected)
        let requestedCarId = await provider.requestedCarId()
        XCTAssertEqual(requestedCarId, 7)
    }

    func testManualHistorySyncRefreshesHealthAndProcessesGeography() async {
        let health = HistorySyncHealth(
            driveSummaryCount: 67,
            driveDetailCount: 67,
            pendingDriveCount: 0,
            chargeSummaryCount: 14,
            chargeDetailCount: 14,
            pendingChargeCount: 0,
            lastSyncAtMilliseconds: 2_000
        )
        let expectedReport = HistorySyncReport(attemptedCarIDs: [1], completedCarIDs: [1], failedCarIDs: [])
        let runner = CapturingHistorySyncRunner(report: expectedReport)
        let processor = CapturingGeographyQueueProcessor(
            report: GeocodeQueueProcessingReport(attemptedCount: 0, completedCount: 0, failedCount: 0)
        )
        let viewModel = SettingsViewModel(
            settingsStore: InMemorySettingsStore(initial: AppSettings(lastSelectedCarId: 1)),
            secretStore: InMemorySecretStore(),
            geographyQueueProcessor: processor,
            historySyncHealthProvider: CapturingHistorySyncHealthProvider(health: health),
            historySyncRunner: runner
        )
        await viewModel.load()

        await viewModel.syncHistoryNow()

        XCTAssertEqual(viewModel.lastHistorySyncReport, expectedReport)
        XCTAssertEqual(viewModel.historySyncHealth, health)
        XCTAssertFalse(viewModel.isSyncingHistory)
        let runCount = await runner.runCount()
        let receivedLimit = await processor.receivedLimit
        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(receivedLimit, 6)
    }

    func testConnectionDiagnosticUsesSavedSettingsAndSecrets() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(serverURL: "https://teslamate.example", appLanguage: .chinese)
        )
        let secrets = InMemorySecretStore()
        try await secrets.set("token-123", for: "apiToken")
        try await secrets.set("alice", for: "httpBasicAuthUsername")
        try await secrets.set("secret", for: "httpBasicAuthPassword")
        try await secrets.set("access-key", for: "apiAccessKey")
        try await secrets.set("secret-key", for: "apiSecretKey")
        let diagnostic = CapturingConnectionDiagnostic()
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets, connectionDiagnostic: diagnostic)
        await viewModel.load()

        await viewModel.testConnection()

        XCTAssertEqual(diagnostic.request?.settings.serverURL, "https://teslamate.example")
        XCTAssertEqual(diagnostic.request?.authenticator.bearerToken, "token-123")
        XCTAssertEqual(diagnostic.request?.authenticator.basicAuth, BasicAuth(username: "alice", password: "secret"))
        XCTAssertEqual(diagnostic.request?.authenticator.aksk, AKSKCredentials(accessKey: "access-key", secretKey: "secret-key"))
        XCTAssertEqual(diagnostic.request?.language, .chinese)
        XCTAssertEqual(viewModel.connectionReport?.summary(language: .chinese), "连接测试通过：可以读取 TeslaMate 数据")
        XCTAssertFalse(viewModel.isTestingConnection)
    }

    func testSavePersistsCloudflareSecretsAndConnectionTestUsesThem() async {
        let settings = InMemorySettingsStore(initial: AppSettings(serverURL: "https://teslamate.example"))
        let secrets = InMemorySecretStore()
        let diagnostic = CapturingConnectionDiagnostic()
        let viewModel = SettingsViewModel(
            settingsStore: settings,
            secretStore: secrets,
            connectionDiagnostic: diagnostic
        )

        await viewModel.save(
            serverURL: "https://teslamate.example",
            secondaryServerURL: "",
            apiToken: "token-123",
            basicUsername: "",
            basicPassword: "",
            cloudflareClientID: "cf-id",
            cloudflareClientSecret: "cf-secret",
            apiAccessKey: "access-key",
            apiSecretKey: "secret-key",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )
        await viewModel.testConnection()

        XCTAssertEqual(secrets.values["cloudflareAccessClientID"], "cf-id")
        XCTAssertEqual(secrets.values["cloudflareAccessClientSecret"], "cf-secret")
        XCTAssertEqual(diagnostic.request?.authenticator.cloudflareAccess?.clientID, "cf-id")
        XCTAssertEqual(diagnostic.request?.authenticator.cloudflareAccess?.clientSecret, "cf-secret")
        XCTAssertEqual(secrets.values["apiAccessKey"], "access-key")
        XCTAssertEqual(secrets.values["apiSecretKey"], "secret-key")
        XCTAssertEqual(diagnostic.request?.authenticator.aksk, AKSKCredentials(accessKey: "access-key", secretKey: "secret-key"))
    }

    func testConnectionDiagnosticCanUseUnsavedFormValues() async throws {
        let store = InMemorySettingsStore(
            initial: AppSettings(
                serverURL: "https://old.example",
                secondaryServerURL: "https://old-backup.example",
                acceptInvalidCerts: false,
                appLanguage: .chinese
            )
        )
        let secrets = InMemorySecretStore()
        try await secrets.set("saved-token", for: "apiToken")
        let diagnostic = CapturingConnectionDiagnostic()
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets, connectionDiagnostic: diagnostic)
        await viewModel.load()

        await viewModel.testConnection(
            serverURL: " https://new.example ",
            secondaryServerURL: " https://new-backup.example ",
            acceptInvalidCerts: true,
            apiToken: " form-token ",
            basicUsername: " alice ",
            basicPassword: " secret "
        )

        XCTAssertEqual(diagnostic.request?.settings.serverURL, "https://new.example")
        XCTAssertEqual(diagnostic.request?.settings.secondaryServerURL, "https://new-backup.example")
        XCTAssertEqual(diagnostic.request?.settings.acceptInvalidCerts, true)
        XCTAssertEqual(diagnostic.request?.authenticator.bearerToken, "form-token")
        XCTAssertEqual(diagnostic.request?.authenticator.basicAuth, BasicAuth(username: "alice", password: "secret"))
        XCTAssertEqual(store.saved?.serverURL, "https://old.example")
        XCTAssertEqual(store.saved?.secondaryServerURL, "https://old-backup.example")
        XCTAssertEqual(store.saved?.acceptInvalidCerts, false)
        XCTAssertEqual(secrets.values["apiToken"], "saved-token")
    }

    func testLoadAndManualRefreshUpdateGeographyCacheHealth() async {
        let provider = SequencedGeographyHealthProvider(values: [
            GeographyCacheHealth(cachedLocationCount: 3, pendingLocationCount: 2, lastUpdatedAt: "2026-07-11T10:00:00Z"),
            GeographyCacheHealth(cachedLocationCount: 5, pendingLocationCount: 0, lastUpdatedAt: "2026-07-11T10:10:00Z")
        ])
        let viewModel = SettingsViewModel(
            settingsStore: InMemorySettingsStore(),
            secretStore: InMemorySecretStore(),
            geographyHealthProvider: provider
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.geographyCacheHealth?.cachedLocationCount, 3)
        XCTAssertEqual(viewModel.geographyCacheHealth?.pendingLocationCount, 2)

        await viewModel.refreshGeographyHealth()
        XCTAssertEqual(viewModel.geographyCacheHealth?.cachedLocationCount, 5)
        XCTAssertEqual(viewModel.geographyCacheHealth?.pendingLocationCount, 0)
        XCTAssertNil(viewModel.geographyHealthError)
    }

    func testProcessingPendingGeographyRefreshesHealthAndReportsFailures() async {
        let provider = SequencedGeographyHealthProvider(values: [
            GeographyCacheHealth(cachedLocationCount: 1, pendingLocationCount: 2, lastUpdatedAt: nil),
            GeographyCacheHealth(cachedLocationCount: 2, pendingLocationCount: 1, lastUpdatedAt: "2026-07-11T10:00:00Z")
        ])
        let processor = CapturingGeographyQueueProcessor(report: GeocodeQueueProcessingReport(attemptedCount: 2, completedCount: 1, failedCount: 1))
        let viewModel = SettingsViewModel(
            settingsStore: InMemorySettingsStore(),
            secretStore: InMemorySecretStore(),
            geographyHealthProvider: provider,
            geographyQueueProcessor: processor
        )

        await viewModel.load()
        await viewModel.processPendingGeography()

        XCTAssertEqual(viewModel.geographyProcessingReport?.completedCount, 1)
        XCTAssertEqual(viewModel.geographyProcessingReport?.failedCount, 1)
        XCTAssertEqual(viewModel.geographyCacheHealth?.cachedLocationCount, 2)
        XCTAssertEqual(viewModel.geographyCacheHealth?.pendingLocationCount, 1)
        let receivedLimit = await processor.receivedLimit
        XCTAssertEqual(receivedLimit, 6)
    }
}

private actor CapturingHistorySyncHealthProvider: HistorySyncHealthProviding {
    let value: HistorySyncHealth
    private var carId: Int?

    init(health: HistorySyncHealth) { self.value = health }

    func health(carId: Int?) async throws -> HistorySyncHealth {
        self.carId = carId
        return value
    }

    func requestedCarId() -> Int? { carId }
}

private actor CapturingHistorySyncRunner: HistorySyncRunning {
    let report: HistorySyncReport
    private var count = 0

    init(report: HistorySyncReport) { self.report = report }

    func run() async -> HistorySyncReport {
        count += 1
        return report
    }

    func runCount() -> Int { count }
}

private actor SequencedGeographyHealthProvider: GeographyCacheHealthProviding {
    private var values: [GeographyCacheHealth]
    init(values: [GeographyCacheHealth]) { self.values = values }
    func health() async throws -> GeographyCacheHealth {
        values.isEmpty ? GeographyCacheHealth(cachedLocationCount: 0, pendingLocationCount: 0, lastUpdatedAt: nil) : values.removeFirst()
    }
}

private actor CapturingGeographyQueueProcessor: GeocodeQueueProcessing {
    let report: GeocodeQueueProcessingReport
    private(set) var receivedLimit: Int?
    init(report: GeocodeQueueProcessingReport) { self.report = report }
    func processPending(limit: Int) async -> GeocodeQueueProcessingReport {
        receivedLimit = limit
        return report
    }
}

private final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private(set) var saved: AppSettings?

    init(initial: AppSettings? = nil) {
        saved = initial
    }

    func load() async -> AppSettings {
        saved ?? AppSettings()
    }

    func save(_ settings: AppSettings) async {
        saved = settings
    }
}

private actor CatalogLoadGate {
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        hasStarted = true
        startContinuation?.resume()
        startContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilLoadStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class InMemorySecretStore: SecretStoring, @unchecked Sendable {
    private(set) var values: [String: String] = [:]

    func get(_ key: String) async throws -> String? {
        values[key]
    }

    func set(_ value: String, for key: String) async throws {
        values[key] = value
    }

    func remove(_ key: String) async throws {
        values.removeValue(forKey: key)
    }
}

private final class CapturingConnectionDiagnostic: TeslaMateConnectionDiagnosing, @unchecked Sendable {
    struct Request: Equatable {
        let settings: AppSettings
        let authenticator: RequestAuthenticator
        let language: AppLanguage
    }

    private(set) var request: Request?

    func run(settings: AppSettings, authenticator: RequestAuthenticator, language: AppLanguage) async -> TeslaMateDiagnosticReport {
        request = Request(settings: settings, authenticator: authenticator, language: language)
        return TeslaMateDiagnosticReport(checks: [
            TeslaMateDiagnosticCheck(
                checkID: .configuration,
                status: .passed,
                title: "服务器",
                message: "可用"
            )
        ])
    }
}
