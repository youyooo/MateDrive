import SwiftUI

public struct CurrentChargeView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CurrentChargeViewModel
    @State private var hasLoaded = false

    private let carId: Int

    public init(carId: Int, viewModel: CurrentChargeViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading current charge", "正在加载当前充电"), showsProgress: true)
            } else if viewModel.state.isChargeStarting {
                LoadingStateView(
                    title: t("Charge Starting", "充电正在开始"),
                    message: t("TeslaMate has not published the active charge yet.", "TeslaMate 还没有发布当前充电数据。"),
                    systemImage: "bolt.badge.clock"
                )
            } else if viewModel.state.isNotCharging, viewModel.state.chargeDetail == nil {
                LoadingStateView(
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
                            Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
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
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await viewModel.load(carId: carId)
            }
        }
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
