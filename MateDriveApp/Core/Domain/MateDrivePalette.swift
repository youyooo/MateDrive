import Foundation

public struct PaletteColor: Equatable, Sendable {
    public let hex: String
    public let alpha: Double

    public init(hex: String, alpha: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        self.hex = "#\(cleaned)"
        self.alpha = alpha
    }

    public func opacity(_ alpha: Double) -> PaletteColor {
        PaletteColor(hex: hex, alpha: alpha)
    }
}

public struct MateDrivePalette: Equatable, Sendable {
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
        self.accentDim = accent.opacity(0.24)
        self.onSurface = onSurface
        self.onSurfaceVariant = onSurface.opacity(0.64)
        self.progressTrack = onSurface.opacity(darkTheme ? 0.16 : 0.10)
        self.acColor = PaletteColor(hex: darkTheme ? "#4CD964" : "#20B15A")
        self.dcColor = PaletteColor(hex: darkTheme ? "#FFB340" : "#F08A24")
    }
}

public enum MateDrivePalettes {
    public static let light = MateDrivePalette(
        surface: PaletteColor(hex: "#F2F4F6"),
        accent: PaletteColor(hex: "#18B85A"),
        onSurface: PaletteColor(hex: "#171A1F"),
        darkTheme: false
    )

    public static let dark = MateDrivePalette(
        surface: PaletteColor(hex: "#121417"),
        accent: PaletteColor(hex: "#42D77D"),
        onSurface: PaletteColor(hex: "#F4F7F5"),
        darkTheme: true
    )

    public static func forColorScheme(darkTheme: Bool) -> MateDrivePalette {
        darkTheme ? dark : light
    }
}
