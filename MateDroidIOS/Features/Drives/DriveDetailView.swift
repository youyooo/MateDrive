import Charts
import MapKit
import SwiftUI
import UniformTypeIdentifiers

public struct DriveDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DriveDetailViewModel
    @State private var hasLoaded = false
    @State private var confirmsTripRemoval = false
    @State private var editsAnnotation = false
    @State private var exportDocument: DriveCSVDocument?
    @State private var exportsCSV = false
    @State private var exportError: String?

    private let carId: Int
    private let driveId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, driveId: Int, exteriorColor: String?, viewModel: DriveDetailViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.driveId = driveId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading drive", "正在加载行程"), showsProgress: true)
            } else if let detail = viewModel.state.driveDetail {
                let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        DriveHeroView(detail: detail, stats: viewModel.state.stats, units: units)
                        DriveRouteReplayView(detail: detail, units: units)
                        DriveStatsGrid(stats: viewModel.state.stats, units: units) { metric in
                            navigate(.driveMetricDetail(carId: carId, driveId: driveId, metric: metric, exteriorColor: exteriorColor))
                        }
                        annotationSection
                        tripMembershipSection
                        WeatherAlongTheWayView(points: viewModel.state.weatherPoints, units: units, isLoading: viewModel.state.isLoadingWeather)
                        DrivePositionCharts(detail: detail, units: units)
                    }
                    .padding(16)
                }
            } else {
                LoadingStateView(title: t("Drive unavailable", "行程不可用"), message: viewModel.state.errorMessage, systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle(t("Drive Detail", "行程详情"))
        .confirmationDialog(t("Remove from trip?", "从路程中移除？"), isPresented: $confirmsTripRemoval, titleVisibility: .visible) {
            Button(t("Remove", "移除"), role: .destructive) { Task { await viewModel.removeFromTrip(carId: carId, driveId: driveId) } }
            Button(t("Cancel", "取消"), role: .cancel) {}
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        navigate(.compareDrives(carId: carId, baseDriveId: driveId, exteriorColor: exteriorColor))
                    } label: { Label(t("Compare", "比较"), systemImage: "arrow.left.arrow.right") }
                    Button { editsAnnotation = true } label: { Label(t("Edit Classification", "编辑分类"), systemImage: "tag") }
                    Button { prepareExport() } label: { Label(t("Export CSV", "导出表格"), systemImage: "square.and.arrow.up") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(t("Drive Actions", "行程操作"))
            }
        }
        .sheet(isPresented: $editsAnnotation) {
            NavigationStack {
                DriveAnnotationEditor(annotation: viewModel.state.annotation) { annotation in
                    Task { await viewModel.saveAnnotation(carId: carId, driveId: driveId, annotation: annotation) }
                    editsAnnotation = false
                }
            }
            .environment(\.appLanguage, appLanguage)
        }
        .fileExporter(
            isPresented: $exportsCSV,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "MateDrive-drive-\(driveId)"
        ) { result in
            if case let .failure(error) = result { exportError = error.localizedDescription }
            exportDocument = nil
        }
        .alert(t("Export Failed", "导出失败"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(t("OK", "确定"), role: .cancel) {}
        } message: {
            Text(UserFacingErrorLocalizer.localizedOptional(exportError, language: appLanguage) ?? "")
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load(carId: carId, driveId: driveId)
        }
    }

    private var annotationSection: some View {
        Button { editsAnnotation = true } label: {
            HStack {
                Image(systemName: "tag").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Classification & Notes", "分类与备注")).font(.headline).foregroundStyle(.primary)
                    Text(viewModel.state.annotation.displayLabel(language: appLanguage)).foregroundStyle(.secondary)
                    if !viewModel.state.annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(viewModel.state.annotation.note).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func prepareExport() {
        guard let detail = viewModel.state.driveDetail else { return }
        let csv = DriveCSVExporter.csv(detail: detail, stats: viewModel.state.stats, annotation: viewModel.state.annotation, units: viewModel.state.units.resolved(for: appDisplayUnitSystem))
        exportDocument = DriveCSVDocument(csv: csv)
        exportsCSV = true
    }

    @ViewBuilder
    private var tripMembershipSection: some View {
        if let membership = viewModel.state.tripMembership {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Saved Trip", "所属路程")).font(.headline)
                Button {
                    navigate(.tripDetail(carId: carId, tripStartDate: membership.snapshot.startDate, exteriorColor: exteriorColor))
                } label: {
                    HStack {
                        Label(membership.trip.displayName(language: appLanguage), systemImage: "map")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                }.buttonStyle(.bordered)
                Button(t("Remove from Trip", "从路程中移除"), role: .destructive) { confirmsTripRemoval = true }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveAnnotationEditor: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @Environment(\.dismiss) private var dismiss
    @State private var classification: DriveClassification
    @State private var customLabel: String
    @State private var note: String
    let onSave: (DriveAnnotation) -> Void

    init(annotation: DriveAnnotation, onSave: @escaping (DriveAnnotation) -> Void) {
        _classification = State(initialValue: annotation.classification)
        _customLabel = State(initialValue: annotation.customLabel)
        _note = State(initialValue: annotation.note)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Picker(t("Classification", "分类"), selection: $classification) {
                ForEach(DriveClassification.allCases) { value in Text(value.title(language: appLanguage)).tag(value) }
            }
            if classification == .custom {
                TextField(t("Custom Label", "自定义标签"), text: $customLabel)
            }
            Section(t("Note", "备注")) {
                TextEditor(text: $note).frame(minHeight: 140)
            }
        }
        .navigationTitle(t("Drive Classification", "行程分类"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("Cancel", "取消")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("Save", "保存")) { onSave(DriveAnnotation(classification: classification, customLabel: customLabel, note: note)) }
                    .disabled(classification == .custom && customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private func t(_ en: String, _ zh: String) -> String { AppText.localized(en, zh, language: appLanguage) }
}

private struct DriveCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    let csv: String
    init(csv: String) { self.csv = csv }
    init(configuration: ReadConfiguration) throws { csv = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? "" }
    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(csv.utf8)) }
}

public struct DriveRouteReplayView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @State private var selectedIndex = 0
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?

    let detail: DriveDetail
    let units: UnitPreferences?

    public var body: some View {
        let samples = DriveReplayBuilder.samples(from: detail.positions ?? [])
        if samples.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                replayMap(samples: samples)
                replayControls(samples: samples)
                replayMetrics(sample: samples[min(selectedIndex, samples.count - 1)])
            }
            .onDisappear { stopPlayback() }
        } else {
            LoadingStateView(title: t("No route coordinates", "暂无路线坐标"), systemImage: "map")
                .frame(minHeight: 120)
        }
    }

    private func replayMap(samples: [DriveReplaySample]) -> some View {
        let coordinates = samples.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let index = min(selectedIndex, samples.count - 1)
        let traveled = Array(coordinates.prefix(index + 1))
        return Map(initialPosition: .region(region(for: coordinates))) {
            MapPolyline(coordinates: coordinates).stroke(.gray.opacity(0.45), lineWidth: 4)
            if traveled.count >= 2 {
                MapPolyline(coordinates: traveled).stroke(.blue, lineWidth: 5)
            }
            Marker(t("Start", "开始"), systemImage: "flag", coordinate: coordinates[0])
            Marker(t("End", "结束"), systemImage: "flag.checkered", coordinate: coordinates[coordinates.count - 1])
            Marker(t("Current", "当前位置"), systemImage: "car.fill", coordinate: coordinates[index])
                .tint(.blue)
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func replayControls(samples: [DriveReplaySample]) -> some View {
        HStack(spacing: 12) {
            Button {
                isPlaying ? stopPlayback() : startPlayback(sampleCount: samples.count)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(isPlaying ? t("Pause replay", "暂停回放") : t("Play route", "播放路线"))

            Slider(
                value: Binding(
                    get: { Double(min(selectedIndex, samples.count - 1)) },
                    set: { selectedIndex = min(max(Int($0.rounded()), 0), samples.count - 1) }
                ),
                in: 0...Double(samples.count - 1),
                step: 1,
                onEditingChanged: { editing in if editing { stopPlayback() } }
            )
            .accessibilityLabel(t("Route progress", "路线进度"))

            Text("\(min(selectedIndex, samples.count - 1) + 1)/\(samples.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    private func replayMetrics(sample: DriveReplaySample) -> some View {
        let position = sample.position
        return HStack(spacing: 0) {
            replayMetric(t("Time", "时间"), value: formattedTime(position.date))
            replayMetric(t("Speed", "速度"), value: position.speed.map { MateDroidUnitFormatter.formatSpeed(Double($0), units: units) } ?? "--")
            replayMetric(t("Power", "功率"), value: position.power.map { "\($0) kW" } ?? "--")
            replayMetric(t("Battery", "电量"), value: position.batteryLevel.map { "\($0)%" } ?? "--")
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func replayMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(verbatim: title).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.caption.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func startPlayback(sampleCount: Int) {
        stopPlayback()
        if selectedIndex >= sampleCount - 1 { selectedIndex = 0 }
        isPlaying = true
        playbackTask = Task { @MainActor in
            while !Task.isCancelled, selectedIndex < sampleCount - 1 {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { break }
                selectedIndex += 1
            }
            if !Task.isCancelled { isPlaying = false }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func formattedTime(_ value: String?) -> String {
        guard let value, let date = DomainDateParser.date(from: value) else { return "--" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2,
            longitude: ((longitudes.min() ?? 0) + (longitudes.max() ?? 0)) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(((latitudes.max() ?? 0) - (latitudes.min() ?? 0)) * 1.4, 0.01),
                longitudeDelta: max(((longitudes.max() ?? 0) - (longitudes.min() ?? 0)) * 1.4, 0.01)
            )
        )
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public struct DriveHeroView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let detail: DriveDetail
    let stats: DriveDetailStats?
    let units: UnitPreferences?

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            routeText
                .font(.title2.weight(.semibold))
                .lineLimit(2)
            Text(dateText(detail.startDate))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(DriveDetailPresentation.distanceText(stats?.distance ?? detail.distance, units: units))
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                Spacer()
                Text(DriveDetailPresentation.batteryText(start: stats?.batteryStart, end: stats?.batteryEnd))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var routeText: Text {
        let start = cleanedAddress(detail.startAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("Start", "开始"))
        let end = cleanedAddress(detail.endAddress).map { Text(verbatim: $0) } ?? Text(verbatim: t("End", "结束"))
        return start + Text(" -> ") + end
    }

    private func cleanedAddress(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func dateText(_ value: String?) -> String {
        guard let value, let date = DomainDateParser.date(from: value) else {
            return value ?? ""
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum DriveDetailPresentation {
    public static func distanceText(_ value: Double?, units: UnitPreferences?) -> String {
        value.map { MateDroidUnitFormatter.formatDistance($0, units: units) } ?? "--"
    }

    public static func speedText(_ value: Double?, units: UnitPreferences?) -> String {
        value.map { MateDroidUnitFormatter.formatSpeed($0, units: units) } ?? "--"
    }

    public static func batteryText(start: Int?, end: Int?) -> String {
        guard let start, let end else { return "--" }
        return "\(start)% -> \(end)%"
    }

    public static func elevationText(gain: Int?, loss: Int?, units: UnitPreferences?) -> String {
        guard let gain, let loss else { return "--" }
        return "+\(MateDroidUnitFormatter.formatElevation(gain, units: units)) / -\(MateDroidUnitFormatter.formatElevation(loss, units: units))"
    }

    public static func durationText(_ value: Int?, language: AppLanguage) -> String {
        value.map { MateDroidUnitFormatter.formatDuration(minutes: $0, language: language) } ?? "--"
    }
}

public struct DriveStatsGrid: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let stats: DriveDetailStats?
    let units: UnitPreferences?
    let onSelectMetric: ((DriveMetricKind) -> Void)?

    public init(stats: DriveDetailStats?, units: UnitPreferences?, onSelectMetric: ((DriveMetricKind) -> Void)? = nil) {
        self.stats = stats
        self.units = units
        self.onSelectMetric = onSelectMetric
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            metricCard(.averageSpeed, value: DriveDetailPresentation.speedText(stats?.speedAvg, units: units))
            metricCard(.maxSpeed, value: DriveDetailPresentation.speedText(stats?.speedMax.map(Double.init), units: units))
            metricCard(
                .efficiency,
                value: stats?.efficiency.map { MateDroidUnitFormatter.formatEfficiency($0, units: units, decimals: 0) } ?? "--",
                subtitle: efficiencySourceSubtitle
            )
            metricCard(
                .energy,
                value: stats?.energyUsed.map { String(format: "%.1f kWh", $0) } ?? "--",
                subtitle: energySourceSubtitle
            )
            metricCard(.elevation, value: DriveDetailPresentation.elevationText(gain: stats?.elevationGain, loss: stats?.elevationLoss, units: units))
            metricCard(.duration, value: DriveDetailPresentation.durationText(stats?.durationMin, language: appLanguage))
        }
    }

    @ViewBuilder
    private func metricCard(_ metric: DriveMetricKind, value: String, subtitle: String? = nil) -> some View {
        if let onSelectMetric {
            Button {
                onSelectMetric(metric)
            } label: {
                MetricCard(title: metric.title(language: appLanguage), value: value, subtitle: subtitle, systemImage: metric.systemImage)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(12)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint(AppText.localized("Open details", "打开详细数据", language: appLanguage))
        } else {
            MetricCard(title: metric.title(language: appLanguage), value: value, subtitle: subtitle, systemImage: metric.systemImage)
        }
    }

    private var energySourceSubtitle: String? {
        stats.map { DriveEnergySourcePresentation.subtitle(for: $0.energySource, language: appLanguage) }
    }

    private var efficiencySourceSubtitle: String? {
        stats.map {
            DriveEnergySourcePresentation.efficiencySubtitle(
                energySource: $0.energySource,
                hasEfficiency: $0.efficiency != nil,
                language: appLanguage
            )
        }
    }

}

public enum DriveEnergySourcePresentation {
    public static func subtitle(for source: DriveEnergySource, language: AppLanguage) -> String {
        switch source {
        case .api:
            return AppText.localized("Direct TeslaMate data", "TeslaMate 原始数据", language: language)
        case .powerSamples:
            return AppText.localized("Reconstructed from power samples", "由功率采样重建", language: language)
        case .unavailable:
            return AppText.localized("No reliable data", "暂无可靠数据", language: language)
        }
    }

    public static func efficiencySubtitle(
        energySource: DriveEnergySource,
        hasEfficiency: Bool,
        language: AppLanguage
    ) -> String {
        if energySource == .unavailable, hasEfficiency {
            return subtitle(for: .api, language: language)
        }
        return subtitle(for: energySource, language: language)
    }
}

public struct DrivePositionCharts: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let detail: DriveDetail
    let units: UnitPreferences?

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t("Analysis", "分析"))
                .font(.title2.weight(.semibold))
                .padding(.bottom, 16)

            chart(t("Speed", "速度"), kind: .speed)
            Divider()
            chart(t("Power", "功率"), kind: .power)
            Divider()
            chart(t("Battery & Heating", "电量和电池加热"), kind: .battery)
            Divider()
            chart(t("Elevation", "海拔"), kind: .elevation)
            Divider()
            chart(t("Temperature", "温度"), kind: .temperature)
            Divider()
            chart(t("Tire Pressure", "胎压"), kind: .tirePressure)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var positions: [DrivePosition] { detail.positions ?? [] }

    private func chart(_ title: String, kind: DriveChartKind) -> some View {
        DriveTimeSeriesChart(
            title: title,
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: kind == .tirePressure ? detail.sourceUnits?.unitOfPressure : nil
        )
        .padding(.vertical, 16)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

public enum DriveChartKind: Sendable {
    case speed, power, battery, elevation, temperature, tirePressure
}

public struct DriveChartSample: Equatable, Sendable, Identifiable {
    public let date: Date
    public let value: Double
    public let series: String
    public let isHighlighted: Bool

    public var id: String { "\(date.timeIntervalSince1970)-\(series)" }
}

public enum DriveChartSampleBuilder {
    public static func samples(
        kind: DriveChartKind,
        positions: [DrivePosition],
        units: UnitPreferences?,
        sourcePressureUnit: String? = nil
    ) -> [DriveChartSample] {
        positions.flatMap { position -> [DriveChartSample] in
            guard let date = position.date.flatMap(DomainDateParser.date(from:)) else { return [] }
            switch kind {
            case .speed:
                guard let value = position.speed.map(Double.init) else { return [] }
                return [sample(date, convertedSpeed(value, units: units), "speed")]
            case .power:
                guard let value = position.power.map(Double.init) else { return [] }
                return [sample(date, value, value < 0 ? "regeneration" : "traction", highlighted: value < 0)]
            case .battery:
                guard let value = position.batteryLevel.map(Double.init) else { return [] }
                return [sample(date, value, "battery", highlighted: position.isBatteryHeaterOn)]
            case .elevation:
                guard let value = position.elevation.map(Double.init) else { return [] }
                return [sample(date, units?.isImperial == true ? value * 3.28084 : value, "elevation")]
            case .temperature:
                var values: [DriveChartSample] = []
                if let outside = position.outsideTemp { values.append(sample(date, convertedTemperature(outside, units: units), "outside")) }
                if let inside = position.insideTemp { values.append(sample(date, convertedTemperature(inside, units: units), "inside")) }
                return values
            case .tirePressure:
                return [
                    pressureSample(position.tpmsPressureFl, date: date, series: "frontLeft", sourceUnit: sourcePressureUnit, units: units),
                    pressureSample(position.tpmsPressureFr, date: date, series: "frontRight", sourceUnit: sourcePressureUnit, units: units),
                    pressureSample(position.tpmsPressureRl, date: date, series: "rearLeft", sourceUnit: sourcePressureUnit, units: units),
                    pressureSample(position.tpmsPressureRr, date: date, series: "rearRight", sourceUnit: sourcePressureUnit, units: units)
                ].compactMap { $0 }
            }
        }
        .sorted { $0.date < $1.date }
    }

    private static func sample(_ date: Date, _ value: Double, _ series: String, highlighted: Bool = false) -> DriveChartSample {
        DriveChartSample(date: date, value: value, series: series, isHighlighted: highlighted)
    }

    private static func convertedSpeed(_ value: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? value * 0.621371 : value
    }

    private static func convertedTemperature(_ value: Double, units: UnitPreferences?) -> Double {
        units?.isImperial == true ? value * 9 / 5 + 32 : value
    }

    private static func pressureSample(
        _ value: Double?,
        date: Date,
        series: String,
        sourceUnit: String?,
        units: UnitPreferences?
    ) -> DriveChartSample? {
        guard let value, value.isFinite, value > 0 else { return nil }
        let bar = sourceUnit?.lowercased() == "psi" ? value / 14.5038 : value
        return sample(date, MateDroidUnitFormatter.pressureValue(bar, units: units), series)
    }
}

public enum DriveChartSelection {
    public static func nearestDate(to date: Date, in samples: [DriveChartSample]) -> Date? {
        samples.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date
    }

    public static func samples(at date: Date, in samples: [DriveChartSample]) -> [DriveChartSample] {
        guard let nearestDate = nearestDate(to: date, in: samples) else { return [] }
        return samples.filter { $0.date == nearestDate }
    }
}

public struct DriveTimeSeriesChart: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @State private var selectedDate: Date?

    let title: String
    let kind: DriveChartKind
    let positions: [DrivePosition]
    let units: UnitPreferences?
    let sourcePressureUnit: String?

    public init(
        title: String,
        kind: DriveChartKind,
        positions: [DrivePosition],
        units: UnitPreferences?,
        sourcePressureUnit: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.positions = positions
        self.units = units
        self.sourcePressureUnit = sourcePressureUnit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let headerValue {
                    Text(verbatim: headerValue)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if samples.isEmpty {
                LoadingStateView(title: t("No data", "暂无数据"), systemImage: "chart.xyaxis.line")
            } else {
                Chart {
                    ForEach(samples) { sample in
                        if kind == .elevation {
                            AreaMark(
                                x: .value("Time", sample.date),
                                yStart: .value("Baseline", yDomain.lowerBound),
                                yEnd: .value("Value", sample.value)
                            )
                                .foregroundStyle(.brown.opacity(0.28))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                                .foregroundStyle(.brown)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                                .interpolationMethod(.catmullRom)
                        } else {
                            if kind == .temperature || kind == .tirePressure {
                                LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value), series: .value("Series", sample.series))
                                    .foregroundStyle(color(for: sample))
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .interpolationMethod(.linear)
                            } else {
                                LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                                    .foregroundStyle(color(for: sample))
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    .interpolationMethod(kind == .speed ? .catmullRom : .linear)
                            }
                            if sample.isHighlighted {
                                PointMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                                    .foregroundStyle(kind == .power ? .green : .red)
                                    .symbolSize(26)
                            }
                        }
                    }
                    if let selectedSample = selectedSamples.first {
                        RuleMark(x: .value("Selected time", selectedSample.date))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        ForEach(selectedSamples) { sample in
                            PointMark(x: .value("Selected time", sample.date), y: .value("Selected value", sample.value))
                                .foregroundStyle(color(for: sample))
                                .symbolSize(48)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisDates) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartYScale(domain: yDomain)
                .chartXSelection(value: $selectedDate)
                .frame(height: 190)
                selectionDetail
                legend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var samples: [DriveChartSample] {
        DriveChartSampleBuilder.samples(
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: sourcePressureUnit
        )
    }

    private var selectedSamples: [DriveChartSample] {
        guard let selectedDate else { return [] }
        return DriveChartSelection.samples(at: selectedDate, in: samples)
    }

    private var headerValue: String? {
        DriveChartHeaderPresentation.valueText(
            kind: kind,
            positions: positions,
            units: units,
            sourcePressureUnit: sourcePressureUnit
        )
    }

    private var yDomain: ClosedRange<Double> {
        DriveChartScale.domain(kind: kind, samples: samples) ?? 0...1
    }

    private var xAxisDates: [Date] {
        DriveChartAxisPresentation.interiorDates(samples: samples)
    }

    @ViewBuilder
    private var selectionDetail: some View {
        if let sample = selectedSamples.first {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    selectionTime(sample.date)
                    selectionValues
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 5) {
                    selectionTime(sample.date)
                    selectionValues
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 34, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func selectionTime(_ date: Date) -> some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption.monospacedDigit().weight(.semibold))
            .fixedSize()
    }

    private var selectionValues: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ForEach(selectedSamples) { selectedSample in
                    selectionItem(selectedSample)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], alignment: .leading, spacing: 5) {
                ForEach(selectedSamples) { selectedSample in
                    selectionItem(selectedSample)
                }
            }
        }
    }

    private func selectionItem(_ sample: DriveChartSample) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color(for: sample)).frame(width: 7, height: 7)
            Text(selectionValue(sample))
                .font(.caption.monospacedDigit())
                .fixedSize()
        }
    }

    private func selectionValue(_ sample: DriveChartSample) -> String {
        let value = sample.value.formatted(.number.precision(.fractionLength(kind == .elevation ? 0 : 1)))
        switch kind {
        case .speed: return "\(value) \(units?.isImperial == true ? "mph" : "km/h")"
        case .power: return "\(value) kW"
        case .battery: return "\(value)%"
        case .elevation: return "\(value) \(units?.isImperial == true ? "ft" : "m")"
        case .temperature:
            let label = sample.series == "inside" ? t("Inside", "车内") : t("Outside", "车外")
            return "\(label) \(value)°\(units?.isImperial == true ? "F" : "C")"
        case .tirePressure:
            return "\(wheelTitle(sample.series)) \(value) \(MateDroidUnitFormatter.pressureUnit(units: units))"
        }
    }

    @ViewBuilder
    private var legend: some View {
        switch kind {
        case .power:
            HStack { legendItem(t("Traction", "驱动"), .orange); legendItem(t("Regeneration", "能量回收"), .green) }
        case .battery:
            HStack { legendItem(t("Battery", "电量"), .green); legendItem(t("Battery heating", "电池加热"), .red) }
        case .temperature:
            HStack { legendItem(t("Outside", "车外"), .blue); legendItem(t("Inside", "车内"), .green) }
        case .tirePressure:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 6) {
                legendItem(t("Front Left", "左前"), .blue)
                legendItem(t("Front Right", "右前"), .green)
                legendItem(t("Rear Left", "左后"), .orange)
                legendItem(t("Rear Right", "右后"), .purple)
            }
        default:
            EmptyView()
        }
    }

    private func legendItem(_ text: String, _ color: Color) -> some View {
        Label { Text(text).font(.caption).foregroundStyle(.secondary) } icon: { Circle().fill(color).frame(width: 8, height: 8) }
    }

    private func color(for sample: DriveChartSample) -> Color {
        switch kind {
        case .speed: return .blue
        case .power: return .orange
        case .battery: return .green
        case .elevation: return .brown
        case .temperature: return sample.series == "inside" ? .green : .blue
        case .tirePressure:
            switch sample.series {
            case "frontLeft": return .blue
            case "frontRight": return .green
            case "rearLeft": return .orange
            default: return .purple
            }
        }
    }

    private func wheelTitle(_ series: String) -> String {
        switch series {
        case "frontLeft": return t("Front Left", "左前")
        case "frontRight": return t("Front Right", "右前")
        case "rearLeft": return t("Rear Left", "左后")
        default: return t("Rear Right", "右后")
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
