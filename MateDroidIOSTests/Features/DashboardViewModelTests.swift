import XCTest
@testable import MateDroidIOS

@MainActor
final class DashboardViewModelTests: XCTestCase {
    func testSynthetic2022Model3PerformanceSharesResolutionAcrossLiveSnapshotAndWidget() async throws {
        let suiteName = "DashboardVehicleImage.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let snapshots = DashboardSnapshotStore(defaults: defaults)
        let widgets = WidgetSnapshotStore(defaults: defaults)
        let car = CarData(
            carId: 7,
            name: "",
            carDetails: CarDetails(model: "3", trimBadging: "P74D", vin: "TSTMODEL3N0000000"),
            carExterior: CarExterior(exteriorColor: "MidnightSilver", wheelType: "Pinwheel18CapKit")
        )
        let settings = InMemoryDashboardSettingsStore(
            settings: AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        )
        let live = DashboardViewModel(
            api: FakeDashboardAPI(cars: [car], statuses: [7: .idleFixture]),
            settingsStore: settings,
            widgetSnapshotStore: widgets,
            dashboardSnapshotStore: snapshots
        )

        await live.load()

        let expectedPath = "CarImages/vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20.png"
        let expectedAssetID = "model-3-refresh-performance-midnight-silver-uberturbine-20"
        XCTAssertEqual(live.state.vehicleImageResolution?.generationID, "model-3-refresh-performance")
        XCTAssertEqual(live.state.vehicleImageResolution?.assetID, expectedAssetID)
        XCTAssertEqual(live.state.vehicleImageResolution?.assetPath, expectedPath)
        XCTAssertEqual(live.state.vehicleImageResolution?.presentationScale, 1)

        let restored = DashboardViewModel(
            api: FakeDashboardAPI(carsResult: .failure(.network("offline"))),
            settingsStore: settings,
            widgetSnapshotStore: widgets,
            dashboardSnapshotStore: snapshots
        )
        await restored.load()

        XCTAssertEqual(restored.state.vehicleImageResolution?.generationID, live.state.vehicleImageResolution?.generationID)
        XCTAssertEqual(restored.state.vehicleImageResolution?.assetID, expectedAssetID)
        XCTAssertEqual(restored.state.carImagePath, expectedPath)
        XCTAssertEqual(restored.state.carImageScaleFactor, 1)
        XCTAssertEqual(widgets.load()?.carImagePath, expectedPath)
        XCTAssertEqual(widgets.load()?.carImageScaleFactor, 1)
        XCTAssertEqual(widgets.load()?.vehicleImageAssetID, expectedAssetID)

        let encodedSnapshot = try JSONEncoder().encode(try XCTUnwrap(DashboardSnapshot(state: live.state)))
        XCTAssertFalse(String(decoding: encodedSnapshot, as: UTF8.self).contains("TSTMODEL3N0000000"))
    }

    func testUnknownModelUsesGenericVehiclePlaceholder() async {
        let car = CarData(
            carId: 8,
            carDetails: CarDetails(model: "hovercraft", vin: "TSTMODEL3N0000000")
        )
        let viewModel = DashboardViewModel(
            api: FakeDashboardAPI(cars: [car], statuses: [8: .idleFixture]),
            settingsStore: InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carImagePath, VehicleImageResolver.genericPlaceholderPath)
        XCTAssertNil(viewModel.state.vehicleImageResolution?.assetID)
        XCTAssertEqual(viewModel.state.vehicleImageResolution?.conflicts, [.unknownModel])
    }

