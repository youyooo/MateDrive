import XCTest
@testable import MateDroidIOS

final class ActivitySessionCardTests: XCTestCase {
    func testMissingCostAndRangeAreAbsentWithoutSyntheticZeroes() {
        let presentation = makePresentation(
            parkingMetrics: makeMetrics(
                netBatteryChangePercent: nil,
                chargeGainPercent: nil,
                standbyBatteryChangePercent: nil,
                ratedRangeChangeKm: nil
            ),
            chargeCost: nil
        )

        XCTAssertEqual(presentation.metrics.map(\.kind), [.parkingDuration])
        XCTAssertFalse(presentation.accessibilityValue.contains("0%"))
        XCTAssertFalse(presentation.accessibilityValue.contains("0.0 km"))
        XCTAssertFalse(presentation.accessibilityValue.contains("cost"))
    }

    func testChargeGainAndStandbyLossRemainDistinctMetrics() {
        let presentation = makePresentation(
            parkingMetrics: makeMetrics(
                netBatteryChangePercent: 28,
                chargeGainPercent: 30,
                standbyBatteryChangePercent: -2,
                ratedRangeChangeKm: -8.5
            )
        )

        let charge = presentation.metrics.first { $0.kind == .chargeGain }
        let standby = presentation.metrics.first { $0.kind == .standbyLoss }

        XCTAssertEqual(charge?.value, "+30%")
        XCTAssertEqual(charge?.semanticColor, .green)
        XCTAssertEqual(standby?.value, "-2%")
        XCTAssertEqual(standby?.semanticColor, .indigo)
        XCTAssertNotEqual(charge?.id, standby?.id)
    }

    func testEstimatedCostUsesOrangeSourceSemantic() throws {
        let cost = SmartActivityChargeCost(
            amount: 6.6,
            currencyCode: "CNY",
            source: .regionalTariff,
            ruleID: "hunan-home",
            isEstimated: true,
            isExplicitlyFree: false,
            components: []
        )
        let presentation = makePresentation(parkingMetrics: makeMetrics(), chargeCost: cost)
        let metric = try XCTUnwrap(presentation.metrics.first { $0.kind == .cost })

        XCTAssertEqual(metric.value, "¥6.60")
        XCTAssertEqual(metric.semanticColor, .orange)
        XCTAssertEqual(metric.sourceText, "Estimated · Regional tariff")
    }

    func testVisualAndAccessibilityMetricsUseTheSameOrder() throws {
        let cost = SmartActivityChargeCost(
            amount: 12.5,
            currencyCode: "USD",
            source: .manual,
            ruleID: nil,
            isEstimated: false,
            isExplicitlyFree: false,
            components: []
        )
        let presentation = makePresentation(
            parkingMetrics: makeMetrics(
                netBatteryChangePercent: 28,
                chargeGainPercent: 30,
                standbyBatteryChangePercent: -2,
                ratedRangeChangeKm: -8.5
            ),
            chargeCost: cost
        )

        XCTAssertEqual(presentation.metrics.map(\.kind), [
            .parkingDuration,
            .netBatteryChange,
            .chargeGain,
            .standbyLoss,
            .ratedRangeChange,
            .cost
        ])

        let value = presentation.accessibilityValue
        let ranges = try presentation.metrics.map { metric in
            try XCTUnwrap(value.range(of: metric.accessibilityText))
        }
        for pair in zip(ranges, ranges.dropFirst()) {
            XCTAssertLessThan(pair.0.lowerBound, pair.1.lowerBound)
        }
        XCTAssertEqual(value, presentation.metrics.map(\.accessibilityText).joined(separator: ", "))
    }

    func testExplicitZeroChangesAreOmittedButExplicitFreeCostIsDisplayed() throws {
        let cost = SmartActivityChargeCost(
            amount: 0,
            currencyCode: "CNY",
            source: .manual,
            ruleID: nil,
            isEstimated: false,
            isExplicitlyFree: true,
            components: []
        )
        let presentation = makePresentation(
            parkingMetrics: makeMetrics(
                netBatteryChangePercent: 0,
                chargeGainPercent: 0,
                standbyBatteryChangePercent: 0,
                ratedRangeChangeKm: 0
            ),
            chargeCost: cost
        )

        XCTAssertEqual(presentation.metrics.map(\.kind), [.parkingDuration, .cost])
        let costMetric = try XCTUnwrap(presentation.metrics.last)
        XCTAssertEqual(costMetric.value, "Free")
        XCTAssertEqual(costMetric.semanticColor, .green)
    }

    private func makePresentation(
        parkingMetrics: ParkingIntervalMetrics?,
        chargeCost: SmartActivityChargeCost? = nil
    ) -> ActivitySessionCardPresentation {
        ActivitySessionCardBuilder.presentation(
            session: SmartActivitySession(
                id: "activity-1",
                carId: 1,
                startDate: Date(timeIntervalSince1970: 1_784_352_600),
                endDate: Date(timeIntervalSince1970: 1_784_356_200),
                placeKey: "geofence:home",
                latitude: 28.2,
                longitude: 112.9,
                geofenceID: "home",
                provisionalKind: .homeCharging,
                classification: nil,
                parkingMetrics: parkingMetrics,
                chargeCost: chargeCost,
                eventReferences: [],
                isOpen: false,
                quality: .complete,
                derivationVersion: 1,
                sourceFingerprint: "source",
                derivationFingerprint: "derived"
            ),
            placeName: "Home",
            language: .english,
            units: .metric,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    private func makeMetrics(
        netBatteryChangePercent: Int? = nil,
        chargeGainPercent: Int? = nil,
        standbyBatteryChangePercent: Int? = nil,
        ratedRangeChangeKm: Double? = nil
    ) -> ParkingIntervalMetrics {
        ParkingIntervalMetrics(
            startDate: Date(timeIntervalSince1970: 1_784_352_600),
            endDate: Date(timeIntervalSince1970: 1_784_356_200),
            duration: 3_600,
            startBatteryPercent: 40,
            endBatteryPercent: 68,
            netBatteryChangePercent: netBatteryChangePercent,
            chargeGainPercent: chargeGainPercent,
            standbyBatteryChangePercent: standbyBatteryChangePercent,
            startRatedRangeKm: 300,
            endRatedRangeKm: ratedRangeChangeKm.map { 300 + $0 },
            ratedRangeChangeKm: ratedRangeChangeKm,
            vehicleReportedChargeEnergyKWh: nil,
            sleepDuration: 1_800,
            awakeDuration: 1_800,
            wakeCount: 1,
            quality: .complete,
            missingReasonCodes: []
        )
    }
}
