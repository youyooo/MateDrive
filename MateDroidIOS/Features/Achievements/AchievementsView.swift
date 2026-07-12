import SwiftUI

public struct AchievementsView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: AchievementsViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: AchievementsViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading achievements", "正在加载成就"), showsProgress: true)
            } else if let error = viewModel.state.errorMessage, viewModel.state.achievements.isEmpty {
                LoadingStateView(title: t("Achievements unavailable", "成就不可用"), message: UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "medal")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        summary
                        ForEach(viewModel.state.achievements) { achievement in
                            achievementCard(achievement)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await viewModel.load(carId: carId) }
            }
        }
        .navigationTitle(t("Achievements", "成就"))
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var summary: some View {
        let total = viewModel.state.summary?.total ?? viewModel.state.achievements.count
        let unlocked = viewModel.state.summary?.unlocked ?? viewModel.state.achievements.filter { $0.tiers.contains(where: \.unlocked) }.count
        return HStack {
            Label(t("Unlocked", "已解锁"), systemImage: "trophy.fill")
            Spacer()
            Text("\(unlocked) / \(total)").font(.title3.bold()).monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func achievementCard(_ achievement: TeslaMateAchievement) -> some View {
        let definition = AchievementDefinition.definition(for: achievement.id)
        let bestTier = achievement.tiers.max { ($0.progress ?? 0) < ($1.progress ?? 0) }
        let unlocked = achievement.tiers.contains(where: \.unlocked)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: definition.systemImage)
                    .font(.title2)
                    .foregroundStyle(unlocked ? Color.yellow : Color.accentColor)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(definition.englishTitle, definition.chineseTitle)).font(.headline)
                    Text(localized(definition.englishDescription, definition.chineseDescription))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if unlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
            }
            if let bestTier {
                ProgressView(value: min(max(bestTier.progress ?? 0, 0), 1))
                HStack {
                    Text(currentValue(achievement))
                    Spacer()
                    Text(threshold(bestTier.threshold, unit: achievement.unit))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            tierRows(achievement)
            extraDetails(achievement)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tierRows(_ achievement: TeslaMateAchievement) -> some View {
        ForEach(achievement.tiers) { tier in
            HStack {
                Label(t("Tier \(tier.tier)", "第 \(tier.tier) 级"), systemImage: tier.unlocked ? "lock.open.fill" : "lock.fill")
                Spacer()
                if let date = tier.unlockedAt.flatMap(DomainDateParser.date(from:)) {
                    Text(date.formatted(date: .abbreviated, time: .omitted)).foregroundStyle(.secondary)
                }
                if let driveId = tier.unlockedDriveId {
                    Button { navigate(.driveDetail(carId: carId, driveId: driveId, exteriorColor: exteriorColor)) } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .accessibilityLabel(t("View related drive", "查看关联行程"))
                }
            }
            .font(.footnote)
        }
    }

    @ViewBuilder
    private func extraDetails(_ achievement: TeslaMateAchievement) -> some View {
        if let missing = achievement.missingHours, !missing.isEmpty {
            Text(t("Missing hours: \(missing.map(String.init).joined(separator: ", "))", "尚缺时段：\(missing.map(String.init).joined(separator: "、")) 点"))
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let places = achievement.visitedPlaces, !places.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(places.prefix(8)) { place in
                    HStack { Text(verbatim: place.name); Spacer(); Text(place.days.map { t("\(format($0)) days", "\(format($0)) 天") } ?? "--") }
                        .font(.footnote)
                }
            }
        }
        if achievement.auxiliaryMinimum != nil || achievement.auxiliaryMaximum != nil {
            HStack {
                Label(extreme(achievement.auxiliaryMinimum, achievement: achievement), systemImage: "arrow.down")
                Spacer()
                Label(extreme(achievement.auxiliaryMaximum, achievement: achievement), systemImage: "arrow.up")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private func currentValue(_ achievement: TeslaMateAchievement) -> String {
        value(achievement.currentValue, unit: achievement.unit)
    }

    private func threshold(_ value: Double?, unit: String?) -> String {
        t("Goal: \(self.value(value, unit: unit))", "目标：\(self.value(value, unit: unit))")
    }

    private func extreme(_ value: Double?, achievement: TeslaMateAchievement) -> String {
        let unit = achievement.id == "thermal_shock" ? "°C" : achievement.id == "vertical_horizon" ? "m" : achievement.unit
        return self.value(value, unit: unit)
    }

    private func value(_ value: Double?, unit: String?) -> String {
        guard let value else { return "--" }
        let units = viewModel.state.units.resolved(for: appDisplayUnitSystem)
        switch unit {
        case "km": return MateDroidUnitFormatter.formatDistance(value, units: units, decimals: 1)
        case "m": return MateDroidUnitFormatter.formatElevation(Int(value.rounded()), units: units)
        case "°C": return MateDroidUnitFormatter.formatTemperature(value, units: units, decimals: 1)
        case "days": return t("\(format(value)) days", "\(format(value)) 天")
        case "min": return MateDroidUnitFormatter.formatDuration(minutes: Int(value.rounded()), language: appLanguage)
        case let unit?: return "\(format(value)) \(unit)"
        case nil: return format(value)
        }
    }

    private func format(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f" : "%.1f", value)
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private func t(_ english: String, _ chinese: String) -> String { localized(english, chinese) }
}
