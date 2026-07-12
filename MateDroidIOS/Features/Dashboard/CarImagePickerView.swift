import SwiftUI

public struct CarImagePickerOption: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let assetPath: String?
    public let swatchHex: String?

    public init(id: String, name: String, assetPath: String? = nil, swatchHex: String? = nil) {
        self.id = id
        self.name = name
        self.assetPath = assetPath
        self.swatchHex = swatchHex
    }
}

public enum CarImagePickerLayout {
    public static let colorOptionWidth: CGFloat = 96
    public static let colorLabelHeight: CGFloat = 32
    public static let colorLabelLineLimit = 2
}

@MainActor
public final class CarImagePickerViewModel: ObservableObject, Identifiable {
    public let id = UUID()

    @Published public private(set) var selectedGenerationID: String
    @Published public private(set) var selectedTrimID: String
    @Published public private(set) var selectedColorID: String
    @Published public private(set) var selectedWheelID: String
    @Published public private(set) var isSubmitting = false
    @Published public private(set) var shouldDismiss = false
    @Published public private(set) var submissionErrorMessage: String?

    public let confidence: VehicleImageConfidence
    public let confidenceName: String
    public let confidenceExplanation: String
    public let detectedGenerationID: String?
    public let detectedGenerationName: String
    public let detectedTrimID: String?
    public let detectedTrimName: String
    public let detectedConfidenceName: String
    public let detectedConflictExplanation: String?
    public let configurationNotice: String?

    private let catalog: VehicleImageCatalog
    private let language: AppLanguage
    private let saveOverride: (VehicleImageOverride?) async throws -> Void

    public init(
        catalog: VehicleImageCatalog,
        automaticResolution: VehicleImageResolution,
        storedOverride: VehicleImageOverride?,
        language: AppLanguage,
        saveOverride: @escaping (VehicleImageOverride?) async throws -> Void
    ) {
        self.catalog = catalog
        self.language = language
        self.saveOverride = saveOverride
        confidence = automaticResolution.confidence
        confidenceName = Self.confidenceName(automaticResolution.confidence, language: language)
        confidenceExplanation = Self.confidenceExplanation(automaticResolution.confidence, language: language)
        detectedConfidenceName = confidenceName
        detectedGenerationID = automaticResolution.generationID
        let detectedGeneration = automaticResolution.generationID.flatMap { generationID in
            catalog.generations.first { $0.id == generationID }
        }
        detectedGenerationName = detectedGeneration.map {
            VehicleImagePickerText.localized($0.localizationKey, language: language)
        } ?? Self.text("Unknown", language: language)
        detectedTrimID = automaticResolution.trimID
        detectedTrimName = detectedGeneration?.trims.first(where: { $0.id == automaticResolution.trimID }).map {
            VehicleImagePickerText.localized($0.localizationKey, language: language)
        } ?? Self.text("Unknown", language: language)
        detectedConflictExplanation = Self.conflictExplanation(automaticResolution.conflicts, language: language)

        let validStoredOverride = storedOverride?.manualOverride(in: catalog)
        let initialAsset = validStoredOverride.flatMap { override in
            catalog.assets.first { $0.id == override.assetID }
        } ?? automaticResolution.assetID.flatMap { assetID in
            catalog.assets.first { $0.id == assetID }
        } ?? catalog.preferredAssets.first

        selectedGenerationID = initialAsset?.generationID ?? ""
        selectedTrimID = initialAsset?.trimID ?? ""
        selectedColorID = initialAsset?.colorID ?? ""
        selectedWheelID = initialAsset?.wheelID ?? ""

        if storedOverride != nil, validStoredOverride == nil {
            configurationNotice = Self.text(
                "The saved configuration is no longer available. Automatic matching has been restored.",
                language: language
            )
        } else {
            configurationNotice = nil
        }
        normalizeSelection()
    }

    public var generationOptions: [CarImagePickerOption] {
        catalog.generations.compactMap { generation in
            guard catalog.preferredAssets.contains(where: { $0.generationID == generation.id }) else { return nil }
            return CarImagePickerOption(id: generation.id, name: localized(generation.localizationKey))
        }
    }

