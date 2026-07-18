import Foundation
import SwiftUI

public enum ActivitySessionCardSemanticColor: String, Equatable, Sendable {
    case neutral
    case blue
    case green
    case orange
    case indigo
}

public enum ActivitySessionCardMetricKind: String, Equatable, Hashable, Sendable {
    case parkingDuration
    case netBatteryChange
    case chargeGain
    case standbyLoss
    case ratedRangeChange
    case cost
}

public struct ActivitySessionCardMetric: Identifiable, Equatable, Sendable {
    public var id: ActivitySessionCardMetricKind { kind }

    public let kind: ActivitySessionCardMetricKind
    public let title: String
    public let value: String
    public let systemImage: String
    public let semanticColor: ActivitySessionCardSemanticColor
    public let sourceText: String?

    public init(
        kind: ActivitySessionCardMetricKind,
        title: String,
        value: String,
        systemImage: String,
        semanticColor: ActivitySessionCardSemanticColor,
        sourceText: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.semanticColor = semanticColor
        self.sourceText = sourceText
    }

    public var accessibilityText: String {
        [title, value, sourceText].compactMap { $0 }.joined(separator: ", ")
    }
}

public struct ActivitySessionCardPresentation: Equatable, Sendable {
    public let title: String
    public let placeText: String
    public let timeText: String
    public let systemImage: String
    public let semanticColor: ActivitySessionCardSemanticColor
    public let metrics: [ActivitySessionCardMetric]

    public init(
        title: String,
        placeText: String,
        timeText: String,
        systemImage: String,
        semanticColor: ActivitySessionCardSemanticColor,
        metrics: [ActivitySessionCardMetric]
    ) {
        self.title = title
        self.placeText = placeText
        self.timeText = timeText
        self.systemImage = systemImage
        self.semanticColor = semanticColor
        self.metrics = metrics
    }

    public var accessibilityLabel: String {
        [title, placeText, timeText].joined(separator: ", ")
    }

    public var accessibilityValue: String {
        metrics.map(\.accessibilityText).joined(separator: ", ")
    }
}

