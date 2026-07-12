import SwiftUI

public struct PalettePreviewView: View {
    @Environment(\.appLanguage) private var appLanguage

    private let samples: [PalettePreviewSample] = [
        PalettePreviewSample(name: "Pearl White", exteriorColor: "PPSW"),
        PalettePreviewSample(name: "Solid Black", exteriorColor: "PBSB"),
        PalettePreviewSample(name: "Midnight Silver", exteriorColor: "PMNG"),
        PalettePreviewSample(name: "Deep Blue", exteriorColor: "PPSB"),
        PalettePreviewSample(name: "Red", exteriorColor: "PPMR"),
        PalettePreviewSample(name: "Quicksilver", exteriorColor: "PN00"),
        PalettePreviewSample(name: "Stealth Grey", exteriorColor: "PN01"),
        PalettePreviewSample(name: "Ultra Red", exteriorColor: "PR01"),
        PalettePreviewSample(name: "Midnight Cherry", exteriorColor: "PR00"),
        PalettePreviewSample(name: "Fallback", exteriorColor: nil)
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(samples) { sample in
                    PalettePreviewCard(sample: sample)
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(t("Palette", "配色"))
        .accessibilityIdentifier("palette_preview_view")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct PalettePreviewCard: View {
    @Environment(\.appLanguage) private var appLanguage

    let sample: PalettePreviewSample

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(sample.exteriorColor ?? t("Default", "默认"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            paletteRow(title: t("Light", "浅色"), palette: sample.lightPalette)
            paletteRow(title: t("Dark", "深色"), palette: sample.darkPalette)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func paletteRow(title: String, palette: CarColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                swatch(title: t("Surface", "表面"), color: palette.surfaceColor)
                swatch(title: t("Accent", "强调"), color: palette.accentColor)
                swatch(title: "AC", color: palette.acColor.color)
                swatch(title: "DC", color: palette.dcColor.color)
            }
        }
    }

    private func swatch(title: String, color: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                }
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(t("color", "颜色"))")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct PalettePreviewSample: Identifiable {
    let name: String
    let exteriorColor: String?

    var id: String {
        exteriorColor ?? "default"
    }

    var lightPalette: CarColorPalette {
        CarColorPalettes.forExteriorColor(exteriorColor, darkTheme: false)
    }

    var darkPalette: CarColorPalette {
        CarColorPalettes.forExteriorColor(exteriorColor, darkTheme: true)
    }
}