    func testUnavailableVehicleImageCatalogUsesGenericPlaceholder() async {
        let viewModel = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .idleFixture]),
            settingsStore: InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            vehicleImageCatalogProvider: UnavailableVehicleImageCatalogProvider()
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carImagePath, VehicleImageResolver.genericPlaceholderPath)
        XCTAssertNil(viewModel.state.vehicleImageResolution?.assetID)
        XCTAssertEqual(viewModel.state.carImageScaleFactor, 1)
    }

    func testOldDashboardSnapshotDecodesWithCompatibleImageDefaults() throws {
        let json = #"{"savedAt":0,"cars":[{"id":7,"name":"Model 3"}],"selectedCarId":7,"carName":"Model 3","isCharging":false,"sentryModeActive":false,"carImagePath":"CarImages/legacy.png"}"#

        let snapshot = try JSONDecoder().decode(DashboardSnapshot.self, from: Data(json.utf8))
        let state = snapshot.state(errorMessage: "offline")

        XCTAssertEqual(state.carImagePath, "CarImages/legacy.png")
        XCTAssertEqual(state.carImageScaleFactor, 1)
        XCTAssertNil(state.vehicleImageResolution?.generationID)
        XCTAssertNil(state.vehicleImageResolution?.assetID)
        XCTAssertNil(state.vehicleState)
        XCTAssertNil(state.vehicleStateSince)
        XCTAssertNil(state.latestDrive)
        XCTAssertNil(state.latestCharge)
    }

    func testDashboardRetainsLocalSummaryWhenStatusRefreshFails() async throws {
        let summary = DashboardCachedSummary(
            latestDrive: DashboardLatestDrive(
                driveId: 20,
                startedAt: Date(timeIntervalSince1970: 1_768_000_000),
                endedAt: Date(timeIntervalSince1970: 1_768_000_900),
                distanceKm: 22,
                durationMinutes: 15,
                energyConsumedNet: nil,
                consumptionNet: nil
            ),
            latestCharge: DashboardLatestCharge(
                chargeId: 30,
                startedAt: Date(timeIntervalSince1970: 1_768_100_000),
                endedAt: Date(timeIntervalSince1970: 1_768_103_600),
                energyAddedKWh: 20,
                cost: 4,
                durationMinutes: 60,
                address: nil,
                startBatteryLevel: nil,
                endBatteryLevel: nil,
                odometerKm: 123_456
            ),
            odometerKm: 123_456,
            sleepSummaries: [:]
        )
        let viewModel = DashboardViewModel(
            api: FakeDashboardAPI(
                carsResult: .success([.modelYWhite]),
                statuses: [1: .failure(.network("offline"))]
            ),
            settingsStore: InMemoryDashboardSettingsStore(settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 1
            )),
            dashboardSnapshotStore: EmptyDashboardSnapshotStore(),
            summaryProvider: StubDashboardSummaryProvider(summary: summary)
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state.latestDrive?.driveId, 20)
        XCTAssertEqual(viewModel.state.latestCharge?.chargeId, 30)
        XCTAssertEqual(viewModel.state.odometer, 123_456)
        XCTAssertTrue(viewModel.state.errorMessage?.contains("offline") == true)
    }

    func testDashboardComputesCurrentSleepFromExplicitAsleepStateUsingInjectedClock() async throws {
        let now = Date(timeIntervalSince1970: 1_768_009_200)
        let status = CarStatusPayload(
            status: CarStatus(
                state: "asleep",
                stateSince: "2026-01-01T00:00:00Z",
                batteryDetails: BatteryDetails(batteryLevel: 50)
            )
        )
        let viewModel = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: status]),
            settingsStore: InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            now: { now }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state.vehicleState, "asleep")
        XCTAssertEqual(viewModel.state.vehicleStateSince, Date(timeIntervalSince1970: 1_767_225_600))
        XCTAssertEqual(viewModel.state.currentSleepDuration, 783_600)
    }

    func testCarImageViewUsesCarFillForMissingAssetsInStableFrame() {
        XCTAssertFalse(CarImageView.canDecodeAsset(at: "CarImages/does-not-exist.png"))
        XCTAssertEqual(CarImageView.fallbackSystemImageName, "car.fill")
        XCTAssertEqual(CarImageView.stableAspectRatio, 2.2)
    }

    func testDashboardTextFormatterUsesChineseForHomeStatusValues() {
        XCTAssertEqual(DashboardTextFormatter.title("Charging", language: .chinese), "充电状态")
        XCTAssertEqual(DashboardTextFormatter.title("Lock", language: .chinese), "门锁")
        XCTAssertEqual(DashboardTextFormatter.title("Sentry", language: .chinese), "哨兵模式")
        XCTAssertEqual(DashboardTextFormatter.title("Outside", language: .chinese), "车外")
        XCTAssertEqual(DashboardTextFormatter.title("Inside", language: .chinese), "车内")
        XCTAssertEqual(DashboardTextFormatter.title("History", language: .chinese), "历史")
        XCTAssertEqual(DashboardTextFormatter.title("Current Charge", language: .chinese), "当前充电")
        XCTAssertEqual(DashboardTextFormatter.title("Achievements", language: .chinese), "成就")
        XCTAssertEqual(DashboardTextFormatter.title("Place Insights", language: .chinese), "地点洞察")
        XCTAssertEqual(DashboardTextFormatter.title("Charges", language: .chinese), "充电记录")
        XCTAssertEqual(DashboardTextFormatter.title("Drives", language: .chinese), "行程")
        XCTAssertEqual(DashboardTextFormatter.title("Updates", language: .chinese), "软件更新")
        XCTAssertEqual(DashboardTextFormatter.title("Location", language: .chinese), "位置")
        XCTAssertEqual(DashboardTextFormatter.title("Odometer", language: .chinese), "里程表")
        XCTAssertEqual(DashboardTextFormatter.title("Software", language: .chinese), "软件版本")
        XCTAssertEqual(DashboardTextFormatter.title("Battery Health", language: .chinese), "电池健康")
        XCTAssertEqual(DashboardTextFormatter.title("Health Source", language: .chinese), "健康来源")
        XCTAssertEqual(DashboardTextFormatter.title("Environment History", language: .chinese), "环境与胎压")
        XCTAssertEqual(DashboardTextFormatter.title("Standby Hotspots", language: .chinese), "待机耗电热点")
        XCTAssertEqual(DashboardTextFormatter.title("Commute Routes", language: .chinese), "通勤路线")
        XCTAssertEqual(DashboardTextFormatter.title("Recent Driving Map", language: .chinese), "近期行驶地图")
        XCTAssertEqual(
            DashboardTextFormatter.statusLine(isCharging: false, sentryModeActive: true, language: .chinese),
            "哨兵模式已开启"
        )
        XCTAssertEqual(DashboardTextFormatter.chargingValue(isCharging: true, language: .chinese), "正在充电")
        XCTAssertEqual(DashboardTextFormatter.sentryValue(isActive: true, language: .chinese), "开启")
        XCTAssertEqual(DashboardTextFormatter.sessionValue(isActive: true, language: .chinese), "开启")
        XCTAssertEqual(DashboardTextFormatter.sessionValue(isActive: false, language: .chinese), "关闭")
        XCTAssertEqual(DashboardTextFormatter.lockText(true, language: .chinese), "已锁定")
        XCTAssertEqual(
            DashboardTextFormatter.historyText(charges: 7, drives: 27, language: .chinese),
            "7 次充电 / 27 次行程"
        )
        XCTAssertEqual(DashboardTextFormatter.updatesText(3, language: .chinese), "3 次软件更新")
    }

    func testDashboardTextFormatterKeepsEnglishForEnglishLanguage() {
        XCTAssertEqual(DashboardTextFormatter.title("Sentry", language: .english), "Sentry")
        XCTAssertEqual(DashboardTextFormatter.title("Current Charge", language: .english), "Current Charge")
        XCTAssertEqual(DashboardTextFormatter.title("Battery Health", language: .english), "Battery Health")
        XCTAssertEqual(
            DashboardTextFormatter.statusLine(isCharging: false, sentryModeActive: true, language: .english),
            "Sentry active"
        )
        XCTAssertEqual(DashboardTextFormatter.chargingValue(isCharging: false, language: .english), "Idle")
        XCTAssertEqual(DashboardTextFormatter.sentryValue(isActive: false, language: .english), "Off")
        XCTAssertEqual(DashboardTextFormatter.sessionValue(isActive: true, language: .english), "Active")
        XCTAssertEqual(DashboardTextFormatter.sessionValue(isActive: false, language: .english), "Inactive")
        XCTAssertEqual(DashboardTextFormatter.lockText(false, language: .english), "Unlocked")
        XCTAssertEqual(
            DashboardTextFormatter.historyText(charges: 7, drives: 27, language: .english),
            "7 charges / 27 drives"
        )
        XCTAssertEqual(DashboardTextFormatter.updatesText(1, language: .english), "1 software update")
        XCTAssertEqual(DashboardTextFormatter.updatesText(3, language: .english), "3 software updates")
    }

    func testDashboardTextFormatterLocalizesEuropeanDynamicCounts() {
        XCTAssertEqual(DashboardTextFormatter.historyText(charges: 15, drives: 74, language: .german), "15 Ladevorgänge / 74 Fahrten")
        XCTAssertEqual(DashboardTextFormatter.updatesText(1, language: .german), "1 Softwareupdate")
        XCTAssertEqual(DashboardTextFormatter.historyText(charges: 15, drives: 74, language: .spanish), "15 cargas / 74 trayectos")
        XCTAssertEqual(DashboardTextFormatter.updatesText(2, language: .spanish), "2 actualizaciones de software")
        XCTAssertEqual(DashboardTextFormatter.historyText(charges: 15, drives: 74, language: .italian), "15 ricariche / 74 viaggi")
        XCTAssertEqual(DashboardTextFormatter.updatesText(2, language: .italian), "2 aggiornamenti software")
        XCTAssertEqual(DashboardTextFormatter.historyText(charges: 15, drives: 74, language: .catalan), "15 carregues / 74 trajectes")
        XCTAssertEqual(DashboardTextFormatter.updatesText(2, language: .catalan), "2 actualitzacions de programari")
    }

    func testDashboardStateBuildsChineseWidgetSnapshot() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 1,
            carName: "Model Y",
            batteryLevel: 68,
            isCharging: true,
            isLocked: true,
            sentryModeActive: true,
            outsideTemperature: 8,
            insideTemperature: 21.5,
            ratedRange: 320,
            odometer: 118_651,
            locationText: "车库",
            softwareVersion: "2026.20.1",
            carImagePath: "car_images/my_PPSW_WY19B.png"
        )

        let snapshot = WidgetDisplayData(dashboardState: state, language: .chinese, displayUnitSystem: .metric)

        XCTAssertEqual(snapshot.carName, "Model Y")
        XCTAssertEqual(snapshot.batteryText, "68%")
        XCTAssertEqual(snapshot.statusText, "正在充电")
        XCTAssertEqual(snapshot.lockText, "已锁定")
        XCTAssertEqual(snapshot.rangeText, "320 km")
        XCTAssertEqual(snapshot.temperatureText, "22°C / 8°C")
        XCTAssertEqual(snapshot.locationText, "车库")
        XCTAssertEqual(snapshot.insideTemperature, 21.5)
        XCTAssertEqual(snapshot.outsideTemperature, 8)
        XCTAssertEqual(snapshot.carImageName, "car_images/my_PPSW_WY19B.png")
        XCTAssertEqual(snapshot.displayLanguage, .chinese)
        XCTAssertEqual(snapshot.displayUnitSystem, .metric)
        XCTAssertTrue(snapshot.isReadOnly)
    }

    func testDashboardStateBuildsEnglishWidgetSnapshotWithImperialUnits() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 1,
            carName: "Model Y",
            batteryLevel: 68,
            isCharging: true,
            isLocked: true,
            outsideTemperature: 8,
            insideTemperature: 21.5,
            ratedRange: 320,
            units: .metric
        )

        let snapshot = WidgetDisplayData(dashboardState: state, language: .english, displayUnitSystem: .imperial)

        XCTAssertEqual(snapshot.displayLanguage, .english)
        XCTAssertEqual(snapshot.displayUnitSystem, .imperial)
        XCTAssertEqual(snapshot.rangeText, "199 mi")
        XCTAssertEqual(snapshot.temperatureText, "71°F / 46°F")
    }

    func testDashboardWidgetCanUseMetricUnitsWithEnglishLanguage() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 1,
            carName: "Model Y",
            ratedRange: 320,
            units: .metric
        )

        let snapshot = WidgetDisplayData(dashboardState: state, language: .english, displayUnitSystem: .metric)

        XCTAssertEqual(snapshot.displayLanguage, .english)
        XCTAssertEqual(snapshot.displayUnitSystem, .metric)
        XCTAssertEqual(snapshot.rangeText, "320 km")
    }

    func testDashboardBuildsTraditionalChineseWidgetSnapshot() {
        let state = DashboardState(
            isLoading: false,
            selectedCarId: 1,
            carName: "Model Y",
            isCharging: true,
            isLocked: true,
            units: .metric
        )

        let snapshot = WidgetDisplayData(
            dashboardState: state,
            language: .traditionalChinese,
            displayUnitSystem: .metric
        )

        XCTAssertEqual(snapshot.displayLanguage, .traditionalChinese)
        XCTAssertEqual(snapshot.statusText, "正在充電")
        XCTAssertEqual(snapshot.lockText, "已鎖定")
    }

    func testDashboardLoadsLastSelectedCarAndStatus() async throws {
        let suiteName = "DashboardViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let widgetSnapshotStore = WidgetSnapshotStore(defaults: defaults)
        let api = FakeDashboardAPI(
            cars: [.legacyModel3, .modelYWhite],
            statuses: [1: .chargingFixture]
        )
        let store = InMemoryDashboardSettingsStore(
            settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 1,
                appLanguage: .chinese
            )
        )
        let viewModel = DashboardViewModel(
            api: api,
            settingsStore: store,
            widgetSnapshotStore: widgetSnapshotStore
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state.selectedCarId, 1)
        XCTAssertEqual(viewModel.state.carName, "Model Y")
        XCTAssertEqual(viewModel.state.vehicleModelName, "Model Y")
        XCTAssertEqual(viewModel.state.batteryLevel, 68)
        XCTAssertTrue(viewModel.state.isCharging)
        XCTAssertEqual(viewModel.state.isLocked, true)
        XCTAssertTrue(viewModel.state.sentryModeActive)
        XCTAssertEqual(viewModel.state.outsideTemperature, 8.0)
        XCTAssertEqual(viewModel.state.insideTemperature, 21.5)
        XCTAssertEqual(viewModel.state.ratedRange, 320)
        XCTAssertEqual(viewModel.state.odometer, 118_651)
        XCTAssertEqual(viewModel.state.locationText, "Home")
        XCTAssertEqual(viewModel.state.softwareVersion, "2026.20.1")
        XCTAssertEqual(viewModel.state.tpmsDetails?.pressureFl, 3.0)
        XCTAssertEqual(viewModel.state.tpmsDetails?.pressureFr, 3.075)
        XCTAssertFalse(viewModel.state.tpmsDetails?.hasWarning ?? true)
        XCTAssertEqual(viewModel.state.carImagePath, "CarImages/vehicle_model-y-juniper-premium_premium_pearl-white_crossflow-19.png")
        XCTAssertEqual(viewModel.state.totalCharges, 24)
        XCTAssertEqual(viewModel.state.totalDrives, 120)
        XCTAssertEqual(viewModel.state.totalUpdates, 8)
        XCTAssertEqual(widgetSnapshotStore.load()?.carName, "Model Y")
        XCTAssertEqual(widgetSnapshotStore.load()?.batteryText, "68%")
        XCTAssertEqual(widgetSnapshotStore.load()?.statusText, "正在充电")
        XCTAssertEqual(widgetSnapshotStore.load()?.rangeText, "320 km")
        XCTAssertEqual(widgetSnapshotStore.load()?.temperatureText, "22°C / 8°C")
        XCTAssertEqual(widgetSnapshotStore.load()?.locationText, "Home")
    }

    func testDashboardFallsBackToFirstCarWhenSavedCarIsMissing() async throws {
        let api = FakeDashboardAPI(
            cars: [.legacyModel3, .modelYWhite],
            statuses: [2: .idleFixture]
        )
        let store = InMemoryDashboardSettingsStore(
            settings: AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 99)
        )
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state.selectedCarId, 2)
        XCTAssertEqual(viewModel.state.carName, "Blue 3")
        XCTAssertEqual(viewModel.state.vehicleModelName, "Model 3")
        XCTAssertFalse(viewModel.state.isCharging)
    }

    func testDashboardUsesResolvedAddressInsteadOfRawCoordinates() async throws {
        let resolver = StubDashboardLocationResolver(result: "梅溪湖街道, 长沙市")
        let viewModel = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .coordinateOnlyFixture]),
            settingsStore: InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            locationResolver: resolver
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.state.locationText, "梅溪湖街道, 长沙市")
        XCTAssertEqual(resolver.requests, ["1:12.207471:34.857727"])
    }

    func testDashboardIgnoresAppNameFromCarAndStatus() async throws {
        let legacyNamedCar = CarData(
            carId: 3,
            name: "MateDrive",
            displayName: "MateDrive",
            carDetails: CarDetails(model: "3", trimBadging: "lr")
        )
        let api = FakeDashboardAPI(
            cars: [legacyNamedCar],
            statuses: [3: .appNameFixture]
        )
        let store = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carName, "Model 3 Long Range")
        XCTAssertEqual(viewModel.state.vehicleModelName, "Model 3 Long Range")
    }

    func testDashboardIgnoresLegacyMateDroidNameFromCarAndStatus() async throws {
        let legacyNamedCar = CarData(
            carId: 6,
            name: "MateDroid",
            displayName: "MateDroid",
            carDetails: CarDetails(model: "3", trimBadging: "lr")
        )
        let api = FakeDashboardAPI(
            cars: [legacyNamedCar],
            statuses: [6: .legacyAppNameFixture]
        )
        let store = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carName, "Model 3 Long Range")
        XCTAssertEqual(viewModel.state.vehicleModelName, "Model 3 Long Range")
        XCTAssertEqual(viewModel.state.cars.first?.name, "Model 3 Long Range")
    }

    func testDashboardIgnoresAppNameVariantsFromCarAndStatus() async throws {
        let appNamedCar = CarData(
            carId: 4,
            name: "MateDrive - Model 3",
            displayName: "MateDrive iOS",
            carDetails: CarDetails(model: "3", trimBadging: "P")
        )
        let api = FakeDashboardAPI(
            cars: [appNamedCar],
            statuses: [4: .appNameVariantFixture]
        )
        let store = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carName, "Model 3 Performance")
        XCTAssertEqual(viewModel.state.vehicleModelName, "Model 3 Performance")
        XCTAssertEqual(viewModel.state.cars.first?.name, "Model 3 Performance")
    }

    func testDashboardUsesVINYearWhenVehicleHasNoCustomName() async throws {
        let car = CarData(
            carId: 7,
            name: "",
            carDetails: CarDetails(model: "3", trimBadging: "P74D", vin: "TSTMODEL3N0000000"),
            carExterior: CarExterior(exteriorColor: "MidnightSilver", wheelType: "Pinwheel18CapKit")
        )
        let api = FakeDashboardAPI(cars: [car], statuses: [7: .idleFixture])
        let store = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carName, "Model 3 Performance")
        XCTAssertEqual(viewModel.state.vehicleModelName, "2022 Model 3 Performance")
        XCTAssertEqual(viewModel.state.cars.first?.name, "2022 Model 3 Performance")
        XCTAssertFalse(viewModel.state.carName.contains("LRW"))
    }

    func testDashboardKeepsUserVehicleNameThatOnlyMentionsMateDriveLater() async throws {
        let namedCar = CarData(
            carId: 5,
            name: "Blue MateDrive",
            displayName: "Blue MateDrive",
            carDetails: CarDetails(model: "Y", trimBadging: "lr")
        )
        let api = FakeDashboardAPI(
            cars: [namedCar],
            statuses: [5: .idleFixture]
        )
        let store = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()

        XCTAssertEqual(viewModel.state.carName, "Blue MateDrive")
    }

    func testSelectingCarPersistsLastSelectedIdAndReloadsStatus() async throws {
        let api = FakeDashboardAPI(
            cars: [.legacyModel3, .modelYWhite],
            statuses: [
                1: .chargingFixture,
                2: .idleFixture
            ]
        )
        let store = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example"))
        let viewModel = DashboardViewModel(api: api, settingsStore: store)

        await viewModel.load()
        await viewModel.selectCar(id: 1)

        XCTAssertEqual(store.settings.lastSelectedCarId, 1)
        XCTAssertEqual(viewModel.state.selectedCarId, 1)
        XCTAssertTrue(viewModel.state.isCharging)
    }

    func testDashboardFallsBackToRecentSnapshotWhenCarsRequestFails() async throws {
        let suiteName = "DashboardOffline.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let snapshots = DashboardSnapshotStore(defaults: defaults)
        let settings = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://one.example", lastSelectedCarId: 1))
        let online = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .chargingFixture]),
            settingsStore: settings,
            dashboardSnapshotStore: snapshots
        )
        await online.load()

        let offline = DashboardViewModel(
            api: FakeDashboardAPI(carsResult: .failure(.network("offline"))),
            settingsStore: settings,
            dashboardSnapshotStore: snapshots
        )
        await offline.load()

        XCTAssertTrue(offline.state.isUsingCachedData)
        XCTAssertNotNil(offline.state.cachedAt)
        XCTAssertEqual(offline.state.carName, "Model Y")
        XCTAssertEqual(offline.state.batteryLevel, 68)
        XCTAssertEqual(offline.state.odometer, 118_651)
        XCTAssertEqual(offline.state.softwareVersion, "2026.20.1")
        XCTAssertEqual(offline.state.tpmsDetails?.pressureFl, 3)
        XCTAssertTrue(offline.state.errorMessage?.contains("offline") == true)
    }

    func testDashboardSnapshotIsIsolatedByServer() async throws {
        let suiteName = "DashboardServerIsolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let snapshots = DashboardSnapshotStore(defaults: defaults)
        let firstSettings = InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://one.example", lastSelectedCarId: 1))
        let online = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .chargingFixture]),
            settingsStore: firstSettings,
            dashboardSnapshotStore: snapshots
        )
        await online.load()

        let otherServer = DashboardViewModel(
            api: FakeDashboardAPI(carsResult: .failure(.network("offline"))),
            settingsStore: InMemoryDashboardSettingsStore(settings: AppSettings(serverURL: "https://two.example", lastSelectedCarId: 1)),
            dashboardSnapshotStore: snapshots
        )
        await otherServer.load()

        XCTAssertFalse(otherServer.state.isUsingCachedData)
        XCTAssertNil(otherServer.state.cachedAt)
        XCTAssertNil(otherServer.state.batteryLevel)
    }

    func testDashboardSnapshotExpiresAfterThirtyDays() async throws {
        let suiteName = "DashboardExpiry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let snapshots = DashboardSnapshotStore(defaults: defaults)
        let state = DashboardState(isLoading: false, selectedCarId: 1, carName: "Old", batteryLevel: 50)
        let old = try XCTUnwrap(DashboardSnapshot(state: state, savedAt: Date().addingTimeInterval(-31 * 24 * 60 * 60)))
        await snapshots.save(old, serverURL: "https://one.example")

        let loaded = await snapshots.load(serverURL: "https://one.example", carId: 1, now: Date())

        XCTAssertNil(loaded)
    }

    func testClearingDashboardSnapshotsPreservesUnrelatedDefaults() async throws {
        let suiteName = "DashboardClear.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("keep", forKey: "unrelated.setting")
        let snapshots = DashboardSnapshotStore(defaults: defaults)
        let state1 = DashboardState(isLoading: false, selectedCarId: 1, carName: "One", batteryLevel: 50)
        let state2 = DashboardState(isLoading: false, selectedCarId: 2, carName: "Two", batteryLevel: 60)
        await snapshots.save(try XCTUnwrap(DashboardSnapshot(state: state1)), serverURL: "https://one.example")
        await snapshots.save(try XCTUnwrap(DashboardSnapshot(state: state2)), serverURL: "https://two.example")
        let countBefore = await snapshots.snapshotCount()
        XCTAssertEqual(countBefore, 2)

        await snapshots.clearAll()

        let countAfter = await snapshots.snapshotCount()
        XCTAssertEqual(countAfter, 0)
        XCTAssertEqual(defaults.string(forKey: "unrelated.setting"), "keep")
    }

    func testDashboardCapturesAndNotifiesSentryAlertOnlyOnceUntilStateClears() async throws {
        let settings = InMemoryDashboardSettingsStore(
            settings: AppSettings(serverURL: "https://teslamate.example", appLanguage: .chinese)
        )
        let sentryStore = CapturingSentryAlertStore()
        let notifications = CapturingDashboardNotificationService()
        let timestamp = Date(timeIntervalSince1970: 1_788_880_000)
        let viewModel = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .sentryAlertFixture]),
            settingsStore: settings,
            notificationService: notifications,
            sentryAlertStore: sentryStore,
            now: { timestamp }
        )

        await viewModel.load()
        await viewModel.refresh()

        XCTAssertEqual(sentryStore.records.count, 1)
        XCTAssertEqual(sentryStore.records.first?.id, "1:1788880000000")
        XCTAssertEqual(sentryStore.records.first?.address, "Garage")
        XCTAssertEqual(sentryStore.records.first?.latitude, SyntheticCoordinates.point().latitude)
        XCTAssertEqual(notifications.sentryDeliveries, ["Model Y:1:Garage"])
        XCTAssertEqual(settings.settings.notificationEventSignatures["1:sentry"], "active")

        let cleared = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .idleFixture]),
            settingsStore: settings,
            notificationService: notifications,
            sentryAlertStore: sentryStore,
            now: { timestamp }
        )
        await cleared.load()
        XCTAssertNil(settings.settings.notificationEventSignatures["1:sentry"])

        let repeated = DashboardViewModel(
            api: FakeDashboardAPI(cars: [.modelYWhite], statuses: [1: .sentryAlertFixture]),
            settingsStore: settings,
            notificationService: notifications,
            sentryAlertStore: sentryStore,
            now: { timestamp.addingTimeInterval(1) }
        )
        await repeated.load()

        XCTAssertEqual(sentryStore.records.count, 2)
        XCTAssertEqual(notifications.sentryDeliveries, ["Model Y:1:Garage", "Model Y:2:Garage"])
    }
}

