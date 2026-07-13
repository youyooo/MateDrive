import XCTest
@testable import MateDroidIOS

@MainActor
final class CarImagePickerViewModelTests: XCTestCase {
    func testCatalogNamesAreLocalizedInEnglishSimplifiedAndTraditionalChinese() {
        let catalog = makeCatalog()
        let resolution = automaticResolution()

        let english = makeViewModel(catalog: catalog, resolution: resolution, language: .english)
        let simplified = makeViewModel(catalog: catalog, resolution: resolution, language: .chinese)
        let traditional = makeViewModel(catalog: catalog, resolution: resolution, language: .traditionalChinese)

        XCTAssertEqual(english.selectedGenerationName, "Model 3 Refresh Performance")
        XCTAssertEqual(english.trimOptions.map(\.name), ["Performance"])
        XCTAssertEqual(english.wheelOptions.map(\.name), ["20-inch Überturbine Wheels", "19-inch Crossflow Wheels"])
        XCTAssertEqual(simplified.selectedGenerationName, "Model 3 焕新版 Performance")
        XCTAssertEqual(simplified.trimOptions.map(\.name), ["高性能版"])
        XCTAssertEqual(simplified.wheelOptions.map(\.name), ["20 英寸 Überturbine 轮毂", "19 英寸 Crossflow 轮毂"])
        XCTAssertEqual(traditional.selectedGenerationName, "Model 3 煥新版 Performance")
        XCTAssertEqual(traditional.trimOptions.map(\.name), ["高性能版"])
        XCTAssertEqual(traditional.wheelOptions.map(\.name), ["20 吋 Überturbine 輪圈", "19 吋 Crossflow 輪圈"])
    }

    func testOptionsOnlyExposeConfigurationsBackedByCatalogAssets() {
        let viewModel = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution())

        XCTAssertEqual(viewModel.trimOptions.map(\.id), ["performance"])
        XCTAssertEqual(viewModel.colorOptions.map(\.id), ["pearl-white", "deep-blue"])
        XCTAssertEqual(viewModel.wheelOptions.map(\.id), ["uberturbine-20", "crossflow-19"])

        viewModel.selectColor(id: "deep-blue")

