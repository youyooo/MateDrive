import SwiftUI
import UIKit

public struct BatteryShareCardOptions: Equatable, Sendable {
    public var includesExactRecordingPeriod: Bool
    public var includesRecordingStartOdometer: Bool

    public init(
        includesExactRecordingPeriod: Bool = false,
        includesRecordingStartOdometer: Bool = false
    ) {
        self.includesExactRecordingPeriod = includesExactRecordingPeriod
        self.includesRecordingStartOdometer = includesRecordingStartOdometer
    }

    public var includesSensitiveDetails: Bool {
        includesExactRecordingPeriod || includesRecordingStartOdometer
    }
}

public struct BatteryShareMetric: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let value: String
    public let systemImage: String
}

public struct BatteryShareCardContent: Equatable, Sendable {
    public let title: String
    public let headline: String
    public let headlineLabel: String
    public let healthFraction: Double?
    public let sourceText: String
    public let confidenceText: String
    public let exactRecordingPeriodText: String?
    public let hiddenDetailsLabel: String?
    public let warningText: String
    public let metrics: [BatteryShareMetric]
    public let optionsIncludeSensitiveDetails: Bool
}

public enum BatteryShareCardBuilder {
    public static func content(
        stats: BatteryStats,
        summary: BatteryHistorySummary?,
        units: UnitPreferences?,
        language: AppLanguage,
        options: BatteryShareCardOptions
    ) -> BatteryShareCardContent {
        let hasAbsoluteHealth = stats.showsAbsoluteHealth && stats.healthPercent != nil
        let headline = hasAbsoluteHealth
            ? BatteryHealthPresentation.percentText(stats.healthPercent)
            : localized("Needs calibration", "需要校准", language: language)
        let headlineLabel = hasAbsoluteHealth
            ? localized("Estimated battery health", "估算电池健康度", language: language)
            : localized("Lifetime health unavailable", "寿命健康度不可用", language: language)
        let warningText = hasAbsoluteHealth
            ? localized(
                "This is an estimate from TeslaMate records and your calibration reference, not a physical battery diagnosis.",
                "该结果根据 TeslaMate 记录和你的校准参考值估算，并非电池物理检测结论。",
                language: language
            )
            : localized(
                "Recording-period retention does not represent lifetime battery health. Add a verified new-car reference before drawing a degradation conclusion.",
                "记录期保持率不代表整车寿命健康度；填写已确认的新车参考值后，才能判断长期衰减。",
                language: language
            )

        var metrics = [
            BatteryShareMetric(
                id: "capacityNow",
                title: localized("Capacity Now", "当前容量", language: language),
                value: stats.currentCapacity.map { String(format: "%.1f kWh", $0) } ?? "--",
                systemImage: "battery.75percent"
            ),
            BatteryShareMetric(
                id: "rangeAt100",
                title: localized("At 100%", "满电续航", language: language),
                value: stats.rangeAt100.map { MateDriveUnitFormatter.formatDistance($0, units: units) } ?? "--",
                systemImage: "road.lanes"
            ),
            BatteryShareMetric(
                id: "dataQuality",
                title: localized("Data Quality", "数据质量", language: language),
                value: qualityText(summary?.quality, language: language),
                systemImage: "checkmark.seal"
            ),
            BatteryShareMetric(
                id: "recordingSpan",
                title: localized("History Span", "历史跨度", language: language),
                value: summary.map { dayText($0.quality.recordedDays, language: language) } ?? "--",
                systemImage: "calendar"
            ),
            BatteryShareMetric(
                id: "recordedCapacityRetention",
                title: recordedRetentionTitle(summary: summary, language: language),
                value: recordedRetentionText(summary: summary),
                systemImage: "chart.line.uptrend.xyaxis"
            ),
            BatteryShareMetric(
                id: "recordedDistance",
                title: localized("Distance Recorded", "已记录里程", language: language),
                value: summary?.recordedDistanceKm.map {
                    MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
                } ?? "--",
                systemImage: "road.lanes"
            )
        ]
        if options.includesRecordingStartOdometer {
            metrics.append(BatteryShareMetric(
                id: "recordingStartOdometer",
                title: localized("Recording Start Odometer", "开始记录时里程", language: language),
                value: stats.recordingStartOdometerKm.map {
                    MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
                } ?? "--",
                systemImage: "gauge.with.dots.needle.33percent"
            ))
        }

        return BatteryShareCardContent(
            title: localized("Battery Report", "电池报告", language: language),
            headline: headline,
            headlineLabel: headlineLabel,
            healthFraction: hasAbsoluteHealth ? stats.healthPercent.map { min(max($0 / 100, 0), 1) } : nil,
            sourceText: stats.healthSource.title(language: language),
            confidenceText: stats.confidence.title(language: language),
            exactRecordingPeriodText: options.includesExactRecordingPeriod
                ? recordingPeriodText(summary: summary, language: language)
                : nil,
            hiddenDetailsLabel: hiddenDetailsLabel(options: options, language: language),
            warningText: warningText,
            metrics: metrics,
            optionsIncludeSensitiveDetails: options.includesSensitiveDetails
        )
    }

    private static func qualityText(_ quality: BatteryHistoryQuality?, language: AppLanguage) -> String {
        guard let quality else { return "--" }
        return "\(quality.score)/100 · \(quality.level.title(language: language))"
    }

    private static func dayText(_ days: Int, language: AppLanguage) -> String {
        String(format: localized("%d days", "%d 天", language: language), days)
    }