public enum ActivitySessionCardBuilder {
    public static func presentation(
        session: SmartActivitySession,
        placeName: String? = nil,
        language: AppLanguage,
        units: UnitPreferences? = nil,
        locale: Locale? = nil,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> ActivitySessionCardPresentation {
        let purpose = session.classification?.purpose ?? session.provisionalKind
        let title = session.classification?.title(language: language) ?? purpose.title(language: language)
        let metrics = metrics(session: session, language: language, units: units)

        return ActivitySessionCardPresentation(
            title: title,
            placeText: resolvedPlaceText(session: session, placeName: placeName, language: language),
            timeText: timeText(
                start: session.startDate,
                end: session.endDate,
                isOpen: session.isOpen,
                language: language,
                locale: locale ?? resolvedLocale(language: language),
                timeZone: timeZone
            ),
            systemImage: session.classification?.systemImage ?? purpose.systemImage,
            semanticColor: sessionColor(session),
            metrics: metrics
        )
    }

    private static func metrics(
        session: SmartActivitySession,
        language: AppLanguage,
        units: UnitPreferences?
    ) -> [ActivitySessionCardMetric] {
        var rows: [ActivitySessionCardMetric] = []
        let qualityNeedsReview = session.parkingMetrics.map {
            $0.quality == .estimated || $0.quality == .partial
        } ?? false
        let measuredColor: ActivitySessionCardSemanticColor = qualityNeedsReview ? .orange : .neutral

        if let duration = session.parkingMetrics?.duration,
           duration.isFinite,
           duration > 0 {
            rows.append(ActivitySessionCardMetric(
                kind: .parkingDuration,
                title: localized("Parked", "停车时长", language: language),
                value: MateDroidUnitFormatter.formatDuration(
                    minutes: max(Int((duration / 60).rounded()), 1),
                    language: language
                ),
                systemImage: "clock.fill",
                semanticColor: (session.parkingMetrics?.sleepDuration ?? 0) > 0 ? .indigo : measuredColor
            ))
        }

        if let value = nonzero(session.parkingMetrics?.netBatteryChangePercent) {
            rows.append(ActivitySessionCardMetric(
                kind: .netBatteryChange,
                title: localized("Net battery change", "电量净变化", language: language),
                value: signedPercent(value),
                systemImage: "battery.50percent",
                semanticColor: qualityNeedsReview ? .orange : (value > 0 ? .green : .neutral)
            ))
        }

        if let value = nonzero(session.parkingMetrics?.chargeGainPercent) {
            rows.append(ActivitySessionCardMetric(
                kind: .chargeGain,
                title: localized("Charge gain", "充电增加", language: language),
                value: signedPercent(value),
                systemImage: "bolt.fill",
                semanticColor: qualityNeedsReview ? .orange : .green
            ))
        }

        if let value = nonzero(session.parkingMetrics?.standbyBatteryChangePercent) {
            rows.append(ActivitySessionCardMetric(
                kind: .standbyLoss,
                title: localized("Standby change", "待机变化", language: language),
                value: signedPercent(value),
                systemImage: "moon.zzz.fill",
                semanticColor: qualityNeedsReview ? .orange : .indigo
            ))
        }

        if let value = nonzeroFinite(session.parkingMetrics?.ratedRangeChangeKm) {
            rows.append(ActivitySessionCardMetric(
                kind: .ratedRangeChange,
                title: localized("Rated-range change", "表显续航变化", language: language),
                value: signedDistance(value, units: units),
                systemImage: "gauge.with.dots.needle.33percent",
                semanticColor: qualityNeedsReview ? .orange : (value > 0 ? .green : .neutral)
            ))
        }

        if let cost = validCost(session.chargeCost) {
            let needsReview = cost.isEstimated
            rows.append(ActivitySessionCardMetric(
                kind: .cost,
                title: localized("Charging cost", "充电费用", language: language),
                value: costText(cost, language: language),
                systemImage: "creditcard.fill",
                semanticColor: needsReview ? .orange : .green,
                sourceText: costSourceText(cost, language: language)
            ))
        }

        return rows
    }

    private static func validCost(_ cost: SmartActivityChargeCost?) -> SmartActivityChargeCost? {
        guard let cost,
              cost.amount.isFinite,
              cost.amount >= 0,
              cost.amount > 0 || cost.isExplicitlyFree
        else { return nil }
        return cost
    }

    private static func costText(_ cost: SmartActivityChargeCost, language: AppLanguage) -> String {
        if cost.isExplicitlyFree, cost.amount == 0 {
            return localized("Free", "免费", language: language)
        }
        return MateDroidCurrencyFormatter.symbol(for: cost.currencyCode) + String(format: "%.2f", cost.amount)
    }

    private static func costSourceText(_ cost: SmartActivityChargeCost, language: AppLanguage) -> String {
        let status = cost.isEstimated
            ? localized("Estimated", "估算", language: language)
            : localized("Confirmed", "已确认", language: language)
        let source: String
        switch cost.source {
        case .manual:
            source = localized("Manual entry", "手动录入", language: language)
        case .api:
            source = localized("TeslaMate", "TeslaMate", language: language)
        case .stationRule:
            source = localized("Station rule", "充电站规则", language: language)
        case .homeRule:
            source = localized("Home rule", "家庭规则", language: language)
        case .regionalTariff:
            source = localized("Regional tariff", "地区电价", language: language)
        }
        return "\(status) · \(source)"
    }

    private static func resolvedPlaceText(
        session: SmartActivitySession,
        placeName: String?,
        language: AppLanguage
    ) -> String {
        if let placeName = nonempty(placeName) { return placeName }

        for reference in session.eventReferences.reversed() {
            if let address = nonempty(reference.sourceActivity.endAddress) ?? nonempty(reference.sourceActivity.startAddress) {
                return address
            }
        }

        if session.placeKey.hasPrefix("geofence:") {
            return localized("Saved place", "已保存地点", language: language)
        }
        if session.placeKey.hasPrefix("coordinate:") {
            return localized("Recorded location", "已记录位置", language: language)
        }
        if session.placeKey.hasPrefix("drive:") {
            return localized("Drive endpoint", "行程终点", language: language)
        }
        return localized("Parking location", "停车地点", language: language)
    }

    private static func timeText(
        start: Date,
        end: Date?,
        isOpen: Bool,
        language: AppLanguage,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let dateTime = DateFormatter()
        dateTime.locale = locale
        dateTime.timeZone = timeZone
        dateTime.dateStyle = .medium
        dateTime.timeStyle = .short

        guard let end, end >= start, !isOpen else {
            return "\(dateTime.string(from: start)) · \(localized("Ongoing", "进行中", language: language))"
        }

        var zonedCalendar = Calendar(identifier: .gregorian)
        zonedCalendar.timeZone = timeZone
        if zonedCalendar.isDate(start, inSameDayAs: end) {
            let timeOnly = DateFormatter()
            timeOnly.locale = locale
            timeOnly.timeZone = timeZone
            timeOnly.dateStyle = .none
            timeOnly.timeStyle = .short
            return "\(dateTime.string(from: start)) – \(timeOnly.string(from: end))"
        }
        return "\(dateTime.string(from: start)) – \(dateTime.string(from: end))"
    }

    private static func sessionColor(_ session: SmartActivitySession) -> ActivitySessionCardSemanticColor {
        let metricsNeedReview = session.parkingMetrics.map {
            $0.quality == .estimated || $0.quality == .partial
        } ?? false
        let sessionNeedsReview = session.quality == .estimated || session.quality == .partial
        if session.chargeCost?.isEstimated == true || metricsNeedReview || sessionNeedsReview { return .orange }

        let purpose = session.classification?.purpose ?? session.provisionalKind
        let isChargingSession = session.eventReferences.contains(where: { $0.kind == .charge })
            || purpose == .replenishment
            || purpose == .homeCharging
            || purpose == .workCharging
        if isChargingSession,
           let chargeGain = session.parkingMetrics?.chargeGainPercent,
           chargeGain > 0 {
            return .green
        }
        if let sleep = session.parkingMetrics?.sleepDuration, sleep.isFinite, sleep > 0 { return .indigo }
        if session.eventReferences.contains(where: { $0.kind == .drive }) { return .blue }
        return .neutral
    }

    private static func signedPercent(_ value: Int) -> String {
        "\(value > 0 ? "+" : "")\(value)%"
    }

    private static func signedDistance(_ value: Double, units: UnitPreferences?) -> String {
        let formatted = MateDroidUnitFormatter.formatDistance(abs(value), units: units)
        return "\(value > 0 ? "+" : "-")\(formatted)"
    }

    private static func nonzero(_ value: Int?) -> Int? {
        guard let value, value != 0 else { return nil }
        return value
    }

    private static func nonzeroFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value != 0 else { return nil }
        return value
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func resolvedLocale(language: AppLanguage) -> Locale {
        language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct ActivitySessionCard: View {
    public let presentation: ActivitySessionCardPresentation

    public init(presentation: ActivitySessionCardPresentation) {
        self.presentation = presentation
    }

    public init(
        session: SmartActivitySession,
        placeName: String? = nil,
        language: AppLanguage = .system,
        units: UnitPreferences? = nil
    ) {
        presentation = ActivitySessionCardBuilder.presentation(
            session: session,
            placeName: placeName,
            language: language,
            units: units
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label(presentation.title, systemImage: presentation.systemImage)
                    .font(.headline)
                    .foregroundStyle(color(presentation.semanticColor))
                Text(presentation.placeText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presentation.timeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(presentation.metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Divider()
                }
                metricRow(metric)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
    }

    @ViewBuilder
    private func metricRow(_ metric: ActivitySessionCardMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(metric.title, systemImage: metric.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(color(metric.semanticColor))
                .fixedSize(horizontal: false, vertical: true)
            if let sourceText = metric.sourceText {
                Text(sourceText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color(metric.semanticColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func color(_ semanticColor: ActivitySessionCardSemanticColor) -> Color {
        switch semanticColor {
        case .neutral: return .secondary
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .indigo: return .indigo
        }
    }
}