    public var trimOptions: [CarImagePickerOption] {
        guard let generation = selectedGeneration else { return [] }
        let validIDs = Set(assetsForGeneration.map(\.trimID))
        return generation.trims.compactMap { trim in
            validIDs.contains(trim.id) ? CarImagePickerOption(id: trim.id, name: localized(trim.localizationKey)) : nil
        }
    }

    public var colorOptions: [CarImagePickerOption] {
        guard let generation = selectedGeneration else { return [] }
        let validIDs = Set(assetsForTrim.map(\.colorID))
        return generation.colors.compactMap { color in
            guard validIDs.contains(color.id) else { return nil }
            return CarImagePickerOption(
                id: color.id,
                name: localized(color.localizationKey),
                swatchHex: Self.swatchHex(for: color.id)
            )
        }
    }

    public var wheelOptions: [CarImagePickerOption] {
        guard let generation = selectedGeneration else { return [] }
        let assets = assetsForColor
        let validIDs = Set(assets.map(\.wheelID))
        return generation.wheels.compactMap { wheel in
            guard validIDs.contains(wheel.id) else { return nil }
            let assetPath = assets.first(where: { $0.wheelID == wheel.id })?.path
            return CarImagePickerOption(id: wheel.id, name: localized(wheel.localizationKey), assetPath: assetPath)
        }
    }

    public var selectedGenerationName: String {
        generationOptions.first(where: { $0.id == selectedGenerationID })?.name ?? text("Unknown")
    }

    public var selectedAssetPath: String? { selectedAsset?.path }
    public var selectedPresentationScale: Double { 1 }
    public var canSave: Bool { selectedAsset != nil && !isSubmitting }

    public func selectGeneration(id: String) {
        guard generationOptions.contains(where: { $0.id == id }) else { return }
        selectedGenerationID = id
        selectedTrimID = ""
        selectedColorID = ""
        selectedWheelID = ""
        normalizeSelection()
    }

    public func selectTrim(id: String) {
        guard trimOptions.contains(where: { $0.id == id }) else { return }
        selectedTrimID = id
        selectedColorID = ""
        selectedWheelID = ""
        normalizeSelection()
    }

    public func selectColor(id: String) {
        guard colorOptions.contains(where: { $0.id == id }) else { return }
        selectedColorID = id
        if !wheelOptions.contains(where: { $0.id == selectedWheelID }) {
            selectedWheelID = wheelOptions.first?.id ?? ""
        }
    }

    public func selectWheel(id: String) {
        guard wheelOptions.contains(where: { $0.id == id }) else { return }
        selectedWheelID = id
    }

    public func save() async {
        guard !isSubmitting, let asset = selectedAsset else { return }
        await submit(VehicleImageOverride(
            generationID: asset.generationID,
            trimID: asset.trimID,
            colorID: asset.colorID,
            wheelID: asset.wheelID,
            assetID: asset.id
        ))
    }

    public func resetToAutomatic() async {
        guard !isSubmitting else { return }
        await submit(nil)
    }

    public func text(_ key: String) -> String {
        Self.text(key, language: language)
    }

    private var selectedGeneration: VehicleGenerationRecord? {
        catalog.generations.first { $0.id == selectedGenerationID }
    }

    private var assetsForGeneration: [VehicleAssetRecord] {
        catalog.preferredAssets.filter { $0.generationID == selectedGenerationID }
    }

    private var assetsForTrim: [VehicleAssetRecord] {
        assetsForGeneration.filter { $0.trimID == selectedTrimID }
    }

    private var assetsForColor: [VehicleAssetRecord] {
        assetsForTrim.filter { $0.colorID == selectedColorID }
    }

    private var selectedAsset: VehicleAssetRecord? {
        assetsForColor.first { $0.wheelID == selectedWheelID }
    }

