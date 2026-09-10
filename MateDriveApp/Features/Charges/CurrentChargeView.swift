import SwiftUI

public struct CurrentChargeView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CurrentChargeViewModel

    private let carId: Int

    public init(carId: Int, viewModel: CurrentChargeViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, !viewModel.state.hasLoadedData {
                LoadingStateView(title: t("Loading current charge", "正在加载当前充电"), showsProgress: true)
            } else if !viewModel.state.hasLoadedData {
                LoadingStateView(
                    title: t("Current Charge Unavailable", "当前充电不可用"),
                    message: viewModel.state.errorMessage.map {
                        UserFacingErrorLocalizer.localized($0, language: appLanguage)
                    },
                    systemImage: "wifi.exclamationmark",
                    retryTitle: t("Try Again", "重试"),
                    retry: {
                        Task { await viewModel.load(carId: carId, forceRefresh: true) }
                    }
                )
            } else if viewModel.state.isChargeStarting {
                statusState(
                    title: t("Charge Starting", "充电正在开始"),
                    message: t("TeslaMate has not published the active charge yet.", "TeslaMate 还没有发布当前充电数据。"),
                    systemImage: "bolt.badge.clock"
                )
            } else if viewModel.state.isNotCharging, viewModel.state.chargeDetail == nil {
                statusState(
                    title: t("No Active Charge", "当前没有充电"),
                    message: t("The car is not currently charging.", "车辆当前未在充电。"),
                    systemImage: "bolt.slash"
                )
            } else {
                let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let detail = viewModel.state.chargeDetail {
                            HStack(spacing: 8) {
                                if viewModel.state.isRefreshing { ProgressView().controlSize(.small) }
                                Label(lastUpdatedText, systemImage: viewModel.state.isRefreshing ? "arrow.triangle.2.circlepath" : "clock")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            ChargeHeroView(detail: detail, stats: viewModel.state.stats, units: units, isDc: viewModel.state.isDcCharge)
                            ChargeStatsGrid(stats: viewModel.state.stats, units: units)
                            ChargePointChart(points: viewModel.state.chronologicalPoints, units: units)
                        }
                        if let error = viewModel.state.errorMessage {
                            refreshWarning(error)
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await viewModel.load(carId: carId)
                }
            }
        }
        .navigationTitle(t("Current Charge", "当前充电"))
        .accessibilityIdentifier("current_charge_view")
        .task(id: carId) {
            await runRefreshLoop()
        }
    }

    private func runRefreshLoop() async {
        await viewModel.load(
            carId: carId,
            forceRefresh: viewModel.state.hasLoadedData
        )
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: viewModel.automaticRefreshInterval)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await viewModel.load(carId: carId, forceRefresh: true)
        }
    }

    private func statusState(title: String, message: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            LoadingStateView(title: title, message: message, systemImage: systemImage)
            if let error = viewModel.state.errorMessage {
                refreshWarning(error)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func refreshWarning(_ error: String) -> some View {
        Label(
            UserFacingErrorLocalizer.localized(error, language: appLanguage),
            systemImage: "exclamationmark.triangle"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .accessibilityIdentifier("current_charge_refresh_warning")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private var lastUpdatedText: String {
        guard let date = viewModel.state.lastUpdatedAt else { return t("Waiting for live data", "正在等待实时数据") }
        let time = date.formatted(date: .omitted, time: .standard)
        return t("Updated \(time)", "更新于 \(time)")
    }
}
