import XCTest
@testable import MateDroidIOS

final class CarImageResolverTests: XCTestCase {
    func testLegacyModelYUsesAndroidColorAndWheelMappings() {
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "Y", exteriorColor: "DeepBlueMetallic", wheelType: "Gemini19", trimBadging: "74D"),
            "car_images/my_PPSB_WY19B.png"
        )
        XCTAssertEqual(CarImageResolver.scaleFactor(model: "Y", exteriorColor: "DeepBlueMetallic", wheelType: "Gemini19"), 1.0)
    }

    func testJuniperModelYStandardAndPerformanceDetectionMatchAndroid() {
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "Y", exteriorColor: "StealthGrey", wheelType: "Photon18", trimBadging: "50"),
            "car_images/myjs_PN01_WY18P.png"
        )
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "Y", exteriorColor: "MarineBlue", wheelType: "Uberturbine21", trimBadging: "P74D"),
            "car_images/myjp_PB02_WY21A.png"
        )
        XCTAssertEqual(CarImageResolver.scaleFactor(model: "Y", exteriorColor: "MarineBlue", wheelType: "Uberturbine21", trimBadging: "P74D"), 1.25)
    }

    func testHighlandModel3DetectionAndFallbacksMatchAndroid() {
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "3", exteriorColor: "Quicksilver", wheelType: "Photon18", trimBadging: nil),
            "car_images/m3h_PN00_W38A.png"
        )
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "3", exteriorColor: "MidnightSilver", wheelType: "Photon18", trimBadging: nil),
            "car_images/m3h_PPSW_W38A.png"
        )
        XCTAssertEqual(
            CarImageResolver.defaultAssetPath(model: "X"),
            "car_images/mx_PPSW_WT20.png"
        )
    }

    func testFallbackTriesExactDefaultWheelDefaultColorThenModelDefault() {
        let existing: Set<String> = ["car_images/myj_PN00_WY19P.png"]

        let path = CarImageResolver.fallbackAssetPath(
            model: "Y",
            exteriorColor: "Quicksilver",
            wheelType: "Helix20",
            trimBadging: "74D",
            assetExists: existing.contains
        )

        XCTAssertEqual(path, "car_images/myj_PN00_WY19P.png")
    }

    func testPickerHelpersMatchAndroidVariantAndWheelRules() {
        XCTAssertEqual(CarImageResolver.detectedDefault(model: "Y", exteriorColor: "StealthGrey", wheelType: "Photon18", trimBadging: "50"), DetectedCarImageDefault(variant: "myjs", wheelCode: "WY18P"))
        XCTAssertEqual(CarImageResolver.variantsForModel(model: "Y", colorCode: "PB02").map(\.id), ["myjp"])
        XCTAssertEqual(CarImageResolver.variantsForModel(model: "3", colorCode: "PMNG").map(\.id), ["m3"])
        XCTAssertEqual(CarImageResolver.wheelsForVariant(variant: "myj", colorCode: "PN00", wheelType: "Crossflow19").map(\.code), ["WY19P"])
    }

    func testTeslaMateModelAliasesResolveVehicleImages() {
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "modely", exteriorColor: "PearlWhiteMultiCoat", wheelType: "Gemini19"),
            "car_images/my_PPSW_WY19B.png"
        )
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "model3", exteriorColor: "Quicksilver", wheelType: "Photon18"),
            "car_images/m3h_PN00_W38A.png"
        )
        XCTAssertEqual(CarImageResolver.defaultAssetPath(model: "modelS"), "car_images/ms_PPSW_WT19.png")
        XCTAssertEqual(CarImageResolver.defaultAssetPath(model: "modelX"), "car_images/mx_PPSW_WT20.png")
        XCTAssertEqual(CarImageResolver.variantsForModel(model: "modelY", colorCode: "PB02").map(\.id), ["myjp"])
    }

    func testTeslaMateOptionCodesResolveExactVehicleImages() {
        XCTAssertEqual(CarImageResolver.mapColor("PPSB"), "PPSB")
        XCTAssertEqual(CarImageResolver.mapColor("ppmr"), "PPMR")
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "3", exteriorColor: "PPSB", wheelType: "W39B"),
            "car_images/m3_PPSB_W39B.png"
        )
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "Y", exteriorColor: "PN00", wheelType: "WY20A", trimBadging: "74D"),
            "car_images/myj_PN00_WY20A.png"
        )
        XCTAssertEqual(
            CarImageResolver.assetPath(model: "Y", exteriorColor: "PB02", wheelType: "WY21A", trimBadging: "P74D"),
            "car_images/myjp_PB02_WY21A.png"
        )
    }
}
