import XCTest
@testable import MateDroidIOS

final class NotificationContentTests: XCTestCase {
    func testChargingNotificationTitleContainsPowerAndChargeType() {
        let content = ChargingNotificationContent(
            carName: "Model Y",
            chargerPowerKW: 11,
            isDC: false,
            batteryLevel: 68,
            chargeLimit: 80
        )

        XCTAssertEqual(content.title, "Model Y - 11 kW AC")
        XCTAssertEqual(content.body, "Battery 68%, limit 80%")
    }

    func testChargingNotificationUsesChineseBodyWhenRequested() {
        let content = ChargingNotificationContent(
            carName: "Model Y",
            chargerPowerKW: 11,
            isDC: false,
            batteryLevel: 68,
            chargeLimit: 80,
            language: .chinese
        )

        XCTAssertEqual(content.title, "Model Y - 11 kW 交流")
        XCTAssertEqual(content.body, "电量 68%，上限 80%")
    }

    func testChargingNotificationUsesEuropeanLanguageBody() {
        let content = ChargingNotificationContent(
            carName: "Model Y",
            chargerPowerKW: 150,
            isDC: true,
            batteryLevel: 68,
            chargeLimit: 80,
            language: .german
        )

        XCTAssertEqual(content.title, "Model Y - 150 kW DC")
        XCTAssertEqual(content.body, "Batterie 68%, Limit 80%")
    }

    func testSentryNotificationIncludesAlertCountAndLocation() {
        let content = SentryNotificationContent(carName: "Model 3", alertCount: 3, locationText: "Garage")

        XCTAssertEqual(content.title, "Model 3 - Sentry Alert #3")
        XCTAssertEqual(content.body, "Detected at Garage")
    }

    func testSentryNotificationUsesChineseTextWhenRequested() {
        let content = SentryNotificationContent(carName: "Model 3", alertCount: 3, locationText: "车库", language: .chinese)

        XCTAssertEqual(content.title, "Model 3 - 哨兵警报 #3")
        XCTAssertEqual(content.body, "检测位置：车库")
    }

    func testSentryNotificationUsesChineseFallbackBodyWhenLocationIsMissing() {
        let content = SentryNotificationContent(carName: "Model 3", alertCount: 1, language: .chinese)

        XCTAssertEqual(content.title, "Model 3 - 哨兵警报 #1")
        XCTAssertEqual(content.body, "哨兵模式检测到活动")
    }

    func testSentryNotificationUsesEuropeanLanguageWithLocation() {
        let content = SentryNotificationContent(carName: "Model 3", alertCount: 2, locationText: "Garaje", language: .spanish)

        XCTAssertEqual(content.title, "Model 3 - Alerta Sentry #2")
        XCTAssertEqual(content.body, "Detectado en Garaje")
    }

    func testTyrePressureNotificationFormatsThreshold() {
        let content = TyrePressureNotificationContent(
            carName: "Model S",
            tyreName: "Front left",
            pressure: 2.1,
            unit: "bar",
            threshold: 2.4
        )

        XCTAssertEqual(content.title, "Model S - Tyre Pressure")
        XCTAssertEqual(content.body, "Front left is 2.1 bar, below 2.4 bar")
    }

    func testTyrePressureNotificationUsesChineseTextWhenRequested() {
        let content = TyrePressureNotificationContent(
            carName: "Model S",
            tyreName: "Front left",
            pressure: 2.1,
            unit: "bar",
            threshold: 2.4,
            language: .chinese
        )

        XCTAssertEqual(content.title, "Model S - 胎压")
        XCTAssertEqual(content.body, "左前轮 当前 2.1 bar，低于 2.4 bar")
    }

    func testTyrePressureNotificationUsesEuropeanLanguageAndLocalizesWheel() {
        let italian = TyrePressureNotificationContent(
            carName: "Model S",
            tyreName: "Rear right",
            pressure: 2.1,
            unit: "bar",
            threshold: 2.4,
            language: .italian
        )
        let catalan = TyrePressureNotificationContent(
            carName: "Model S",
            tyreName: "Front left",
            pressure: 2.1,
            unit: "bar",
            threshold: 2.4,
            language: .catalan
        )

        XCTAssertEqual(italian.title, "Model S - Pressione pneumatici")
        XCTAssertEqual(italian.body, "Posteriore destro è a 2.1 bar, sotto 2.4 bar")
        XCTAssertEqual(catalan.body, "Davanter esquerre és a 2.1 bar, per sota de 2.4 bar")
    }
}
