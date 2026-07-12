import XCTest
@testable import MateDroidIOS

final class VehicleImageOverrideTests: XCTestCase {
    func testOverrideRoundTripsAndCanBeClearedWithoutExposingStorageKey() throws {
        let serverURL = URL(string: "https://teslamate.example/base")!
        let override = VehicleImageOverride(
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "midnight-silver",
            wheelID: "uberturbine-20",
            assetID: "reviewed-midnight"
        )
        var settings = AppSettings()

        settings.setVehicleImageOverride(override, for: serverURL, carID: 7)

        XCTAssertEqual(settings.vehicleImageOverride(for: serverURL, carID: 7), override)
        XCTAssertEqual(
            try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
                .vehicleImageOverride(for: serverURL, carID: 7),
            override
        )

        settings.clearVehicleImageOverride(for: serverURL, carID: 7)

        XCTAssertNil(settings.vehicleImageOverride(for: serverURL, carID: 7))
    }

    func testSameCarIDOnDifferentServersUsesSeparateOverrides() {
        let firstServer = URL(string: "https://first.example")!
        let secondServer = URL(string: "https://second.example")!
        let firstOverride = VehicleImageOverride(
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "pearl-white",
            wheelID: "uberturbine-20",
            assetID: "default"
        )
        let secondOverride = VehicleImageOverride(
            generationID: "model-3-highland",
            trimID: "long-range",
            colorID: "stealth-grey",
            wheelID: "photon-18",
            assetID: "highland"
        )
        var settings = AppSettings()

        settings.setVehicleImageOverride(firstOverride, for: firstServer, carID: 7)
        settings.setVehicleImageOverride(secondOverride, for: secondServer, carID: 7)

        XCTAssertEqual(settings.vehicleImageOverride(for: firstServer, carID: 7), firstOverride)
        XCTAssertEqual(settings.vehicleImageOverride(for: secondServer, carID: 7), secondOverride)
    }

    func testDeletedCatalogIDsAreIgnoredWithoutRemovingStoredOverride() {
        let serverURL = URL(string: "https://teslamate.example")!
        let storedOverride = VehicleImageOverride(
            generationID: "removed-generation",
            trimID: "performance",
            colorID: "midnight-silver",
            wheelID: "uberturbine-20",
            assetID: "removed-asset"
        )
        var settings = AppSettings()
        settings.setVehicleImageOverride(storedOverride, for: serverURL, carID: 7)

        let manualOverride = settings.manualVehicleImageOverride(
            for: serverURL,
            carID: 7,
            catalog: VehicleImageCatalog(
                schemaVersion: VehicleImageCatalog.currentSchemaVersion,
                generations: [],
                assets: []
            )
        )

        XCTAssertNil(manualOverride)
        XCTAssertEqual(settings.vehicleImageOverride(for: serverURL, carID: 7), storedOverride)
    }

    @MainActor
    func testBundledCatalogMigratesUniqueLegacyM3WheelAndLeavesAmbiguousPairAutomatic() throws {
        let catalog = try BundledVehicleImageCatalogProvider(bundle: .main).catalog()

        XCTAssertEqual(
            VehicleImageOverride.migrateLegacy(variant: "m3", wheelCode: "W32D", catalog: catalog),
            VehicleImageOverride(
                generationID: "model-3-refresh-performance",
                trimID: "performance",
                colorID: "pearl-white",
                wheelID: "uberturbine-20",
                assetID: "legacy-model-3-refresh-performance"
            )
        )
        XCTAssertNil(VehicleImageOverride.migrateLegacy(variant: "m3", wheelCode: "W38B", catalog: catalog))
        XCTAssertNil(VehicleImageOverride.migrateLegacy(variant: "m3h", wheelCode: "W32D", catalog: catalog))
    }

    @MainActor
    func testBundledEarlyOverrideWithoutAssetIDRestoresReviewedAssetRegardlessOfCatalogOrder() throws {
        let bundled = try BundledVehicleImageCatalogProvider(bundle: .main).catalog()
        let stored = VehicleImageOverride(
            generationID: "model-3-early",
            trimID: "base",
            colorID: "pearl-white",
            wheelID: "aero-18"
        )
        let expected = VehicleImageManualOverride(
            generationID: "model-3-early",
            trimID: "base",
            colorID: "pearl-white",
            wheelID: "aero-18",
            assetID: "model-3-early-base-pearl-white-aero-18"
        )
        let catalogs = [
            bundled,
            VehicleImageCatalog(
                schemaVersion: bundled.schemaVersion,
                generations: bundled.generations,
                assets: Array(bundled.assets.reversed())
            )
        ]

        for catalog in catalogs {
            XCTAssertEqual(stored.manualOverride(in: catalog), expected)
        }
    }

    @MainActor
    func testCurrentOverrideWinsWhenPayloadAlsoHasLegacyKeys() throws {
        let serverURL = URL(string: "https://teslamate.example")!
        let currentOverride = VehicleImageOverride(
            generationID: "model-3-refresh-performance",
            trimID: "performance",
            colorID: "pearl-white",
            wheelID: "uberturbine-20",
            assetID: "legacy-model-3-refresh-performance"
        )
        var settings = AppSettings(serverURL: serverURL.absoluteString)
        settings.setVehicleImageOverride(currentOverride, for: serverURL, carID: 7)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        payload["carImageVariants"] = ["7": "m3"]
        payload["carImageWheelCodes"] = ["7": "W32D"]
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: payload))
        let catalog = try BundledVehicleImageCatalogProvider(bundle: .main).catalog()
        var migrated = decoded

        XCTAssertTrue(migrated.migrateLegacyVehicleImageOverrides(catalog: catalog))

        XCTAssertEqual(migrated.vehicleImageOverride(for: serverURL, carID: 7), currentOverride)
    }
}
