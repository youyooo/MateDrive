import XCTest
@testable import MateDroidIOS

@MainActor
final class SmartActivitySettingsTests: XCTestCase {
    func testHomeTariffRegionRoundTripsWithoutChangingCurrencyOrDuplicatingKey() throws {
        var settings = AppSettings(currencyCode: "HKD")
        settings.homeTariffRegionCode = " cn-43 "

        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(decoded.homeTariffRegionCode, "CN-43")
        XCTAssertEqual(decoded.residentialTariffRegionCode, "CN-43")
        XCTAssertEqual(decoded.currencyCode, "HKD")
        XCTAssertEqual(object["residentialTariffRegionCode"] as? String, "CN-43")
        XCTAssertNil(object["homeTariffRegionCode"])
    }

    func testLegacyHomeTariffRegionDecodesAndCanonicalValueWinsWhenBothExist() throws {
        let legacy = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"currencyCode":"HKD","homeTariffRegionCode":" cn-43 "}"#.utf8)
        )
        let mixed = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"residentialTariffRegionCode":"CN-31","homeTariffRegionCode":"CN-43"}"#.utf8)
        )

        XCTAssertEqual(legacy.residentialTariffRegionCode, "CN-43")
        XCTAssertEqual(legacy.currencyCode, "HKD")
        XCTAssertEqual(mixed.homeTariffRegionCode, "CN-31")
    }

    func testCatalogStatusReportsVersionAndUniqueSources() {
        let model = makeModel(catalog: Self.catalog)

        XCTAssertEqual(model.catalogStatus?.version, 7)
        XCTAssertEqual(model.catalogStatus?.generatedAt, "2026-07-18")
        XCTAssertEqual(model.catalogStatus?.regionCount, 1)
        XCTAssertEqual(model.catalogStatus?.verifiedRegionCount, 1)
        XCTAssertEqual(model.catalogStatus?.sourceCount, 1)
        XCTAssertEqual(model.catalogRegions.map(\.regionCode), ["CN-43"])
    }

    func testRebuildRequiresConfirmationAndOnlyCallsIndexerMaintenance() async {
        let indexer = RecordingSmartActivityIndexer()
        let labels = RecordingActivityLabelStore()
        let observations = RecordingPricingObservationStore()
        let model = makeModel(indexer: indexer, labels: labels, observations: observations)

        model.requestConfirmation(for: .rebuildDerivedActivities)
        XCTAssertEqual(model.pendingConfirmation, .rebuildDerivedActivities)
        let callsBeforeConfirmation = await indexer.calls()
        XCTAssertEqual(callsBeforeConfirmation, [])

        await model.confirmPendingAction()

        let indexerCalls = await indexer.calls()
        let labelRemovals = await labels.removeAllCount()
        let observationRemovals = await observations.removeAllCount()
        XCTAssertEqual(indexerCalls, [.removeDerivedData, .rebuild([9, 3])])
        XCTAssertEqual(labelRemovals, 0)
        XCTAssertEqual(observationRemovals, 0)
        XCTAssertEqual(model.lastResult, .rebuilt(completedCarCount: 2, failedCarCount: 0))
    }

    func testClearSuggestionsRequiresConfirmationAndOnlyClearsLearningStores() async {
        let indexer = RecordingSmartActivityIndexer()
        let labels = RecordingActivityLabelStore()
        let observations = RecordingPricingObservationStore()
        let model = makeModel(indexer: indexer, labels: labels, observations: observations)

        model.requestConfirmation(for: .clearLearnedSuggestions)
        model.cancelConfirmation()
        await model.confirmPendingAction()
        let labelRemovalsBeforeConfirmation = await labels.removeAllCount()
        let observationRemovalsBeforeConfirmation = await observations.removeAllCount()
        XCTAssertEqual(labelRemovalsBeforeConfirmation, 0)
        XCTAssertEqual(observationRemovalsBeforeConfirmation, 0)

        model.requestConfirmation(for: .clearLearnedSuggestions)
        await model.confirmPendingAction()

        let indexerCalls = await indexer.calls()
        let labelRemovals = await labels.removeAllCount()
        let observationRemovals = await observations.removeAllCount()
        XCTAssertEqual(indexerCalls, [])
        XCTAssertEqual(labelRemovals, 1)
        XCTAssertEqual(observationRemovals, 1)
        XCTAssertEqual(model.lastResult, .learnedSuggestionsCleared)
    }

    private func makeModel(
        indexer: RecordingSmartActivityIndexer = RecordingSmartActivityIndexer(),
        labels: RecordingActivityLabelStore = RecordingActivityLabelStore(),
        observations: RecordingPricingObservationStore = RecordingPricingObservationStore(),
        catalog: RegionalChargingTariffCatalog? = nil
    ) -> SmartActivitySettingsModel {
        let resolvedCatalog = catalog ?? Self.catalog
        return SmartActivitySettingsModel(
            indexer: indexer,
            labelStore: labels,
            pricingObservationStore: observations,
            carIds: { [9, 3] },
            catalogProvider: { resolvedCatalog }
        )
    }

    private static let catalog = RegionalChargingTariffCatalog(
        version: 7,
        generatedAt: "2026-07-18",
        regions: [
            RegionalChargingTariffRegion(
                regionCode: "CN-43",
                names: ["en": "Hunan", "zh-Hans": "湖南"],
                availability: .verified,
                verifiedAt: "2026-07-18",
                tariffs: [
                    RegionalChargingTariff(
                        id: "hunan-home",
                        status: .active,
                        customerClass: "residential",
                        chargeType: .ac,
                        currencyCode: "CNY",
                        effectiveFromDate: "2026-01-01",
                        effectiveToDate: nil,
                        documentID: "fixture",
                        sourceURL: URL(string: "https://example.com/tariff")!,
                        basePricePerKWh: 0.5,
                        timeSegments: [],
                        serviceFeePerKWh: 0,
                        sessionFee: 0,
                        applicableWeekdays: nil,
                        applicableMonths: nil
                    )
                ]
            )
        ]
    )
}

private actor RecordingSmartActivityIndexer: SmartActivityIndexing {
    enum Call: Equatable, Sendable {
        case removeDerivedData
        case rebuild([Int])
    }

    private var recordedCalls: [Call] = []

    func rebuild(carIds: [Int]) async -> SmartActivityIndexReport {
        recordedCalls.append(.rebuild(carIds))
        return SmartActivityIndexReport(
            attemptedCarIds: carIds,
            completedCarIds: carIds,
            failedCarIds: [],
            unchangedCarIds: []
        )
    }

    func removeDerivedData() async throws {
        recordedCalls.append(.removeDerivedData)
    }

    func calls() -> [Call] { recordedCalls }
}

private actor RecordingActivityLabelStore: ActivityLabelOverrideStoring {
    private var removals = 0

    func overrides(carId: Int) async throws -> [ActivityLabelOverride] { [] }
    func override(id: String) async throws -> ActivityLabelOverride? { nil }
    func save(_ value: ActivityLabelOverride) async throws {}
    func delete(id: String) async throws {}
    func removeAll() async throws { removals += 1 }
    func removeAllCount() -> Int { removals }
}

private actor RecordingPricingObservationStore: ChargePricingObservationStoring {
    private var removals = 0

    func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation] { [] }
    func save(_ value: ChargePricingObservation) async throws {}
    func remove(id: String) async throws {}
    func removeAll() async throws { removals += 1 }
    func removeAllCount() -> Int { removals }
}
