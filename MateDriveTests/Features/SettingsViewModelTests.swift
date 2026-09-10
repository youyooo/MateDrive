import XCTest
@testable import MateDriveApp

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testOldSettingsDecodeWithCurrentDefaults() throws {
        let data = """
        {
          "serverURL": "https://teslamate.example",
          "currencyCode": "CNY"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.serverURL, "https://teslamate.example")
        XCTAssertEqual(settings.currencyCode, "CNY")
        XCTAssertTrue(settings.chargeTariffTemplates.isEmpty)
    }

    func testGeofenceKindsDecodeOldValuesAndExposeNewKinds() throws {
        XCTAssertEqual(try JSONDecoder().decode(GeofenceKind.self, from: Data("\"home\"".utf8)), .home)
        XCTAssertEqual(try JSONDecoder().decode(GeofenceKind.self, from: Data("\"work\"".utf8)), .work)
        XCTAssertEqual(GeofenceKind.shopping.title(language: .english), "Shopping")
        XCTAssertEqual(GeofenceKind.schoolPickup.title(language: .chinese), "学校或接送")
        XCTAssertEqual(GeofenceKind.shopping.systemImage, "cart.fill")
        XCTAssertEqual(GeofenceKind.schoolPickup.systemImage, "figure.2.and.child.holdinghands")
    }

    func testTariffTemplatesRoundTripAndSaveWithoutChangingRulesOrServerSettings() async throws {
        let rule = ChargePricingRule(id: "rule", name: "Existing Rule", pricePerKWh: 1)
        let store = InMemorySettingsStore(initial: AppSettings(
            serverURL: "https://teslamate.example",
            currencyCode: "CNY",
            chargePricingRules: [rule]
        ))
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())
        await viewModel.load()
        let template = ChargeTariffTemplate(
            id: "template",
            name: "Peak and Valley",
            chargeType: .ac,
            pricePerKWh: 0.8,
            timeSegments: [
                ChargePricingTimeSegment(startMinuteOfDay: 0, endMinuteOfDay: 479, pricePerKWh: 0.4),
                ChargePricingTimeSegment(startMinuteOfDay: 480, endMinuteOfDay: 1_439, pricePerKWh: 0.8)
            ]
        )

        await viewModel.saveChargeTariffTemplates([template])

        let saved = try XCTUnwrap(store.saved)
        XCTAssertEqual(saved.serverURL, "https://teslamate.example")
        XCTAssertEqual(saved.currencyCode, "CNY")
        XCTAssertEqual(saved.chargePricingRules, [rule])
        XCTAssertEqual(saved.chargeTariffTemplates, [template])

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.chargeTariffTemplates, [template])
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

    func testSavingHomeTariffRegionPreservesConcurrentlyLearnedPricingRule() async throws {
        let store = AtomicMergeSettingsStore(initial: AppSettings(currencyCode: "CNY"))
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())
        await viewModel.load()
        let learnedRule = ChargePricingRule(
            id: "learned",
            name: "Learned station",
            pricePerKWh: 0.66,
            origin: .stationLearned,
            currencyCode: "CNY",
            stationKey: "station:test"
        )
        _ = try await store.updateAtomically { current in
            var updated = current
            updated.chargePricingRules.append(learnedRule)
            return updated
        }

        await viewModel.saveHomeTariffRegionCode("CN-43")

        let saved = await store.load()
        XCTAssertEqual(saved.homeTariffRegionCode, "CN-43")
        XCTAssertTrue(saved.chargePricingRules.contains(learnedRule))
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
        XCTAssertEqual(settings.currencyCode, MateDriveCurrencyFormatter.automaticCode)
        XCTAssertEqual(settings.displayUnitSystem, .teslamate)
        XCTAssertEqual(settings.appLanguage, .system)
        XCTAssertEqual(settings.authenticationMode, .none)
        XCTAssertFalse(settings.usesCloudflareAccess)
        XCTAssertFalse(settings.forceChineseLanguage)
        XCTAssertFalse(settings.allowsThirdPartyRouteWeather)
        XCTAssertTrue(settings.mergeAdjacentDrives)
        XCTAssertEqual(settings.adjacentDriveMergeMaximumGapMinutes, 30)
    }

    func testRouteWeatherPermissionDefaultsOffAndPersistsWithoutChangingServerSettings() async throws {
        let store = InMemorySettingsStore(initial: AppSettings(
            serverURL: "https://teslamate.example",
            currencyCode: "CNY"
        ))
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )
        await viewModel.load()

        XCTAssertFalse(viewModel.settings.allowsThirdPartyRouteWeather)
        let didSave = await viewModel.saveThirdPartyRouteWeatherPermission(true)
        XCTAssertTrue(didSave)

        let saved = await store.load()
        XCTAssertTrue(saved.allowsThirdPartyRouteWeather)
        XCTAssertEqual(saved.serverURL, "https://teslamate.example")
        XCTAssertEqual(saved.currencyCode, "CNY")

        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(saved)
        )
        let legacy = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(restored.allowsThirdPartyRouteWeather)
        XCTAssertFalse(legacy.allowsThirdPartyRouteWeather)
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

    func testOverlappingGeofencesPreferVehicleScopeThenNearestCenter() {
        let vehicleCenter = SyntheticCoordinates.point()
        let globalCenter = SyntheticCoordinates.point(
            latitudeOffset: 0.000_05,
            longitudeOffset: 0.000_05
        )
        let fartherVehicleCenter = SyntheticCoordinates.point(
            latitudeOffset: 0.000_3,
            longitudeOffset: 0.000_3
        )
        let globalShopping = GeofenceRule(
            id: "global-shopping",
            name: "Global Shopping",
            kind: .shopping,
            latitude: globalCenter.latitude,
            longitude: globalCenter.longitude,
            radiusMeters: 80
        )
        let vehicleHome = GeofenceRule(
            id: "vehicle-home",
            carId: 7,
            name: "Vehicle Home",
            kind: .home,
            latitude: vehicleCenter.latitude,
            longitude: vehicleCenter.longitude,
            radiusMeters: 200
        )
        let fartherVehicleWork = GeofenceRule(
            id: "vehicle-work",
            carId: 7,
            name: "Vehicle Work",
            kind: .work,
            latitude: fartherVehicleCenter.latitude,
            longitude: fartherVehicleCenter.longitude,
            radiusMeters: 200
        )

        let scopedMatch = GeofenceRuleEngine.matchingRule(
            latitude: globalCenter.latitude,
            longitude: globalCenter.longitude,
            carId: 7,
            rules: [globalShopping, vehicleHome]
        )
        let nearestMatch = GeofenceRuleEngine.matchingRule(
            latitude: vehicleCenter.latitude,
            longitude: vehicleCenter.longitude,
            carId: 7,
            rules: [fartherVehicleWork, vehicleHome]
        )

        XCTAssertEqual(scopedMatch?.id, "vehicle-home")
        XCTAssertEqual(nearestMatch?.id, "vehicle-home")
    }

    func testAppLanguageExposesSupportedLocalizations() {
        XCTAssertEqual(
            AppLanguage.allCases,
            [.system, .english, .chinese, .traditionalChinese]
        )
        XCTAssertEqual(AppLanguage.traditionalChinese.localeIdentifier, "zh-Hant")
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

        XCTAssertEqual(settings.currencyCode, MateDriveCurrencyFormatter.automaticCode)
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
        XCTAssertEqual(settings.authenticationMode, .automatic)
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
                authenticationMode: .automatic,
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
            initial: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .automatic,
                currencyCode: "EUR"
            )
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

    func testChangingServerSuspendsOldSyncBeforeSavingAndResumesAfterward() async {
        let store = InMemorySettingsStore(
            initial: AppSettings(serverURL: "https://old.example")
        )
        let syncController = RecordingSettingsSyncController()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore(),
            syncController: syncController
        )
        await viewModel.load()

        let didSave = await viewModel.save(
            serverURL: "https://new.example",
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertTrue(didSave)
        let syncEvents = await syncController.events
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
        XCTAssertEqual(store.saved?.serverURL, "https://new.example")
    }

    func testSavingRemoteServerCannotPersistInvalidCertificateBypass() async {
        let store = InMemorySettingsStore()
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        let didSave = await viewModel.save(
            serverURL: "https://review.example",
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: true,
            currencyCode: "USD",
            appLanguage: .english,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertTrue(didSave)
        XCTAssertEqual(store.saved?.serverURL, "https://review.example")
        XCTAssertFalse(store.saved?.acceptInvalidCerts ?? true)
    }

    func testSavingRejectsServerURLWithEmbeddedCredentialsBeforeChangingSecrets() async throws {
        let original = AppSettings(serverURL: "https://old.example", authenticationMode: .bearerToken)
        let store = InMemorySettingsStore(initial: original)
        let secrets = InMemorySecretStore()
        try await secrets.set("old-token", for: "apiToken")
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets)
        await viewModel.load()

        let didSave = await viewModel.save(
            serverURL: "https://alice" + ":secret@example.com",
            secondaryServerURL: "",
            authenticationMode: .bearerToken,
            apiToken: "new-token",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertFalse(didSave)
        XCTAssertEqual(store.saved?.serverURL, original.serverURL)
        XCTAssertEqual(secrets.values["apiToken"], "old-token")
        XCTAssertTrue(viewModel.saveErrorMessage?.contains("不能包含") == true)
    }

    func testSavingPrivateHTTPSServerCanPersistInvalidCertificateBypass() async {
        let store = InMemorySettingsStore()
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: InMemorySecretStore())

        let didSave = await viewModel.save(
            serverURL: "https://192.168.3.82:3030",
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: true,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertTrue(didSave)
        XCTAssertTrue(store.saved?.acceptInvalidCerts ?? false)
    }

    func testCredentialFailureKeepsPreviousSettingsAndRestoresSecrets() async throws {
        let original = AppSettings(
            serverURL: "https://old.example",
            authenticationMode: .automatic,
            currencyCode: "CNY"
        )
        let store = InMemorySettingsStore(initial: original)
        let secrets = FailingSecretStore(
            values: ["apiToken": "old-token"],
            failNextSetForKey: "apiToken"
        )
        let syncController = RecordingSettingsSyncController()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: secrets,
            syncController: syncController
        )
        await viewModel.load()

        let didSave = await viewModel.save(
            serverURL: "https://new.example",
            secondaryServerURL: "",
            authenticationMode: .bearerToken,
            apiToken: "new-token",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "HKD",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertFalse(didSave)
        XCTAssertEqual(store.saved?.serverURL, "https://old.example")
        XCTAssertEqual(store.saved?.authenticationMode, .automatic)
        XCTAssertEqual(store.saved?.currencyCode, "CNY")
        let restoredToken = await secrets.value(for: "apiToken")
        XCTAssertEqual(restoredToken, "old-token")
        XCTAssertNotNil(viewModel.saveErrorMessage)
        let syncEvents = await syncController.events
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
    }

    func testSettingsPersistenceFailureRestoresSecretsAndResumesOldSync() async throws {
        let original = AppSettings(
            serverURL: "https://old.example",
            authenticationMode: .bearerToken,
            currencyCode: "CNY"
        )
        let store = FailingSettingsStore(initial: original)
        let secrets = InMemorySecretStore()
        try await secrets.set("old-token", for: "apiToken")
        let syncController = RecordingSettingsSyncController()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: secrets,
            syncController: syncController
        )
        await viewModel.load()

        let didSave = await viewModel.save(
            serverURL: "https://new.example",
            secondaryServerURL: "",
            authenticationMode: .bearerToken,
            apiToken: "new-token",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "HKD",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertFalse(didSave)
        let persisted = await store.load()
        XCTAssertEqual(persisted.serverURL, original.serverURL)
        XCTAssertEqual(persisted.currencyCode, original.currencyCode)
        XCTAssertEqual(secrets.values["apiToken"], "old-token")
        XCTAssertNotNil(viewModel.saveErrorMessage)
        let syncEvents = await syncController.events
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
    }

    func testCredentialChangeOnSameServerRestartsSyncAndPublishesRevision() async throws {
        let original = AppSettings(
            serverURL: "https://teslamate.example",
            authenticationMode: .bearerToken
        )
        let store = InMemorySettingsStore(initial: original)
        let secrets = InMemorySecretStore()
        try await secrets.set("old-token", for: "apiToken")
        let syncController = RecordingSettingsSyncController()
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: secrets,
            syncController: syncController
        )
        await viewModel.load()

        let didSave = await viewModel.save(
            serverURL: original.serverURL,
            secondaryServerURL: "https://backup.example",
            authenticationMode: .bearerToken,
            apiToken: "new-token",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertTrue(didSave)
        XCTAssertEqual(viewModel.connectionConfigurationRevision, 1)
        XCTAssertEqual(secrets.values["apiToken"], "new-token")
        let syncEvents = await syncController.events
        XCTAssertEqual(syncEvents, [.suspended, .resumed])
    }

    func testConcurrentSettingsSaveIsRejectedWhileFirstSaveIsPending() async {
        let original = AppSettings(serverURL: "https://teslamate.example")
        let store = BlockingSettingsStore(initial: original)
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )
        await viewModel.load()

        let firstSave = Task {
            await viewModel.save(
                serverURL: original.serverURL,
                secondaryServerURL: "",
                apiToken: "",
                basicUsername: "",
                basicPassword: "",
                acceptInvalidCerts: false,
                currencyCode: "CNY",
                appLanguage: .chinese,
                batteryReferenceRangeKm: nil,
                batteryRecordingStartOdometerKm: nil
            )
        }
        await store.waitUntilSaveStarts()

        let secondSave = await viewModel.save(
            serverURL: original.serverURL,
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "USD",
            appLanguage: .english,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )
        await store.releaseSave()
        let firstDidSave = await firstSave.value

        XCTAssertFalse(secondSave)
        XCTAssertTrue(firstDidSave)
        XCTAssertEqual(viewModel.settings.currencyCode, "CNY")
    }

    func testFullSettingsSavePreservesConcurrentlyLearnedPricingRule() async throws {
        let original = AppSettings(
            serverURL: "https://teslamate.example",
            currencyCode: "CNY"
        )
        let store = AtomicMergeSettingsStore(initial: original)
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )
        await viewModel.load()
        let learnedRule = ChargePricingRule(
            id: "learned-during-edit",
            name: "Learned Station",
            pricePerKWh: 0.66,
            origin: .stationLearned,
            currencyCode: "CNY",
            stationKey: "station:learned"
        )
        _ = try await store.updateAtomically { current in
            var updated = current
            updated.chargePricingRules.append(learnedRule)
            return updated
        }

        let didSave = await viewModel.save(
            serverURL: original.serverURL,
            secondaryServerURL: "",
            apiToken: "",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "HKD",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertTrue(didSave)
        let persisted = await store.load()
        XCTAssertEqual(persisted.currencyCode, "HKD")
        XCTAssertTrue(persisted.chargePricingRules.contains(learnedRule))
        XCTAssertTrue(viewModel.settings.chargePricingRules.contains(learnedRule))
    }

    func testIndependentSettingMutationsMergeWithoutClobberingEachOther() async {
        let store = AtomicMergeSettingsStore(initial: AppSettings(currencyCode: "CNY"))
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )
        await viewModel.load()
        let coordinate = SyntheticCoordinates.point()
        let geofence = GeofenceRule(
            id: "home",
            carId: 7,
            name: "Home",
            kind: .home,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radiusMeters: 150
        )
        let template = ChargeTariffTemplate(
            id: "overnight",
            name: "Overnight",
            chargeType: .ac,
            pricePerKWh: 0.5
        )

        async let languageUpdate: Void = viewModel.saveAppLanguage(.chinese)
        async let geofenceUpdate: Void = viewModel.saveGeofenceRules([geofence])
        async let templateUpdate: Void = viewModel.saveChargeTariffTemplates([template])
        _ = await (languageUpdate, geofenceUpdate, templateUpdate)

        let persisted = await store.load()
        XCTAssertEqual(persisted.appLanguage, .chinese)
        XCTAssertEqual(persisted.geofenceRules, [geofence])
        XCTAssertEqual(persisted.chargeTariffTemplates, [template])
        XCTAssertEqual(viewModel.settings.appLanguage, .chinese)
        XCTAssertEqual(viewModel.settings.geofenceRules, [geofence])
        XCTAssertEqual(viewModel.settings.chargeTariffTemplates, [template])
    }

    func testIndependentSettingFailureRestoresPersistedStateAndReportsError() async {
        let original = AppSettings(
            serverURL: "https://teslamate.example",
            appLanguage: .english
        )
        let store = FailingSettingsStore(initial: original)
        let viewModel = SettingsViewModel(
            settingsStore: store,
            secretStore: InMemorySecretStore()
        )
        await viewModel.load()

        await viewModel.saveAppLanguage(.chinese)
        let persisted = await store.load()

        XCTAssertEqual(viewModel.settings.appLanguage, .english)
        XCTAssertNotNil(viewModel.saveErrorMessage)
        XCTAssertEqual(persisted.appLanguage, .english)
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
            initial: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .automatic,
                appLanguage: .chinese
            )
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
            initial: AppSettings(
                serverURL: "https://teslamate.example",
                authenticationMode: .automatic,
                appLanguage: .chinese
            )
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

        let report = await viewModel.testConnection()

        XCTAssertEqual(diagnostic.request?.settings.serverURL, "https://teslamate.example")
        XCTAssertEqual(diagnostic.request?.authenticator.bearerToken, "token-123")
        XCTAssertEqual(diagnostic.request?.authenticator.basicAuth, BasicAuth(username: "alice", password: "secret"))
        XCTAssertEqual(diagnostic.request?.authenticator.aksk, AKSKCredentials(accessKey: "access-key", secretKey: "secret-key"))
        XCTAssertEqual(diagnostic.request?.language, .chinese)
        XCTAssertEqual(report, viewModel.connectionReport)
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
            authenticationMode: .apiKeys,
            usesCloudflareAccess: true,
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
                authenticationMode: .automatic,
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

    func testSavingBearerAuthenticationRemovesConflictingCredentials() async throws {
        let store = InMemorySettingsStore(initial: AppSettings(
            serverURL: "https://teslamate.example",
            authenticationMode: .automatic,
            usesCloudflareAccess: true
        ))
        let secrets = InMemorySecretStore()
        try await secrets.set("old-token", for: "apiToken")
        try await secrets.set("alice", for: "httpBasicAuthUsername")
        try await secrets.set("secret", for: "httpBasicAuthPassword")
        try await secrets.set("access-key", for: "apiAccessKey")
        try await secrets.set("secret-key", for: "apiSecretKey")
        try await secrets.set("cf-id", for: "cloudflareAccessClientID")
        try await secrets.set("cf-secret", for: "cloudflareAccessClientSecret")
        let viewModel = SettingsViewModel(settingsStore: store, secretStore: secrets)
        await viewModel.load()

        await viewModel.save(
            serverURL: "https://teslamate.example",
            secondaryServerURL: "",
            authenticationMode: .bearerToken,
            usesCloudflareAccess: false,
            apiToken: "new-token",
            basicUsername: "",
            basicPassword: "",
            acceptInvalidCerts: false,
            currencyCode: "CNY",
            appLanguage: .chinese,
            batteryReferenceRangeKm: nil,
            batteryRecordingStartOdometerKm: nil
        )

        XCTAssertEqual(store.saved?.authenticationMode, .bearerToken)
        XCTAssertFalse(store.saved?.usesCloudflareAccess ?? true)
        XCTAssertEqual(secrets.values["apiToken"], "new-token")
        XCTAssertNil(secrets.values["httpBasicAuthUsername"])
        XCTAssertNil(secrets.values["httpBasicAuthPassword"])
        XCTAssertNil(secrets.values["apiAccessKey"])
        XCTAssertNil(secrets.values["apiSecretKey"])
        XCTAssertNil(secrets.values["cloudflareAccessClientID"])
        XCTAssertNil(secrets.values["cloudflareAccessClientSecret"])
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

    func testEssentialLoadPublishesConfigurationBeforeOperationalChecks() async {
        let geography = CountingGeographyHealthProvider()
        let history = CountingHistorySyncHealthProvider()
        let notifications = CountingNotificationService()
        let viewModel = SettingsViewModel(
            settingsStore: InMemorySettingsStore(
                initial: AppSettings(serverURL: "https://teslamate.example")
            ),
            secretStore: InMemorySecretStore(),
            geographyHealthProvider: geography,
            historySyncHealthProvider: history,
            notificationService: notifications
        )

        await viewModel.loadEssentials()

        let essentialGeographyRequests = await geography.requestCount
        let essentialHistoryRequests = await history.requestCount
        let essentialNotificationRequests = await notifications.authorizationRequestCount
        XCTAssertTrue(viewModel.settings.isConfigured)
        XCTAssertEqual(essentialGeographyRequests, 0)
        XCTAssertEqual(essentialHistoryRequests, 0)
        XCTAssertEqual(essentialNotificationRequests, 0)

        await viewModel.refreshOperationalState()

        let refreshedGeographyRequests = await geography.requestCount
        let refreshedHistoryRequests = await history.requestCount
        let refreshedNotificationRequests = await notifications.authorizationRequestCount
        XCTAssertEqual(refreshedGeographyRequests, 1)
        XCTAssertEqual(refreshedHistoryRequests, 1)
        XCTAssertEqual(refreshedNotificationRequests, 1)
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

private actor CountingGeographyHealthProvider: GeographyCacheHealthProviding {
    private(set) var requestCount = 0

    func health() async throws -> GeographyCacheHealth {
        requestCount += 1
        return GeographyCacheHealth(
            cachedLocationCount: 0,
            pendingLocationCount: 0,
            lastUpdatedAt: nil
        )
    }
}

private actor CountingHistorySyncHealthProvider: HistorySyncHealthProviding {
    private(set) var requestCount = 0

    func health(carId _: Int?) async throws -> HistorySyncHealth {
        requestCount += 1
        return HistorySyncHealth(
            driveSummaryCount: 0,
            driveDetailCount: 0,
            pendingDriveCount: 0,
            chargeSummaryCount: 0,
            chargeDetailCount: 0,
            pendingChargeCount: 0,
            lastSyncAtMilliseconds: nil
        )
    }
}

private actor CountingNotificationService: AppNotificationServicing {
    private(set) var authorizationRequestCount = 0

    func authorizationStatus() async -> AppNotificationAuthorizationStatus {
        authorizationRequestCount += 1
        return .denied
    }

    func requestAuthorization() async throws -> Bool { false }
    func deliverCharging(carName _: String, chargerPowerKW _: Double, isDC _: Bool, batteryLevel _: Int?, chargeLimit _: Int?, identifier _: String) async throws {}
    func deliverSentry(carName _: String, alertCount _: Int, locationText _: String?, identifier _: String) async throws {}
    func deliverTyrePressure(carName _: String, tyreName _: String, pressure _: Double, unit _: String, threshold _: Double, identifier _: String) async throws {}
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

private actor RecordingSettingsSyncController: AppDataSyncSuspending {
    enum Event: Equatable {
        case suspended
        case resumed
    }

    private(set) var events: [Event] = []

    func suspendAndWait() {
        events.append(.suspended)
    }

    func resume() {
        events.append(.resumed)
    }
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

private actor FailingSettingsStore: SettingsStoring {
    enum Failure: Error {
        case injected
    }

    private var value: AppSettings

    init(initial: AppSettings) {
        value = initial
    }

    func load() async -> AppSettings {
        value
    }

    func save(_ settings: AppSettings) async {}

    func saveThrowing(_ settings: AppSettings) async throws {
        throw Failure.injected
    }
}

private actor BlockingSettingsStore: SettingsStoring {
    private var value: AppSettings
    private var saveStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(initial: AppSettings) {
        value = initial
    }

    func load() async -> AppSettings {
        value
    }

    func save(_ settings: AppSettings) async {
        value = settings
    }

    func saveThrowing(_ settings: AppSettings) async throws {
        saveStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
        value = settings
    }

    func waitUntilSaveStarts() async {
        guard !saveStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseSave() {
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private actor AtomicMergeSettingsStore: SettingsStoring, AtomicSettingsUpdating {
    private var value: AppSettings

    init(initial: AppSettings) {
        value = initial
    }

    func load() async -> AppSettings { value }
    func save(_ settings: AppSettings) async { value = settings }

    func updateAtomically(
        _ transform: @Sendable (AppSettings) -> AppSettings
    ) async throws -> AppSettings {
        value = transform(value)
        return value
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

private actor FailingSecretStore: SecretStoring {
    enum Failure: Error {
        case injected
    }

    private var values: [String: String]
    private var failNextSetForKey: String?

    init(values: [String: String], failNextSetForKey: String?) {
        self.values = values
        self.failNextSetForKey = failNextSetForKey
    }

    func get(_ key: String) async throws -> String? {
        values[key]
    }

    func set(_ value: String, for key: String) async throws {
        if failNextSetForKey == key {
            failNextSetForKey = nil
            throw Failure.injected
        }
        values[key] = value
    }

    func remove(_ key: String) async throws {
        values.removeValue(forKey: key)
    }

    func value(for key: String) -> String? {
        values[key]
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
