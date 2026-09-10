import SwiftUI

private struct MateDrivePaletteKey: EnvironmentKey {
    static let defaultValue = MateDrivePalettes.light
}

public extension EnvironmentValues {
    var mateDrivePalette: MateDrivePalette {
        get { self[MateDrivePaletteKey.self] }
        set { self[MateDrivePaletteKey.self] = newValue }
    }
}

public extension View {
    func mateDrivePalette(_ palette: MateDrivePalette) -> some View {
        environment(\.mateDrivePalette, palette)
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

public extension MateDrivePalette {
    var surfaceColor: Color { surface.color }
    var accentColor: Color { accent.color }
    var accentDimColor: Color { accentDim.color }
    var onSurfaceColor: Color { onSurface.color }
    var onSurfaceVariantColor: Color { onSurfaceVariant.color }
    var progressTrackColor: Color { progressTrack.color }
}