private final class CapturingSentryAlertStore: SentryAlertLogStoring, @unchecked Sendable {
    private(set) var records: [SentryAlertLogRecord] = []
    func alertLogs(carId: Int) async throws -> [SentryAlertLogRecord] { records.filter { $0.carId == carId } }
    func activeSessionStartedAt(carId: Int) async throws -> Int64? { nil }
    func hourlyCounts(carId: Int, sinceMillis: Int64) async throws -> [SentryHourlyCount] { [] }
    func upsert(_ record: SentryAlertLogRecord) async throws { records.append(record) }
}

private final class CapturingDashboardNotificationService: AppNotificationServicing, @unchecked Sendable {
    private(set) var sentryDeliveries: [String] = []
    func authorizationStatus() async -> AppNotificationAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func deliverCharging(carName: String, chargerPowerKW: Double, isDC: Bool, batteryLevel: Int?, chargeLimit: Int?, identifier: String) async throws {}
    func deliverSentry(carName: String, alertCount: Int, locationText: String?, identifier: String) async throws {
        sentryDeliveries.append("\(carName):\(alertCount):\(locationText ?? "")")
    }
    func deliverTyrePressure(carName: String, tyreName: String, pressure: Double, unit: String, threshold: Double, identifier: String) async throws {}
}

