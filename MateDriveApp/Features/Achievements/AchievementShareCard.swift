import SwiftUI
import UIKit

public struct AchievementShareCardOptions: Equatable, Sendable {
    public var includesUnlockDates: Bool
    public var includesPlaceNames: Bool
    public var includesProgressDetails: Bool

    public init(
        includesUnlockDates: Bool = false,
        includesPlaceNames: Bool = false,
        includesProgressDetails: Bool = false
    ) {
        self.includesUnlockDates = includesUnlockDates
        self.includesPlaceNames = includesPlaceNames
        self.includesProgressDetails = includesProgressDetails
    }

    public var includesSensitiveDetails: Bool {
        includesUnlockDates || includesPlaceNames || includesProgressDetails
    }
}

public struct AchievementShareTier: Equatable, Identifiable, Sendable {
    public let tier: Int
    public let title: String
    public let unlocked: Bool
    public let progress: Double?
    public let progressText: String
    public let unlockDateText: String?

    public var id: Int { tier }
}

public struct AchievementShareCardContent: Equatable, Sendable {
    public let reportTitle: String
    public let achievementTitle: String
    public let achievementDescription: String
    public let systemImage: String
    public let statusText: String
    public let isUnlocked: Bool
    public let currentValueText: String
    public let currentLabel: String
    public let goalText: String
    public let goalLabel: String
    public let progress: Double?
    public let progressText: String
    public let progressLabel: String
    public let tiers: [AchievementShareTier]
    public let placeNamesText: String?
    public let detailLines: [String]
    public let hiddenDetailsLabel: String?
    public let optionsIncludeSensitiveDetails: Bool
}

public enum AchievementShareCardBuilder {
    public static func content(
        achievement: TeslaMateAchievement,
        units: UnitPreferences?,
        language: AppLanguage,
        options: AchievementShareCardOptions
    ) -> AchievementShareCardContent {
        let definition = AchievementDefinition.definition(for: achievement.id)
        let sortedTiers = achievement.tiers.sorted { $0.tier < $1.tier }
        let focusTier = sortedTiers.first(where: { !$0.unlocked }) ?? sortedTiers.last
        let unlocked = sortedTiers.contains(where: \.unlocked)
        let progress = focusTier?.progress.flatMap(validProgress)

        return AchievementShareCardContent(
            reportTitle: localized("Achievement Card", "成就卡片", language: language),
            achievementTitle: localized(definition.englishTitle, definition.chineseTitle, language: language),
            achievementDescription: localized(definition.englishDescription, definition.chineseDescription, language: language),
            systemImage: definition.systemImage,
            statusText: unlocked
                ? localized("Unlocked", "已解锁", language: language)
                : localized("In Progress", "进行中", language: language),
            isUnlocked: unlocked,
            currentValueText: formatValue(achievement.currentValue, unit: achievement.unit, units: units, language: language),
            currentLabel: localized("Current", "当前", language: language),
            goalText: formatValue(focusTier?.threshold, unit: achievement.unit, units: units, language: language),
            goalLabel: localized("Goal", "目标", language: language),
            progress: progress,
            progressText: progress.map { String(format: "%.0f%%", $0 * 100) } ?? "--",
            progressLabel: localized("Progress", "进度", language: language),
            tiers: sortedTiers.map {
                AchievementShareTier(
                    tier: $0.tier,
                    title: String(
                        format: localized("Tier %d", "第 %d 级", language: language),
                        $0.tier
                    ),
                    unlocked: $0.unlocked,
                    progress: $0.progress.flatMap(validProgress),
                    progressText: $0.progress.flatMap(validProgress).map { String(format: "%.0f%%", $0 * 100) } ?? "--",
                    unlockDateText: options.includesUnlockDates ? unlockDate($0.unlockedAt, language: language) : nil
                )
            },
            placeNamesText: options.includesPlaceNames ? placeNames(achievement.visitedPlaces, language: language) : nil,
            detailLines: options.includesProgressDetails
                ? progressDetails(achievement, units: units, language: language)
                : [],
            hiddenDetailsLabel: hiddenDetailsLabel(achievement: achievement, options: options, language: language),
            optionsIncludeSensitiveDetails: options.includesSensitiveDetails
        )
    }

