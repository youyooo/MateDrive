import Foundation
import XCTest
@testable import MateDroidIOS

@MainActor
final class VehicleImageCatalogTests: XCTestCase {
    func testDecodesSchemaVersionOneAndAllFirstPhaseGenerations() throws {
        let catalog = try decode(fixture())

        XCTAssertEqual(catalog.schemaVersion, VehicleImageCatalog.currentSchemaVersion)
        XCTAssertEqual(catalog.generations.count, 20)
        XCTAssertTrue(catalog.assets.allSatisfy { $0.reviewStatus == .legacy })
        XCTAssertEqual(
            Set(catalog.generations.map(\.id)),
            [
                "roadster-1", "model-s-nosecone", "model-s-facelift", "model-s-refresh", "model-s-plaid",
                "model-x-legacy", "model-x-refresh", "model-x-plaid", "model-3-early", "model-3-refresh",
                "model-3-refresh-performance", "model-3-highland", "model-3-highland-performance", "model-y-legacy",
                "model-y-legacy-performance", "model-y-juniper-standard", "model-y-juniper-premium",
                "model-y-juniper-performance", "cybertruck-awd", "cybertruck-cyberbeast"
            ]
        )
    }

    func testRejectsUnsupportedSchemaVersion() {
        var value = fixture()
        value["schemaVersion"] = 2

        assertValidationFailure(value, expected: .unsupportedSchemaVersion(2))
    }

    func testRejectsDuplicateGenerationIDs() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[1]["id"] = generations[0]["id"]
        value["generations"] = generations

