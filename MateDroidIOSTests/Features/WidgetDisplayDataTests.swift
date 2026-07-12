import XCTest
@testable import MateDroidIOS

final class WidgetDisplayDataTests: XCTestCase {
    func testWidgetDisplayDataCarriesResolvedImagePathAndScale() {
        let data = WidgetDisplayData.fixture(
            vehicleImageAssetID: "reviewed-m3-performance",
            carImagePath: "CarImages/m3_PPSW_W32D.png",
            carImageScaleFactor: 1.35
        )

        XCTAssertEqual(data.carImagePath, "CarImages/m3_PPSW_W32D.png")
        XCTAssertEqual(data.vehicleImageAssetID, "reviewed-m3-performance")
        XCTAssertEqual(data.carImageScaleFactor, 1.35)
        XCTAssertEqual(data.carImageName, data.carImagePath)
    }

    func testOldWidgetPayloadDecodesWithImageDefaults() throws {
        let json = #"{"carName":"Model 3","isCharging":false,"sentryModeActive":false,"isReadOnly":true,"displayLanguage":"english"}"#

        let data = try JSONDecoder().decode(WidgetDisplayData.self, from: Data(json.utf8))

        XCTAssertNil(data.carImagePath)
        XCTAssertNil(data.vehicleImageAssetID)
        XCTAssertEqual(data.carImageScaleFactor, 1)
        XCTAssertEqual(data.displayLanguage, .english)
    }

    func testWidgetDisplayDataIncludesReadOnlyBatteryAndStatusFields() {
        let data = WidgetDisplayData.fixture(
            carName: "Model Y",
            batteryLevel: 68,
            ratedRange: 320,
            isCharging: true,
            isLocked: true,
            sentryModeActive: false,
            insideTemperature: 21,
            outsideTemperature: 8,
            displayLanguage: .english
        )

        XCTAssertEqual(data.carName, "Model Y")
        XCTAssertEqual(data.batteryLevel, 68)
        XCTAssertTrue(data.isCharging)
        XCTAssertTrue(data.isReadOnly)
        XCTAssertEqual(data.batteryText, "68%")
        XCTAssertEqual(data.statusText, "Charging")
        XCTAssertEqual(data.lockText, "Locked")
        XCTAssertEqual(data.rangeText, "199 mi")
        XCTAssertEqual(data.temperatureText, "70°F / 46°F")
    }

    func testWidgetDisplayDataUsesChineseStatusAndLockTextWhenRequested() {
        let charging = WidgetDisplayData.fixture(
            ratedRange: 320,
            isCharging: true,
            isLocked: true,
            insideTemperature: 21,
            outsideTemperature: 8,
            displayLanguage: .chinese
        )
        let sentry = WidgetDisplayData.fixture(
            isCharging: false,
            isLocked: false,
            sentryModeActive: true,
            displayLanguage: .chinese
        )
        let parked = WidgetDisplayData.fixture(
            isCharging: false,
            isLocked: true,
            sentryModeActive: false,
            displayLanguage: .chinese
        )

        XCTAssertEqual(charging.statusText, "正在充电")
        XCTAssertEqual(charging.lockText, "已锁定")
        XCTAssertEqual(charging.rangeText, "320 km")
        XCTAssertEqual(charging.temperatureText, "21°C / 8°C")
        XCTAssertEqual(sentry.statusText, "哨兵")
        XCTAssertEqual(sentry.lockText, "已解锁")
        XCTAssertEqual(parked.statusText, "已停车")
    }

    func testWidgetDisplayDataUsesTraditionalChineseTextWhenRequested() {
        let charging = WidgetDisplayData.fixture(
            isCharging: true,
            isLocked: true,
            displayLanguage: .traditionalChinese,
            displayUnitSystem: .metric
        )
        let parked = WidgetDisplayData.fixture(
            isCharging: false,
            isLocked: false,
            displayLanguage: .traditionalChinese,
            displayUnitSystem: .metric
        )

        XCTAssertEqual(charging.statusText, "正在充電")
        XCTAssertEqual(charging.lockText, "已鎖定")
        XCTAssertEqual(parked.statusText, "已解鎖")
    }

    func testWidgetDisplayDataUsesExplicitUnitSystemOverLanguageDefault() {
        let data = WidgetDisplayData.fixture(
            ratedRange: 320,
            insideTemperature: 21,
            outsideTemperature: 8,
            displayLanguage: .english,
            displayUnitSystem: .metric
        )

        XCTAssertEqual(data.rangeText, "320 km")
        XCTAssertEqual(data.temperatureText, "21°C / 8°C")
    }

    func testWidgetDisplayDataOmitsLockTextWhenLockStateIsUnknown() {
        let data = WidgetDisplayData.fixture(isLocked: nil)

        XCTAssertNil(data.lockText)
    }

    func testWidgetDisplayDataCodableRoundTripPreservesDisplayLanguage() throws {
        let original = WidgetDisplayData.fixture(
            carName: "Model 3",
            batteryLevel: 51,
            isCharging: false,
            isLocked: false,
            sentryModeActive: true,
            displayLanguage: .chinese
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetDisplayData.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.statusText, "哨兵")
        XCTAssertEqual(decoded.lockText, "已解锁")
    }

    func testWidgetSnapshotStorePersistsLatestDisplayData() throws {
        let suiteName = "WidgetDisplayDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = WidgetSnapshotStore(defaults: defaults)
        let data = WidgetDisplayData.fixture(
            carName: "Model Y",
            batteryLevel: 78,
            isCharging: true,
            displayLanguage: .chinese
        )

        store.save(data)

        XCTAssertEqual(store.load(), data)
        XCTAssertEqual(store.load()?.statusText, "正在充电")

        store.remove()
        XCTAssertNil(store.load())
    }
}
