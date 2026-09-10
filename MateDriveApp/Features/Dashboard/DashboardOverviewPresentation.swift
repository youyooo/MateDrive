import Foundation

enum DashboardOverviewAccent: Equatable, Sendable {
    case drive
    case charge
    case odometer
}

enum DashboardOverviewHighlightStyle: Equatable, Sendable {
    case efficient
    case aboveBenchmark
    case gold
    case silver
    case bronze
    case personalBest
    case progress
}

struct DashboardOverviewHighlight: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
    let style: DashboardOverviewHighlightStyle
}

struct DashboardOverviewMetric: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: String
}

struct DashboardOverviewItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let primaryLabel: String
    let primaryValue: String
    let timestamp: String?
    let metrics: [DashboardOverviewMetric]
    let systemImage: String
    let accent: DashboardOverviewAccent
    let highlight: DashboardOverviewHighlight?
    let route: AppRoute?
}

struct DashboardOverviewPresentation: Equatable, Sendable {
    let items: [DashboardOverviewItem]

    init(state: DashboardState, units: UnitPreferences?, language: AppLanguage) {
        let carId = state.selectedCarId
        let drive = state.latestDrive
        let charge = state.latestCharge

        items = [
            DashboardOverviewItem(
                id: "latest-drive",
                title: Self.text("Latest Drive", "最近一次行程", language: language),
                primaryLabel: Self.text("Actual Distance", "实际行驶", language: language),
                primaryValue: drive?.distanceKm.map {
                    MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 1)
                } ?? "--",
                timestamp: Self.dateText(drive?.endedAt ?? drive?.startedAt, language: language),
                metrics: [
                    DashboardOverviewMetric(
                        id: "range-drop",
                        label: Self.text("Rated Range Used", "表显消耗", language: language),
                        value: drive?.ratedRangeDropKm.map {
                            MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
                        } ?? "--"
                    ),
                    DashboardOverviewMetric(
                        id: "remaining-range",
                        label: Self.text("Estimated Remaining", "预计剩余", language: language),
                        value: drive?.remainingRatedRangeKm.map {
                            MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
                        } ?? "--"
                    ),
                    DashboardOverviewMetric(
                        id: "duration",
                        label: Self.text("Duration", "时长", language: language),
                        value: drive?.durationMinutes.map {
                            MateDriveUnitFormatter.formatDuration(minutes: $0, language: language)
                        } ?? "--"
                    )
                ],
                systemImage: "road.lanes",
                accent: .drive,
                highlight: Self.driveHighlight(drive, units: units, language: language),
                route: carId.map { id in
                    drive.map {
                        .driveDetail(carId: id, driveId: $0.driveId, exteriorColor: state.exteriorColor)
                    } ?? .drives(carId: id, exteriorColor: state.exteriorColor)
                }
            ),
            DashboardOverviewItem(
                id: "latest-charge",
                title: Self.text("Latest Charge", "最近一次充电", language: language),
                primaryLabel: Self.text("Energy Added", "充入电量", language: language),
                primaryValue: Self.energyText(charge?.energyAddedKWh),
                timestamp: Self.dateText(charge?.endedAt ?? charge?.startedAt, language: language),
                metrics: [
                    DashboardOverviewMetric(
                        id: "battery-change",
                        label: Self.text("Battery", "电量变化", language: language),
                        value: Self.batteryChangeText(charge)
                    ),
                    DashboardOverviewMetric(
                        id: "duration",
                        label: Self.text("Duration", "时长", language: language),
                        value: charge?.durationMinutes.map {
                            MateDriveUnitFormatter.formatDuration(minutes: $0, language: language)
                        } ?? "--"
                    ),
                    DashboardOverviewMetric(
                        id: "cost",
                        label: charge?.isCostHistoricalReference == true
                            ? Self.text("Historical reference", "历史参考费用", language: language)
                            : (
                                charge?.isCostEstimated == true
                                    ? Self.text("Estimated", "预计费用", language: language)
                                    : Self.text("Cost", "本次费用", language: language)
                            ),
                        value: Self.costText(
                            charge?.cost,
                            currencyCode: state.currencyCode,
                            language: language
                        )
                    )
                ],
                systemImage: "bolt.fill",
                accent: .charge,
                highlight: nil,
                route: carId.map { id in
                    charge.map {
                        .chargeDetail(carId: id, chargeId: $0.chargeId, exteriorColor: state.exteriorColor)
                    } ?? .charges(carId: id, exteriorColor: state.exteriorColor)
                }
            ),
            DashboardOverviewItem(
                id: "odometer",
                title: Self.text("Total Odometer", "总里程", language: language),
                primaryLabel: Self.text("Recorded Odometer", "累计里程", language: language),
                primaryValue: state.odometer.map {
                    MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
                } ?? "--",
                timestamp: Self.dateText(state.cachedAt, language: language),
                metrics: [
                    DashboardOverviewMetric(
                        id: "drive-count",
                        label: Self.text("Drives Recorded", "累计行程", language: language),
                        value: Self.countText(state.totalDrives, singular: "drive", plural: "drives", chineseUnit: "次", language: language)
                    ),
                    DashboardOverviewMetric(
                        id: "latest-distance",
                        label: Self.text("Latest Drive", "最近行驶", language: language),
                        value: drive?.distanceKm.map {
                            MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 1)
                        } ?? "--"
                    ),
                    DashboardOverviewMetric(
                        id: "rated-range",
                        label: Self.text("Rated Range", "额定续航", language: language),
                        value: state.ratedRange.map {
                            MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
                        } ?? "--"
                    )
                ],
                systemImage: "gauge.with.dots.needle.50percent",
                accent: .odometer,
                highlight: nil,
                route: carId.map {
                    .mileage(carId: $0, exteriorColor: state.exteriorColor, targetDay: nil)
                }
            )
        ]
    }

    private static func text(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }

    private static func energyText(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "--" }
        return String(format: "%.1f kWh", value)
    }

    private static func costText(
        _ value: Double?,
        currencyCode: String,
        language: AppLanguage
    ) -> String {
        guard let value, value.isFinite, value >= 0 else {
            return text("Add cost", "待补充", language: language)
        }
        return MateDriveCurrencyFormatter.symbol(for: currencyCode)
            + String(format: "%.2f", value)
    }

    private static func driveHighlight(
        _ drive: DashboardLatestDrive?,
        units: UnitPreferences?,
        language: AppLanguage
    ) -> DashboardOverviewHighlight? {
        guard let intelligence = drive?.intelligence else { return nil }
        let benchmark = intelligence.benchmark
        let efficiencyText = benchmark.currentEfficiency.map {
            MateDriveUnitFormatter.formatEfficiency($0, units: units, decimals: 0)
        } ?? "--"

        if benchmark.accent == .personalBest {
            let detail: String
            if let previous = benchmark.previousBestEfficiency,
               let current = benchmark.currentEfficiency,
               previous > current {
                let saved = MateDriveUnitFormatter.formatEfficiency(previous - current, units: units, decimals: 0)
                detail = text(
                    "Saved \(saved) versus the previous record",
                    "较原纪录节省 \(saved)",
                    language: language
                )
            } else {
                detail = text("Lowest energy use on this route", "这条路线最低能耗", language: language)
            }
            return DashboardOverviewHighlight(
                title: text("New personal best", "新的个人最佳", language: language),
                detail: detail,
                systemImage: "trophy.fill",
                style: .personalBest
            )
        }

        switch benchmark.accent {
        case .gold:
            return DashboardOverviewHighlight(
                title: text("Lowest energy use on this route", "同路线最低能耗", language: language),
                detail: text("Historical No. 1 · \(efficiencyText)", "历史第 1 名 · \(efficiencyText)", language: language),
                systemImage: "trophy.fill",
                style: .gold
            )
        case .silver:
            return DashboardOverviewHighlight(
                title: text("Second-lowest on this route", "同路线能耗第 2 名", language: language),
                detail: efficiencyText,
                systemImage: "medal.fill",
                style: .silver
            )
        case .bronze:
            return DashboardOverviewHighlight(
                title: text("Third-lowest on this route", "同路线能耗第 3 名", language: language),
                detail: efficiencyText,
                systemImage: "medal.fill",
                style: .bronze
            )
        case .efficient:
            let percent = abs(Int((benchmark.percentageDifference ?? 0).rounded()))
            return DashboardOverviewHighlight(
                title: text("Beat personal baseline by \(percent)%", "优于个人标定 \(percent)%", language: language),
                detail: benchmark.isThreeDriveStreak
                    ? text("Three efficient drives in a row", "连续 3 次优于个人标定", language: language)
                    : efficiencyText,
                systemImage: "leaf.fill",
                style: .efficient
            )
        case .aboveBenchmark:
            let percent = max(Int((benchmark.percentageDifference ?? 0).rounded()), 0)
            return DashboardOverviewHighlight(
                title: text("Above personal baseline by \(percent)%", "高于个人标定 \(percent)%", language: language),
                detail: efficiencyText,
                systemImage: "gauge.with.dots.needle.67percent",
                style: .aboveBenchmark
            )
        case .neutral:
            if intelligence.confirmedLabel != nil, benchmark.samplesNeeded > 0 {
                return DashboardOverviewHighlight(
                    title: intelligence.confirmedLabel?.name ?? text("Personal baseline", "个人标定", language: language),
                    detail: text(
                        "Complete \(benchmark.samplesNeeded) more similar drives to establish a baseline",
                        "再完成 \(benchmark.samplesNeeded) 次相似行程，即可建立个人标定",
                        language: language
                    ),
                    systemImage: "chart.line.uptrend.xyaxis",
                    style: .progress
                )
            }
            if intelligence.suggestion != nil {
                return DashboardOverviewHighlight(
                    title: text("Similar commute detected", "发现相似通勤", language: language),
                    detail: text("Confirm the route to start a personal baseline", "确认路线后开始建立个人标定", language: language),
                    systemImage: "sparkles",
                    style: .progress
                )
            }
            return nil
        case .personalBest:
            return nil
        }
    }

    private static func batteryChangeText(_ charge: DashboardLatestCharge?) -> String {
        guard let start = charge?.startBatteryLevel, let end = charge?.endBatteryLevel else {
            return "--"
        }
        return "\(start)% → \(end)%"
    }

    private static func countText(
        _ value: Int?,
        singular: String,
        plural: String,
        chineseUnit: String,
        language: AppLanguage
    ) -> String {
        guard let value, value >= 0 else { return "--" }
        if MateDriveUnitFormatter.usesChineseLabels(language: language) {
            return "\(value)\(chineseUnit)"
        }
        return "\(value) \(value == 1 ? singular : plural)"
    }

    private static func dateText(_ date: Date?, language: AppLanguage) -> String? {
        guard let date else { return nil }
        let locale = MateDriveUnitFormatter.usesChineseLabels(language: language)
            ? Locale(identifier: "zh_CN")
            : Locale(identifier: "en_US")
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
