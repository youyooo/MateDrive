import SwiftUI
import UIKit

public struct ActivityPeriodDateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = min(start, end)
        self.end = max(start, end)
    }
}

public struct ActivityPeriodShareCardOptions: Equatable, Sendable {
    public var includesExactDateRange: Bool
    public var includesCosts: Bool

    public init(includesExactDateRange: Bool = false, includesCosts: Bool = false) {
        self.includesExactDateRange = includesExactDateRange
        self.includesCosts = includesCosts
    }

    public var includesSensitiveDetails: Bool {
        includesExactDateRange || includesCosts
    }
}

public struct ActivityPeriodShareMetric: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let value: String
    public let systemImage: String
}

public struct ActivityPeriodShareCardContent: Equatable, Sendable {
    public let title: String
    public let periodLabel: String
    public let exactDateRangeText: String?
    public let historyIsComplete: Bool
    public let historyLabel: String
    public let recordCountText: String
    public let recordCountLabel: String
    public let hiddenDetailsLabel: String?
    public let scopeLabels: [String]
    public let metrics: [ActivityPeriodShareMetric]
    public let costMetrics: [ActivityPeriodShareMetric]
    public let coverageNotes: [String]
}

public enum ActivityPeriodShareCardBuilder {
    public static func content(
        summary: ActivityPeriodSummary,
        dateFilter: ActivityDateFilter,
        activityFilter: ActivityFilter,
        dateRange: ActivityPeriodDateRange?,
        historyIsComplete: Bool,
        locationFilterIsActive: Bool,
        currencyCode: String,
        units: UnitPreferences?,
        language: AppLanguage,
        options: ActivityPeriodShareCardOptions
    ) -> ActivityPeriodShareCardContent {
        let metrics = [
            ActivityPeriodShareMetric(
                id: "distance",
                title: localized("Distance", "里程", language: language),
                value: ActivitySummaryPresentation.distanceText(
                    summary.distanceKm,
                    isComplete: summary.distanceIsComplete && historyIsComplete,
                    units: units
                ),
                systemImage: "road.lanes"
            ),
            ActivityPeriodShareMetric(
                id: "drivingEnergy",
                title: localized("Driving Energy", "行驶能量", language: language),
                value: ActivitySummaryPresentation.energyText(
                    summary.drivingEnergyKWh,
                    isComplete: summary.drivingEnergyIsComplete && historyIsComplete
                ),
                systemImage: "bolt.car.fill"
            ),
            ActivityPeriodShareMetric(
                id: "chargedEnergy",
                title: localized("Charged Energy", "充入能量", language: language),
                value: ActivitySummaryPresentation.energyText(
                    summary.chargedEnergyKWh,
                    isComplete: summary.chargedEnergyIsComplete && historyIsComplete
                ),
                systemImage: "bolt.fill"
            ),
            countMetric(id: "drives", title: localized("Drives", "行程", language: language), count: summary.driveCount, historyIsComplete: historyIsComplete, systemImage: "steeringwheel"),
            countMetric(id: "charges", title: localized("Charges", "充电", language: language), count: summary.chargeCount, historyIsComplete: historyIsComplete, systemImage: "ev.charger.fill"),
            countMetric(id: "parking", title: localized("Parked", "停车", language: language), count: summary.parkingCount, historyIsComplete: historyIsComplete, systemImage: "parkingsign.circle.fill")
        ]

        var costMetrics: [ActivityPeriodShareMetric] = []
        if options.includesCosts {
            let chargeCostValue = summary.chargeCount == 0
                ? (historyIsComplete ? 0 : nil)
                : summary.knownChargeCost
            costMetrics = [
                ActivityPeriodShareMetric(
                    id: "chargeCost",
                    title: localized("Known Charge Cost", "已知充电费用", language: language),
                    value: ActivitySummaryPresentation.currencyText(
                        chargeCostValue,
                        isComplete: summary.chargeCostIsComplete && historyIsComplete,
                        currencyCode: currencyCode
                    ),
                    systemImage: "creditcard.fill"
                ),
                ActivityPeriodShareMetric(
                    id: "parkingCost",
                    title: localized("Parking Cost", "停车费用", language: language),
                    value: ActivitySummaryPresentation.parkingCostText(
                        summary.parkingCost,
                        parkingCount: summary.parkingCount,
                        historyIsComplete: historyIsComplete,
                        currencyCode: currencyCode
                    ),
                    systemImage: "parkingsign"
                )
            ]
        }

        return ActivityPeriodShareCardContent(
            title: localized("Activity Recap", "活动回顾", language: language),
            periodLabel: periodTitle(dateFilter, language: language),
            exactDateRangeText: options.includesExactDateRange ? dateRangeText(dateRange, language: language) : nil,
            historyIsComplete: historyIsComplete,
            historyLabel: historyIsComplete
                ? localized("Complete history", "完整历史记录", language: language)
                : localized("Partial history", "历史记录不完整", language: language),
            recordCountText: countText(summary.activityCount, historyIsComplete: historyIsComplete),
            recordCountLabel: localized("Records", "记录", language: language),
            hiddenDetailsLabel: hiddenDetailsLabel(options, language: language),
            scopeLabels: scopeLabels(activityFilter: activityFilter, locationFilterIsActive: locationFilterIsActive, language: language),
            metrics: metrics,
            costMetrics: costMetrics,
            coverageNotes: coverageNotes(summary: summary, historyIsComplete: historyIsComplete, language: language)
        )
    }

