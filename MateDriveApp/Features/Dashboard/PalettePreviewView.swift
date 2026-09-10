import SwiftUI

public struct PalettePreviewView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            preview(title: "Light", palette: MateDrivePalettes.light)
            preview(title: "Dark", palette: MateDrivePalettes.dark)
        }
        .padding()
        .navigationTitle("MateDrive")
        .accessibilityIdentifier("palette_preview_view")
    }

    private func preview(title: String, palette: MateDrivePalette) -> some View {
        HStack {
            Circle().fill(palette.accentColor).frame(width: 28, height: 28)
            Text(title).foregroundStyle(palette.onSurfaceColor)
            Spacer()
        }
        .padding()
        .background(palette.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
