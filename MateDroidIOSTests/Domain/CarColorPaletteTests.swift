import XCTest
@testable import MateDroidIOS

final class CarColorPaletteTests: XCTestCase {
    func testWhiteDefaultPaletteMatchesAndroidHexValues() {
        let palette = CarColorPalettes.forExteriorColor("PPSW", darkTheme: false)

        XCTAssertEqual(palette.surface, PaletteColor(hex: "#F5F3F0"))
        XCTAssertEqual(palette.accent, PaletteColor(hex: "#8B7355"))
        XCTAssertEqual(palette.onSurface, PaletteColor(hex: "#2A2520"))
        XCTAssertEqual(palette.accentDim, PaletteColor(hex: "#8B7355", alpha: 0.3))
    }

    func testSpecificCarColorsMatchAndroidPaletteSelection() {
        XCTAssertEqual(CarColorPalettes.forExteriorColor("UltraRed", darkTheme: false).accent, PaletteColor(hex: "#E03030"))
        XCTAssertEqual(CarColorPalettes.forExteriorColor("PN01", darkTheme: true).surface, PaletteColor(hex: "#1E2022"))
        XCTAssertEqual(CarColorPalettes.forExteriorColor("DeepBlueMetallic", darkTheme: false).surface, PaletteColor(hex: "#E5EBF5"))
        XCTAssertEqual(CarColorPalettes.forExteriorColor(nil, darkTheme: true).accent, PaletteColor(hex: "#8BAEE8"))
    }
}
