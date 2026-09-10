import XCTest
@testable import MateDriveApp

final class ChargeLiveActivityPresentationTests: XCTestCase {
    func testChargeLabelsMetricsAndDurationInAllLanguages() {
        let cases: [(
            WidgetDisplayLanguage,
            ac: String,
            dc: String,
            battery: String,
            limit: String,
            remaining: String
        )] = [
            (.english, "AC charging", "DC charging", "Battery", "Limit 80%", "1h 05m remaining"),
            (.chinese, "交流充电", "直流充电", "电量", "目标 80%", "剩余 1小时05分钟"),
            (.traditionalChinese, "交流充電", "直流充電", "電量", "目標 80%", "剩餘 1小時05分鐘")
        ]

        for item in cases {
            let ac = makePresentation(language: item.0, isDC: false)
            let dc = makePresentation(language: item.0, isDC: true)
            XCTAssertEqual(ac.statusText, item.ac)
            XCTAssertEqual(dc.statusText, item.dc)
            XCTAssertEqual(ac.batteryLabelText, item.battery)
            XCTAssertEqual(ac.limitText, item.limit)
            XCTAssertEqual(ac.remainingText, item.remaining)
        }
    }

    func testShortAndZeroDurationInAllLanguages() {
        let cases: [(WidgetDisplayLanguage, Int, String)] = [
            (.english, 5, "5m remaining"),
            (.english, 0, "0m remaining"),
            (.chinese, 5, "剩余 5分钟"),
            (.chinese, 0, "剩余 0分钟"),
            (.traditionalChinese, 5, "剩餘 5分鐘"),
            (.traditionalChinese, 0, "剩餘 0分鐘")
        ]

        for (language, minutes, expected) in cases {
            XCTAssertEqual(
                makePresentation(language: language, timeToFullMinutes: minutes).remainingText,
                expected
            )
        }
    }

    func testTrustPrecedenceIsOfflineThenStaleThenPartialThenChargeType() {
        XCTAssertEqual(
            makePresentation(quality: .offline, isStale: true).statusText,
            "Offline"
        )
        XCTAssertEqual(
            makePresentation(quality: .complete, isStale: true).statusText,
            "Update pending"
        )
        XCTAssertEqual(
            makePresentation(quality: .partial, isStale: false).statusText,
            "Partial data"
        )
        XCTAssertEqual(
            makePresentation(quality: .complete, isStale: false).statusText,
            "AC charging"
        )
    }

    func testTrustLabelsAreLocalized() {
        let cases: [(WidgetDisplayLanguage, WidgetChargeDataQuality, Bool, String)] = [
            (.english, .offline, false, "Offline"),
            (.chinese, .offline, false, "离线"),
            (.traditionalChinese, .offline, false, "離線"),
            (.english, .complete, true, "Update pending"),
            (.chinese, .complete, true, "等待更新"),
            (.traditionalChinese, .complete, true, "等待更新"),
            (.english, .partial, false, "Partial data"),
            (.chinese, .partial, false, "部分数据待更新"),
            (.traditionalChinese, .partial, false, "部分資料待更新")
        ]

        for (language, quality, isStale, expected) in cases {
            XCTAssertEqual(
                makePresentation(language: language, quality: quality, isStale: isStale).statusText,
                expected
            )
        }
    }

    func testAccessibilityContainsEveryVisibleMetricAndTrustState() {
        let value = makePresentation(quality: .partial)

        for expected in [
            "Model 3", "Partial data", "Battery", "64%", "Limit 80%",
            "72 kW", "18.4 kWh", "1h 05m remaining"
        ] {
            XCTAssertTrue(value.accessibilityText.contains(expected), "Missing \(expected)")
        }
        XCTAssertTrue(value.accessibilityText.contains(value.updatedText))
    }

    func testMissingMetricsAreOmittedExceptBatteryPlaceholder() {
        let value = makePresentation(
            batteryLevel: nil,
            chargeLimitSoc: nil,
            chargerPowerKW: nil,
            energyAddedKWh: nil,
            timeToFullMinutes: nil
        )

        XCTAssertEqual(value.batteryText, "--")
        XCTAssertNil(value.limitText)
        XCTAssertNil(value.powerText)
        XCTAssertNil(value.energyText)
        XCTAssertNil(value.remainingText)
        XCTAssertFalse(value.accessibilityText.contains("0 kW"))
        XCTAssertFalse(value.accessibilityText.contains("0.0 kWh"))
    }

    func testChargingProgressClampsBatteryAndLimitToAValidRange() {
        XCTAssertEqual(
            makePresentation(batteryLevel: 120, chargeLimitSoc: 80).progress,
            WidgetChargeProgress(current: 80, total: 80)
        )
        XCTAssertEqual(
            makePresentation(batteryLevel: -5, chargeLimitSoc: 120).progress,
            WidgetChargeProgress(current: 0, total: 100)
        )
    }

    func testOfflineAndStaleChargingKeepCachedProgress() {
        XCTAssertEqual(
            makePresentation(quality: .offline, isStale: false).progress,
            WidgetChargeProgress(current: 64, total: 80)
        )
        XCTAssertEqual(
            makePresentation(quality: .complete, isStale: true).progress,
            WidgetChargeProgress(current: 64, total: 80)
        )
    }

