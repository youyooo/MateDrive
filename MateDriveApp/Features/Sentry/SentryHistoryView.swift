import SwiftUI

public struct SentryHistoryView: View {
    @Environment(\.appLanguage) private var appLanguage
    @StateObject private var viewModel: SentryHistoryViewModel
    @State private var hasLoaded = false

    private let carId: Int

    public init(carId: Int, viewModel: SentryHistoryViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, !viewModel.state.hasLoadedData {
                LoadingStateView(title: t("Loading sentry history", "正在加载哨兵记录"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, !viewModel.state.hasLoadedData {
                LoadingStateView(
                    title: t("Sentry history unavailable", "哨兵记录不可用"),
                    message: UserFacingErrorLocalizer.localized(error, language: appLanguage),
                    systemImage: "shield.slash",
                    retryTitle: t("Try Again", "重试"),
                    retry: { Task { await viewModel.load(carId: carId) } }
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(error, language: appLanguage),
                                systemImage: "wifi.exclamationmark"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("sentry_history_refresh_warning")
                        }
                        sessionSummary
                        heatmap
                        alertGroups
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle(t("Sentry", "哨兵"))
        .accessibilityIdentifier("sentry_history_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var sessionSummary: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(
                title: t("Session", "当前会话"),
                value: DashboardTextFormatter.sessionValue(isActive: viewModel.state.isSessionActive, language: appLanguage),
                systemImage: "shield.lefthalf.filled"
            )
            MetricCard(title: t("Current Alerts", "当前警报"), value: "\(viewModel.state.currentSessionAlerts.count)", systemImage: "bell.badge")
            MetricCard(title: t("History", "历史"), value: "\(viewModel.state.pastAlertsByDay.flatMap(\.alerts).count)", systemImage: "clock.arrow.circlepath")
        }
    }

    private var heatmap: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Last 6 Days", "最近 6 天"))
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 12), spacing: 4) {
                let maxCount = max(viewModel.state.heatmapCounts.max() ?? 1, 1)
                ForEach(Array(viewModel.state.heatmapCounts.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.red.opacity(count == 0 ? 0.12 : 0.25 + 0.65 * (Double(count) / Double(maxCount))))
                        .frame(height: 16)
                }
            }
        }
    }

    private var alertGroups: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !viewModel.state.currentSessionAlerts.isEmpty {
                alertSection(title: t("Current Session", "当前会话"), alerts: viewModel.state.currentSessionAlerts)
            }
            if viewModel.state.pastAlertsByDay.isEmpty && viewModel.state.currentSessionAlerts.isEmpty {
                LoadingStateView(title: t("No sentry alerts recorded", "暂无哨兵警报记录"), systemImage: "shield")
            } else {
                ForEach(viewModel.state.pastAlertsByDay) { group in
                    alertSection(title: group.date.formatted(date: .abbreviated, time: .omitted), alerts: group.alerts)
                }
            }
        }
    }

    private func alertSection(title: String, alerts: [SentryAlertRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.locationText)
                            .font(.body.weight(.semibold))
                        Text(alert.detectedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            }
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