    private func submit(_ override: VehicleImageOverride?) async {
        isSubmitting = true
        submissionErrorMessage = nil
        do {
            try await saveOverride(override)
            shouldDismiss = true
        } catch {
            submissionErrorMessage = text("Unable to update vehicle image. Please try again.")
        }
        isSubmitting = false
    }

    private func normalizeSelection() {
        if !trimOptions.contains(where: { $0.id == selectedTrimID }) {
            selectedTrimID = trimOptions.first?.id ?? ""
        }
        if !colorOptions.contains(where: { $0.id == selectedColorID }) {
            selectedColorID = colorOptions.first?.id ?? ""
        }
        if !wheelOptions.contains(where: { $0.id == selectedWheelID }) {
            selectedWheelID = wheelOptions.first?.id ?? ""
        }
    }

    private func localized(_ key: String) -> String {
        VehicleImagePickerText.localized(key, language: language)
    }

    private static func text(_ key: String, language: AppLanguage) -> String {
        VehicleImagePickerText.localized(key, language: language)
    }

    private static func confidenceName(_ confidence: VehicleImageConfidence, language: AppLanguage) -> String {
        switch confidence {
        case .exact: text("Exact match", language: language)
        case .inferred: text("Inferred match", language: language)
        case .fallback: text("Fallback match", language: language)
        case .manual: text("Manual match", language: language)
        }
    }

    private static func confidenceExplanation(_ confidence: VehicleImageConfidence, language: AppLanguage) -> String {
        switch confidence {
        case .exact:
            text("Matched directly from the vehicle details.", language: language)
        case .inferred:
            text("Matched from vehicle details with catalog defaults where data was unavailable.", language: language)
        case .fallback:
            text("Using the closest available catalog image.", language: language)
        case .manual:
            text("Using your saved vehicle image configuration.", language: language)
        }
    }

    private static func conflictExplanation(_ conflicts: [VehicleImageConflict], language: AppLanguage) -> String? {
        guard let conflict = conflicts.first else { return nil }
        return switch conflict {
        case .reportedWheelContradictsFactoryTrim:
            text("The reported wheels conflict with the detected factory trim. Choose the configuration that matches your vehicle.", language: language)
        case .invalidManualOverride:
            text("The saved configuration is no longer available. Automatic matching has been restored.", language: language)
        case .modelYearUnavailable:
            text("The model year is unavailable, so the generation was inferred.", language: language)
        case .modelYearOutsideCatalog:
            text("The model year falls outside the catalog range. Check the detected generation.", language: language)
        case .unknownModel:
            text("The vehicle model was not recognized. Choose a catalog generation manually.", language: language)
        }
    }

    private static func swatchHex(for colorID: String) -> String {
        switch colorID {
        case "pearl-white": "#F3F3EF"
        case "stainless": "#8B9197"
        case "deep-blue": "#305F94"
        default: "#777777"
        }
    }
}

