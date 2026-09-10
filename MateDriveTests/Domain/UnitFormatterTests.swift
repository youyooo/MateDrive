import XCTest
@testable import MateDriveApp

final class UnitFormatterTests: XCTestCase {
    func testCurrencySymbolsAreConsistentAndUnknownCodesRemainVisible() {
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "CNY"), "¥")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "rmb"), "¥")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "HKD"), "HK$")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "TWD"), "NT$")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "KRW"), "₩")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "USD"), "$")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "CHF"), "CHF ")
        XCTAssertEqual(MateDriveCurrencyFormatter.symbol(for: "  "), "¤")
    }

    func testAutomaticCurrencyUsesDeviceRegion() {
        XCTAssertEqual(MateDriveCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "zh_CN")), "CNY")
        XCTAssertEqual(MateDriveCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "zh_HK")), "HKD")
        XCTAssertEqual(MateDriveCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "zh_TW")), "TWD")
        XCTAssertEqual(MateDriveCurrencyFormatter.systemCurrencyCode(locale: Locale(identifier: "en_US")), "USD")
        XCTAssertEqual(MateDriveCurrencyFormatter.automaticSymbol(locale: Locale(identifier: "zh_CN")), "¥")
        XCTAssertEqual(MateDriveCurrencyFormatter.automaticSymbol(locale: Locale(identifier: "zh_HK")), "HK$")
        XCTAssertEqual(MateDriveCurrencyFormatter.automaticSymbol(locale: Locale(identifier: "zh_TW")), "NT$")
        XCTAssertEqual(MateDriveCurrencyFormatter.automaticSymbol(locale: Locale(identifier: "en_US")), "$")
        XCTAssertGreaterThan(MateDriveCurrencyFormatter.supportedCodes.count, 100)
        XCTAssertTrue(Set(["CNY", "HKD", "TWD", "USD"]).isSubset(of: Set(MateDriveCurrencyFormatter.supportedCodes)))
    }

    func testFeatureStateDefaultsUseAutomaticDeviceCurrency() {
        let expected = MateDriveCurrencyFormatter.automaticSymbol()

        XCTAssertEqual(ChargesState().currencySymbol, expected)
        XCTAssertEqual(ChargeDetailState().currencySymbol, expected)
        XCTAssertEqual(CompareChargesState().currencySymbol, expected)
        XCTAssertEqual(TripsState().currencySymbol, expected)
        XCTAssertEqual(TripDetailState().currencySymbol, expected)
        XCTAssertEqual(StatsState().currencySymbol, expected)
        XCTAssertEqual(MileageState().currencySymbol, expected)
    }

    func testDistanceAndSpeedConvertFromMetricBaseValues() {
        XCTAssertEqual(MateDriveUnitFormatter.formatDistance(1234.5, units: .metric), "1,234.5 km")
        XCTAssertEqual(MateDriveUnitFormatter.formatDistance(100, units: .imperial), "62.1 mi")
        XCTAssertEqual(MateDriveUnitFormatter.formatSpeed(100, units: .imperial), "62 mph")
        XCTAssertEqual(MateDriveUnitFormatter.distanceValue(42, units: .imperial), 26.097582, accuracy: 0.000001)
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
        XCTAssertEqual(MateDriveUnitFormatter.formatTemperature(22, units: .imperial), "72°F")
        XCTAssertEqual(MateDriveUnitFormatter.formatTemperature(21.6, units: .metric), "22°C")
        XCTAssertEqual(MateDriveUnitFormatter.formatPressure(2.4, units: .imperial), "34.8 psi")
        XCTAssertEqual(MateDriveUnitFormatter.formatEfficiency(244.4, units: .metric), "244.4 Wh/km")
        XCTAssertEqual(MateDriveUnitFormatter.formatEfficiency(150, units: .imperial, decimals: 0), "241 Wh/mi")
    }

    func testElevationIsConvertedForImperialOnly() {
        XCTAssertEqual(MateDriveUnitFormatter.formatElevation(100, units: .metric), "100 m")
        XCTAssertEqual(MateDriveUnitFormatter.formatElevation(100, units: .imperial), "328 ft")
        XCTAssertEqual(MateDriveUnitFormatter.elevationUnit(units: .imperial), "ft")
    }

    func testDurationUsesSelectedLanguageLabels() {
        XCTAssertEqual(MateDriveUnitFormatter.formatDuration(minutes: 136, language: .english), "2h 16m")
        XCTAssertEqual(MateDriveUnitFormatter.formatDuration(minutes: 22, language: .english), "22m")
        XCTAssertEqual(MateDriveUnitFormatter.formatDuration(minutes: 136, language: .chinese), "2小时 16分钟")
        XCTAssertEqual(MateDriveUnitFormatter.formatDuration(minutes: 22, language: .chinese), "22分钟")
        XCTAssertEqual(MateDriveUnitFormatter.formatDuration(minutes: 136, language: .traditionalChinese), "2小時 16分鐘")
        XCTAssertEqual(MateDriveUnitFormatter.formatDuration(minutes: 22, language: .traditionalChinese), "22分鐘")
    }
}
