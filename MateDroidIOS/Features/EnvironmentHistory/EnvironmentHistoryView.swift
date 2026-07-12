import Charts
import SwiftUI

public struct EnvironmentHistoryView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: EnvironmentHistoryViewModel
    @State private var selectedTemperatureDate: Date?
    @State private var selectedPressureDate: Date?
    private let carId: Int

    public init(carId: Int, viewModel: EnvironmentHistoryViewModel) {
        self.carId = carId
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading, viewModel.state.response == nil {
                LoadingStateView(title: t("Loading environment history", "正在加载环境历史"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.response == nil {
                LoadingStateView(title: t("Environment history unavailable", "环境历史不可用"), message: error, systemImage: "thermometer.variable.and.figure")
            } else {
                content
            }
        }
        .navigationTitle(t("Environment History", "环境与胎压"))
        .task { await viewModel.load(carId: carId) }
        .refreshable { await viewModel.load(carId: carId) }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                rangePicker
                if let response = viewModel.state.response {
                    if let error = viewModel.state.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if viewModel.datedPoints.isEmpty {
                        Label(t("No timestamped environment samples in this range", "此范围内没有带时间的环境采样"), systemImage: "chart.line.downtrend.xyaxis")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    summary(response)
                    temperatureChart(response)
                    pressureChart(response)
                    energyChart(response)
                    leakSection(response)
                    dataQuality(response)
                }
            }
            .padding(16)
        }
    }

    private var rangePicker: some View {
        Picker(t("Range", "范围"), selection: Binding(
            get: { viewModel.state.range },
            set: { range in Task { await viewModel.select(range, carId: carId) } }
        )) {
            ForEach(EnvironmentHistoryRange.allCases) { range in
                Text(rangeTitle(range)).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .disabled(viewModel.state.isLoading)
    }

    private func summary(_ response: EnvironmentHistoryResponse) -> some View {
        let units = resolvedUnits(response)
        return VStack(alignment: .leading, spacing: 10) {
            Text(t("Overview", "概览")).font(.headline)
            HStack(spacing: 10) {
                summaryMetric(t("Data Points", "数据点"), "\(response.data.summary?.pointCount ?? response.data.series.count)", "chart.xyaxis.line")
                summaryMetric(t("Samples", "采样数"), response.data.summary?.sampleCount.map(String.init) ?? "--", "dot.scope")
            }
            HStack(spacing: 10) {
                summaryMetric(t("Lowest", "最低胎压"), response.data.summary?.lowestPressure?.value.map { MateDroidUnitFormatter.formatPressure(pressureBar($0, response: response), units: units) } ?? "--", "tirepressure")
                summaryMetric(t("Avg Outside", "平均车外"), response.data.summary?.averageOutsideTemp.map { MateDroidUnitFormatter.formatTemperature(temperatureCelsius($0, response: response), units: units, decimals: 1) } ?? "--", "thermometer.medium")
            }
        }
    }

    private func summaryMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func temperatureChart(_ response: EnvironmentHistoryResponse) -> some View {
        let units = resolvedUnits(response)
        return chartSection(title: t("Temperature", "温度"), subtitle: MateDroidUnitFormatter.temperatureUnit(units: units)) {
            Chart {
                ForEach(viewModel.datedPoints) { point in
                    if let date = point.timestamp, let value = point.outsideTemp {
                        LineMark(x: .value("Time", date), y: .value("Temperature", MateDroidUnitFormatter.temperatureValue(temperatureCelsius(value, response: response), units: units)), series: .value("Series", t("Outside", "车外")))
                            .foregroundStyle(by: .value("Series", t("Outside", "车外"))).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Time", date), y: .value("Temperature", MateDroidUnitFormatter.temperatureValue(temperatureCelsius(value, response: response), units: units)))
                            .foregroundStyle(.blue).symbolSize(18)
                    }
                    if let date = point.timestamp, let value = point.insideTemp {
                        LineMark(x: .value("Time", date), y: .value("Temperature", MateDroidUnitFormatter.temperatureValue(temperatureCelsius(value, response: response), units: units)), series: .value("Series", t("Inside", "车内")))
                            .foregroundStyle(by: .value("Series", t("Inside", "车内"))).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Time", date), y: .value("Temperature", MateDroidUnitFormatter.temperatureValue(temperatureCelsius(value, response: response), units: units)))
                            .foregroundStyle(.green).symbolSize(18)
                    }
                }
                if let point = selectedEnvironmentPoint(for: selectedTemperatureDate), let date = point.timestamp {
                    RuleMark(x: .value(t("Selected", "已选择"), date))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) { temperatureSelection(point, response: response) }
                }
            }
            .chartForegroundStyleScale(domain: [t("Outside", "车外"), t("Inside", "车内")], range: [.blue, .green])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXSelection(value: $selectedTemperatureDate)
        }
    }

    private func pressureChart(_ response: EnvironmentHistoryResponse) -> some View {
        let units = resolvedUnits(response)
        let lines = tireLines
        return chartSection(title: t("Tire Pressure", "胎压"), subtitle: MateDroidUnitFormatter.pressureUnit(units: units)) {
            Chart {
                ForEach(lines) { line in
                    ForEach(viewModel.datedPoints) { point in
                        if let date = point.timestamp, let pressure = line.value(point) {
                            LineMark(x: .value("Time", date), y: .value("Pressure", MateDroidUnitFormatter.pressureValue(pressureBar(pressure, response: response), units: units)), series: .value("Wheel", line.title))
                                .foregroundStyle(by: .value("Wheel", line.title))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Time", date), y: .value("Pressure", MateDroidUnitFormatter.pressureValue(pressureBar(pressure, response: response), units: units)))
                                .foregroundStyle(by: .value("Wheel", line.title))
                                .symbolSize(18)
                        }
                    }
                }
                if let point = selectedEnvironmentPoint(for: selectedPressureDate), let date = point.timestamp {
                    RuleMark(x: .value(t("Selected", "已选择"), date))
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .leading) { pressureSelection(point, response: response) }
                }
            }
            .chartForegroundStyleScale(domain: lines.map(\.title), range: [.blue, .green, .orange, .purple])
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXSelection(value: $selectedPressureDate)
        }
    }

    @ViewBuilder
    private func energyChart(_ response: EnvironmentHistoryResponse) -> some View {
        if !response.data.temperatureEnergyBuckets.isEmpty {
            let units = resolvedUnits(response)
            chartSection(title: t("Temperature and Consumption", "温度与电耗"), subtitle: MateDroidUnitFormatter.efficiencyUnit(units: units)) {
                Chart(response.data.temperatureEnergyBuckets) { bucket in
                    if let from = bucket.temperatureFrom, let to = bucket.temperatureTo, let value = bucket.medianConsumptionWhPerUnit {
                        BarMark(
                            x: .value("Temperature", MateDroidUnitFormatter.temperatureValue(temperatureCelsius((from + to) / 2, response: response), units: units)),
                            y: .value("Consumption", MateDroidUnitFormatter.efficiencyValue(consumptionWhPerKm(value, response: response), units: units))
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func leakSection(_ response: EnvironmentHistoryResponse) -> some View {
        if !response.data.leakObservations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Pressure Change", "胎压变化")).font(.headline)
                Text(t("Server observations compare robust median samples. They are evidence to inspect, not a diagnosis.", "服务端使用中位数采样比较胎压变化。这些结果用于提示检查，并非故障诊断。"))
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(response.data.leakObservations) { item in
                    HStack {
                        Label(wheelTitle(item.wheel), systemImage: "tirepressure")
                        Spacer()
                        Text(item.delta.map { signedPressure($0, response: response) } ?? "--")
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle((item.delta ?? 0) < -0.15 ? .red : .secondary)
                        Text(confidenceTitle(item.confidence)).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func dataQuality(_ response: EnvironmentHistoryResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("Data Quality", "数据质量")).font(.headline)
            Text("\(t("Grain", "粒度")): \(grainTitle(response.data.metadata?.resolvedGrain)) · \(t("Minimum samples", "最低采样数")): \(response.data.metadata?.minSamples.map(String.init) ?? "--")")
            Text(t("Values are server-side medians. Missing samples are omitted and never replaced with zero.", "数值来自服务端中位数；缺失采样会被省略，不会用零代替。"))
        }
        .font(.footnote).foregroundStyle(.secondary)
    }

    private func chartSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.headline); Spacer(); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            content().frame(height: 220)
        }
    }

    private var tireLines: [TireLine] {
        [
            TireLine(id: "fl", title: t("Front Left", "左前"), value: { $0.tpmsPressureFl }),
            TireLine(id: "fr", title: t("Front Right", "右前"), value: { $0.tpmsPressureFr }),
            TireLine(id: "rl", title: t("Rear Left", "左后"), value: { $0.tpmsPressureRl }),
            TireLine(id: "rr", title: t("Rear Right", "右后"), value: { $0.tpmsPressureRr })
        ]
    }

    private func selectedEnvironmentPoint(for date: Date?) -> EnvironmentHistoryPoint? {
        guard let date else { return nil }
        return EnvironmentChartSelection.nearest(to: date, in: viewModel.datedPoints)
    }

    private func temperatureSelection(_ point: EnvironmentHistoryPoint, response: EnvironmentHistoryResponse) -> some View {
        let units = resolvedUnits(response)
        return VStack(alignment: .leading, spacing: 2) {
            if let value = point.outsideTemp { Text(t("Outside", "车外") + " " + MateDroidUnitFormatter.formatTemperature(temperatureCelsius(value, response: response), units: units, decimals: 1)) }
            if let value = point.insideTemp { Text(t("Inside", "车内") + " " + MateDroidUnitFormatter.formatTemperature(temperatureCelsius(value, response: response), units: units, decimals: 1)) }
        }
        .font(.caption2.monospacedDigit()).padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func pressureSelection(_ point: EnvironmentHistoryPoint, response: EnvironmentHistoryResponse) -> some View {
        let units = resolvedUnits(response)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(tireLines) { line in
                if let value = line.value(point) { Text(line.title + " " + MateDroidUnitFormatter.formatPressure(pressureBar(value, response: response), units: units)) }
            }
        }
        .font(.caption2.monospacedDigit()).padding(5).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func resolvedUnits(_ response: EnvironmentHistoryResponse) -> UnitPreferences? {
        UnitPreferences(unitOfLength: response.units?.unitOfLength, unitOfTemperature: response.units?.unitOfTemperature, unitOfPressure: response.units?.unitOfPressure).resolved(for: appDisplayUnitSystem)
    }
    private func rangeTitle(_ range: EnvironmentHistoryRange) -> String { switch range { case .sevenDays: t("7D", "7天"); case .thirtyDays: t("30D", "30天"); case .ninetyDays: t("90D", "90天"); case .oneYear: t("1Y", "1年") } }
    private func wheelTitle(_ value: String?) -> String { switch value { case "front_left": t("Front Left", "左前"); case "front_right": t("Front Right", "右前"); case "rear_left": t("Rear Left", "左后"); case "rear_right": t("Rear Right", "右后"); default: t("Unknown", "未知") } }
    private func confidenceTitle(_ value: String?) -> String { switch value { case "high": t("High", "高"); case "medium": t("Medium", "中"); case "low": t("Low", "低"); default: "--" } }
    private func grainTitle(_ value: String?) -> String { value == "hour" ? t("Hourly", "小时") : value == "day" ? t("Daily", "每日") : "--" }
    private func temperatureCelsius(_ value: Double, response: EnvironmentHistoryResponse) -> Double { response.units?.unitOfTemperature == "F" ? (value - 32) * 5 / 9 : value }
    private func pressureBar(_ value: Double, response: EnvironmentHistoryResponse) -> Double { response.units?.unitOfPressure == "psi" ? value / 14.5038 : value }
    private func consumptionWhPerKm(_ value: Double, response: EnvironmentHistoryResponse) -> Double { response.units?.unitOfLength == "mi" ? value * 0.621371 : value }
    private func signedPressure(_ value: Double, response: EnvironmentHistoryResponse) -> String { let units = resolvedUnits(response); let converted = MateDroidUnitFormatter.pressureValue(pressureBar(value, response: response), units: units); return String(format: "%+.2f %@", converted, MateDroidUnitFormatter.pressureUnit(units: units)) }
    private func t(_ english: String, _ chinese: String) -> String { AppText.localized(english, chinese, language: appLanguage) }
}

public enum EnvironmentChartSelection {
    public static func nearest(to date: Date, in points: [EnvironmentHistoryPoint]) -> EnvironmentHistoryPoint? {
        points.compactMap { point -> (EnvironmentHistoryPoint, Date)? in
            point.timestamp.map { (point, $0) }
        }.min { abs($0.1.timeIntervalSince(date)) < abs($1.1.timeIntervalSince(date)) }?.0
    }
}

private struct TireLine: Identifiable {
    let id: String
    let title: String
    let value: (EnvironmentHistoryPoint) -> Double?
}
