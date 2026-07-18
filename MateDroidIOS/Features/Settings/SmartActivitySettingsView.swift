import SwiftUI

public struct SmartActivityTariffCatalogStatus: Equatable, Sendable {
    public let version: Int
    public let generatedAt: String
    public let regionCount: Int
    public let verifiedRegionCount: Int
    public let sourceCount: Int

    public init(
        version: Int,
        generatedAt: String,
        regionCount: Int,
        verifiedRegionCount: Int,
        sourceCount: Int
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.regionCount = regionCount
        self.verifiedRegionCount = verifiedRegionCount
        self.sourceCount = sourceCount
    }
}

public enum SmartActivityMaintenanceAction: Equatable, Sendable {
    case rebuildDerivedActivities
    case clearLearnedSuggestions
}

public enum SmartActivityMaintenanceResult: Equatable, Sendable {
    case rebuilt(completedCarCount: Int, failedCarCount: Int)
    case learnedSuggestionsCleared
    case failed(String)
}

@MainActor
public final class SmartActivitySettingsModel: ObservableObject {
    @Published public private(set) var catalogStatus: SmartActivityTariffCatalogStatus?
    @Published public private(set) var catalogRegions: [RegionalChargingTariffRegion] = []
    @Published public private(set) var catalogError: String?
    @Published public private(set) var pendingConfirmation: SmartActivityMaintenanceAction?
    @Published public private(set) var isPerformingMaintenance = false
    @Published public private(set) var lastResult: SmartActivityMaintenanceResult?

    private let indexer: any SmartActivityIndexing
    private let labelStore: any ActivityLabelOverrideStoring
    private let pricingObservationStore: any ChargePricingObservationStoring
    private let carIds: @Sendable () -> [Int]
    private let catalogProvider: @Sendable () throws -> RegionalChargingTariffCatalog

    public init(
        indexer: any SmartActivityIndexing,
        labelStore: any ActivityLabelOverrideStoring,
        pricingObservationStore: any ChargePricingObservationStoring,
        carIds: @escaping @Sendable () -> [Int],
        catalogProvider: @escaping @Sendable () throws -> RegionalChargingTariffCatalog = {
            try RegionalChargingTariffCatalog.load()
        }
    ) {
        self.indexer = indexer
        self.labelStore = labelStore
        self.pricingObservationStore = pricingObservationStore
        self.carIds = carIds
        self.catalogProvider = catalogProvider
        refreshCatalogStatus()
    }

    public func refreshCatalogStatus() {
        do {
            let catalog = try catalogProvider()
            catalogRegions = catalog.regions.sorted { $0.regionCode < $1.regionCode }
            let sourceURLs = Set(
                catalog.regions
                    .flatMap(\.tariffs)
                    .map { $0.sourceURL.absoluteString }
            )
            catalogStatus = SmartActivityTariffCatalogStatus(
                version: catalog.version,
                generatedAt: catalog.generatedAt,
                regionCount: catalog.regions.count,
                verifiedRegionCount: catalog.regions.filter { $0.availability == .verified }.count,
                sourceCount: sourceURLs.count
            )
            catalogError = nil
        } catch {
            catalogRegions = []
            catalogStatus = nil
            catalogError = error.localizedDescription
        }
    }

    public func requestConfirmation(for action: SmartActivityMaintenanceAction) {
        guard !isPerformingMaintenance else { return }
        pendingConfirmation = action
    }

    public func cancelConfirmation() {
        pendingConfirmation = nil
    }

    public func confirmPendingAction() async {
        guard let action = pendingConfirmation, !isPerformingMaintenance else { return }
        pendingConfirmation = nil
        isPerformingMaintenance = true
        defer { isPerformingMaintenance = false }

        do {
            switch action {
            case .rebuildDerivedActivities:
                try await indexer.removeDerivedData()
                let report = await indexer.rebuild(carIds: carIds())
                lastResult = .rebuilt(
                    completedCarCount: report.completedCarIds.count,
                    failedCarCount: report.failedCarIds.count
                )
            case .clearLearnedSuggestions:
                try await labelStore.removeAll()
                try await pricingObservationStore.removeAll()
                lastResult = .learnedSuggestionsCleared
            }
        } catch {
            lastResult = .failed(error.localizedDescription)
        }
    }
}

@MainActor
public struct SmartActivitySettingsView<GeofenceDestination: View, ChargePricingDestination: View>: View {
    @ObservedObject private var settingsViewModel: SettingsViewModel
    @StateObject private var model: SmartActivitySettingsModel
    private let geofenceDestination: () -> GeofenceDestination
    private let chargePricingDestination: () -> ChargePricingDestination

    public init(
        settingsViewModel: SettingsViewModel,
        indexer: any SmartActivityIndexing,
        labelStore: any ActivityLabelOverrideStoring,
        pricingObservationStore: any ChargePricingObservationStoring,
        carIds: @escaping @Sendable () -> [Int],
        catalogProvider: @escaping @Sendable () throws -> RegionalChargingTariffCatalog = {
            try RegionalChargingTariffCatalog.load()
        },
        @ViewBuilder geofenceDestination: @escaping () -> GeofenceDestination,
        @ViewBuilder chargePricingDestination: @escaping () -> ChargePricingDestination
    ) {
        self.settingsViewModel = settingsViewModel
        _model = StateObject(wrappedValue: SmartActivitySettingsModel(
            indexer: indexer,
            labelStore: labelStore,
            pricingObservationStore: pricingObservationStore,
            carIds: carIds,
            catalogProvider: catalogProvider
        ))
        self.geofenceDestination = geofenceDestination
        self.chargePricingDestination = chargePricingDestination
    }