private final class StubDashboardLocationResolver: DashboardLocationResolving, @unchecked Sendable {
    private let result: String?
    private(set) var requests: [String] = []

    init(result: String?) { self.result = result }

    func address(carId: Int, latitude: Double, longitude: Double) async -> String? {
        requests.append("\(carId):\(latitude):\(longitude)")
        return result
    }
}

private struct StubDashboardSummaryProvider: DashboardSummaryProviding {
    let value: DashboardCachedSummary

    init(summary: DashboardCachedSummary) {
        value = summary
    }

    func summary(carId _: Int) async throws -> DashboardCachedSummary {
        value
    }
}

private final class FakeDashboardAPI: DashboardAPIProviding, @unchecked Sendable {
    private let carsResult: APIResult<[CarData]>
    private let statusFixtures: [Int: APIResult<CarStatusPayload>]

    init(cars: [CarData], statuses: [Int: CarStatusPayload]) {
        self.carsResult = .success(cars)
        self.statusFixtures = statuses.mapValues(APIResult.success)
    }

    init(carsResult: APIResult<[CarData]>, statuses: [Int: APIResult<CarStatusPayload>] = [:]) {
        self.carsResult = carsResult
        self.statusFixtures = statuses
    }

    func cars() async -> APIResult<[CarData]> {
        carsResult
    }