    private static func countMetric(id: String, title: String, count: Int, historyIsComplete: Bool, systemImage: String) -> ActivityPeriodShareMetric {
        ActivityPeriodShareMetric(id: id, title: title, value: countText(count, historyIsComplete: historyIsComplete), systemImage: systemImage)
    }

    private static func countText(_ count: Int, historyIsComplete: Bool) -> String {
        (historyIsComplete ? "" : "≥") + String(count)
    }

    private static func periodTitle(_ filter: ActivityDateFilter, language: AppLanguage) -> String {
        switch filter {
        case .all: localized("All time", "全部时间", language: language)
        case .sevenDays: localized("Last 7 days", "最近 7 天", language: language)
        case .thirtyDays: localized("Last 30 days", "最近 30 天", language: language)
        case .thisYear: localized("This year", "今年", language: language)
        }
    }

    private static func dateRangeText(_ range: ActivityPeriodDateRange?, language: AppLanguage) -> String? {
        guard let range else { return nil }
        let locale = language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        return "\(range.start.formatted(style)) – \(range.end.formatted(style))"
    }

    private static func hiddenDetailsLabel(_ options: ActivityPeriodShareCardOptions, language: AppLanguage) -> String? {
        switch (options.includesExactDateRange, options.includesCosts) {
        case (false, false): localized("Exact dates and costs hidden", "精确日期和费用已隐藏", language: language)
        case (false, true): localized("Exact dates hidden", "精确日期已隐藏", language: language)
        case (true, false): localized("Costs hidden", "费用已隐藏", language: language)
        case (true, true): nil
        }
    }

    private static func scopeLabels(activityFilter: ActivityFilter, locationFilterIsActive: Bool, language: AppLanguage) -> [String] {
        var labels: [String] = []
        switch activityFilter {
        case .all: break
        case .drive: labels.append(localized("Drives only", "仅行程", language: language))
        case .charge: labels.append(localized("Charges only", "仅充电", language: language))
        case .park: labels.append(localized("Parking only", "仅停车", language: language))
        }
        if locationFilterIsActive {
            labels.append(localized("Location filter applied", "已应用地点筛选", language: language))
        }
        return labels
    }

    private static func coverageNotes(summary: ActivityPeriodSummary, historyIsComplete: Bool, language: AppLanguage) -> [String] {
        var notes: [String] = []
        if !historyIsComplete {
            notes.append(localized("Totals reflect loaded records only.", "汇总仅反映已加载的记录。", language: language))
        }
        appendCoverage(&notes, key: "Distance coverage: %d/%d", chinese: "里程覆盖：%d/%d", known: summary.distanceRecordCount, total: summary.driveCount, language: language)
        appendCoverage(&notes, key: "Driving energy coverage: %d/%d", chinese: "行驶能量覆盖：%d/%d", known: summary.drivingEnergyRecordCount, total: summary.driveCount, language: language)
        appendCoverage(&notes, key: "Charge energy coverage: %d/%d", chinese: "充电电量覆盖：%d/%d", known: summary.chargedEnergyRecordCount, total: summary.chargeCount, language: language)
        appendCoverage(&notes, key: "Price coverage: %d/%d", chinese: "价格覆盖：%d/%d", known: summary.pricedChargeCount, total: summary.chargeCount, language: language)
        if summary.parkingCost.unmatchedParkingCount == 1 {
            notes.append(localized("1 parking record unmatched", "1 条停车记录未匹配", language: language))
        } else if summary.parkingCost.unmatchedParkingCount > 1 {
            notes.append(formatted("%d parking records unmatched", "%d 条停车记录未匹配", language: language, summary.parkingCost.unmatchedParkingCount))
        }
        return notes
    }

    private static func appendCoverage(_ notes: inout [String], key: String, chinese: String, known: Int, total: Int, language: AppLanguage) {
        guard known < total else { return }
        notes.append(formatted(key, chinese, language: language, known, total))
    }