public struct CarImagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CarImagePickerViewModel

    public init(viewModel: CarImagePickerViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        List {
            Section(viewModel.text("Detected configuration")) {
                LabeledContent(viewModel.text("Generation")) {
                    Text(verbatim: viewModel.detectedGenerationName)
                }
                LabeledContent(viewModel.text("Trim")) {
                    Text(verbatim: viewModel.detectedTrimName)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: viewModel.detectedConfidenceName)
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: viewModel.confidenceExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)

                if let conflict = viewModel.detectedConflictExplanation {
                    warningLabel(conflict)
                }
            }

            Section(viewModel.text("Manual configuration")) {
                Picker(viewModel.text("Generation"), selection: generationBinding) {
                    ForEach(viewModel.generationOptions) { option in
                        Text(verbatim: option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(viewModel.text("Trim")) {
                Picker(viewModel.text("Trim"), selection: trimBinding) {
                    ForEach(viewModel.trimOptions) { option in
                        Text(verbatim: option.name).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Section(viewModel.text("Color")) {
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        ForEach(viewModel.colorOptions) { option in
                            Button {
                                viewModel.selectColor(id: option.id)
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(PaletteColor(hex: option.swatchHex ?? "#777777").color)
                                        Circle()
                                            .stroke(.secondary.opacity(0.45), lineWidth: 1)
                                        if option.id == viewModel.selectedColorID {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(option.id == "pearl-white" ? .black : .white)
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                    Text(verbatim: option.name)
                                        .font(.caption)
                                        .lineLimit(CarImagePickerLayout.colorLabelLineLimit)
                                        .multilineTextAlignment(.center)
                                        .frame(height: CarImagePickerLayout.colorLabelHeight, alignment: .top)
                                }
                                .frame(width: CarImagePickerLayout.colorOptionWidth)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: option.name))
                            .accessibilityAddTraits(option.id == viewModel.selectedColorID ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Section(viewModel.text("Wheels")) {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(viewModel.wheelOptions) { option in
                            Button {
                                viewModel.selectWheel(id: option.id)
                            } label: {
                                VStack(spacing: 6) {
                                    CarImageView(
                                        assetPath: option.assetPath,
                                        scaleFactor: CGFloat(viewModel.selectedPresentationScale)
                                    )
                                    .frame(width: 128, height: 58)
                                    Text(verbatim: option.name)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 32, alignment: .top)
                                }
                                .frame(width: 144, height: 102)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(option.id == viewModel.selectedWheelID ? Color.accentColor : .secondary.opacity(0.25), lineWidth: option.id == viewModel.selectedWheelID ? 2 : 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: option.name))
                            .accessibilityAddTraits(option.id == viewModel.selectedWheelID ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            if let notice = viewModel.configurationNotice {
                Section {
                    warningLabel(notice)
                }
            }

            if let submissionError = viewModel.submissionErrorMessage {
                Section {
                    Label {
                        Text(verbatim: submissionError)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Label(viewModel.text("Use this configuration"), systemImage: "checkmark.circle.fill")
                        }
                        Spacer()
                    }
                }
                .disabled(!viewModel.canSave)

                Button(role: .cancel) {
                    Task { await viewModel.resetToAutomatic() }
                } label: {
                    HStack {
                        Spacer()
                        Label(viewModel.text("Use automatic match"), systemImage: "wand.and.stars")
                        Spacer()
                    }
                }
                .disabled(viewModel.isSubmitting)
            }
        }
        .navigationTitle(viewModel.text("Vehicle image"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(viewModel.text("Cancel")) { dismiss() }
            }
        }
        .onChange(of: viewModel.shouldDismiss) { _, shouldDismiss in
            if shouldDismiss { dismiss() }
        }
    }

    private var generationBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedGenerationID },
            set: { viewModel.selectGeneration(id: $0) }
        )
    }

    private var trimBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedTrimID },
            set: { viewModel.selectTrim(id: $0) }
        )
    }

    private func warningLabel(_ message: String) -> some View {
        Label {
            Text(verbatim: message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.orange)
    }
}

public enum VehicleImagePickerText {
    public static func localized(_ key: String, language: AppLanguage, bundle: Bundle = .main) -> String {
        let identifier: String
        switch language {
        case .system:
            identifier = Locale.preferredLanguages.first ?? "en"
        case .english:
            identifier = "en"
        case .chinese:
            identifier = "zh-Hans"
        case .traditionalChinese:
            identifier = "zh-Hant"
        case .german:
            identifier = "de"
        case .spanish:
            identifier = "es"
        case .italian:
            identifier = "it"
        case .catalan:
            identifier = "ca"
        }

        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let resource = normalized.hasPrefix("zh-Hant") || normalized.hasPrefix("zh-TW") || normalized.hasPrefix("zh-HK") || normalized.hasPrefix("zh-MO")
            ? "zh-Hant"
            : normalized.hasPrefix("zh") ? "zh-Hans" : String(normalized.split(separator: "-").first ?? "en")
        for candidate in [resource, "en"] {
            guard let path = bundle.path(forResource: candidate, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path)
            else { continue }
            let value = localizedBundle.localizedString(forKey: key, value: key, table: nil)
            if value != key || candidate == "en" { return value }
        }
        return key
    }
}