    func carStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        guard let status = statusFixtures[carId] else {
            return .failure(.emptyBody)
        }
        return status
    }
}

private final class InMemoryDashboardSettingsStore: SettingsStoring, @unchecked Sendable {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {
        self.settings = settings
    }
}

private final class UnavailableVehicleImageCatalogProvider: VehicleImageCatalogProviding, @unchecked Sendable {
    func catalog() throws -> VehicleImageCatalog {
        throw BundledVehicleImageCatalogProviderError.resourceNotFound
    }
}

private extension CarData {
    static let legacyModel3 = CarData(
        carId: 2,
        name: "Blue 3",
        carDetails: CarDetails(model: "3", trimBadging: nil, efficiency: 151.2),
        carExterior: CarExterior(exteriorColor: "DeepBlueMetallic", wheelType: "Pinwheel18"),
        teslamateStats: TeslamateStats(totalCharges: 11, totalDrives: 64)
    )

    static let modelYWhite = CarData(
        carId: 1,
        carDetails: CarDetails(model: "Y", trimBadging: "74D", efficiency: 165.0),
        carExterior: CarExterior(exteriorColor: "PearlWhiteMultiCoat", wheelType: "Gemini19"),
        teslamateStats: TeslamateStats(totalCharges: 24, totalDrives: 120, totalUpdates: 8)
    )
}

