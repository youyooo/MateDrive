import SwiftUI

public struct CarImagePickerView: View {
    @Environment(\.appLanguage) private var appLanguage

    private let model: String?
    private let exteriorColor: String?
    private let wheelType: String?
    private let trimBadging: String?
    private let selectedAssetPath: String?
    private let onSelect: (String?) -> Void

    @State private var selectedVariant: String

    public init(
        model: String?,
        exteriorColor: String?,
        wheelType: String?,
        trimBadging: String?,
        selectedAssetPath: String?,
        onSelect: @escaping (String?) -> Void
    ) {
        self.model = model
        self.exteriorColor = exteriorColor
        self.wheelType = wheelType
        self.trimBadging = trimBadging
        self.selectedAssetPath = selectedAssetPath
        self.onSelect = onSelect

        let detected = CarImageResolver.detectedDefault(
            model: model,
            exteriorColor: exteriorColor,
            wheelType: wheelType,
            trimBadging: trimBadging
        )
        _selectedVariant = State(initialValue: detected.variant)
    }

    public var body: some View {
        let colorCode = CarImageResolver.mapColor(exteriorColor)
        let variants = CarImageResolver.variantsForModel(
            model: model,
            colorCode: colorCode,
            trimBadging: trimBadging,
            wheelType: wheelType
        )
        let resolvedVariants = variants.isEmpty ? [CarVariant(id: selectedVariant, displayNameIdentifier: selectedVariant)] : variants
        let wheels = CarImageResolver.wheelsForVariant(variant: selectedVariant, colorCode: colorCode, wheelType: wheelType)

        List {
            Section {
                Picker(t("Variant", "车型版本"), selection: $selectedVariant) {
                    ForEach(resolvedVariants, id: \.id) { variant in
                        Text(displayName(forVariant: variant.id)).tag(variant.id)
                    }
                }
            }

            Section {
                ForEach(wheels, id: \.code) { wheel in
                    Button {
                        onSelect(wheel.assetPath)
                    } label: {
                        HStack(spacing: 12) {
                            CarImageView(assetPath: wheel.assetPath, scaleFactor: CGFloat(CarImageResolver.scaleFactor(forVariant: selectedVariant)))
                                .frame(width: 112, height: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(wheel.displayName)
                                    .font(.body.weight(.medium))
                                Text(selectedVariant.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if wheel.assetPath == selectedAssetPath {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    onSelect(nil)
                } label: {
                    Label(t("Automatic", "自动识别"), systemImage: "wand.and.stars")
                }
            }
        }
        .navigationTitle(t("Car Image", "车辆图片"))
    }

    private func displayName(forVariant variant: String) -> String {
        switch variant {
        case "my":
            return "Model Y Legacy"
        case "myjs":
            return "Model Y Juniper Standard"
        case "myj":
            return "Model Y Juniper"
        case "myjp":
            return "Model Y Juniper Performance"
        case "m3":
            return "Model 3 Legacy"
        case "m3h":
            return "Model 3 Highland"
        case "m3hp":
            return "Model 3 Highland Performance"
        case "ms":
            return "Model S"
        case "mx":
            return "Model X"
        default:
            return variant.uppercased()
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
