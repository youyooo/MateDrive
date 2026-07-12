import SwiftUI

public struct CompareDrivesView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CompareDrivesViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let baseDriveId: Int

    public init(carId: Int, baseDriveId: Int, viewModel: CompareDrivesViewModel) {
        self.carId = carId
        self.baseDriveId = baseDriveId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Comparing drives", "正在比较行程"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sortPicker
                        average
                        rows
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Compare Drives", "比较行程"))
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId, baseDriveId: baseDriveId)
        }
    }

    private var sortPicker: some View {
        Picker(t("Sort", "排序"), selection: Binding(
            get: { viewModel.state.sort },
            set: { viewModel.setSort($0) }
        )) {
            ForEach(DriveCompareSort.allCases, id: \.self) { sort in
                Text(LocalizedStringKey(sort.rawValue)).tag(sort)
            }
        }
        .pickerStyle(.segmented)
    }

    private var average: some View {
        let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Route Drives", "同路线行程"), value: "\(viewModel.state.average.count)", systemImage: "road.lanes")
            MetricCard(title: t("Avg Duration", "平均时长"), value: DriveDetailPresentation.durationText(viewModel.state.average.durationMin, language: appLanguage), systemImage: "clock")
            MetricCard(title: t("Avg Speed", "平均速度"), value: DriveDetailPresentation.speedText(viewModel.state.average.speedAvg, units: units), systemImage: "speedometer")
            MetricCard(title: t("Avg Efficiency", "平均效率"), value: viewModel.state.average.efficiency.map { MateDroidUnitFormatter.formatEfficiency($0, units: units, decimals: 0) } ?? "--", systemImage: "leaf")
        }
    }

    private var rows: some View {
        let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)

        return VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if viewModel.state.rows.isEmpty {
                LoadingStateView(title: t("No comparable drives", "暂无可比较的行程"), systemImage: "arrow.left.arrow.right")
            } else {
                ForEach(viewModel.state.rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(row.isBase ? t("This Drive", "本次行程") : dateText(row.startDate))
                                .font(.body.weight(.semibold))
                            Spacer()
                            if row.isBase {
                                Text(t("Base", "基准"))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.blue.opacity(0.18)))
                                    .foregroundStyle(.blue)
                            }
                        }
                        routeText(row)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        HStack(spacing: 10) {
                            pill(DriveDetailPresentation.distanceText(row.distance, units: units))
                            pill(DriveDetailPresentation.durationText(row.durationMin, language: appLanguage))
                            pill(DriveDetailPresentation.speedText(row.speedAvg, units: units))
                            if let efficiency = row.efficiency {
                                pill(MateDroidUnitFormatter.formatEfficiency(efficiency, units: units, decimals: 0))
                            }
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(row.isBase ? Color.blue.opacity(0.12) : Color(uiColor: .secondarySystemBackground))
                    )
                }
            }
        }
    }

    private func pill(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemBackground)))
    }

    private func routeText(_ row: ComparableDriveRow) -> Text {
        let start = cleanedAddress(row.startAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("Start", "开始"))
        let end = cleanedAddress(row.endAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("End", "结束"))
        return start + Text(" -> ") + end
    }

    private func cleanedAddress(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func durationText(_ value: Int) -> String {
        MateDroidUnitFormatter.formatDuration(minutes: value, language: appLanguage)
    }

    private func dateText(_ value: String) -> String {
        guard let date = DomainDateParser.date(from: value) else {
            return value
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