private extension CarStatusPayload {
    static let chargingFixture = CarStatusPayload(
        status: CarStatus(
            displayName: "Model Y",
            odometer: 118_651,
            carStatus: CarStatusDetails(locked: true, sentryMode: true),
            carGeodata: CarGeodata(geofence: "Home", latitude: SyntheticCoordinates.point().latitude, longitude: SyntheticCoordinates.point().longitude),
            carVersions: CarVersions(version: "2026.20.1"),
            climateDetails: ClimateDetails(insideTemp: 21.5, outsideTemp: 8.0),
            batteryDetails: BatteryDetails(batteryLevel: 68, ratedBatteryRange: 320),
            chargingDetails: ChargingDetails(pluggedIn: true, chargingState: "Charging", chargerPhases: 0),
            tpmsDetails: TpmsDetails(
                pressureFl: 3.0,
                pressureFr: 3.075,
                pressureRl: 2.95,
                pressureRr: 3.0,
                warningFl: false,
                warningFr: false,
                warningRl: false,
                warningRr: false
            )
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let idleFixture = CarStatusPayload(
        status: CarStatus(
            displayName: nil,
            carStatus: CarStatusDetails(locked: false, sentryMode: false),
            climateDetails: ClimateDetails(insideTemp: 19.5, outsideTemp: 11.0),
            batteryDetails: BatteryDetails(batteryLevel: 44),
            chargingDetails: ChargingDetails(pluggedIn: false, chargingState: "Disconnected")
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let sentryAlertFixture = CarStatusPayload(
        status: CarStatus(
            displayName: "Model Y",
            carStatus: CarStatusDetails(locked: true, sentryMode: true, centerDisplayState: "7"),
            carGeodata: CarGeodata(geofence: "Garage", latitude: SyntheticCoordinates.point().latitude, longitude: SyntheticCoordinates.point().longitude),
            batteryDetails: BatteryDetails(batteryLevel: 66)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let coordinateOnlyFixture = CarStatusPayload(
        status: CarStatus(
            displayName: "Model Y",
            carStatus: CarStatusDetails(locked: true, sentryMode: false),
            carGeodata: CarGeodata(geofence: "", latitude: SyntheticCoordinates.point(latitudeOffset: 0.207471, longitudeOffset: 0.857727).latitude, longitude: SyntheticCoordinates.point(latitudeOffset: 0.207471, longitudeOffset: 0.857727).longitude),
            batteryDetails: BatteryDetails(batteryLevel: 82)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let appNameFixture = CarStatusPayload(
        status: CarStatus(
            displayName: "MateDrive",
            carStatus: CarStatusDetails(locked: true, sentryMode: false),
            batteryDetails: BatteryDetails(batteryLevel: 52)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let legacyAppNameFixture = CarStatusPayload(
        status: CarStatus(
            displayName: "MateDroid",
            carStatus: CarStatusDetails(locked: true, sentryMode: false),
            batteryDetails: BatteryDetails(batteryLevel: 52)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )

    static let appNameVariantFixture = CarStatusPayload(
        status: CarStatus(
            displayName: "MateDrive iOS",
            carStatus: CarStatusDetails(locked: true, sentryMode: false),
            batteryDetails: BatteryDetails(batteryLevel: 52)
        ),
        units: Units(unitOfLength: "km", unitOfTemperature: "C", unitOfPressure: "bar")
    )
}
