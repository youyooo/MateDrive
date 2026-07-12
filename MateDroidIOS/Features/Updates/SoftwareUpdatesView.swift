import SwiftUI

public struct SoftwareUpdatesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @StateObject private var viewModel: SoftwareUpdatesViewModel
    @State private var hasLoaded = false

    private let carId: Int

    public init(carId: Int, viewModel: SoftwareUpdatesViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading updates", "正在加载软件更新"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        filters
                        summary
                        chart
                        rows
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Updates", "软件更新"))
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var filters: some View {
        Picker(t("Range", "范围"), selection: Binding(
            get: { viewModel.state.filterMonths ?? 0 },
            set: { viewModel.setFilter(months: $0 == 0 ? nil : $0) }
        )) {
            Text(t("All Time", "全部")).tag(0)
            Text(t("6 Months", "6 个月")).tag(6)
            Text(t("Year", "一年")).tag(12)
        }
        .pickerStyle(.segmented)
    }

    private var summary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Updates", "更新"), value: "\(viewModel.state.stats.totalUpdates)", systemImage: "arrow.down.circle")
            MetricCard(title: t("Average Gap", "平均间隔"), value: daysText(Int(viewModel.state.stats.meanDaysBetweenUpdates.rounded())), systemImage: "calendar")
            MetricCard(title: t("Newest", "最新"), value: viewModel.state.stats.newestVersion ?? "--", systemImage: "sparkles")
            MetricCard(title: t("Oldest", "最旧"), value: viewModel.state.stats.oldestVersion ?? "--", systemImage: "clock.arrow.circlepath")
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Updates per Month", "每月更新"))
                .font(.headline)
            HStack(alignment: .bottom, spacing: 5) {
                let maxCount = max(viewModel.state.monthlyData.map(\.count).max() ?? 1, 1)
                ForEach(viewModel.state.monthlyData) { point in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.tint)
                        .frame(height: max(6, CGFloat(point.count) / CGFloat(maxCount) * 110))
                        .help("\(point.month): \(point.count)")
                }
            }
            .frame(height: 120)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if viewModel.state.updates.isEmpty {
                LoadingStateView(title: t("No software updates found", "未找到软件更新记录"), systemImage: "shippingbox")
            } else {
                ForEach(viewModel.state.updates) { update in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(update.version)
                                .font(.body.weight(.semibold))
                            Spacer()
                            if update.id == viewModel.state.longestInstalledId {
                                Text(t("Longest", "最长"))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                                    .foregroundStyle(.orange)
                            } else if update.isCurrent {
                                Text(t("Current", "当前"))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.green.opacity(0.18)))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(update.installDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? unknownInstallDateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let days = update.daysInstalled {
                            Text(daysInstalledText(days))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
                }
            }
        }
    }

    private var unknownInstallDateText: String {
        SoftwareUpdateTextFormatter.unknownInstallDate(language: appLanguage)
    }

    private func daysText(_ days: Int) -> String {
        SoftwareUpdateTextFormatter.days(days, language: appLanguage)
    }

    private func daysInstalledText(_ days: Int) -> String {
        SoftwareUpdateTextFormatter.daysInstalled(days, language: appLanguage)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

enum SoftwareUpdateTextFormatter {
    static func unknownInstallDate(language: AppLanguage) -> String {
        AppText.localized("Unknown install date", "安装日期未知", language: language)
    }

    static func days(_ value: Int, language: AppLanguage) -> String {
        String(format: AppText.localized("%d days", "%d 天", language: language), value)
    }

    static func daysInstalled(_ value: Int, language: AppLanguage) -> String {
        String(format: AppText.localized("%d days installed", "已安装 %d 天", language: language), value)
    }
}
