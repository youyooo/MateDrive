import SwiftUI

struct DashboardOverviewCards: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme

    let items: [DashboardOverviewItem]
    let onSelect: (AppRoute) -> Void

    var body: some View {
        VStack(spacing: 9) {
            ForEach(items) { item in
                Button {
                    guard let route = item.route else { return }
                    onSelect(route)
                } label: {
                    card(item)
                }
                .buttonStyle(.plain)
                .disabled(item.route == nil)
            }
        }
    }

    private func card(_ item: DashboardOverviewItem) -> some View {
        let accent = accentColor(item.accent)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let highlightTint = item.highlight.map { highlightColor($0.style) }

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 11) {
                cardHeader(item, accent: accent)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: item.primaryLabel)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(supportingTextColor)
                        Text(verbatim: item.primaryValue)
                            .font(.system(item.accent == .odometer ? .title : .title2, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(primaryValueColor(item, accent: accent))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    if let timestamp = item.timestamp,
                       item.highlight?.style == .gold || item.highlight?.style == .personalBest {
                        Text(verbatim: timestamp)
                            .font(.caption)
                            .foregroundStyle(timestampTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                metricRow(item.metrics, accent: accent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, item.highlight == nil ? 13 : 11)

            if let highlight = item.highlight {
                highlightStrip(highlight)
            }
        }
        .frame(maxWidth: .infinity, minHeight: item.accent == .odometer ? 140 : 130, alignment: .leading)
        .background {
            shape.fill(Color(uiColor: .secondarySystemBackground))
            if let highlightTint {
                shape.fill(highlightTint.opacity(colorScheme == .dark ? 0.08 : 0.045))
            }
        }
        .overlay {
            shape.stroke(
                highlightTint ?? Color(uiColor: .separator).opacity(0.24),
                lineWidth: item.highlight.map { borderWidth($0.style) } ?? 0.7
            )
        }
        .shadow(
            color: achievementShadow(item.highlight),
            radius: item.highlight?.style == .personalBest ? 12 : 0,
            x: 0,
            y: 5
        )
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            item.route == nil
                ? Text("")
                : Text(verbatim: AppText.localized("Open details", "打开详情", language: appLanguage))
        )
    }

    private func cardHeader(_ item: DashboardOverviewItem, accent: Color) -> some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.11))
                Image(systemName: item.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 28, height: 28)

            Text(verbatim: item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let highlight = item.highlight,
               highlight.style == .personalBest || highlight.style == .gold {
                Label(
                    highlight.style == .personalBest
                        ? AppText.localized("Best", "最佳", language: appLanguage)
                        : AppText.localized("No. 1", "第 1 名", language: appLanguage),
                    systemImage: "trophy.fill"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(achievementBadgeColor(highlight.style))
                .fixedSize(horizontal: false, vertical: true)
            } else if let timestamp = item.timestamp {
                Text(verbatim: timestamp)
                    .font(.caption)
                    .foregroundStyle(timestampTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if item.route != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func metricRow(_ metrics: [DashboardOverviewMetric], accent: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Divider()
                        .frame(height: 36)
                        .padding(.horizontal, 7)
                }
                metricView(metric, accent: accent)
            }
        }
    }

    private func metricView(_ metric: DashboardOverviewMetric, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(metric.label, systemImage: metricIcon(metric.id))
                .font(.caption2.weight(.medium))
                .foregroundStyle(supportingTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: metric.value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(metricColor(metric.id, fallback: accent))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightStrip(_ highlight: DashboardOverviewHighlight) -> some View {
        let tint = highlightColor(highlight.style)
        return HStack(spacing: 11) {
            Image(systemName: highlight.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(achievementBadgeColor(highlight.style))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: highlight.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: highlight.detail)
                    .font(.caption)
                    .foregroundStyle(supportingTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(colorScheme == .dark ? 0.12 : 0.075))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tint.opacity(0.28))
                .frame(height: 0.7)
        }
    }

    private func primaryValueColor(_ item: DashboardOverviewItem, accent: Color) -> Color {
        guard let highlight = item.highlight else { return accent }
        switch highlight.style {
        case .personalBest, .gold:
            return highlightColor(highlight.style)
        default:
            return accent
        }
    }

    private func accentColor(_ accent: DashboardOverviewAccent) -> Color {
        switch accent {
        case .drive:
            return colorScheme == .dark
                ? Color(red: 0.31, green: 0.65, blue: 1.00)
                : Color(red: 0.08, green: 0.38, blue: 0.76)
        case .charge:
            return colorScheme == .dark
                ? Color(red: 0.26, green: 0.84, blue: 0.49)
                : Color(red: 0.02, green: 0.43, blue: 0.17)
        case .odometer:
            return colorScheme == .dark
                ? Color(red: 1.00, green: 0.69, blue: 0.28)
                : Color(red: 0.56, green: 0.27, blue: 0.00)
        }
    }

    private func highlightColor(_ style: DashboardOverviewHighlightStyle) -> Color {
        switch style {
        case .efficient:
            return accentColor(.charge)
        case .aboveBenchmark:
            return accentColor(.odometer)
        case .gold:
            return Color(red: 0.82, green: 0.58, blue: 0.10)
        case .personalBest:
            return accentColor(.charge)
        case .silver:
            return Color(red: 0.49, green: 0.54, blue: 0.61)
        case .bronze:
            return Color(red: 0.65, green: 0.38, blue: 0.20)
        case .progress:
            return accentColor(.drive)
        }
    }

    private var supportingTextColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.76 : 0.72)
    }

    private var timestampTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func borderWidth(_ style: DashboardOverviewHighlightStyle) -> CGFloat {
        switch style {
        case .personalBest, .gold:
            return 1.5
        case .silver, .bronze, .efficient, .aboveBenchmark:
            return 1.1
        case .progress:
            return 0.8
        }
    }

    private func achievementBadgeColor(_ style: DashboardOverviewHighlightStyle) -> Color {
        style == .personalBest
            ? Color(red: 0.82, green: 0.58, blue: 0.10)
            : highlightColor(style)
    }

    private func achievementShadow(_ highlight: DashboardOverviewHighlight?) -> Color {
        guard highlight?.style == .personalBest else { return .clear }
        return achievementBadgeColor(.personalBest).opacity(colorScheme == .dark ? 0.14 : 0.12)
    }

    private func metricIcon(_ id: String) -> String {
        switch id {
        case "range-drop": return "gauge.open.with.lines.needle.33percent"
        case "remaining-range": return "battery.75percent"
        case "duration": return "clock"
        case "battery-change": return "battery.100percent.bolt"
        case "cost": return "creditcard.fill"
        case "drive-count": return "road.lanes"
        case "latest-distance": return "arrow.right"
        case "rated-range": return "gauge.with.dots.needle.50percent"
        default: return "circle.fill"
        }
    }

    private func metricColor(_ id: String, fallback: Color) -> Color {
        switch id {
        case "range-drop":
            return accentColor(.odometer)
        case "remaining-range", "battery-change", "cost":
            return accentColor(.charge)
        default:
            return fallback
        }
    }
}