        assertValidationFailure(value, expected: .duplicateGenerationID("roadster-1"))
    }

    func testRejectsDuplicateAssetIDs() {
        var value = fixture()
        var assets = value["assets"] as! [[String: Any]]
        assets[1]["id"] = assets[0]["id"]
        value["assets"] = assets

        assertValidationFailure(value, expected: .duplicateAssetID("legacy-roadster-1"))
    }

    func testRejectsNonInclusiveYearRange() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[0]["yearStart"] = 2013
        generations[0]["yearEnd"] = 2012
        value["generations"] = generations

        assertValidationFailure(value, expected: .invalidYearRange(generationID: "roadster-1", start: 2013, end: 2012))
    }

    func testRejectsMissingDefaultReferences() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[0]["defaultWheelID"] = "missing-wheel"
        value["generations"] = generations

        assertValidationFailure(value, expected: .missingDefaultWheel(generationID: "roadster-1", wheelID: "missing-wheel"))
    }

    func testRejectsMissingDefaultTrimReference() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[0]["defaultTrimID"] = "missing-trim"
        value["generations"] = generations

        assertValidationFailure(value, expected: .missingDefaultTrim(generationID: "roadster-1", trimID: "missing-trim"))
    }

    func testRejectsMissingDefaultColorReference() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[0]["defaultColorID"] = "missing-color"
        value["generations"] = generations

        assertValidationFailure(value, expected: .missingDefaultColor(generationID: "roadster-1", colorID: "missing-color"))
    }

    func testRejectsTiedGenerationMatcherPriorities() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[2]["matcherPriority"] = generations[1]["matcherPriority"]
        value["generations"] = generations

        assertValidationFailure(value, expected: .tiedMatcherPriority(model: "Model S", priority: 20))
    }

    func testRejectsReferencedAssetPathThatIsNotBundled() {
        var value = fixture()
        var assets = value["assets"] as! [[String: Any]]
        assets[0]["path"] = "CarImages/missing.png"
        value["assets"] = assets

        assertValidationFailure(value, expected: .missingBundledAssetPath("CarImages/missing.png"))
    }

    func testRejectsLegacyFallbackFromAnotherGeneration() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[0]["legacyFallback"] = [
            "assetID": "legacy-model-s-nosecone",
            "path": "CarImages/ms_PPSW_WT19.png"
        ]
        value["generations"] = generations

        assertValidationFailure(value, expected: .invalidLegacyFallback(generationID: "roadster-1"))
    }

    func testRejectsMissingLegacyFallbackAsset() {
        var value = fixture()
        var generations = value["generations"] as! [[String: Any]]
        generations[0]["legacyFallback"] = [
            "assetID": "missing-asset",
            "path": "CarImages/m3_PPSW_W38B.png"
        ]
        value["generations"] = generations

        assertValidationFailure(value, expected: .invalidLegacyFallback(generationID: "roadster-1"))
    }

    func testRejectsAssetWithUnknownGenerationReference() {
        var value = fixture()
        var assets = value["assets"] as! [[String: Any]]
        assets[assets.count - 1]["generationID"] = "missing-generation"
        value["assets"] = assets

        assertValidationFailure(value, expected: .invalidAssetReference(assetID: "additional-roadster-asset"))
    }

    func testRejectsAssetWithUnknownTrimReference() {
        var value = fixture()
        var assets = value["assets"] as! [[String: Any]]
        assets[assets.count - 1]["trimID"] = "missing-trim"
        value["assets"] = assets

        assertValidationFailure(value, expected: .invalidAssetReference(assetID: "additional-roadster-asset"))
    }

    func testRejectsAssetWithUnknownWheelReference() {
        var value = fixture()
        var assets = value["assets"] as! [[String: Any]]
        assets[assets.count - 1]["wheelID"] = "missing-wheel"
        value["assets"] = assets

        assertValidationFailure(value, expected: .invalidAssetReference(assetID: "additional-roadster-asset"))
    }

    func testRejectsAssetWithUnknownColorReference() {
        var value = fixture()
        var assets = value["assets"] as! [[String: Any]]
        assets[assets.count - 1]["colorID"] = "missing-color"
        value["assets"] = assets

        assertValidationFailure(value, expected: .invalidAssetReference(assetID: "additional-roadster-asset"))
    }

    func testBundledProviderLoadsTheCatalogFromTheAppBundle() throws {
        let provider = BundledVehicleImageCatalogProvider(bundle: .main)

        let first = try provider.catalog()
        let second = try provider.catalog()

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.schemaVersion, VehicleImageCatalog.currentSchemaVersion)
        XCTAssertEqual(first.generations.count, firstPhaseGenerationIDs.count)
        XCTAssertEqual(Set(first.generations.map(\.id)), firstPhaseGenerationIDs)
        XCTAssertEqual(first.assets.filter { $0.reviewStatus == .legacy }.count, firstPhaseGenerationIDs.count)
        XCTAssertEqual(
            first.assets.first { $0.id == "model-3-refresh-performance-midnight-silver-uberturbine-20" },
            VehicleAssetRecord(
                id: "model-3-refresh-performance-midnight-silver-uberturbine-20",
                generationID: "model-3-refresh-performance",
                trimID: "performance",
                wheelID: "uberturbine-20",
                colorID: "midnight-silver",
                path: "CarImages/vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20.png",
                reviewStatus: .reviewed
            )
        )
    }

    func testBundledEarlyModel3CatalogDefinesReviewedAssetAndAliasBoundaries() throws {
        let catalog = try BundledVehicleImageCatalogProvider(bundle: .main).catalog()
        let generation = try XCTUnwrap(catalog.generations.first { $0.id == "model-3-early" })

        XCTAssertEqual(generation.yearStart, 2017)
        XCTAssertEqual(generation.yearEnd, 2020)
        XCTAssertEqual(generation.trims.first { $0.id == "base" }?.aliases, ["rwd", "long range", "performance"])
        XCTAssertEqual(generation.wheels.first { $0.id == "aero-18" }?.aliases, ["W38B", "aero18", "pinwheel18"])
        XCTAssertEqual(generation.colors.first { $0.id == "pearl-white" }?.aliases, ["PPSW", "pearlwhite"])
        XCTAssertEqual(
            catalog.assets.first { $0.id == "model-3-early-base-pearl-white-aero-18" },
            VehicleAssetRecord(
                id: "model-3-early-base-pearl-white-aero-18",
                generationID: "model-3-early",
                trimID: "base",
                wheelID: "aero-18",
                colorID: "pearl-white",
                path: "CarImages/vehicle_model-3-early_base_pearl-white_aero-18.png",
                reviewStatus: .reviewed
            )
        )
    }

    private func decode(_ value: [String: Any]) throws -> VehicleImageCatalog {
        try VehicleImageCatalog.decode(
            from: JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            bundledAssetPaths: expectedAssetPaths
        )
    }

    private func assertValidationFailure(
        _ value: [String: Any],
        expected: VehicleImageCatalogValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try decode(value), file: file, line: line) { error in
            XCTAssertEqual(error as? VehicleImageCatalogValidationError, expected, file: file, line: line)
        }
    }

    private var expectedAssetPaths: Set<String> {
        Set((fixture()["assets"] as! [[String: Any]]).compactMap { $0["path"] as? String })
    }

    private var firstPhaseGenerationIDs: Set<String> {
        [
            "roadster-1", "model-s-nosecone", "model-s-facelift", "model-s-refresh", "model-s-plaid",
            "model-x-legacy", "model-x-refresh", "model-x-plaid", "model-3-early", "model-3-refresh",
            "model-3-refresh-performance", "model-3-highland", "model-3-highland-performance", "model-y-legacy",
            "model-y-legacy-performance", "model-y-juniper-standard", "model-y-juniper-premium",
            "model-y-juniper-performance", "cybertruck-awd", "cybertruck-cyberbeast"
        ]
    }

    private func fixture() -> [String: Any] {
        let generations: [(String, String, Int, Int?, String)] = [
            ("roadster-1", "Roadster", 2008, 2012, "m3_PPSW_W38B.png"),
            ("model-s-nosecone", "Model S", 2012, 2015, "ms_PPSW_WT19.png"),
            ("model-s-facelift", "Model S", 2016, 2020, "ms_PPSW_WT19.png"),
            ("model-s-refresh", "Model S", 2021, nil, "ms_PPSW_WT19.png"),
            ("model-s-plaid", "Model S", 2021, nil, "ms_PPSW_WT19.png"),
            ("model-x-legacy", "Model X", 2015, 2020, "mx_PPSW_WT20.png"),
            ("model-x-refresh", "Model X", 2021, nil, "mx_PPSW_WT20.png"),
            ("model-x-plaid", "Model X", 2021, nil, "mx_PPSW_WT22.png"),
            ("model-3-early", "Model 3", 2017, 2020, "m3_PPSW_W38B.png"),
            ("model-3-refresh", "Model 3", 2021, 2023, "m3_PPSW_W38B.png"),
            ("model-3-refresh-performance", "Model 3", 2021, 2023, "m3_PPSW_W32D.png"),
            ("model-3-highland", "Model 3", 2024, nil, "m3h_PPSW_W38A.png"),
            ("model-3-highland-performance", "Model 3", 2024, nil, "m3hp_PPSW_W30P.png"),
            ("model-y-legacy", "Model Y", 2020, 2024, "my_PPSW_WY19B.png"),
            ("model-y-legacy-performance", "Model Y", 2020, 2024, "my_PPSW_WY20P.png"),
            ("model-y-juniper-standard", "Model Y", 2025, nil, "myjs_PPSW_WY18P.png"),
            ("model-y-juniper-premium", "Model Y", 2025, nil, "myj_PPSW_WY19P.png"),
            ("model-y-juniper-performance", "Model Y", 2025, nil, "myjp_PPSW_WY21A.png"),
            ("cybertruck-awd", "Cybertruck", 2023, nil, "my_PPSW_WY19B.png"),
            ("cybertruck-cyberbeast", "Cybertruck", 2023, nil, "my_PPSW_WY20P.png")
        ]

        return [
            "schemaVersion": 1,
            "generations": generations.enumerated().map { index, generation in
                var value: [String: Any] = [
                    "id": generation.0,
                    "model": generation.1,
                    "aliases": [generation.1.replacingOccurrences(of: " ", with: "").lowercased()],
                    "yearStart": generation.2,
                    "matcherPriority": (index + 1) * 10,
                    "localizationKey": "vehicle.generation.\(generation.0)",
                    "trims": [[
                        "id": "default",
                        "aliases": ["default"],
                        "localizationKey": "vehicle.trim.default"
                    ]],
                    "wheels": [[
                        "id": "default-wheel",
                        "aliases": ["default-wheel"],
                        "localizationKey": "vehicle.wheel.default"
                    ]],
                    "colors": [[
                        "id": "default-color",
                        "aliases": ["default-color"],
                        "localizationKey": "vehicle.color.default"
                    ]],
                    "defaultTrimID": "default",
                    "defaultWheelID": "default-wheel",
                    "defaultColorID": "default-color",
                    "legacyFallback": [
                        "assetID": "legacy-\(generation.0)",
                        "path": "CarImages/\(generation.4)"
                    ]
                ]
                if let yearEnd = generation.3 {
                    value["yearEnd"] = yearEnd
                }
                return value
            },
            "assets": generations.map { generation in
                [
                    "id": "legacy-\(generation.0)",
                    "generationID": generation.0,
                    "trimID": "default",
                    "wheelID": "default-wheel",
                    "colorID": "default-color",
                    "path": "CarImages/\(generation.4)",
                    "reviewStatus": "legacy"
                ]
            } + [[
                "id": "additional-roadster-asset",
                "generationID": "roadster-1",
                "trimID": "default",
                "wheelID": "default-wheel",
                "colorID": "default-color",
                "path": "CarImages/m3_PPSW_W38B.png",
                "reviewStatus": "legacy"
            ]]
        ]
    }
}