    private static func validProgress(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    private static func unlockDate(_ value: String?, language: AppLanguage) -> String? {
        guard let date = value.flatMap(DomainDateParser.date(from:)) else { return nil }
        let locale = language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
    }

    private static func placeNames(_ places: [AchievementPlace]?, language: AppLanguage) -> String? {
        let names = (places ?? []).prefix(4).map(\.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: localized(", ", "、", language: language))
    }

    private static func progressDetails(
        _ achievement: TeslaMateAchievement,
        units: UnitPreferences?,
        language: AppLanguage
    ) -> [String] {
        var lines: [String] = []
        if let hours = achievement.missingHours, !hours.isEmpty {
            let values = hours.map(String.init).joined(separator: localized(", ", "、", language: language))
            lines.append(String(
                format: localized("Missing hours: %@", "尚缺时段：%@ 点", language: language),
                values
            ))
        }
        if achievement.id == "thermal_shock",
           achievement.auxiliaryMinimum != nil || achievement.auxiliaryMaximum != nil {
            lines.append(extremeLine(
                minimum: achievement.auxiliaryMinimum,
                maximum: achievement.auxiliaryMaximum,
                unit: "°C",
                units: units,
                language: language
            ))
        } else if achievement.id == "vertical_horizon",
                  achievement.auxiliaryMinimum != nil || achievement.auxiliaryMaximum != nil {
            lines.append(extremeLine(
                minimum: achievement.auxiliaryMinimum,
                maximum: achievement.auxiliaryMaximum,
                unit: "m",
                units: units,
                language: language
            ))
        }
        return lines
    }

    private static func extremeLine(
        minimum: Double?,
        maximum: Double?,
        unit: String,
        units: UnitPreferences?,
        language: AppLanguage
    ) -> String {
        let low = formatValue(minimum, unit: unit, units: units, language: language)
        let high = formatValue(maximum, unit: unit, units: units, language: language)
        return String(format: localized("Recorded range: %@ – %@", "记录范围：%@ – %@", language: language), low, high)
    }

    private static func hiddenDetailsLabel(
        achievement: TeslaMateAchievement,
        options: AchievementShareCardOptions,
        language: AppLanguage
    ) -> String? {
        var hidden: [String] = []
        if !options.includesUnlockDates, achievement.tiers.contains(where: { $0.unlockedAt != nil }) {
            hidden.append(localized("unlock dates", "解锁日期", language: language))
        }
        if !options.includesPlaceNames, !(achievement.visitedPlaces ?? []).isEmpty {
            hidden.append(localized("place names", "地点名称", language: language))
        }
        let hasDetails = !(achievement.missingHours ?? []).isEmpty
            || achievement.auxiliaryMinimum != nil
            || achievement.auxiliaryMaximum != nil
        if !options.includesProgressDetails, hasDetails {
            hidden.append(localized("progress details", "进度细节", language: language))
        }
        guard !hidden.isEmpty else { return nil }
        return String(
            format: localized("%@ hidden", "%@ 已隐藏", language: language),
            hidden.joined(separator: localized(", ", "、", language: language))
        )
    }

    private static func formatValue(
        _ value: Double?,
        unit: String?,
        units: UnitPreferences?,
        language: AppLanguage
    ) -> String {
        guard let value, value.isFinite else { return "--" }
        switch unit {
        case "km":
            return MateDriveUnitFormatter.formatDistance(value, units: units, decimals: 1)
        case "m":
            return MateDriveUnitFormatter.formatElevation(Int(value.rounded()), units: units)
        case "°C":
            return MateDriveUnitFormatter.formatTemperature(value, units: units, decimals: 1)
        case "days":
            return String(format: localized("%@ days", "%@ 天", language: language), number(value))
        case "min":
            return MateDriveUnitFormatter.formatDuration(minutes: Int(value.rounded()), language: language)
        case let unit?:
            return "\(number(value)) \(unit)"
        case nil:
            return number(value)
        }
    }

    private static func number(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct AchievementShareCardView: View {
    public static let size = CGSize(width: 540, height: 675)

    let content: AchievementShareCardContent

    public init(content: AchievementShareCardContent) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.063, blue: 0.071)
            VStack(alignment: .leading, spacing: 0) {
                header
                hero.padding(.top, 30)
                valueGrid.padding(.top, 28)
                tierSection.padding(.top, 24)
                Spacer(minLength: 14)
                details
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
            Spacer()
            Text(content.reportTitle)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var hero: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle().fill(.white.opacity(0.07))
                Circle()
                    .stroke(content.isUnlocked ? Color.yellow.opacity(0.8) : Color.cyan.opacity(0.7), lineWidth: 4)
                    .padding(7)
                Image(systemName: content.systemImage)
                    .font(.system(size: 43, weight: .semibold))
                    .foregroundStyle(content.isUnlocked ? Color.yellow : Color.cyan)
            }
            .frame(width: 116, height: 116)

            VStack(alignment: .leading, spacing: 7) {
                Label(content.statusText, systemImage: content.isUnlocked ? "checkmark.seal.fill" : "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(content.isUnlocked ? Color.green : Color.cyan)
                Text(content.achievementTitle)
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(content.achievementDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(3)
            }
        }
    }

    private var valueGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                valueCell(title: content.currentLabel, value: content.currentValueText, icon: "gauge.with.dots.needle.50percent")
                valueCell(title: content.goalLabel, value: content.goalText, icon: "flag.checkered")
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(content.progressLabel)
                        .foregroundStyle(.white.opacity(0.52))
                    Spacer()
                    Text(content.progressText).foregroundStyle(.white).monospacedDigit()
                }
                .font(.system(size: 13, weight: .semibold))
                shareProgressBar(
                    value: content.progress,
                    color: content.progress == nil ? .gray : .green
                )
            }
            .padding(14)
            .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func valueCell(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tierSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(content.tiers.prefix(4)) { tier in
                HStack(spacing: 10) {
                    Image(systemName: tier.unlocked ? "lock.open.fill" : "lock.fill")
                        .foregroundStyle(tier.unlocked ? Color.green : Color.white.opacity(0.42))
                        .frame(width: 20)
                    Text(tier.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    shareProgressBar(
                        value: tier.progress,
                        color: tier.progress == nil ? .gray : .green
                    )
                    Text(tier.progressText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                    if let date = tier.unlockDateText {
                        Text(date)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let places = content.placeNamesText {
                Label(places, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(content.detailLines, id: \.self) { line in
                Label(line, systemImage: "info.circle")
                    .foregroundStyle(.white.opacity(0.55))
            }
            if let hidden = content.hiddenDetailsLabel {
                Label(hidden, systemImage: "eye.slash.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }

    private func shareProgressBar(value: Double?, color: Color) -> some View {
        GeometryReader { proxy in
            let progress = min(max(value ?? 0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 5)
    }
}

public struct AchievementShareComposerView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var options = AchievementShareCardOptions()
    @State private var sharedImage: AchievementSharedImage?
    @State private var renderError: String?

    let achievement: TeslaMateAchievement
    let units: UnitPreferences?

    public init(achievement: TeslaMateAchievement, units: UnitPreferences?) {
        self.achievement = achievement
        self.units = units
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Form {
                    Section {
                        Toggle(t("Include unlock dates", "包含解锁日期"), isOn: $options.includesUnlockDates)
                            .disabled(!hasUnlockDates)
                        Toggle(t("Include place names", "包含地点名称"), isOn: $options.includesPlaceNames)
                            .disabled(!hasPlaces)
                        Toggle(t("Include progress details", "包含进度细节"), isOn: $options.includesProgressDetails)
                            .disabled(!hasProgressDetails)
                    }
                    if options.includesSensitiveDetails {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Sensitive details selected", "已选择敏感信息")).font(.headline)
                                    Text(t(
                                        "Anyone receiving this image can see the selected achievement details.",
                                        "收到图片的人都能看到已选择的成就信息。"
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
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
            .navigationTitle(t("Share Achievement", "分享成就"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { dismiss() }
                }
            }
        }
        .sheet(item: $sharedImage) { payload in
            AchievementShareActivityView(activityItems: [payload.image])
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
            let widthScale = max((proxy.size.width - 32) / AchievementShareCardView.size.width, 0.1)
            let heightScale = max((proxy.size.height - 24) / AchievementShareCardView.size.height, 0.1)
            let scale = min(widthScale, heightScale)
            AchievementShareCardView(content: cardContent)
                .scaleEffect(scale)
                .frame(width: AchievementShareCardView.size.width * scale, height: AchievementShareCardView.size.height * scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 310)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Achievement Share Card", "成就分享卡片"))
    }

    private var cardContent: AchievementShareCardContent {
        AchievementShareCardBuilder.content(
            achievement: achievement,
            units: units,
            language: appLanguage,
            options: options
        )
    }

    private var hasUnlockDates: Bool { achievement.tiers.contains { $0.unlockedAt != nil } }
    private var hasPlaces: Bool { !(achievement.visitedPlaces ?? []).isEmpty }
    private var hasProgressDetails: Bool {
        !(achievement.missingHours ?? []).isEmpty
            || achievement.auxiliaryMinimum != nil
            || achievement.auxiliaryMaximum != nil
    }

    @MainActor
    private func shareImage() {
        let renderer = ImageRenderer(content: AchievementShareCardView(content: cardContent))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            renderError = t("Unable to create share image.", "无法生成分享图片。")
            return
        }
        sharedImage = AchievementSharedImage(image: image)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct AchievementSharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct AchievementShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