    private static func recordedRetentionTitle(summary: BatteryHistorySummary?, language: AppLanguage) -> String {
        if summary?.recordedCapacityRetentionPercent != nil {
            return localized("Recorded Capacity Retention", "记录期容量保持率", language: language)
        }
        return localized("Recorded Range Retention", "记录期续航保持率", language: language)
    }

    private static func recordedRetentionText(summary: BatteryHistorySummary?) -> String {
        let value = summary?.recordedCapacityRetentionPercent ?? summary?.recordedRangeRetentionPercent
        return value.map { String(format: "%.1f%%", $0) } ?? "--"
    }

    private static func recordingPeriodText(summary: BatteryHistorySummary?, language: AppLanguage) -> String? {
        guard let summary,
              let start = summary.startDate.flatMap(DomainDateParser.date(from:)),
              let end = summary.endDate.flatMap(DomainDateParser.date(from:))
        else { return nil }
        let locale = language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }

    private static func hiddenDetailsLabel(options: BatteryShareCardOptions, language: AppLanguage) -> String? {
        switch (options.includesExactRecordingPeriod, options.includesRecordingStartOdometer) {
        case (false, false):
            return localized(
                "Exact recording dates and start odometer hidden",
                "精确记录日期和起始里程已隐藏",
                language: language
            )
        case (false, true):
            return localized("Exact recording dates hidden", "精确记录日期已隐藏", language: language)
        case (true, false):
            return localized("Recording start odometer hidden", "开始记录时里程已隐藏", language: language)
        case (true, true):
            return nil
        }
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct BatteryShareCardView: View {
    public static let size = CGSize(width: 540, height: 675)

    let content: BatteryShareCardContent

    public init(content: BatteryShareCardContent) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.063, blue: 0.071)

            VStack(alignment: .leading, spacing: 0) {
                header
                healthSummary
                    .padding(.top, 28)
                metricsGrid
                    .padding(.top, 28)
                Spacer(minLength: 16)
                warning
                footer
                    .padding(.top, 18)
            }
            .padding(42)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Label("MateDrive", systemImage: "bolt.car.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)
            Spacer()
            Text(content.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var healthSummary: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.12), lineWidth: 12)
                if let fraction = content.healthFraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            Color(red: 0.25, green: 0.84, blue: 0.48),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 7) {
                Text(content.headlineLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(content.headline)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("\(content.sourceText) · \(content.confidenceText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                if let period = content.exactRecordingPeriodText {
                    Label(period, systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                } else if let hidden = content.hiddenDetailsLabel {
                    Label(hidden, systemImage: "eye.slash.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(2)
                }
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            alignment: .leading,
            spacing: 19
        ) {
            ForEach(content.metrics) { metric in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.25, green: 0.84, blue: 0.48))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(metric.value)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                }
            }
        }
    }

    private var warning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
            Text(content.warningText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
    }
}

public struct BatteryShareComposerView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var options = BatteryShareCardOptions()
    @State private var sharedImage: BatterySharedImage?
    @State private var renderError: String?

    let stats: BatteryStats
    let summary: BatteryHistorySummary?
    let units: UnitPreferences?

    public init(stats: BatteryStats, summary: BatteryHistorySummary?, units: UnitPreferences?) {
        self.stats = stats
        self.summary = summary
        self.units = units
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Form {
                    Section {
                        Toggle(
                            t("Include exact recording dates", "包含精确记录日期"),
                            isOn: $options.includesExactRecordingPeriod
                        )
                        Toggle(
                            t("Include recording start odometer", "包含开始记录时里程"),
                            isOn: $options.includesRecordingStartOdometer
                        )
                    }

                    if options.includesSensitiveDetails {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Sensitive details selected", "已选择敏感信息"))
                                        .font(.headline)
                                    Text(t(
                                        "Anyone receiving this image can see the selected battery history details.",
                                        "收到图片的人都能看到已选择的电池历史信息。"
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)

                Button(action: shareImage) {
                    Label(t("Share Image", "分享图片"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(t("Share Battery Report", "分享电池报告"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { dismiss() }
                }
            }
        }
        .sheet(item: $sharedImage) { payload in
            BatteryShareActivityView(activityItems: [payload.image])
        }
        .alert(t("Unable to create share image.", "无法生成分享图片。"), isPresented: Binding(
            get: { renderError != nil },
            set: { if !$0 { renderError = nil } }
        )) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let widthScale = max((proxy.size.width - 32) / BatteryShareCardView.size.width, 0.1)
            let heightScale = max((proxy.size.height - 24) / BatteryShareCardView.size.height, 0.1)
            let scale = min(widthScale, heightScale)

            BatteryShareCardView(content: cardContent)
                .scaleEffect(scale)
                .frame(
                    width: BatteryShareCardView.size.width * scale,
                    height: BatteryShareCardView.size.height * scale
                )
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 310)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Battery Share Card", "电池分享卡片"))
    }

    private var cardContent: BatteryShareCardContent {
        BatteryShareCardBuilder.content(
            stats: stats,
            summary: summary,
            units: units,
            language: appLanguage,
            options: options
        )
    }

    @MainActor
    private func shareImage() {
        let renderer = ImageRenderer(content: BatteryShareCardView(content: cardContent))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            renderError = t("Unable to create share image.", "无法生成分享图片。")
            return
        }
        sharedImage = BatterySharedImage(image: image)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct BatterySharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct BatteryShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
