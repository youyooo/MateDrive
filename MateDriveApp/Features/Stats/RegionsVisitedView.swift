import SwiftUI

public struct RegionsVisitedView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: RegionsVisitedViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let countryName: String
    private let year: Int?

    public init(carId: Int, countryName: String, year: Int?, viewModel: RegionsVisitedViewModel) {
        self.carId = carId
        self.countryName = countryName
        self.year = year
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.regions.isEmpty {
                LoadingStateView(title: t("Loading regions", "正在加载地区"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        sortPicker
                        if viewModel.state.isEnrichingLocations {
                            Label(t("Completing location data", "正在补全位置信息"), systemImage: "location.magnifyingglass")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if let result = viewModel.state.enrichmentResult {
                            enrichmentStatus(result) {
                                Task { await viewModel.retryLocationEnrichment() }
                            }
                        }
                        if let error = viewModel.state.errorMessage, !viewModel.state.regions.isEmpty {
                            Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                        if let error = viewModel.state.errorMessage, viewModel.state.regions.isEmpty {
                            LoadingStateView(title: t("Unable to load regions", "无法加载地区统计"), message: UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                        } else if viewModel.state.regions.isEmpty {
                            LoadingStateView(title: t("No regions recorded", "暂无地区记录"), systemImage: "map")
                        } else {
                            ForEach(viewModel.state.regions) { region in
                                row(region)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Regions", "地区"))
        .accessibilityIdentifier("regions_visited_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId, countryName: countryName, year: year)
        }
    }

    private func enrichmentStatus(_ result: GeographyEnrichmentResult, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(enrichmentText(result))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if result.failedCount > 0 || result.candidateCount > result.locations.count {
                Button(action: retry) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(t("Retry location completion", "重试位置补全"))
            }
        }
    }

    private func enrichmentText(_ result: GeographyEnrichmentResult) -> String {
        if MateDriveUnitFormatter.usesChineseLabels(language: appLanguage) {
            return "已补全 \(result.locations.count) · 缓存 \(result.cachedCount) · 失败 \(result.failedCount)"
        }
        return "Completed \(result.locations.count) · Cached \(result.cachedCount) · Failed \(result.failedCount)"
    }

    private var sortPicker: some View {
        Picker(t("Sort", "排序"), selection: Binding(
            get: { viewModel.state.sortOrder },
            set: { viewModel.setSortOrder($0) }
        )) {
            ForEach(RegionSortOrder.allCases, id: \.self) { order in
                Text(order.title(language: appLanguage)).tag(order)
            }
        }
        .pickerStyle(.menu)
    }

    private func row(_ region: RegionVisitRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(region.regionName)
                    .font(.body.weight(.semibold))
                Text(activityCountText(drives: region.driveCount, charges: region.chargeCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let coverage = GeographyCoveragePresentation.coverageText(
                    driveCount: region.driveCount,
                    missingDriveDistanceCount: region.missingDriveDistanceCount,
                    chargeCount: region.chargeCount,
                    missingChargeEnergyCount: region.missingChargeEnergyCount,
                    language: appLanguage
                ) {
                    Text(coverage).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(GeographyCoveragePresentation.valuePrefix(missingCount: region.missingDriveDistanceCount) + MateDriveUnitFormatter.formatDistance(region.totalDistanceKm, units: viewModel.state.units.resolved(for: appDisplayUnitSystem)))
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(GeographyCoveragePresentation.valuePrefix(missingCount: region.missingChargeEnergyCount) + String(format: "%.1f kWh", region.totalChargeEnergyKwh))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func activityCountText(drives: Int, charges: Int) -> String {
        if MateDriveUnitFormatter.usesChineseLabels(language: appLanguage) {
            return "\(drives) 次行程 · \(charges) 次充电"
        }
        return "\(drives) drives · \(charges) charges"
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

extension RegionSortOrder {
    func title(language: AppLanguage) -> String {
        let chinese: String
        switch self {
        case .firstVisit:
            chinese = "首次到访"
        case .alphabetical:
            return "A-Z"
        case .driveCount:
            chinese = "行程"
        case .distance:
            chinese = "距离"
        case .energy:
            chinese = "能量"
        case .charges:
            chinese = "充电"
        }
        return AppText.localized(rawValue, chinese, language: language)
    }
}
