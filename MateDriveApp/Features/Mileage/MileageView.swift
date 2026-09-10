import SwiftUI

public struct MileageView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: MileageViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let targetDay: String?
    private let navigate: (AppRoute) -> Void
    private let exteriorColor: String?

    public init(carId: Int, exteriorColor: String?, targetDay: String?, viewModel: MileageViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.targetDay = targetDay
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.years.isEmpty {
                LoadingStateView(title: t("Loading mileage", "正在加载里程"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let errorMessage = viewModel.state.errorMessage {
                            Label(
                                UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage),
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                        overview
                        years
                        if !viewModel.state.months.isEmpty {
                            months
                        }
                        if !viewModel.state.days.isEmpty {
                            days
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle(t("Mileage", "里程"))
        .accessibilityIdentifier("mileage_view")
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
            if let targetDay {
                selectTargetDay(targetDay)
            }
        }
    }

    private var overview: some View {
        let distance = viewModel.state.years.reduce(0) { $0 + $1.distance }
        let distanceRecords = viewModel.state.years.reduce(0) { $0 + $1.distanceRecordCount }
        let drives = viewModel.state.years.reduce(0) { $0 + $1.driveCount }
        let distanceIsComplete = distanceRecords == drives
        let yearlyEnergy = viewModel.state.years.compactMap(\.energy)
        let energy = yearlyEnergy.count == viewModel.state.years.count ? yearlyEnergy.reduce(0, +) : nil
        let energyIsComplete = energy != nil && viewModel.state.years.allSatisfy(\.energyIsComplete)
        let costValues = viewModel.state.years.compactMap(\.energyCost)
        let cost = costValues.isEmpty ? nil : costValues.reduce(0, +)
        let pricedCharges = viewModel.state.years.reduce(0) { $0 + $1.pricedChargeCount }
        let charges = viewModel.state.years.reduce(0) { $0 + $1.chargeCount }
        let costIsComplete = pricedCharges == charges
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(title: t("Lifetime", "累计"), value: MileagePresentation.distanceText(distance, isComplete: distanceIsComplete, units: resolvedUnits), subtitle: distanceCoverageText(known: distanceRecords, total: drives), systemImage: "road.lanes")
            MetricCard(title: t("Drives", "行程"), value: "\(drives)", systemImage: "number")
            MetricCard(title: t("Energy", "能量"), value: energyText(energy, isComplete: energyIsComplete), systemImage: "bolt.fill")
            MetricCard(title: t("Average", "平均"), value: distanceRecords > 0 ? MileagePresentation.distanceText(distance / Double(distanceRecords), isComplete: distanceIsComplete, units: resolvedUnits) : "--", systemImage: "chart.bar")
            MetricCard(title: t("Known Cost", "已知费用"), value: costText(cost, isComplete: costIsComplete), subtitle: costCoverageText(priced: pricedCharges, total: charges), systemImage: "creditcard")
        }
    }

    private var years: some View {
        section(title: t("Mileage by Year", "按年里程"), items: viewModel.state.years) { item in
            Button {
                viewModel.selectYear(item.year)
            } label: {
                mileageRow(title: "\(item.year)", driveCount: item.driveCount, distance: item.distance, distanceIsComplete: item.distanceIsComplete, distanceRecordCount: item.distanceRecordCount, energy: item.energy, energyIsComplete: item.energyIsComplete, cost: item.energyCost, costIsComplete: item.energyCostIsComplete, pricedCharges: item.pricedChargeCount, charges: item.chargeCount)
            }
            .buttonStyle(.plain)
        }
    }

    private var months: some View {
        section(title: t("Mileage by Month", "按月里程"), items: viewModel.state.months) { item in
            Button {
                viewModel.selectMonth(item.yearMonth)
            } label: {
                mileageRow(title: item.yearMonth, driveCount: item.driveCount, distance: item.distance, distanceIsComplete: item.distanceIsComplete, distanceRecordCount: item.distanceRecordCount, energy: item.energy, energyIsComplete: item.energyIsComplete, cost: item.energyCost, costIsComplete: item.energyCostIsComplete, pricedCharges: item.pricedChargeCount, charges: item.chargeCount)
            }
            .buttonStyle(.plain)
        }
    }

    private var days: some View {
        section(title: t("Mileage by Day", "按日里程"), items: viewModel.state.days) { item in
            VStack(alignment: .leading, spacing: 8) {
                mileageRow(title: item.date, driveCount: item.driveCount, distance: item.distance, distanceIsComplete: item.distanceIsComplete, distanceRecordCount: item.distanceRecordCount, energy: item.energy, energyIsComplete: item.energyIsComplete, cost: item.energyCost, costIsComplete: item.energyCostIsComplete, pricedCharges: item.pricedChargeCount, charges: item.chargeCount)
                ForEach(item.drives) { drive in
                    Button {
                        if let driveId = drive.driveId {
                            navigate(.driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor))
                        }
                    } label: {
                        HStack {
                            routeText(drive)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(MileagePresentation.distanceText(drive.distance, isComplete: drive.distance != nil, units: resolvedUnits))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }

    private func section<Item: Identifiable, Content: View>(title: String, items: [Item], @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: title)
                .font(.headline)
            if items.isEmpty {
                LoadingStateView(title: t("No mileage data", "暂无里程数据"), systemImage: "speedometer")
            } else {
                ForEach(items) { item in
                    content(item)
                }
            }
        }
    }

    private func mileageRow(title: String, driveCount: Int, distance: Double, distanceIsComplete: Bool, distanceRecordCount: Int, energy: Double?, energyIsComplete: Bool, cost: Double?, costIsComplete: Bool, pricedCharges: Int, charges: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                driveCountText(driveCount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(MileagePresentation.distanceText(distance, isComplete: distanceIsComplete, units: resolvedUnits))
                    .font(.body.weight(.semibold).monospacedDigit())
                if let coverage = distanceCoverageText(known: distanceRecordCount, total: driveCount) {
                    Text(coverage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(energyText(energy, isComplete: energyIsComplete))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if charges > 0 {
                    Text(verbatim: "\(costText(cost, isComplete: costIsComplete)) · \(costCoverageText(priced: pricedCharges, total: charges))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func selectTargetDay(_ day: String) {
        guard let year = Int(day.prefix(4)) else { return }
        viewModel.selectYear(year)
        viewModel.selectMonth(String(day.prefix(7)))
        viewModel.selectDay(day)
    }

    private func driveCountText(_ count: Int) -> Text {
        if MateDriveUnitFormatter.usesChineseLabels(language: appLanguage) {
            return Text(verbatim: "\(count) 次行程")
        }
        return Text(verbatim: "\(count) drives")
    }

    private func routeText(_ drive: DriveData) -> Text {
        let start = cleanedAddress(drive.startAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("Start", "开始"))
        let end = cleanedAddress(drive.endAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("End", "结束"))
        return start + Text(" → ") + end
    }

    private func cleanedAddress(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private var resolvedUnits: UnitPreferences? {
        viewModel.state.units.resolved(for: appDisplayUnitSystem)
    }

    private func distanceCoverageText(known: Int, total: Int) -> String? {
        guard known < total else { return nil }
        return t("Distance coverage \(known)/\(total)", "里程覆盖 \(known)/\(total)")
    }

    private func energyText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + String(format: "%.1f kWh", $0) } ?? "--"
    }

    private func costText(_ value: Double?, isComplete: Bool) -> String {
        value.map { (isComplete ? "" : "≥") + viewModel.state.currencySymbol + String(format: "%.2f", $0) } ?? "--"
    }

    private func costCoverageText(priced: Int, total: Int) -> String {
        t("Cost coverage \(priced)/\(total)", "费用覆盖 \(priced)/\(total)")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum MileagePresentation {
    public static func distanceText(_ value: Double?, isComplete: Bool, units: UnitPreferences?) -> String {
        value.map { (isComplete ? "" : "≥") + MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }
}
