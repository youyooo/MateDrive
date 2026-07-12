import Foundation

public struct PaletteColor: Equatable, Sendable {
    public let hex: String
    public let alpha: Double

    public init(hex: String, alpha: Double = 1.0) {
        self.hex = PaletteColor.normalizedHex(hex)
        self.alpha = alpha
    }

    public func opacity(_ alpha: Double) -> PaletteColor {
        PaletteColor(hex: hex, alpha: alpha)
    }

    private static func normalizedHex(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        return "#\(cleaned)"
    }
}

public struct CarColorPalette: Equatable, Sendable {
    public let surface: PaletteColor
    public let accent: PaletteColor
    public let accentDim: PaletteColor
    public let onSurface: PaletteColor
    public let onSurfaceVariant: PaletteColor
    public let progressTrack: PaletteColor
    public let acColor: PaletteColor
    public let dcColor: PaletteColor

    public init(surface: PaletteColor, accent: PaletteColor, onSurface: PaletteColor, darkTheme: Bool) {
        self.surface = surface
        self.accent = accent
        self.accentDim = accent.opacity(0.3)
        self.onSurface = onSurface
        self.onSurfaceVariant = onSurface.opacity(0.7)
        self.progressTrack = onSurface.opacity(0.1)
        self.acColor = PaletteHarmonizer.harmonizeACColor(accent: accent, darkTheme: darkTheme)
        self.dcColor = PaletteHarmonizer.harmonizeDCColor(accent: accent, darkTheme: darkTheme)
    }
}

public enum CarColorPalettes {
    public static let defaultLight = palette(surface: "#F5F3F0", accent: "#8B7355", onSurface: "#2A2520", darkTheme: false)
    public static let defaultDark = palette(surface: "#1E2530", accent: "#8BAEE8", onSurface: "#E8EEF8", darkTheme: true)

    public static func forExteriorColor(_ exteriorColor: String?, darkTheme: Bool) -> CarColorPalette {
        let colorKey = exteriorColor?.lowercased().replacingOccurrences(of: " ", with: "") ?? ""

        switch true {
        case colorKey.contains("white") || colorKey == "ppsw":
            return darkTheme ? whiteDark : whiteLight
        case colorKey.contains("black") || colorKey == "pbsb" || colorKey == "pmbl":
            return darkTheme ? blackDark : blackLight
        case colorKey.contains("midnightsilver") || colorKey.contains("steelgrey") || colorKey == "pmng":
            return darkTheme ? midnightSilverDark : midnightSilverLight
        case colorKey.contains("silver") || colorKey == "pmss":
            return darkTheme ? midnightSilverDark : midnightSilverLight
        case colorKey.contains("deepblue") || colorKey == "ppsb":
            return darkTheme ? deepBlueDark : deepBlueLight
        case colorKey.contains("quicksilver") || colorKey == "pn00":
            return darkTheme ? quicksilverDark : quicksilverLight
        case colorKey.contains("stealthgrey") || colorKey.contains("stealth") || colorKey == "pn01":
            return darkTheme ? stealthGreyDark : stealthGreyLight
        case colorKey.contains("midnightcherry") || colorKey == "pr00":
            return darkTheme ? midnightCherryDark : midnightCherryLight
        case colorKey.contains("ultrared") || colorKey == "pr01":
            return darkTheme ? ultraRedDark : ultraRedLight
        case colorKey.contains("red") || colorKey == "ppmr":
            return darkTheme ? redDark : redLight
        default:
            return darkTheme ? defaultDark : defaultLight
        }
    }

    private static let whiteLight = defaultLight
    private static let whiteDark = defaultDark
    private static let blackLight = palette(surface: "#D8DADC", accent: "#505458", onSurface: "#1E2022", darkTheme: false)
    private static let blackDark = palette(surface: "#2A2520", accent: "#C9A66B", onSurface: "#F5F3F0", darkTheme: true)
    private static let midnightSilverLight = palette(surface: "#ECEEF0", accent: "#6B7A8C", onSurface: "#22262B", darkTheme: false)
    private static let midnightSilverDark = palette(surface: "#22262B", accent: "#8FA4B8", onSurface: "#ECEEF0", darkTheme: true)
    private static let deepBlueLight = palette(surface: "#E5EBF5", accent: "#3B5998", onSurface: "#1A2235", darkTheme: false)
    private static let deepBlueDark = palette(surface: "#1A2235", accent: "#6B8BC3", onSurface: "#E5EBF5", darkTheme: true)
    private static let redLight = palette(surface: "#F8E8E8", accent: "#C45050", onSurface: "#2E1A1A", darkTheme: false)
    private static let redDark = palette(surface: "#2E1A1A", accent: "#E07070", onSurface: "#F8E8E8", darkTheme: true)
    private static let quicksilverLight = palette(surface: "#F0EDE8", accent: "#A09080", onSurface: "#252320", darkTheme: false)
    private static let quicksilverDark = palette(surface: "#252320", accent: "#B0A090", onSurface: "#F0EDE8", darkTheme: true)
    private static let stealthGreyLight = palette(surface: "#ECEDEE", accent: "#606570", onSurface: "#1E2022", darkTheme: false)
    private static let stealthGreyDark = palette(surface: "#1E2022", accent: "#909598", onSurface: "#ECEDEE", darkTheme: true)
    private static let ultraRedLight = palette(surface: "#FAEBEB", accent: "#E03030", onSurface: "#301818", darkTheme: false)
    private static let ultraRedDark = palette(surface: "#301818", accent: "#FF5050", onSurface: "#FAEBEB", darkTheme: true)
    private static let midnightCherryLight = palette(surface: "#F5E5E8", accent: "#8B3040", onSurface: "#251518", darkTheme: false)
    private static let midnightCherryDark = palette(surface: "#251518", accent: "#C05068", onSurface: "#F5E5E8", darkTheme: true)

