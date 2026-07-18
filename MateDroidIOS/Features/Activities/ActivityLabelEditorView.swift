import Foundation
import SwiftUI

public extension Notification.Name {
    static let activityLabelOverrideDidChange = Notification.Name("ActivityLabelOverrideDidChange")
}

public enum ActivityLabelSemanticColor: String, CaseIterable, Equatable, Identifiable, Sendable {
    case blue
    case green
    case orange
    case indigo
    case pink
    case teal

    public var id: String { rawValue }

    public var colorHex: String {
        switch self {
        case .blue: return "#007AFF"
        case .green: return "#34C759"
        case .orange: return "#FF9500"
        case .indigo: return "#5856D6"
        case .pink: return "#FF2D55"
        case .teal: return "#30B0C7"
        }
    }

    public init(colorHex: String) {
        let normalized = colorHex.uppercased()
        self = Self.allCases.first { $0.colorHex == normalized } ?? .blue
    }
}

public struct ActivityLabelEditorDraft: Equatable, Sendable {
    public var scope: ActivityLabelScope
    public var purpose: SmartActivityPurpose
    public var customName: String
    public var symbolName: String
    public var semanticColor: ActivityLabelSemanticColor
    public var startMinute: Int?
    public var endMinute: Int?

    public init(
        scope: ActivityLabelScope = .sessionOnly,
        purpose: SmartActivityPurpose = .unclassified,
        customName: String = "",
        symbolName: String = SmartActivityPurpose.unclassified.systemImage,
        semanticColor: ActivityLabelSemanticColor = .blue,
        startMinute: Int? = nil,
        endMinute: Int? = nil
    ) {
        self.scope = scope
        self.purpose = purpose
        self.customName = customName
        self.symbolName = symbolName
        self.semanticColor = semanticColor
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public init(override value: ActivityLabelOverride) {
        self.init(
            scope: value.scope,
            purpose: value.purpose,
            customName: value.customName ?? "",
            symbolName: value.icon,
            semanticColor: ActivityLabelSemanticColor(colorHex: value.colorHex),
            startMinute: value.startMinute,
            endMinute: value.endMinute
        )
    }
}

public struct ActivityLabelEditorContext: Equatable, Sendable {
    public let carId: Int
    public let sessionId: String
    public let placeKey: String?

    public init(carId: Int, sessionId: String, placeKey: String?) {
        self.carId = carId
        self.sessionId = sessionId
        self.placeKey = placeKey
    }
}

public enum ActivityLabelEditorValidationError: Error, Equatable, LocalizedError, Sendable {
    case customNameRequired
    case incompleteTimeWindow
    case invalidTimeWindow
    case placeRequired

    public var errorDescription: String? {
        switch self {
        case .customNameRequired:
            return "自定义用途名称不能为空"
        case .incompleteTimeWindow:
            return "开始和结束时间必须同时填写"
        case .invalidTimeWindow:
            return "时间必须在 00:00 至 23:59 之间"
        case .placeRequired:
            return "此地点以后规则需要有效地点"
        }
    }
}

public enum ActivityLabelEditorValidator {
    public static func validate(
        _ draft: ActivityLabelEditorDraft,
        context: ActivityLabelEditorContext
    ) throws {
        if draft.purpose == .custom,
           draft.customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ActivityLabelEditorValidationError.customNameRequired
        }

        if (draft.startMinute == nil) != (draft.endMinute == nil) {
            throw ActivityLabelEditorValidationError.incompleteTimeWindow
        }

        if let startMinute = draft.startMinute,
           let endMinute = draft.endMinute,
           (!(0...1_439).contains(startMinute) || !(0...1_439).contains(endMinute)) {
            throw ActivityLabelEditorValidationError.invalidTimeWindow
        }

        if draft.scope == .futureAtPlace,
           normalized(context.placeKey) == nil {
            throw ActivityLabelEditorValidationError.placeRequired
        }
    }

    public static func makeOverride(
        from draft: ActivityLabelEditorDraft,
        context: ActivityLabelEditorContext,
        replacing existing: ActivityLabelOverride? = nil,
        updatedAt: Date = Date()
    ) throws -> ActivityLabelOverride {
        try validate(draft, context: context)

        let placeKey = draft.scope == .futureAtPlace ? normalized(context.placeKey) : nil
        let sessionId = draft.scope == .sessionOnly ? context.sessionId : nil
        let trimmedName = draft.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = draft.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = trimmedSymbol.isEmpty ? draft.purpose.systemImage : trimmedSymbol

        return ActivityLabelOverride(
            id: existing?.id ?? generatedID(
                context: context,
                scope: draft.scope,
                placeKey: placeKey
            ),
            carId: context.carId,
            sessionId: sessionId,
            placeKey: placeKey,
            scope: draft.scope,
            purpose: draft.purpose,
            customName: draft.purpose == .custom ? trimmedName : nil,
            icon: icon,
            colorHex: draft.semanticColor.colorHex,
            startMinute: draft.startMinute,
            endMinute: draft.endMinute,
            updatedAt: updatedAt
        )
    }

