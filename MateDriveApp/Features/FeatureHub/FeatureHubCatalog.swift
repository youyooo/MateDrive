import Foundation

struct FeatureHubItem: Identifiable, Equatable, Sendable {
    let id: String
    let titleEnglish: String
    let titleChinese: String
    let subtitleEnglish: String
    let subtitleChinese: String
    let systemImage: String
    let route: AppRoute

    func title(language: AppLanguage) -> String {
        AppText.localized(titleEnglish, titleChinese, language: language)
    }

    func subtitle(language: AppLanguage) -> String {
        AppText.localized(subtitleEnglish, subtitleChinese, language: language)
    }
}

struct FeatureHubSection: Identifiable, Equatable, Sendable {
    let id: String
    let titleEnglish: String
    let titleChinese: String
    let items: [FeatureHubItem]

    func title(language: AppLanguage) -> String {
        AppText.localized(titleEnglish, titleChinese, language: language)
    }
}

enum FeatureHubCatalog {
    static func sections(carId: Int, exteriorColor: String?) -> [FeatureHubSection] {
        [
            FeatureHubSection(
                id: "common",
                titleEnglish: "Common",
                titleChinese: "常用",
                items: [
                    item(
                        "current-charge", "Current Charge", "当前充电",
                        "Live charging progress", "查看实时充电进度",
                        "bolt.car", .currentCharge(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "activities", "Activities", "活动",
                        "Driving and charging timeline", "行驶与充电时间线",
                        "clock.arrow.circlepath", .activities(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "drives", "Drives", "行程",
                        "Routes, energy and details", "路线、电耗与详细数据",
                        "road.lanes", .drives(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "battery", "Battery", "电池",
                        "Health and range trends", "健康度与续航趋势",
                        "battery.75percent", .battery(carId: carId, efficiency: nil, exteriorColor: exteriorColor)
                    )
                ]
            ),
            FeatureHubSection(
                id: "charging-driving",
                titleEnglish: "Charging & Driving",
                titleChinese: "充电与驾驶",
                items: [
                    item(
                        "charges", "Charges", "充电记录",
                        "Sessions, energy and costs", "充电量、费用与记录",
                        "bolt.fill", .charges(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "recent-map", "Recent Driving Map", "近期行驶地图",
                        "See recent routes together", "集中查看近期路线",
                        "map", .recentDrivingMap(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "trips", "Trips", "路程",
                        "Group drives into journeys", "将多个行程整理成路程",
                        "point.topleft.down.to.point.bottomright.curvepath", .trips(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "energy-balance", "Energy Balance", "能量收支",
                        "Compare charging and usage", "对比充入与消耗电量",
                        "arrow.left.arrow.right", .energyCycles(carId: carId, exteriorColor: exteriorColor)
                    )
                ]
            ),
            FeatureHubSection(
                id: "insights",
                titleEnglish: "Data Insights",
                titleChinese: "数据洞察",
                items: [
                    item(
                        "stats", "Stats", "统计",
                        "Long-term driving summary", "长期驾驶数据汇总",
                        "chart.xyaxis.line", .stats(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "mileage", "Mileage", "里程",
                        "Daily and monthly distance", "按日和按月查看里程",
                        "gauge.with.dots.needle.50percent", .mileage(carId: carId, exteriorColor: exteriorColor, targetDay: nil)
                    ),
                    item(
                        "places", "Place Insights", "地点洞察",
                        "Frequent stops and visits", "常去地点与停留记录",
                        "mappin.and.ellipse", .places(carId: carId)
                    ),
                    item(
                        "drive-insights", "Drive Insights", "行程洞察",
                        "Efficiency and behavior trends", "能耗与驾驶趋势",
                        "chart.line.text.clipboard", .driveInsights(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "environment", "Environment History", "环境与胎压",
                        "Temperature and tyre pressure", "温度与胎压历史",
                        "thermometer.variable.and.figure", .environmentHistory(carId: carId)
                    ),
                    item(
                        "standby-hotspots", "Standby Hotspots", "待机耗电热点",
                        "Find locations with high drain", "发现高待机耗电地点",
                        "moon.zzz", .topDrainLocations(carId: carId)
                    ),
                    item(
                        "commute-routes", "Commute Routes", "通勤路线",
                        "Compare recurring routes", "比较常用通勤路线",
                        "arrow.triangle.swap", .commuteRoutes(carId: carId)
                    )
                ]
            ),
            FeatureHubSection(
                id: "records",
                titleEnglish: "Vehicle Records",
                titleChinese: "车辆记录",
                items: [
                    item(
                        "achievements", "Achievements", "成就",
                        "Driving milestones", "驾驶与里程成就",
                        "trophy", .achievements(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "updates", "Updates", "软件更新",
                        "Vehicle software history", "车辆软件版本记录",
                        "arrow.down.circle", .updates(carId: carId, exteriorColor: exteriorColor)
                    ),
                    item(
                        "sentry", "Sentry", "哨兵",
                        "Recorded sentry events", "已记录的哨兵事件",
                        "shield.lefthalf.filled", .sentryHistory(carId: carId, exteriorColor: exteriorColor)
                    )
                ]
            )
        ]
    }

    private static func item(
        _ id: String,
        _ titleEnglish: String,
        _ titleChinese: String,
        _ subtitleEnglish: String,
        _ subtitleChinese: String,
        _ systemImage: String,
        _ route: AppRoute
    ) -> FeatureHubItem {
        FeatureHubItem(
            id: id,
            titleEnglish: titleEnglish,
            titleChinese: titleChinese,
            subtitleEnglish: subtitleEnglish,
            subtitleChinese: subtitleChinese,
            systemImage: systemImage,
            route: route
        )
    }
}
