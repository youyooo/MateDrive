import SwiftUI

private struct CarPaletteKey: EnvironmentKey {
    static let defaultValue = CarColorPalettes.defaultLight
}

public extension EnvironmentValues {
    var carPalette: CarColorPalette {
        get { self[CarPaletteKey.self] }
        set { self[CarPaletteKey.self] = newValue }
    }
}

public extension View {
    func carPalette(_ palette: CarColorPalette) -> some View {
        environment(\.carPalette, palette)
    }
}

public extension PaletteColor {
    var color: Color {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xff) / 255.0
        let green = Double((value >> 8) & 0xff) / 255.0
        let blue = Double(value & 0xff) / 255.0

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

public extension CarColorPalette {
    var surfaceColor: Color { surface.color }
    var accentColor: Color { accent.color }
    var accentDimColor: Color { accentDim.color }
    var onSurfaceColor: Color { onSurface.color }
    var onSurfaceVariantColor: Color { onSurfaceVariant.color }
    var progressTrackColor: Color { progressTrack.color }
}