        XCTAssertEqual(viewModel.wheelOptions.map(\.id), ["crossflow-19"])
        XCTAssertEqual(viewModel.selectedWheelID, "crossflow-19")
        XCTAssertEqual(viewModel.selectedAssetPath, "CarImages/blue-crossflow.png")
    }

    func testConfidenceExplanationUsesLocalizedCopy() {
        let english = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution(), language: .english)
        let simplified = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution(), language: .chinese)
        let traditional = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution(), language: .traditionalChinese)

        XCTAssertEqual(english.confidenceName, "Inferred match")
        XCTAssertEqual(english.confidenceExplanation, "Matched from vehicle details with catalog defaults where data was unavailable.")
        XCTAssertEqual(simplified.confidenceName, "推断匹配")
        XCTAssertEqual(simplified.confidenceExplanation, "根据车辆信息匹配，缺失数据使用目录默认值。")
        XCTAssertEqual(traditional.confidenceName, "推斷配對")
        XCTAssertEqual(traditional.confidenceExplanation, "根據車輛資訊配對，缺少資料時使用目錄預設值。")
    }

    func testConflictExplanationIsLocalizedAndDoesNotExposeRawTelemetry() {
        let rawWheel = "Pinwheel18CapKit"
        let resolution = VehicleImageResolution(
            assetID: "white-uberturbine",
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "pearl-white",
            wheelID: "uberturbine-20",
            assetPath: "CarImages/white-uberturbine.png",
            presentationScale: 1,
            confidence: .inferred,
            evidence: [.model, .explicitTrim, .default],
            conflicts: [.reportedWheelContradictsFactoryTrim],
            usesLegacyAsset: false
        )

        let viewModel = makeViewModel(catalog: makeCatalog(), resolution: resolution, language: .english)

        XCTAssertEqual(viewModel.detectedConflictExplanation, "The reported wheels conflict with the detected factory trim. Choose the configuration that matches your vehicle.")
        XCTAssertFalse(viewModel.detectedConflictExplanation?.contains(rawWheel) == true)
    }

    func testValidOverrideKeepsAutomaticDetectionSeparateFromEditableSelection() {
        let catalog = makeCatalog(includeModelY: true)
        let override = VehicleImageOverride(
            generationID: "model-y-legacy",
            trimID: "standard",
            colorID: "pearl-white",
            wheelID: "gemini-19",
            assetID: "model-y-white"
        )

        let viewModel = makeViewModel(
            catalog: catalog,
            resolution: automaticResolution(),
            storedOverride: override
        )

        XCTAssertEqual(viewModel.detectedGenerationID, "model-3-refresh-performance")
        XCTAssertEqual(viewModel.detectedGenerationName, "Model 3 Refresh Performance")
        XCTAssertEqual(viewModel.detectedTrimID, "performance")
        XCTAssertEqual(viewModel.detectedTrimName, "Performance")
        XCTAssertEqual(viewModel.detectedConfidenceName, "Inferred match")
        XCTAssertEqual(viewModel.selectedGenerationID, "model-y-legacy")
        XCTAssertEqual(viewModel.selectedTrimID, "standard")

        viewModel.selectGeneration(id: "model-3-refresh-performance")

        XCTAssertEqual(viewModel.detectedGenerationID, "model-3-refresh-performance")
        XCTAssertEqual(viewModel.detectedTrimID, "performance")
        XCTAssertEqual(viewModel.detectedConfidenceName, "Inferred match")
    }

    func testSaveEmitsSelectedOverrideAndRequestsDismissal() async {
        let recorder = SaveRecorder()
        let viewModel = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution()) { override in
            await recorder.record(override)
        }
        viewModel.selectColor(id: "deep-blue")

        await viewModel.save()

        let savedValues = await recorder.snapshot()
        XCTAssertEqual(
            savedValues,
            [VehicleImageOverride(
                generationID: "model-3-refresh-performance",
                trimID: "performance",
                colorID: "deep-blue",
                wheelID: "crossflow-19",
                assetID: "blue-crossflow"
            )]
        )
        XCTAssertTrue(viewModel.shouldDismiss)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testBundledEarlyModel3PickerPrefersReviewedPreviewThumbnailAndSavedAsset() async throws {
        let catalog = try BundledVehicleImageCatalogProvider(bundle: .main).catalog()
        let resolution = VehicleImageResolver(catalog: catalog).resolve(
            VehicleImageDescriptor(
                model: "Model 3",
                modelYear: 2020,
                trimBadging: "rwd",
                wheelType: "W38B",
                exteriorColor: "PPSW",
                spoilerType: nil
            )
        )
        let recorder = SaveRecorder()
        let viewModel = makeViewModel(catalog: catalog, resolution: resolution) { override in
            await recorder.record(override)
        }

        XCTAssertEqual(
            viewModel.selectedAssetPath,
            "CarImages/vehicle_model-3-early_base_pearl-white_aero-18.png"
        )
        XCTAssertEqual(
            viewModel.wheelOptions.first { $0.id == "aero-18" }?.assetPath,
            "CarImages/vehicle_model-3-early_base_pearl-white_aero-18.png"
        )

        await viewModel.save()
        let savedValues = await recorder.snapshot()

        XCTAssertEqual(
            savedValues,
            [VehicleImageOverride(
                generationID: "model-3-early",
                trimID: "base",
                colorID: "pearl-white",
                wheelID: "aero-18",
                assetID: "model-3-early-base-pearl-white-aero-18"
            )]
        )
    }

    func testBundledRemainingModel3PickersPreferReviewedPreviewThumbnailAndSavedAsset() async throws {
        let catalog = try BundledVehicleImageCatalogProvider(bundle: .main).catalog()
        let cases = [
            (
                year: 2021,
                trim: "rwd",
                wheel: "W38B",
                color: "PPSW",
                generationID: "model-3-refresh",
                wheelID: "aero-18",
                assetID: "model-3-refresh-base-pearl-white-aero-18",
                assetPath: "CarImages/vehicle_model-3-refresh_base_pearl-white_aero-18.png"
            ),
            (
                year: 2024,
                trim: "long range",
                wheel: "W38A",
                color: "PPSW",
                generationID: "model-3-highland",
                wheelID: "photon-18",
                assetID: "model-3-highland-base-pearl-white-photon-18",
                assetPath: "CarImages/vehicle_model-3-highland_base_pearl-white_photon-18.png"
            ),
            (
                year: 2024,
                trim: "P74D",
                wheel: "W30P",
                color: "PN01",
                generationID: "model-3-highland-performance",
                wheelID: "performance-20",
                assetID: "model-3-highland-performance-performance-stealth-grey-performance-20",
                assetPath: "CarImages/vehicle_model-3-highland-performance_performance_stealth-grey_performance-20.png"
            )
        ]

        for testCase in cases {
            let resolution = VehicleImageResolver(catalog: catalog).resolve(
                VehicleImageDescriptor(
                    model: "Model 3",
                    modelYear: testCase.year,
                    trimBadging: testCase.trim,
                    wheelType: testCase.wheel,
                    exteriorColor: testCase.color,
                    spoilerType: nil
                )
            )
            let recorder = SaveRecorder()
            let viewModel = makeViewModel(catalog: catalog, resolution: resolution) { override in
                await recorder.record(override)
            }

            XCTAssertEqual(viewModel.selectedAssetPath, testCase.assetPath, "year \(testCase.year)")
            XCTAssertEqual(
                viewModel.wheelOptions.first { $0.id == testCase.wheelID }?.assetPath,
                testCase.assetPath,
                "year \(testCase.year)"
            )

            await viewModel.save()
            let savedValues = await recorder.snapshot()
            XCTAssertEqual(savedValues.count, 1, "year \(testCase.year)")
            XCTAssertEqual(savedValues.first??.generationID, testCase.generationID, "year \(testCase.year)")
            XCTAssertEqual(savedValues.first??.assetID, testCase.assetID, "year \(testCase.year)")
        }
    }

    func testResetToAutomaticClearsOverrideAndRequestsDismissal() async {
        let recorder = SaveRecorder()
        let viewModel = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution()) { override in
            await recorder.record(override)
        }

        await viewModel.resetToAutomatic()

        let savedValues = await recorder.snapshot()
        XCTAssertEqual(savedValues.count, 1)
        XCTAssertNil(savedValues[0])
        XCTAssertTrue(viewModel.shouldDismiss)
    }

    func testInvalidStoredOverrideRecoversToAutomaticSelection() {
        let invalid = VehicleImageOverride(
            generationID: "removed-generation",
            trimID: "removed-trim",
            colorID: "removed-color",
            wheelID: "removed-wheel",
            assetID: "removed-asset"
        )

        let viewModel = makeViewModel(
            catalog: makeCatalog(),
            resolution: automaticResolution(),
            storedOverride: invalid,
            language: .english
        )

        XCTAssertEqual(viewModel.selectedGenerationID, "model-3-refresh-performance")
        XCTAssertEqual(viewModel.selectedTrimID, "performance")
        XCTAssertEqual(viewModel.selectedColorID, "pearl-white")
        XCTAssertEqual(viewModel.selectedWheelID, "uberturbine-20")
        XCTAssertEqual(viewModel.configurationNotice, "The saved configuration is no longer available. Automatic matching has been restored.")
    }

    func testRejectedSaveStaysOpenAndShowsLocalizedActionableError() async {
        let viewModel = makeViewModel(
            catalog: makeCatalog(),
            resolution: automaticResolution(),
            language: .traditionalChinese
        ) { _ in
            throw PickerSubmissionError.rejected
        }

        await viewModel.save()

        XCTAssertFalse(viewModel.shouldDismiss)
        XCTAssertFalse(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.submissionErrorMessage, "無法更新車輛圖片，請再試一次。")
    }

    func testConcurrentSaveAndResetOnlySubmitFirstOperation() async {
        let recorder = SaveRecorder()
        let gate = SubmissionGate()
        let viewModel = makeViewModel(catalog: makeCatalog(), resolution: automaticResolution()) { override in
            await recorder.record(override)
            await gate.suspendUntilReleased()
        }
        let saveTask = Task { await viewModel.save() }
        await gate.waitUntilEntered()

        await viewModel.resetToAutomatic()
        await gate.release()
        await saveTask.value

        let savedValues = await recorder.snapshot()
        XCTAssertEqual(savedValues.count, 1)
        XCTAssertNotNil(savedValues[0])
        XCTAssertTrue(viewModel.shouldDismiss)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testColorLabelsReserveTwoLinesForSpanishAndCatalanNames() {
        XCTAssertEqual(VehicleImagePickerText.localized("vehicle.color.stainless", language: .spanish), "Acero inoxidable")
        XCTAssertEqual(VehicleImagePickerText.localized("vehicle.color.stainless", language: .catalan), "Acer inoxidable")
        XCTAssertEqual(CarImagePickerLayout.colorLabelLineLimit, 2)
        XCTAssertGreaterThanOrEqual(CarImagePickerLayout.colorLabelHeight, 32)
        XCTAssertGreaterThanOrEqual(CarImagePickerLayout.colorOptionWidth, 96)
    }

    func testDashboardSavePersistsReresolvesSnapshotsWidgetsAndResetsToAutomatic() async throws {
        let suiteName = "CarImagePickerDashboard.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let widgetStore = WidgetSnapshotStore(defaults: defaults)
        let snapshotStore = PickerDashboardSnapshotStore()
        let settingsStore = PickerDashboardSettingsStore(
            settings: AppSettings(serverURL: "https://teslamate.example", lastSelectedCarId: 7)
        )
        let catalog = makeCatalog()
        let car = CarData(
            carId: 7,
            carDetails: CarDetails(model: "3", trimBadging: "P74D", vin: "TSTMODEL3N0000000"),
            carExterior: CarExterior(exteriorColor: "PPSW", wheelType: "W32D")
        )
        let dashboard = DashboardViewModel(
            api: PickerDashboardAPI(car: car),
            settingsStore: settingsStore,
            widgetSnapshotStore: widgetStore,
            dashboardSnapshotStore: snapshotStore,
            vehicleImageCatalogProvider: PickerCatalogProvider(catalog: catalog)
        )
        await dashboard.load()
        let override = VehicleImageOverride(
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "deep-blue",
            wheelID: "crossflow-19",
            assetID: "blue-crossflow"
        )

        try await dashboard.setVehicleImageOverride(override)

        XCTAssertEqual(
            settingsStore.settings.vehicleImageOverride(for: URL(string: "https://teslamate.example")!, carID: 7),
            override
        )
        XCTAssertEqual(dashboard.state.vehicleImageResolution?.assetID, "blue-crossflow")
        XCTAssertEqual(dashboard.state.vehicleImageResolution?.confidence, .manual)
        XCTAssertEqual(snapshotStore.saved.last?.vehicleImageAssetID, "blue-crossflow")
        XCTAssertEqual(widgetStore.load()?.vehicleImageAssetID, "blue-crossflow")

        try await dashboard.setVehicleImageOverride(nil)

        XCTAssertNil(settingsStore.settings.vehicleImageOverride(for: URL(string: "https://teslamate.example")!, carID: 7))
        XCTAssertEqual(dashboard.state.vehicleImageResolution?.assetID, "white-uberturbine")
        XCTAssertEqual(dashboard.state.vehicleImageResolution?.confidence, .exact)
        XCTAssertEqual(snapshotStore.saved.last?.vehicleImageAssetID, "white-uberturbine")
        XCTAssertEqual(widgetStore.load()?.vehicleImageAssetID, "white-uberturbine")
    }

    func testDashboardRejectsInvalidOverrideWithTypedFailure() async {
        let dashboard = DashboardViewModel(
            api: PickerDashboardAPI(car: CarData(carId: 7, carDetails: CarDetails(model: "3"))),
            settingsStore: PickerDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            vehicleImageCatalogProvider: PickerCatalogProvider(catalog: makeCatalog())
        )
        await dashboard.load()
        let invalid = VehicleImageOverride(
            generationID: "removed",
            trimID: "removed",
            colorID: "removed",
            wheelID: "removed",
            assetID: "removed"
        )

        do {
            try await dashboard.setVehicleImageOverride(invalid)
            XCTFail("Expected invalid override rejection")
        } catch {
            XCTAssertEqual(error as? DashboardVehicleImageOverrideError, .invalidOverride)
        }
    }

    func testDashboardRejectsSubmissionWhenNoCurrentVehicleIsLoaded() async {
        let dashboard = DashboardViewModel(
            api: PickerDashboardAPI(car: CarData(carId: 7)),
            settingsStore: PickerDashboardSettingsStore(settings: AppSettings(serverURL: "https://teslamate.example")),
            vehicleImageCatalogProvider: PickerCatalogProvider(catalog: makeCatalog())
        )

        do {
            try await dashboard.setVehicleImageOverride(nil)
            XCTFail("Expected missing vehicle rejection")
        } catch {
            XCTAssertEqual(error as? DashboardVehicleImageOverrideError, .currentVehicleUnavailable)
        }
    }

    private func makeViewModel(
        catalog: VehicleImageCatalog,
        resolution: VehicleImageResolution,
        storedOverride: VehicleImageOverride? = nil,
        language: AppLanguage = .english,
        save: @escaping @Sendable (VehicleImageOverride?) async throws -> Void = { _ in }
    ) -> CarImagePickerViewModel {
        CarImagePickerViewModel(
            catalog: catalog,
            automaticResolution: resolution,
            storedOverride: storedOverride,
            language: language,
            saveOverride: save
        )
    }

    private func automaticResolution() -> VehicleImageResolution {
        VehicleImageResolution(
            assetID: "white-uberturbine",
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "pearl-white",
            wheelID: "uberturbine-20",
            assetPath: "CarImages/white-uberturbine.png",
            presentationScale: 1,
            confidence: .inferred,
            evidence: [.model, .year, .explicitTrim, .default],
            conflicts: [],
            usesLegacyAsset: false
        )
    }

    private func makeCatalog(includeModelY: Bool = false) -> VehicleImageCatalog {
        let generation = VehicleGenerationRecord(
            id: "model-3-refresh-performance",
            model: "Model 3",
            aliases: ["3", "model3"],
            yearStart: 2021,
            yearEnd: 2023,
            matcherPriority: 10,
            localizationKey: "vehicle.generation.model-3-refresh-performance",
            trims: [
                VehicleTrimRecord(id: "performance", aliases: ["P74D"], localizationKey: "vehicle.trim.performance"),
                VehicleTrimRecord(id: "unavailable", aliases: [], localizationKey: "vehicle.trim.base")
            ],
            wheels: [
                VehicleWheelRecord(id: "uberturbine-20", aliases: ["W32D"], localizationKey: "vehicle.wheel.uberturbine-20"),
                VehicleWheelRecord(id: "crossflow-19", aliases: ["W38A"], localizationKey: "vehicle.wheel.crossflow-19"),
                VehicleWheelRecord(id: "unavailable", aliases: [], localizationKey: "vehicle.wheel.aero-18")
            ],
            colors: [
                VehicleColorRecord(id: "pearl-white", aliases: ["PPSW"], localizationKey: "vehicle.color.pearl-white"),
                VehicleColorRecord(id: "deep-blue", aliases: ["PPSB"], localizationKey: "vehicle.color.deep-blue"),
                VehicleColorRecord(id: "unavailable", aliases: [], localizationKey: "vehicle.color.stainless")
            ],
            defaultTrimID: "performance",
            defaultWheelID: "uberturbine-20",
            defaultColorID: "pearl-white",
            legacyFallback: VehicleLegacyFallbackRecord(assetID: "white-uberturbine", path: "CarImages/white-uberturbine.png")
        )
        let modelY = VehicleGenerationRecord(
            id: "model-y-legacy",
            model: "Model Y",
            aliases: ["Y"],
            yearStart: 2020,
            yearEnd: 2024,
            matcherPriority: 20,
            localizationKey: "vehicle.generation.model-y-legacy",
            trims: [VehicleTrimRecord(id: "standard", aliases: [], localizationKey: "vehicle.trim.standard")],
            wheels: [VehicleWheelRecord(id: "gemini-19", aliases: [], localizationKey: "vehicle.wheel.gemini-19")],
            colors: [VehicleColorRecord(id: "pearl-white", aliases: [], localizationKey: "vehicle.color.pearl-white")],
            defaultTrimID: "standard",
            defaultWheelID: "gemini-19",
            defaultColorID: "pearl-white",
            legacyFallback: VehicleLegacyFallbackRecord(assetID: "model-y-white", path: "CarImages/model-y-white.png")
        )
        let modelYAsset = VehicleAssetRecord(
            id: "model-y-white",
            generationID: modelY.id,
            trimID: "standard",
            wheelID: "gemini-19",
            colorID: "pearl-white",
            path: "CarImages/model-y-white.png",
            reviewStatus: .reviewed
        )
        return VehicleImageCatalog(
            schemaVersion: VehicleImageCatalog.currentSchemaVersion,
            generations: [generation] + (includeModelY ? [modelY] : []),
            assets: [
                VehicleAssetRecord(
                    id: "white-uberturbine",
                    generationID: generation.id,
                    trimID: "performance",
                    wheelID: "uberturbine-20",
                    colorID: "pearl-white",
                    path: "CarImages/white-uberturbine.png",
                    reviewStatus: .reviewed
                ),
                VehicleAssetRecord(
                    id: "white-crossflow",
                    generationID: generation.id,
                    trimID: "performance",
                    wheelID: "crossflow-19",
                    colorID: "pearl-white",
                    path: "CarImages/white-crossflow.png",
                    reviewStatus: .reviewed
                ),
                VehicleAssetRecord(
                    id: "blue-crossflow",
                    generationID: generation.id,
                    trimID: "performance",
                    wheelID: "crossflow-19",
                    colorID: "deep-blue",
                    path: "CarImages/blue-crossflow.png",
                    reviewStatus: .reviewed
                )
            ] + (includeModelY ? [modelYAsset] : [])
        )
    }
}