    private static func generatedID(
        context: ActivityLabelEditorContext,
        scope: ActivityLabelScope,
        placeKey: String?
    ) -> String {
        switch scope {
        case .sessionOnly:
            return "activity-label:\(context.carId):session:\(context.sessionId)"
        case .futureAtPlace:
            return "activity-label:\(context.carId):place:\(placeKey ?? "")"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

public struct ActivityLabelEditorView: View {
    private let context: ActivityLabelEditorContext
    private let existingOverride: ActivityLabelOverride?
    private let labelStore: any ActivityLabelOverrideStoring
    private let notificationCenter: NotificationCenter
    private let onSaved: (ActivityLabelOverride) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ActivityLabelEditorDraft
    @State private var isSaving = false
    @State private var saveError: String?

    public init(
        context: ActivityLabelEditorContext,
        existingOverride: ActivityLabelOverride? = nil,
        labelStore: any ActivityLabelOverrideStoring,
        notificationCenter: NotificationCenter = .default,
        onSaved: @escaping (ActivityLabelOverride) -> Void = { _ in }
    ) {
        self.context = context
        self.existingOverride = existingOverride
        self.labelStore = labelStore
        self.notificationCenter = notificationCenter
        self.onSaved = onSaved
        _draft = State(
            initialValue: existingOverride.map { ActivityLabelEditorDraft(override: $0) } ?? .init()
        )
    }

    public var body: some View {
        Form {
            Section("应用范围") {
                Picker("应用范围", selection: $draft.scope) {
                    Text("仅本次").tag(ActivityLabelScope.sessionOnly)
                    Text("此地点以后").tag(ActivityLabelScope.futureAtPlace)
                }
                .pickerStyle(.segmented)

                if draft.scope == .futureAtPlace, normalizedPlaceKey == nil {
                    validationMessage(ActivityLabelEditorValidationError.placeRequired.localizedDescription)
                }
            }

            Section("活动用途") {
                Picker("用途", selection: $draft.purpose) {
                    ForEach(SmartActivityPurpose.allCases, id: \.rawValue) { purpose in
                        Label(purpose.title(language: .chinese), systemImage: purpose.systemImage)
                            .tag(purpose)
                    }
                }

                if draft.purpose == .custom {
                    TextField("自定义名称", text: $draft.customName)
                        .textInputAutocapitalization(.never)
                }

                HStack {
                    Image(systemName: previewSymbol)
                        .frame(width: 28)
                    TextField("SF Symbol", text: $draft.symbolName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Section("颜色") {
                HStack(spacing: 18) {
                    ForEach(ActivityLabelSemanticColor.allCases) { color in
                        Button {
                            draft.semanticColor = color
                        } label: {
                            Circle()
                                .fill(swiftUIColor(color))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if draft.semanticColor == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.rawValue)
                        .accessibilityAddTraits(draft.semanticColor == color ? .isSelected : [])
                    }
                }
            }

            Section("生效时间") {
                Toggle("限制时间段", isOn: timeWindowEnabled)

                if timeWindowEnabled.wrappedValue {
                    minuteStepper("开始", minute: startMinute)
                    minuteStepper("结束", minute: endMinute)
                    Text("支持跨午夜，例如 22:00 至 06:00")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let message = currentValidationMessage ?? saveError {
                Section {
                    validationMessage(message)
                }
            }
        }
        .navigationTitle("编辑活动标签")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("保存")
                    }
                }
                .disabled(isSaving || currentValidationMessage != nil)
            }
        }
        .onChange(of: draft) { _, _ in
            saveError = nil
        }
    }

    private var normalizedPlaceKey: String? {
        guard let value = context.placeKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private var previewSymbol: String {
        let value = draft.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? draft.purpose.systemImage : value
    }

    private var currentValidationMessage: String? {
        do {
            try ActivityLabelEditorValidator.validate(draft, context: context)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var timeWindowEnabled: Binding<Bool> {
        Binding(
            get: { draft.startMinute != nil || draft.endMinute != nil },
            set: { enabled in
                if enabled {
                    draft.startMinute = draft.startMinute ?? 0
                    draft.endMinute = draft.endMinute ?? 1_439
                } else {
                    draft.startMinute = nil
                    draft.endMinute = nil
                }
            }
        )
    }

    private var startMinute: Binding<Int> {
        Binding(
            get: { draft.startMinute ?? 0 },
            set: { draft.startMinute = $0 }
        )
    }

    private var endMinute: Binding<Int> {
        Binding(
            get: { draft.endMinute ?? 1_439 },
            set: { draft.endMinute = $0 }
        )
    }

    private func minuteStepper(_ title: String, minute: Binding<Int>) -> some View {
        Stepper(value: minute, in: 0...1_439, step: 15) {
            LabeledContent(title, value: formattedMinute(minute.wrappedValue))
        }
    }

    private func formattedMinute(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    @ViewBuilder
    private func validationMessage(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
            .accessibilityLabel(message)
    }

    private func swiftUIColor(_ color: ActivityLabelSemanticColor) -> Color {
        switch color {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .indigo: return .indigo
        case .pink: return .pink
        case .teal: return .teal
        }
    }

    private func save() {
        saveError = nil
        isSaving = true

        Task { @MainActor in
            do {
                let value = try ActivityLabelEditorValidator.makeOverride(
                    from: draft,
                    context: context,
                    replacing: existingOverride
                )
                try await labelStore.save(value)

                var userInfo: [String: Any] = [
                    "carId": value.carId,
                    "sessionId": context.sessionId
                ]
                if let placeKey = value.placeKey {
                    userInfo["placeKey"] = placeKey
                }
                notificationCenter.post(
                    name: .activityLabelOverrideDidChange,
                    object: nil,
                    userInfo: userInfo
                )
                onSaved(value)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