    private static func palette(surface: String, accent: String, onSurface: String, darkTheme: Bool) -> CarColorPalette {
        CarColorPalette(
            surface: PaletteColor(hex: surface),
            accent: PaletteColor(hex: accent),
            onSurface: PaletteColor(hex: onSurface),
            darkTheme: darkTheme
        )
    }
}

private enum PaletteHarmonizer {
    private struct HSL {
        let hue: Double
        let saturation: Double
        let lightness: Double
    }

    static func harmonizeACColor(accent: PaletteColor, darkTheme: Bool) -> PaletteColor {
        let base = darkTheme ? PaletteColor(hex: "#66BB6A") : PaletteColor(hex: "#4CAF50")
        let green = hsl(from: base)
        let accentHSL = hsl(from: accent)
        let newHue = clamp(green.hue + (accentHSL.hue - green.hue) * 0.20, min: 0, max: 1)
        let newSaturation = darkTheme
            ? clamp(green.saturation * 0.95, min: 0.4, max: 1)
            : clamp(green.saturation * 0.85, min: 0.3, max: 0.9)
        let newLightness = darkTheme
            ? clamp(green.lightness * 0.55, min: 0.3, max: 0.7)
            : clamp(green.lightness * 0.95, min: 0.3, max: 0.7)
        return color(from: HSL(hue: newHue, saturation: newSaturation, lightness: newLightness))
    }

    static func harmonizeDCColor(accent: PaletteColor, darkTheme: Bool) -> PaletteColor {
        let base = darkTheme ? PaletteColor(hex: "#FFA726") : PaletteColor(hex: "#FF9800")
        let orange = hsl(from: base)
        let accentHSL = hsl(from: accent)
        let newHue = clamp(orange.hue + (accentHSL.hue - orange.hue) * 0.10, min: 0, max: 1)
        let newSaturation = darkTheme
            ? clamp(orange.saturation * 1.05, min: 0.6, max: 1)
            : clamp(orange.saturation * 0.95, min: 0.5, max: 0.9)
        let newLightness = darkTheme
            ? clamp(orange.lightness * 0.55, min: 0.35, max: 0.75)
            : clamp(orange.lightness * 0.95, min: 0.35, max: 0.75)
        return color(from: HSL(hue: newHue, saturation: newSaturation, lightness: newLightness))
    }

    private static func hsl(from color: PaletteColor) -> HSL {
        let rgb = rgbComponents(from: color.hex)
        let red = rgb.red
        let green = rgb.green
        let blue = rgb.blue
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2

        guard delta != 0 else {
            return HSL(hue: 0, saturation: 0, lightness: lightness)
        }

        let saturation = lightness < 0.5 ? delta / (maxValue + minValue) : delta / (2 - maxValue - minValue)
        let hue: Double
        if maxValue == red {
            hue = ((green - blue) / delta + (green < blue ? 6 : 0)) / 6
        } else if maxValue == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }

        return HSL(hue: hue, saturation: saturation, lightness: lightness)
    }

    private static func color(from hsl: HSL) -> PaletteColor {
        let hue = clamp(hsl.hue, min: 0, max: 1)
        let saturation = clamp(hsl.saturation, min: 0, max: 1)
        let lightness = clamp(hsl.lightness, min: 0, max: 1)

        if saturation == 0 {
            return rgbColor(red: lightness, green: lightness, blue: lightness)
        }

        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        let red = hueToRGB(p: p, q: q, t: hue + 1.0 / 3.0)
        let green = hueToRGB(p: p, q: q, t: hue)
        let blue = hueToRGB(p: p, q: q, t: hue - 1.0 / 3.0)
        return rgbColor(red: red, green: green, blue: blue)
    }

    private static func hueToRGB(p: Double, q: Double, t rawT: Double) -> Double {
        var t = rawT
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
        return p
    }

    private static func rgbColor(red: Double, green: Double, blue: Double) -> PaletteColor {
        let redValue = Int(round(clamp(red, min: 0, max: 1) * 255))
        let greenValue = Int(round(clamp(green, min: 0, max: 1) * 255))
        let blueValue = Int(round(clamp(blue, min: 0, max: 1) * 255))
        return PaletteColor(hex: String(format: "#%02X%02X%02X", redValue, greenValue, blueValue))
    }

    private static func rgbComponents(from hex: String) -> (red: Double, green: Double, blue: Double) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0
        return (red, green, blue)
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}