    public var body: some View {
        Form {
            Section(t("Rules", "规则")) {
                NavigationLink(destination: geofenceDestination) {
                    Label(t("Geofences", "地理围栏"), systemImage: "mappin.and.ellipse")
                }
                NavigationLink(destination: chargePricingDestination) {
                    Label(t("Charging Prices", "充电价格"), systemImage: "bolt.badge.clock")
                }
            }

            Section(t("Residential Tariff", "住宅电价")) {
                Picker(t("Region", "地区"), selection: tariffRegionBinding) {
                    Text(t("Not configured", "未设置")).tag(String?.none)
                    ForEach(model.catalogRegions, id: \.regionCode) { region in
                        Text(regionName(region)).tag(Optional(region.regionCode))
                    }
                }

                if let status = model.catalogStatus {
                    LabeledContent(t("Catalog Version", "目录版本"), value: "v\(status.version)")
                    LabeledContent(t("Generated", "生成日期"), value: status.generatedAt)
                    LabeledContent(
                        t("Verified Regions", "已核验地区"),
                        value: "\(status.verifiedRegionCount)/\(status.regionCount)"
                    )
                    Label(
                        status.sourceCount > 0
                            ? t("Official source references are available.", "已包含官方来源引用。")
                            : t("No source references are available.", "暂无来源引用。"),
                        systemImage: status.sourceCount > 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(status.sourceCount > 0 ? .green : .orange)
                } else if let error = model.catalogError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section(t("Maintenance", "维护")) {
                Button {
                    model.requestConfirmation(for: .rebuildDerivedActivities)
                } label: {
                    Label(t("Rebuild Derived Activities", "重建派生动态"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.isPerformingMaintenance)

                Button(role: .destructive) {
                    model.requestConfirmation(for: .clearLearnedSuggestions)
                } label: {
                    Label(t("Clear Learned Suggestions", "清除学习建议"), systemImage: "brain.head.profile")
                }
                .disabled(model.isPerformingMaintenance)

                if model.isPerformingMaintenance {
                    ProgressView(t("Working", "正在处理"))
                }
                if let result = model.lastResult {
                    resultLabel(result)
                }
            }
        }
        .navigationTitle(t("Smart Activities", "智能动态"))
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationPresented,
            titleVisibility: .visible
        ) {
            Button(confirmationButtonTitle, role: .destructive) {
                Task { await model.confirmPendingAction() }
            }
            Button(t("Cancel", "取消"), role: .cancel) {
                model.cancelConfirmation()
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var tariffRegionBinding: Binding<String?> {
        Binding(
            get: { settingsViewModel.settings.homeTariffRegionCode },
            set: { regionCode in
                Task { await settingsViewModel.saveHomeTariffRegionCode(regionCode) }
            }
        )
    }

    private var confirmationPresented: Binding<Bool> {
        Binding(
            get: { model.pendingConfirmation != nil },
            set: { isPresented in
                if !isPresented { model.cancelConfirmation() }
            }
        )
    }

    private var confirmationTitle: String {
        switch model.pendingConfirmation {
        case .rebuildDerivedActivities:
            return t("Rebuild derived activities?", "重建派生动态？")
        case .clearLearnedSuggestions:
            return t("Clear learned suggestions?", "清除学习建议？")
        case nil:
            return ""
        }
    }

    private var confirmationButtonTitle: String {
        switch model.pendingConfirmation {
        case .rebuildDerivedActivities:
            return t("Rebuild", "重建")
        case .clearLearnedSuggestions:
            return t("Clear", "清除")
        case nil:
            return t("Confirm", "确认")
        }
    }

    private var confirmationMessage: String {
        switch model.pendingConfirmation {
        case .rebuildDerivedActivities:
            return t(
                "Only derived activity sessions will be removed and regenerated. Original activities, charges, and drives stay unchanged.",
                "仅删除并重新生成派生动态，原始动态、充电和行程数据不会改变。"
            )
        case .clearLearnedSuggestions:
            return t(
                "Confirmed place-label rules and charging price observations will be removed. Original activities, charges, and drives stay unchanged.",
                "将清除已学习的地点标签规则和充电价格观察，原始动态、充电和行程数据不会改变。"
            )
        case nil:
            return ""
        }
    }

    @ViewBuilder
    private func resultLabel(_ result: SmartActivityMaintenanceResult) -> some View {
        switch result {
        case let .rebuilt(completedCarCount, failedCarCount):
            Label(
                t(
                    "Rebuilt \(completedCarCount) vehicles; \(failedCarCount) failed.",
                    "已重建 \(completedCarCount) 辆车，\(failedCarCount) 辆失败。"
                ),
                systemImage: failedCarCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(failedCarCount == 0 ? .green : .orange)
        case .learnedSuggestionsCleared:
            Label(t("Learned suggestions cleared.", "学习建议已清除。"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func regionName(_ region: RegionalChargingTariffRegion) -> String {
        let languageKey: String
        switch settingsViewModel.settings.appLanguage {
        case .chinese: languageKey = "zh-Hans"
        case .traditionalChinese: languageKey = "zh-Hant"
        default: languageKey = "en"
        }
        return region.names[languageKey]
            ?? region.names[languageKey == "zh-Hans" ? "zh" : "en"]
            ?? region.regionCode
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: settingsViewModel.settings.appLanguage)
    }
}
