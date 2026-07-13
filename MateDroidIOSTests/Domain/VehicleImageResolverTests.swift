import Foundation
import XCTest
@testable import MateDroidIOS

final class VehicleImageResolverTests: XCTestCase {
    func testExactReviewedAssetUsesOrderedCanonicalEvidence() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed, includeMidnightAsset: true))

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "model3",
                modelYear: 2022,
                trimBadging: "P74D",
                wheelType: "Uberturbine20",
                exteriorColor: "MidnightSilver",
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.generationID, "model-3-refresh-performance")
        XCTAssertEqual(resolution.assetID, "reviewed-midnight")
        XCTAssertEqual(resolution.trimID, "performance")
        XCTAssertEqual(resolution.colorID, "midnight-silver")
        XCTAssertEqual(resolution.wheelID, "uberturbine-20")
        XCTAssertEqual(resolution.assetPath, "CarImages/reviewed-midnight.png")
        XCTAssertEqual(resolution.confidence, .exact)
        XCTAssertEqual(resolution.evidence, [.model, .year, .explicitTrim, .generationSpecificWheel, .color])
        XCTAssertEqual(resolution.conflicts, [])
        XCTAssertFalse(resolution.usesLegacyAsset)
    }

    func testMissingExactAssetKeepsGenerationAndTrimThenUsesReviewedDefaults() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed))

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "3",
                modelYear: 2022,
                trimBadging: "P74D",
                wheelType: "Uberturbine20",
                exteriorColor: "MidnightSilver",
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.generationID, "model-3-refresh-performance")
        XCTAssertEqual(resolution.trimID, "performance")
        XCTAssertEqual(resolution.colorID, "pearl-white")
        XCTAssertEqual(resolution.wheelID, "uberturbine-20")
        XCTAssertEqual(resolution.assetPath, "CarImages/reviewed-default.png")
        XCTAssertEqual(resolution.confidence, .inferred)
        XCTAssertEqual(resolution.evidence, [.model, .year, .explicitTrim, .generationSpecificWheel, .color, .default])
        XCTAssertFalse(resolution.usesLegacyAsset)
    }

    func testMissingConfigurationFieldsUseCatalogDefaultsAsInference() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed))

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "3",
                modelYear: 2022,
                trimBadging: nil,
                wheelType: nil,
                exteriorColor: nil,
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.trimID, "performance")
        XCTAssertEqual(resolution.colorID, "pearl-white")
        XCTAssertEqual(resolution.wheelID, "uberturbine-20")
        XCTAssertEqual(resolution.confidence, .inferred)
        XCTAssertEqual(resolution.evidence, [.model, .year, .default])
    }

    func testLegacyGenerationAssetReportsFallback() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .legacy))

        let resolution = resolver.resolve(descriptor())

        XCTAssertEqual(resolution.assetPath, "CarImages/legacy-default.png")
        XCTAssertEqual(resolution.confidence, .fallback)
        XCTAssertEqual(resolution.evidence.last, .default)
        XCTAssertTrue(resolution.usesLegacyAsset)
    }

    func testValidManualOverrideWinsAndUsesOverrideEvidenceFirst() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed, includeMidnightAsset: true))
        let override = VehicleImageManualOverride(
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "midnight-silver",
            wheelID: "uberturbine-20",
            assetID: "reviewed-midnight"
        )

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "unknown raw model",
                modelYear: nil,
                trimBadging: nil,
                wheelType: nil,
                exteriorColor: nil,
                spoilerType: nil
            ),
            manualOverride: override
        )

        XCTAssertEqual(resolution.assetPath, "CarImages/reviewed-midnight.png")
        XCTAssertEqual(resolution.confidence, .manual)
        XCTAssertEqual(resolution.evidence, [.override])
        XCTAssertEqual(resolution.conflicts, [])
    }

    func testInvalidManualOverrideIsIgnoredAndReportedWithoutBreakingAutomaticMatch() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed))
        let override = VehicleImageManualOverride(
            generationID: "removed-generation",
            trimID: "performance",
            colorID: "pearl-white",
            wheelID: "uberturbine-20",
            assetID: "removed-asset"
        )

        let resolution = resolver.resolve(descriptor(), manualOverride: override)

        XCTAssertEqual(resolution.generationID, "model-3-refresh-performance")
        XCTAssertEqual(resolution.confidence, .exact)
        XCTAssertEqual(resolution.conflicts, [.invalidManualOverride])
        XCTAssertFalse(resolution.evidence.contains(.override))
    }

    @MainActor
    func testBundledSynthetic2022PerformanceUsesReviewedMidnightSilverAsset() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "model3",
                modelYear: 2022,
                trimBadging: "P74D",
                wheelType: "Uberturbine20",
                exteriorColor: "MidnightSilver",
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.generationID, "model-3-refresh-performance")
        XCTAssertEqual(resolution.assetID, "model-3-refresh-performance-midnight-silver-uberturbine-20")
        XCTAssertEqual(resolution.trimID, "performance")
        XCTAssertEqual(resolution.colorID, "midnight-silver")
        XCTAssertEqual(resolution.wheelID, "uberturbine-20")
        XCTAssertEqual(
            resolution.assetPath,
            "CarImages/vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20.png"
        )
        XCTAssertEqual(resolution.confidence, .exact)
        XCTAssertEqual(resolution.evidence, [.model, .year, .explicitTrim, .generationSpecificWheel, .color])
        XCTAssertEqual(resolution.conflicts, [])
        XCTAssertFalse(resolution.usesLegacyAsset)
    }

    @MainActor
    func testReported2022PerformanceConflictUsesReviewedFactoryWheelAndLeaksNoRawEvidence() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())
        let rawValues = ["P74D", "Pinwheel18CapKit", "MidnightSilver"]

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "3",
                modelYear: 2022,
                trimBadging: rawValues[0],
                wheelType: rawValues[1],
                exteriorColor: rawValues[2],
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.generationID, "model-3-refresh-performance")
        XCTAssertEqual(resolution.assetID, "model-3-refresh-performance-midnight-silver-uberturbine-20")
        XCTAssertEqual(resolution.trimID, "performance")
        XCTAssertEqual(resolution.colorID, "midnight-silver")
        XCTAssertEqual(resolution.wheelID, "uberturbine-20")
        XCTAssertEqual(
            resolution.assetPath,
            "CarImages/vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20.png"
        )
        XCTAssertEqual(resolution.conflicts, [.reportedWheelContradictsFactoryTrim])
        XCTAssertEqual(resolution.confidence, .inferred)
        XCTAssertFalse(resolution.usesLegacyAsset)
        let evidenceText = resolution.evidence.map(\.description).joined(separator: " ")
        for rawValue in rawValues {
            XCTAssertFalse(evidenceText.localizedCaseInsensitiveContains(rawValue))
        }
    }

    @MainActor
    func testBundledPearlWhitePerformancePreservesLegacyFallback() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())

        let resolution = resolver.resolve(descriptor())

        XCTAssertEqual(resolution.assetID, "legacy-model-3-refresh-performance")
        XCTAssertEqual(resolution.colorID, "pearl-white")
        XCTAssertEqual(resolution.assetPath, "CarImages/m3_PPSW_W32D.png")
        XCTAssertEqual(resolution.confidence, .fallback)
        XCTAssertEqual(resolution.conflicts, [])
        XCTAssertTrue(resolution.usesLegacyAsset)
    }

    @MainActor
    func testBundledEarlyModel3AliasesAndContradictoryWheelResolveExpectedReviewedAsset() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())
        let cases: [(year: Int, trim: String, wheel: String, color: String, confidence: VehicleImageConfidence, evidence: [VehicleImageEvidence], conflicts: [VehicleImageConflict])] = [
            (2017, "rwd", "W38B", "PPSW", .exact, [.model, .year, .explicitTrim, .generationSpecificWheel, .color], []),
            (2017, "long range", "aero18", "pearlwhite", .exact, [.model, .year, .explicitTrim, .generationSpecificWheel, .color], []),
            (2020, "performance", "pinwheel18", "PPSW", .exact, [.model, .year, .explicitTrim, .generationSpecificWheel, .color], []),
            (2020, "performance", "W32D", "PPSW", .inferred, [.model, .year, .explicitTrim, .color, .default], [.reportedWheelContradictsFactoryTrim])
        ]

        for testCase in cases {
            let resolution = resolver.resolve(
                VehicleImageDescriptor(
                    model: "Model 3",
                    modelYear: testCase.year,
                    trimBadging: testCase.trim,
                    wheelType: testCase.wheel,
                    exteriorColor: testCase.color,
                    spoilerType: nil
                )
            )

            XCTAssertEqual(resolution.generationID, "model-3-early", "year \(testCase.year)")
            XCTAssertEqual(resolution.assetID, "model-3-early-base-pearl-white-aero-18", "year \(testCase.year)")
            XCTAssertEqual(resolution.trimID, "base", "trim \(testCase.trim)")
            XCTAssertEqual(resolution.wheelID, "aero-18", "wheel \(testCase.wheel)")
            XCTAssertEqual(resolution.colorID, "pearl-white", "color \(testCase.color)")
            XCTAssertEqual(
                resolution.assetPath,
                "CarImages/vehicle_model-3-early_base_pearl-white_aero-18.png",
                "year \(testCase.year)"
            )
            XCTAssertEqual(resolution.confidence, testCase.confidence, "wheel \(testCase.wheel)")
            XCTAssertEqual(resolution.evidence, testCase.evidence, "wheel \(testCase.wheel)")
            XCTAssertEqual(resolution.conflicts, testCase.conflicts, "wheel \(testCase.wheel)")
            XCTAssertFalse(resolution.usesLegacyAsset, "year \(testCase.year)")
            XCTAssertFalse(resolution.evidence.map(\.description).joined().contains(testCase.wheel))
        }
    }

    @MainActor
    func testBundledModel3GenerationBoundarySelectsReviewedAssets() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())
        let cases = [
            (year: 2020, generationID: "model-3-early", assetID: "model-3-early-base-pearl-white-aero-18"),
            (year: 2021, generationID: "model-3-refresh", assetID: "model-3-refresh-base-pearl-white-aero-18")
        ]

        for testCase in cases {
            let resolution = resolver.resolve(
                VehicleImageDescriptor(
                    model: "model3",
                    modelYear: testCase.year,
                    trimBadging: "rwd",
                    wheelType: "W38B",
                    exteriorColor: "PPSW",
                    spoilerType: nil
                )
            )

            XCTAssertEqual(resolution.generationID, testCase.generationID, "year \(testCase.year)")
            XCTAssertEqual(resolution.assetID, testCase.assetID, "year \(testCase.year)")
            XCTAssertEqual(resolution.confidence, .exact, "year \(testCase.year)")
            XCTAssertFalse(resolution.usesLegacyAsset, "year \(testCase.year)")
        }
    }

    @MainActor
    func testBundledHighlandPerformancePearlWhitePreservesLegacyFallback() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "Model 3",
                modelYear: 2024,
                trimBadging: "P74D",
                wheelType: "W30P",
                exteriorColor: "PPSW",
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.generationID, "model-3-highland-performance")
        XCTAssertEqual(resolution.assetID, "legacy-model-3-highland-performance")
        XCTAssertEqual(resolution.trimID, "performance")
        XCTAssertEqual(resolution.colorID, "pearl-white")
        XCTAssertEqual(resolution.wheelID, "performance-20")
        XCTAssertEqual(resolution.assetPath, "CarImages/m3hp_PPSW_W30P.png")
        XCTAssertEqual(resolution.confidence, .fallback)
        XCTAssertEqual(resolution.conflicts, [])
        XCTAssertTrue(resolution.usesLegacyAsset)
    }

    @MainActor
    func testBundledRemainingModel3GenerationAliasesBoundariesAndContradictoryWheels() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())
        let reviewedRefreshID = "model-3-refresh-base-pearl-white-aero-18"
        let reviewedRefreshPath = "CarImages/vehicle_model-3-refresh_base_pearl-white_aero-18.png"
        let reviewedHighlandID = "model-3-highland-base-pearl-white-photon-18"
        let reviewedHighlandPath = "CarImages/vehicle_model-3-highland_base_pearl-white_photon-18.png"
        let reviewedHighlandPerformanceID = "model-3-highland-performance-performance-stealth-grey-performance-20"
        let reviewedHighlandPerformancePath = "CarImages/vehicle_model-3-highland-performance_performance_stealth-grey_performance-20.png"
        let cases: [(
            label: String,
            year: Int,
            trim: String,
            wheel: String,
            color: String,
            generationID: String,
            trimID: String,
            wheelID: String,
            colorID: String,
            assetID: String,
            assetPath: String,
            confidence: VehicleImageConfidence,
            conflicts: [VehicleImageConflict],
            usesLegacyAsset: Bool
        )] = [
            ("refresh lower bound and canonical aliases", 2021, "rwd", "W38B", "PPSW", "model-3-refresh", "base", "aero-18", "pearl-white", reviewedRefreshID, reviewedRefreshPath, .exact, [], false),
            ("refresh upper bound and normalized aliases", 2023, "long range", "aero18", "pearlwhite", "model-3-refresh", "base", "aero-18", "pearl-white", reviewedRefreshID, reviewedRefreshPath, .exact, [], false),
            ("refresh rejects Highland wheel evidence", 2023, "rwd", "W38A", "PPSW", "model-3-refresh", "base", "aero-18", "pearl-white", reviewedRefreshID, reviewedRefreshPath, .inferred, [.reportedWheelContradictsFactoryTrim], false),
            ("Highland lower bound and canonical aliases", 2024, "rwd", "W38A", "PPSW", "model-3-highland", "base", "photon-18", "pearl-white", reviewedHighlandID, reviewedHighlandPath, .exact, [], false),
            ("Highland open upper bound and normalized aliases", 2026, "long range", "photon18", "pearlwhite", "model-3-highland", "base", "photon-18", "pearl-white", reviewedHighlandID, reviewedHighlandPath, .exact, [], false),
            ("Highland rejects refresh wheel evidence", 2024, "rwd", "W38B", "PPSW", "model-3-highland", "base", "photon-18", "pearl-white", reviewedHighlandID, reviewedHighlandPath, .inferred, [.reportedWheelContradictsFactoryTrim], false),
            ("Highland Performance lower bound and telemetry aliases", 2024, "P74D", "W30P", "PN01", "model-3-highland-performance", "performance", "performance-20", "stealth-grey", reviewedHighlandPerformanceID, reviewedHighlandPerformancePath, .exact, [], false),
            ("Highland Performance open upper bound and normalized aliases", 2026, "performance", "performance20", "StealthGrey", "model-3-highland-performance", "performance", "performance-20", "stealth-grey", reviewedHighlandPerformanceID, reviewedHighlandPerformancePath, .exact, [], false),
            ("Highland Performance rejects refresh wheel evidence", 2024, "performance", "W32D", "PN01", "model-3-highland-performance", "performance", "performance-20", "stealth-grey", reviewedHighlandPerformanceID, reviewedHighlandPerformancePath, .inferred, [.reportedWheelContradictsFactoryTrim], false)
        ]

        for testCase in cases {
            let resolution = resolver.resolve(
                VehicleImageDescriptor(
                    model: "Model 3",
                    modelYear: testCase.year,
                    trimBadging: testCase.trim,
                    wheelType: testCase.wheel,
                    exteriorColor: testCase.color,
                    spoilerType: nil
                )
            )

            XCTAssertEqual(resolution.generationID, testCase.generationID, testCase.label)
            XCTAssertEqual(resolution.trimID, testCase.trimID, testCase.label)
            XCTAssertEqual(resolution.wheelID, testCase.wheelID, testCase.label)
            XCTAssertEqual(resolution.colorID, testCase.colorID, testCase.label)
            XCTAssertEqual(resolution.assetID, testCase.assetID, testCase.label)
            XCTAssertEqual(resolution.assetPath, testCase.assetPath, testCase.label)
            XCTAssertEqual(resolution.confidence, testCase.confidence, testCase.label)
            XCTAssertEqual(resolution.conflicts, testCase.conflicts, testCase.label)
            XCTAssertEqual(resolution.usesLegacyAsset, testCase.usesLegacyAsset, testCase.label)
            XCTAssertFalse(
                resolution.evidence.map(\.description).joined().localizedCaseInsensitiveContains(testCase.wheel),
                testCase.label
            )
        }
    }

    @MainActor
    func testBundledModel3GenerationTransitionsSelectExpectedCatalogAsset() throws {
        let resolver = VehicleImageResolver(catalog: try BundledVehicleImageCatalogProvider(bundle: .main).catalog())
        let cases = [
            (year: 2020, trim: "rwd", wheel: "W38B", color: "PPSW", generationID: "model-3-early", assetID: "model-3-early-base-pearl-white-aero-18"),
            (year: 2021, trim: "rwd", wheel: "W38B", color: "PPSW", generationID: "model-3-refresh", assetID: "model-3-refresh-base-pearl-white-aero-18"),
            (year: 2023, trim: "long range", wheel: "aero18", color: "pearlwhite", generationID: "model-3-refresh", assetID: "model-3-refresh-base-pearl-white-aero-18"),
            (year: 2024, trim: "long range", wheel: "photon18", color: "pearlwhite", generationID: "model-3-highland", assetID: "model-3-highland-base-pearl-white-photon-18")
        ]

        for testCase in cases {
            let resolution = resolver.resolve(
                VehicleImageDescriptor(
                    model: "model3",
                    modelYear: testCase.year,
                    trimBadging: testCase.trim,
                    wheelType: testCase.wheel,
                    exteriorColor: testCase.color,
                    spoilerType: nil
                )
            )

            XCTAssertEqual(resolution.generationID, testCase.generationID, "year \(testCase.year)")
            XCTAssertEqual(resolution.assetID, testCase.assetID, "year \(testCase.year)")
        }
    }

    func testMissingYearCanBeInferredFromGenerationSpecificWheel() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed, includeEarlyGeneration: true))

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "Model 3",
                modelYear: nil,
                trimBadging: "performance",
                wheelType: "W32D",
                exteriorColor: "PPSW",
                spoilerType: nil
            )
        )

        XCTAssertEqual(resolution.generationID, "model-3-refresh-performance")
        XCTAssertEqual(resolution.confidence, .inferred)
        XCTAssertEqual(resolution.conflicts, [.modelYearUnavailable])
        XCTAssertEqual(resolution.evidence, [.model, .explicitTrim, .generationSpecificWheel, .color])
    }

    func testUnknownModelUsesGenericPlaceholderWithoutPretendingToBeModel3() {
        let resolver = VehicleImageResolver(catalog: catalog(reviewStatus: .reviewed))

        let resolution = resolver.resolve(
            VehicleImageDescriptor(
                model: "not-a-catalog-model",
                modelYear: 2022,
                trimBadging: "P74D",
                wheelType: "Uberturbine20",
                exteriorColor: "MidnightSilver",
                spoilerType: nil
            )
        )

        XCTAssertNil(resolution.generationID)
        XCTAssertNil(resolution.trimID)
        XCTAssertNil(resolution.colorID)
        XCTAssertNil(resolution.wheelID)
        XCTAssertNil(resolution.assetID)
        XCTAssertEqual(resolution.assetPath, VehicleImageResolver.genericPlaceholderPath)
        XCTAssertEqual(resolution.confidence, .fallback)
        XCTAssertEqual(resolution.evidence, [])
        XCTAssertEqual(resolution.conflicts, [.unknownModel])
        XCTAssertFalse(resolution.usesLegacyAsset)
    }

    func testVINModelYearDecoderReturnsOnlyUniqueSyntheticModelYear() {
        XCTAssertEqual(
            VINModelYearDecoder.modelYear(from: "TSTMODEL3N0000000", validYears: 2017...2025),
            2022
        )
        XCTAssertEqual(
            VINModelYearDecoder.modelYear(from: "tstmodel3n0000000", validYears: 2017...2025),
            2022
        )
        XCTAssertEqual(
            VINModelYearDecoder.modelYear(from: "TSTMODEL3N0000000", validYears: 1990...2030),
            nil,
            "N repeats for 1992 and 2022 and must not be guessed"
        )
        XCTAssertNil(VINModelYearDecoder.modelYear(from: "TSTMODEL3I0000000", validYears: 2017...2025))
        XCTAssertNil(VINModelYearDecoder.modelYear(from: "TOO-SHORT", validYears: 2017...2025))
    }

    func testVINModelYearDecoderRejectsUnicodeBeforeIndexingUppercaseValue() {
        let malformedVIN = "և123456NAX1234567"

        XCTAssertEqual(malformedVIN.count, 17)
        XCTAssertNil(VINModelYearDecoder.modelYear(from: malformedVIN, validYears: 2017...2025))
    }

    func testVINModelYearDecoderRejectsLigaturesBeforeUppercaseExpansion() {
        let expandsToSeventeenASCIICharacters = "ﬃ123456N1234567"
        let seventeenRawCharacters = "ﬃ12345678N1234567"

        XCTAssertEqual(expandsToSeventeenASCIICharacters.uppercased().count, 17)
        XCTAssertEqual(seventeenRawCharacters.count, 17)
        XCTAssertNil(VINModelYearDecoder.modelYear(from: expandsToSeventeenASCIICharacters, validYears: 2017...2025))
        XCTAssertNil(VINModelYearDecoder.modelYear(from: seventeenRawCharacters, validYears: 2017...2025))
    }

    private func descriptor() -> VehicleImageDescriptor {
        VehicleImageDescriptor(
            model: "3",
            modelYear: 2022,
            trimBadging: "P74D",
            wheelType: "Uberturbine20",
            exteriorColor: "PPSW",
            spoilerType: nil
        )
    }

    private func catalog(
        reviewStatus: VehicleImageReviewStatus,
        includeMidnightAsset: Bool = false,
        includeEarlyGeneration: Bool = false
    ) -> VehicleImageCatalog {
        let performance = VehicleGenerationRecord(
            id: "model-3-refresh-performance",
            model: "Model 3",
            aliases: ["model 3", "model3", "3"],
            yearStart: 2021,
            yearEnd: 2023,
            matcherPriority: 30,
            localizationKey: "vehicle.generation.model-3-refresh-performance",
            trims: [VehicleTrimRecord(id: "performance", aliases: ["performance", "P74D"], localizationKey: "vehicle.trim.performance")],
            wheels: [VehicleWheelRecord(id: "uberturbine-20", aliases: ["W32D", "uberturbine20"], localizationKey: "vehicle.wheel.uberturbine-20")],
            colors: [
                VehicleColorRecord(id: "pearl-white", aliases: ["PPSW", "pearlwhite"], localizationKey: "vehicle.color.pearl-white"),
                VehicleColorRecord(id: "midnight-silver", aliases: ["PMNG", "midnightsilver"], localizationKey: "vehicle.color.midnight-silver")
            ],
            defaultTrimID: "performance",
            defaultWheelID: "uberturbine-20",
            defaultColorID: "pearl-white",
            legacyFallback: VehicleLegacyFallbackRecord(assetID: "reviewed-default", path: reviewStatus == .legacy ? "CarImages/legacy-default.png" : "CarImages/reviewed-default.png")
        )
        let defaultAsset = VehicleAssetRecord(
            id: "reviewed-default",
            generationID: performance.id,
            trimID: "performance",
            wheelID: "uberturbine-20",
            colorID: "pearl-white",
            path: reviewStatus == .legacy ? "CarImages/legacy-default.png" : "CarImages/reviewed-default.png",
            reviewStatus: reviewStatus
        )
        let midnightAsset = VehicleAssetRecord(
            id: "reviewed-midnight",
            generationID: performance.id,
            trimID: "performance",
            wheelID: "uberturbine-20",
            colorID: "midnight-silver",
            path: "CarImages/reviewed-midnight.png",
            reviewStatus: .reviewed
        )
        let early = VehicleGenerationRecord(
            id: "model-3-early",
            model: "Model 3",
            aliases: ["model 3", "model3", "3"],
            yearStart: 2017,
            yearEnd: 2020,
            matcherPriority: 10,
            localizationKey: "vehicle.generation.model-3-early",
            trims: [VehicleTrimRecord(id: "base", aliases: ["rwd"], localizationKey: "vehicle.trim.base")],
            wheels: [VehicleWheelRecord(id: "aero-18", aliases: ["W38B", "pinwheel18"], localizationKey: "vehicle.wheel.aero-18")],
            colors: [VehicleColorRecord(id: "pearl-white", aliases: ["PPSW"], localizationKey: "vehicle.color.pearl-white")],
            defaultTrimID: "base",
            defaultWheelID: "aero-18",
            defaultColorID: "pearl-white",
            legacyFallback: VehicleLegacyFallbackRecord(assetID: "early-default", path: "CarImages/early-default.png")
        )
        let earlyAsset = VehicleAssetRecord(
            id: "early-default",
            generationID: early.id,
            trimID: "base",
            wheelID: "aero-18",
            colorID: "pearl-white",
            path: "CarImages/early-default.png",
            reviewStatus: .reviewed
        )

        return VehicleImageCatalog(
            schemaVersion: VehicleImageCatalog.currentSchemaVersion,
            generations: includeEarlyGeneration ? [early, performance] : [performance],
            assets: (includeEarlyGeneration ? [earlyAsset] : []) + [defaultAsset] + (includeMidnightAsset ? [midnightAsset] : [])
        )
    }
}