    func testIdleOrInvalidMetricsNeverProduceProgress() {
        XCTAssertNil(makePresentation(isCharging: false).progress)
        XCTAssertNil(makePresentation(batteryLevel: nil).progress)
        XCTAssertNil(makePresentation(chargeLimitSoc: nil).progress)
        XCTAssertNil(makePresentation(chargeLimitSoc: 0).progress)
        XCTAssertNil(makePresentation(chargeLimitSoc: -1).progress)
    }

    func testWidgetViewsOnlyReceivePresentationAfterTheActivityBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("MateDriveWidget/ChargeLiveActivityWidget.swift"),
            encoding: .utf8
        )
        let normalized = source
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        XCTAssertEqual(source.components(separatedBy: "state: context.state").count - 1, 2)
        XCTAssertFalse(normalized.contains("ChargeLiveActivityLockScreenView( state:"))
        XCTAssertFalse(normalized.contains("ChargeProgress( state:"))
        XCTAssertFalse(normalized.contains("let state: ChargeLiveActivityAttributes.ContentState"))
    }

    func testLegacyActivityPayloadDecodesWithSafeDefaults() throws {
        let attributes = try JSONDecoder().decode(
            ChargeLiveActivityAttributes.self,
            from: Data(#"{"carID":7,"carName":"Model 3"}"#.utf8)
        )
        let state = try JSONDecoder().decode(
            ChargeLiveActivityAttributes.ContentState.self,
            from: Data(#"{"isDC":false,"isCharging":true,"updatedAt":0}"#.utf8)
        )

        XCTAssertEqual(attributes.carID, 7)
        XCTAssertNil(attributes.vehicleIdentifier)
        XCTAssertEqual(state.displayLanguage, .system)
        XCTAssertEqual(state.quality, .complete)
    }

    func testNewActivityPayloadRoundTripsVehicleLanguageQualityAndMetrics() throws {
        let identifier = String(repeating: "a", count: 64)
        let attributes = ChargeLiveActivityAttributes(
            carName: "Model 3",
            vehicleIdentifier: identifier
        )
        let state = ChargeLiveActivityAttributes.ContentState(
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: true,
            isCharging: true,
            displayLanguage: .traditionalChinese,
            quality: .partial,
            updatedAt: Date(timeIntervalSince1970: 1_786_320_000)
        )

        let decodedAttributes = try JSONDecoder().decode(
            ChargeLiveActivityAttributes.self,
            from: JSONEncoder().encode(attributes)
        )
        XCTAssertNil(decodedAttributes.carID)
        XCTAssertEqual(decodedAttributes.carName, "Model 3")
        XCTAssertEqual(decodedAttributes.vehicleIdentifier, identifier)

        let decodedState = try JSONDecoder().decode(
            ChargeLiveActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decodedState, state)
        XCTAssertEqual(decodedState.displayLanguage, .traditionalChinese)
        XCTAssertEqual(decodedState.quality, .partial)
    }

    // Production break caught: direct attribute encoding bypasses the manager and serializes a malformed or sensitive identifier.
    func testNewActivityAttributesRejectEveryNoncanonicalVehicleIdentifierDuringEncoding() {
        let invalidIdentifiers = [
            "7",
            String(repeating: "g", count: 64),
            "https://teslamate.example",
            String(repeating: "A", count: 64)
        ]

        for invalidIdentifier in invalidIdentifiers {
            let attributes = ChargeLiveActivityAttributes(
                carName: "Model 3",
                vehicleIdentifier: invalidIdentifier
            )

            XCTAssertThrowsError(
                try JSONEncoder().encode(attributes),
                "Encoded a noncanonical identifier: \(invalidIdentifier)"
            )
        }
    }

    func testLiveActivityStaleDateIsExactlyTwoMinutesAfterUpdate() {
        let updatedAt = Date(timeIntervalSince1970: 1_786_320_000)
        XCTAssertEqual(
            ChargeLiveActivitySnapshot.fixture(updatedAt: updatedAt).staleDate,
            updatedAt.addingTimeInterval(120)
        )
    }

    private func makePresentation(
        language: WidgetDisplayLanguage = .english,
        isDC: Bool = false,
        isCharging: Bool = true,
        quality: WidgetChargeDataQuality = .complete,
        isStale: Bool = false,
        batteryLevel: Int? = 64,
        chargeLimitSoc: Int? = 80,
        chargerPowerKW: Int? = 72,
        energyAddedKWh: Double? = 18.4,
        timeToFullMinutes: Int? = 65
    ) -> ChargeLiveActivityPresentation {
        ChargeLiveActivityPresentation.make(
            attributes: ChargeLiveActivityAttributes(
                carName: "Model 3",
                vehicleIdentifier: String(repeating: "a", count: 64)
            ),
            state: ChargeLiveActivityAttributes.ContentState(
                batteryLevel: batteryLevel,
                chargeLimitSoc: chargeLimitSoc,
                chargerPowerKW: chargerPowerKW,
                energyAddedKWh: energyAddedKWh,
                timeToFullMinutes: timeToFullMinutes,
                isDC: isDC,
                isCharging: isCharging,
                displayLanguage: language,
                quality: quality,
                updatedAt: Date(timeIntervalSince1970: 1_786_320_000)
            ),
            isStale: isStale
        )
    }
}
