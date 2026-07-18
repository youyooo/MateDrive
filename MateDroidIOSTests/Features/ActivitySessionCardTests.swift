import SwiftUI
import UIKit
import XCTest
@testable import MateDroidIOS

@MainActor
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
        XCTAssertEqual(presentation.semanticColor, .orange)
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

    func testSleepSessionRemainsIndigoWhenItIncludesDriveReferences() {
        let arrival = SmartActivityEventReference(sourceActivity: TeslaMateActivity(
            id: 42,
            type: "drive",
            startDate: "2026-07-18T00:30:00Z",
            endDate: "2026-07-18T01:00:00Z",
            endAddress: "Home"
        ))
        let presentation = makePresentation(
            parkingMetrics: makeMetrics(),
            eventReferences: [arrival],
            provisionalKind: .parking
        )

        XCTAssertEqual(presentation.semanticColor, .indigo)
    }

    func testAccessibilityDynamicTypeProducesFiniteExpandedHostedLayout() {
        let presentation = ActivitySessionCardPresentation(
            title: "Overnight parking and charging activity",
            placeText: "A deliberately long saved parking location name for constrained phone layout",
            timeText: "July 18, 2026 at 1:00 AM - July 18, 2026 at 8:30 AM",
            systemImage: "moon.zzz.fill",
            semanticColor: .indigo,
            metrics: [
                ActivitySessionCardMetric(
                    kind: .parkingDuration,
                    title: "Parking duration",
                    value: "7 hr 30 min",
                    systemImage: "clock.fill",
                    semanticColor: .indigo
                ),
                ActivitySessionCardMetric(
                    kind: .standbyLoss,
                    title: "Standby battery change",
                    value: "-2%",
                    systemImage: "moon.zzz.fill",
                    semanticColor: .indigo
                ),
                ActivitySessionCardMetric(
                    kind: .cost,
                    title: "Charging cost",
                    value: "$12.50",
                    systemImage: "creditcard.fill",
                    semanticColor: .green,
                    sourceText: "Confirmed - Manual entry"
                )
            ]
        )

        let normalSize = hostedSize(
            presentation: presentation,
            dynamicTypeSize: .large,
            width: 320
        )
        let accessibilitySize = hostedSize(
            presentation: presentation,
            dynamicTypeSize: .accessibility3,
            width: 320
        )

        for size in [normalSize, accessibilitySize] {
            XCTAssertTrue(size.width.isFinite)
            XCTAssertTrue(size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(size.width, 320)
        }
        XCTAssertGreaterThan(accessibilitySize.height, normalSize.height)
    }

    private func makePresentation(
        parkingMetrics: ParkingIntervalMetrics?,
        chargeCost: SmartActivityChargeCost? = nil,
        eventReferences: [SmartActivityEventReference] = [],
        provisionalKind: SmartActivityPurpose = .homeCharging
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
                provisionalKind: provisionalKind,
                classification: nil,
                parkingMetrics: parkingMetrics,
                chargeCost: chargeCost,
                eventReferences: eventReferences,
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

    private func hostedSize(
        presentation: ActivitySessionCardPresentation,
        dynamicTypeSize: DynamicTypeSize,
        width: CGFloat
    ) -> CGSize {
        let view = ActivitySessionCard(presentation: presentation)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        let controller = UIHostingController(rootView: view)
        let fittingConstraint = CGSize(width: width, height: 10_000)
        controller.view.bounds = CGRect(origin: .zero, size: fittingConstraint)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        return controller.sizeThatFits(in: fittingConstraint)
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
