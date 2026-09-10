import XCTest
@testable import MateDriveApp

final class ChargePriceConfirmationTests: XCTestCase {
    func testFutureStationRuleWithoutUnitPriceOrBilledEnergyIsRejected() {
        let issues = ChargePricingConfirmationValidator.validate(makeConfirmation(
            scope: .futureAtStation,
            finalAmount: 12,
            billedEnergyKWh: nil,
            pricePerKWh: nil
        ))

        XCTAssertEqual(issues, [.missingFutureUnitPrice])
    }

    func testRejectsNonFiniteAndNegativeMoneyValuesAndNonPositiveBilledEnergy() {
        let issues = ChargePricingConfirmationValidator.validate(makeConfirmation(
            finalAmount: .infinity,
            billedEnergyKWh: 0,
            pricePerKWh: -0.1,
            serviceFeePerKWh: .nan,
            fixedFee: -1
        ))

        XCTAssertEqual(issues, [
            .invalidFinalAmount,
            .invalidBilledEnergy,
            .invalidUnitPrice,
            .invalidServiceFee,
            .invalidFixedFee
        ])
    }

    func testTimeWindowRequiresBothBoundariesWithinMinuteOfDay() {
        XCTAssertEqual(
            ChargePricingConfirmationValidator.validate(makeConfirmation(
                startMinute: 60,
                endMinute: nil
            )),
            [.incompleteTimeWindow]
        )
        XCTAssertEqual(
            ChargePricingConfirmationValidator.validate(makeConfirmation(
                startMinute: -1,
                endMinute: 1_440
            )),
            [.invalidTimeWindow]
        )
        XCTAssertEqual(
            ChargePricingConfirmationValidator.validate(makeConfirmation(
                startMinute: 0,
                endMinute: 1_439
            )),
            []
        )
    }

    func testExplicitZeroFinalAmountIsValid() {
        let value = makeConfirmation(
            scope: .sessionOnly,
            finalAmount: 0,
            billedEnergyKWh: nil,
            pricePerKWh: nil
        )

        XCTAssertEqual(ChargePricingConfirmationValidator.validate(value), [])
    }

    func testFutureRuleCanDeriveUnitPriceFromBillComponents() throws {
        let value = makeConfirmation(
            scope: .futureAtStation,
            finalAmount: 12,
            billedEnergyKWh: 10,
            pricePerKWh: nil,
            serviceFeePerKWh: 0.2,
            fixedFee: 1
        )

        XCTAssertEqual(ChargePricingConfirmationValidator.validate(value), [])
        XCTAssertEqual(
            try XCTUnwrap(ChargePricingConfirmationValidator.resolvedUnitPrice(for: value)),
            0.9,
            accuracy: 0.000_001
        )
    }

    func testFutureRuleRejectsBillComponentsThatDeriveNegativeUnitPrice() {
        let value = makeConfirmation(
            scope: .futureAtStation,
            finalAmount: 1,
            billedEnergyKWh: 10,
            pricePerKWh: nil,
            serviceFeePerKWh: 0.2,
            fixedFee: 1
        )

        XCTAssertEqual(
            ChargePricingConfirmationValidator.validate(value),
            [.missingFutureUnitPrice]
        )
    }

    private func makeConfirmation(
        scope: ChargePricingObservationScope = .sessionOnly,
        finalAmount: Double = 12,
        billedEnergyKWh: Double? = 10,
        pricePerKWh: Double? = 1,
        serviceFeePerKWh: Double? = nil,
        fixedFee: Double? = nil,
        currencyCode: String = "CNY",
        startMinute: Int? = nil,
        endMinute: Int? = nil
    ) -> ChargePricingConfirmation {
        ChargePricingConfirmation(
            carId: 1,
            chargeId: 2,
            stationKey: "station:test",
            scope: scope,
            finalAmount: finalAmount,
            billedEnergyKWh: billedEnergyKWh,
            pricePerKWh: pricePerKWh,
            serviceFeePerKWh: serviceFeePerKWh,
            fixedFee: fixedFee,
            currencyCode: currencyCode,
            coordinates: GeocodeLocation(latitude: SyntheticCoordinates.point(latitudeOffset: 0.2282).northing, longitude: SyntheticCoordinates.point(longitudeOffset: 0.9388).easting),
            chargerIdentity: .ac,
            startMinute: startMinute,
            endMinute: endMinute
        )
    }
}
