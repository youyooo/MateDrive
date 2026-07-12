import XCTest
@testable import MateDroidIOS

final class UnitFormatterTests: XCTestCase {
    func testCurrencySymbolsAreConsistentAndUnknownCodesRemainVisible() {
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "CNY"), "¥")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "rmb"), "¥")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "HKD"), "HK$")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "TWD"), "NT$")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "KRW"), "₩")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "USD"), "$")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "CHF"), "CHF ")
        XCTAssertEqual(MateDroidCurrencyFormatter.symbol(for: "  "), "¤")
    }

    func testAutomaticCurrencyUsesDeviceRegion() {
        XCTAssertEqual(MateDroidCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "zh_CN")), "CNY")
        XCTAssertEqual(MateDroidCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "zh_HK")), "HKD")
        XCTAssertEqual(MateDroidCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "zh_TW")), "TWD")
        XCTAssertEqual(MateDroidCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "en_US")), "USD")
        XCTAssertGreaterThan(MateDroidCurrencyFormatter.supportedCodes.count, 100)
        XCTAssertTrue(Set(["CNY", "HKD", "TWD", "USD"]).isSubset(of: Set(MateDroidCurrencyFormatter.supportedCodes)))
    }

    func testDistanceAndSpeedConvertFromMetricBaseValues() {
        XCTAssertEqual(MateDroidUnitFormatter.formatDistance(1234.5, units: .metric), "1,234.5 km")
        XCTAssertEqual(MateDroidUnitFormatter.formatDistance(100, units: .imperial), "62.1 mi")
        XCTAssertEqual(MateDroidUnitFormatter.formatSpeed(100, units: .imperial), "62 mph")
        XCTAssertEqual(MateDroidUnitFormatter.distanceValue(42, units: .imperial), 26.097582, accuracy: 0.000001)
    }

    func testDisplayUnitPreferenceIsIndependentFromLanguage() {
        XCTAssertEqual(UnitPreferences.metric.resolved(for: AppLanguage.english), .metric)
        XCTAssertEqual(UnitPreferences.imperial.resolved(for: AppLanguage.chinese), .imperial)
        XCTAssertEqual(UnitPreferences.imperial.resolved(for: DisplayUnitSystem.teslamate), .imperial)
        XCTAssertEqual(UnitPreferences.metric.resolved(for: DisplayUnitSystem.imperial), .imperial)
        XCTAssertEqual(UnitPreferences.imperial.resolved(for: DisplayUnitSystem.metric), .metric)
        XCTAssertNil(UnitPreferences.resolved(nil, for: DisplayUnitSystem.teslamate))
        XCTAssertEqual(UnitPreferences.resolved(nil, for: DisplayUnitSystem.metric), .metric)
    }

    func testTemperaturePressureAndEfficiencyConvertFromMetricBaseValues() {
        XCTAssertEqual(MateDroidUnitFormatter.formatTemperature(22, units: .imperial), "72°F")
        XCTAssertEqual(MateDroidUnitFormatter.formatTemperature(21.6, units: .metric), "22°C")
        XCTAssertEqual(MateDroidUnitFormatter.formatPressure(2.4, units: .imperial), "34.8 psi")
        XCTAssertEqual(MateDroidUnitFormatter.formatEfficiency(244.4, units: .metric), "244.4 Wh/km")
        XCTAssertEqual(MateDroidUnitFormatter.formatEfficiency(150, units: .imperial, decimals: 0), "241 Wh/mi")
    }

    func testElevationIsConvertedForImperialOnly() {
        XCTAssertEqual(MateDroidUnitFormatter.formatElevation(100, units: .metric), "100 m")
        XCTAssertEqual(MateDroidUnitFormatter.formatElevation(100, units: .imperial), "328 ft")
        XCTAssertEqual(MateDroidUnitFormatter.elevationUnit(units: .imperial), "ft")
    }

    func testDurationUsesSelectedLanguageLabels() {
        XCTAssertEqual(MateDroidUnitFormatter.formatDuration(minutes: 136, language: .english), "2h 16m")
        XCTAssertEqual(MateDroidUnitFormatter.formatDuration(minutes: 22, language: .english), "22m")
        XCTAssertEqual(MateDroidUnitFormatter.formatDuration(minutes: 136, language: .chinese), "2小时 16分钟")
        XCTAssertEqual(MateDroidUnitFormatter.formatDuration(minutes: 22, language: .chinese), "22分钟")
        XCTAssertEqual(MateDroidUnitFormatter.formatDuration(minutes: 136, language: .traditionalChinese), "2小時 16分鐘")
        XCTAssertEqual(MateDroidUnitFormatter.formatDuration(minutes: 22, language: .traditionalChinese), "22分鐘")
    }
}