    private static func formatted(_ english: String, _ chinese: String, language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: localized(english, chinese, language: language), arguments: arguments)
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct ActivityPeriodShareCardView: View {
    public static let size = CGSize(width: 540, height: 675)

    let content: ActivityPeriodShareCardContent

    public init(content: ActivityPeriodShareCardContent) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.063, blue: 0.071)
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                recapHeader.padding(.top, 30)
                metricsGrid.padding(.top, 26)
                if !content.costMetrics.isEmpty {
                    costRow.padding(.top, 24)
                }
                Spacer(minLength: 16)
                detailFooter
            }
            .padding(40)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var brandHeader: some View {
        HStack {
            Label("MateDrive", systemImage: "bolt.car.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .symbolRenderingMode(.monochrome)
            Spacer()
            Text(content.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var recapHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 9) {
                Text(content.periodLabel)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let exactDateRangeText = content.exactDateRangeText {
                    Label(exactDateRangeText, systemImage: "calendar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Label(content.historyLabel, systemImage: content.historyIsComplete ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(content.recordCountText.hasPrefix("≥") ? Color.orange : Color(red: 0.25, green: 0.84, blue: 0.48))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(content.recordCountText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.25, green: 0.84, blue: 0.48))
                    .monospacedDigit()
                Text(content.recordCountLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
            ForEach(content.metrics) { metric in
                metricView(metric)
            }
        }
    }

    private var costRow: some View {
        HStack(spacing: 22) {
            ForEach(content.costMetrics) { metric in
                metricView(metric).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
        }
    }

    private func metricView(_ metric: ActivityPeriodShareMetric) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(metric.value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
    }

    private var detailFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hiddenDetailsLabel = content.hiddenDetailsLabel {
                Label(hiddenDetailsLabel, systemImage: "eye.slash.fill")
                    .foregroundStyle(.white.opacity(0.55))
            }
            ForEach(content.scopeLabels, id: \.self) { label in
                Label(label, systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.white.opacity(0.55))
            }
            ForEach(content.coverageNotes, id: \.self) { note in
                Text(note).foregroundStyle(.white.opacity(0.42))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
    }
}

public struct ActivityPeriodShareComposerView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var options = ActivityPeriodShareCardOptions()
    @State private var sharedImage: ActivityPeriodSharedImage?
    @State private var renderError: String?

    let summary: ActivityPeriodSummary
    let dateFilter: ActivityDateFilter
    let activityFilter: ActivityFilter
    let dateRange: ActivityPeriodDateRange?
    let historyIsComplete: Bool
    let locationFilterIsActive: Bool
    let currencyCode: String
    let units: UnitPreferences?

    public init(
        summary: ActivityPeriodSummary,
        dateFilter: ActivityDateFilter,
        activityFilter: ActivityFilter,
        dateRange: ActivityPeriodDateRange?,
        historyIsComplete: Bool,
        locationFilterIsActive: Bool,
        currencyCode: String,
        units: UnitPreferences?
    ) {
        self.summary = summary
        self.dateFilter = dateFilter
        self.activityFilter = activityFilter
        self.dateRange = dateRange
        self.historyIsComplete = historyIsComplete
        self.locationFilterIsActive = locationFilterIsActive
        self.currencyCode = currencyCode
        self.units = units
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Form {
                    Section {
                        Toggle(t("Include exact activity dates", "包含精确活动日期"), isOn: $options.includesExactDateRange)
                            .disabled(dateRange == nil)
                        Toggle(t("Include costs", "包含费用"), isOn: $options.includesCosts)
                    }
                    if options.includesSensitiveDetails {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Sensitive details selected", "已选择敏感信息")).font(.headline)
                                    Text(t(
                                        "Anyone receiving this image can see the selected period details.",
                                        "收到图片的人都能看到已选择的周期信息。"
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                    if !historyIsComplete {
                        Section {
                            Label(
                                t("This recap uses loaded records only and marks totals as partial.", "此回顾仅使用已加载记录，并将汇总标记为不完整。"),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
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
            .navigationTitle(t("Share Period Recap", "分享周期回顾"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { dismiss() }
                }
            }
        }
        .sheet(item: $sharedImage) { payload in
            ActivityPeriodShareActivityView(activityItems: [payload.image])
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
            let widthScale = max((proxy.size.width - 32) / ActivityPeriodShareCardView.size.width, 0.1)
            let heightScale = max((proxy.size.height - 24) / ActivityPeriodShareCardView.size.height, 0.1)
            let scale = min(widthScale, heightScale)
            ActivityPeriodShareCardView(content: cardContent)
                .scaleEffect(scale)
                .frame(width: ActivityPeriodShareCardView.size.width * scale, height: ActivityPeriodShareCardView.size.height * scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 310)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Period Recap Share Card", "周期回顾分享卡片"))
    }

    private var cardContent: ActivityPeriodShareCardContent {
        ActivityPeriodShareCardBuilder.content(
            summary: summary,
            dateFilter: dateFilter,
            activityFilter: activityFilter,
            dateRange: dateRange,
            historyIsComplete: historyIsComplete,
            locationFilterIsActive: locationFilterIsActive,
            currencyCode: currencyCode,
            units: units,
            language: appLanguage,
            options: options
        )
    }

    @MainActor
    private func shareImage() {
        let renderer = ImageRenderer(content: ActivityPeriodShareCardView(content: cardContent))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            renderError = t("Unable to create share image.", "无法生成分享图片。")
            return
        }
        sharedImage = ActivityPeriodSharedImage(image: image)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ActivityPeriodSharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ActivityPeriodShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