private actor SaveRecorder {
    private(set) var values: [VehicleImageOverride?] = []

    func record(_ value: VehicleImageOverride?) {
        values.append(value)
    }

    func snapshot() -> [VehicleImageOverride?] {
        values
    }
}

private actor SubmissionGate {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func suspendUntilReleased() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum PickerSubmissionError: Error {
    case rejected
}

private final class PickerDashboardSettingsStore: SettingsStoring, @unchecked Sendable {
    var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async -> AppSettings { settings }
    func save(_ settings: AppSettings) async { self.settings = settings }
}

private final class PickerDashboardSnapshotStore: DashboardSnapshotStoring, @unchecked Sendable {
    private(set) var saved: [DashboardSnapshot] = []

    func save(_ snapshot: DashboardSnapshot, serverURL: String) async {
        saved.append(snapshot)
    }

    func load(serverURL: String, carId: Int, now: Date) async -> DashboardSnapshot? { nil }
}

private struct PickerCatalogProvider: VehicleImageCatalogProviding {
    let catalogValue: VehicleImageCatalog

    init(catalog: VehicleImageCatalog) {
        catalogValue = catalog
    }

    func catalog() throws -> VehicleImageCatalog { catalogValue }
}

private struct PickerDashboardAPI: DashboardAPIProviding {
    let car: CarData

    func cars() async -> APIResult<[CarData]> { .success([car]) }
    func carStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        .success(CarStatusPayload(status: nil, units: nil))
    }
}
