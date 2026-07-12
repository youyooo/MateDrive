import Foundation

public enum DriveMetricKind: String, CaseIterable, Hashable, Sendable, Identifiable {
    case averageSpeed
    case maxSpeed
    case efficiency
    case energy
    case elevation
    case duration

    public var id: String { rawValue }

    public var title: String {
        englishTitle
    }

    public func title(language: AppLanguage) -> String {
        guard MateDroidUnitFormatter.usesChineseLabels(language: language) else {
            return englishTitle
        }

        switch self {
        case .averageSpeed:
            return "平均速度"
        case .maxSpeed:
            return "最高速度"
        case .efficiency:
            return "效率"
        case .energy:
            return "能量"
        case .elevation:
            return "海拔"
        case .duration:
            return "时长"
        }
    }

    private var englishTitle: String {
        switch self {
        case .averageSpeed:
            return "Avg Speed"
        case .maxSpeed:
            return "Max Speed"
        case .efficiency:
            return "Efficiency"
        case .energy:
            return "Energy"
        case .elevation:
            return "Elevation"
        case .duration:
            return "Duration"
        }
    }

    public var systemImage: String {
        switch self {
        case .averageSpeed:
            return "speedometer"
        case .maxSpeed:
            return "gauge.with.dots.needle.bottom.100percent"
        case .efficiency:
            return "leaf"
        case .energy:
            return "bolt.fill"
        case .elevation:
            return "mountain.2"
        case .duration:
            return "clock"
        }
    }
}

public enum AppRoute: Hashable, Sendable {
    case settings
    case dashboard
    case palettePreview
    case charges(carId: Int, exteriorColor: String?)
    case chargeDetail(carId: Int, chargeId: Int, exteriorColor: String?)
    case compareCharges(carId: Int, baseChargeId: Int, exteriorColor: String?)
    case currentCharge(carId: Int, exteriorColor: String?)
    case activities(carId: Int, exteriorColor: String?)
    case places(carId: Int)
    case achievements(carId: Int, exteriorColor: String?)
    case drives(carId: Int, exteriorColor: String?)
    case recentDrivingMap(carId: Int, exteriorColor: String?)
    case driveDetail(carId: Int, driveId: Int, exteriorColor: String?)
    case driveMetricDetail(carId: Int, driveId: Int, metric: DriveMetricKind, exteriorColor: String?)
    case compareDrives(carId: Int, baseDriveId: Int, exteriorColor: String?)
    case battery(carId: Int, efficiency: Double?, exteriorColor: String?)
    case mileage(carId: Int, exteriorColor: String?, targetDay: String?)
    case updates(carId: Int, exteriorColor: String?)
    case stats(carId: Int, exteriorColor: String?)
    case costReview(carId: Int, exteriorColor: String?)
    case drivingRecords(carId: Int, exteriorColor: String?)
    case driveInsights(carId: Int, exteriorColor: String?)
    case environmentHistory(carId: Int)
    case topDrainLocations(carId: Int)
    case commuteRoutes(carId: Int)
    case countriesVisited(carId: Int, exteriorColor: String?, year: Int?)
    case regionsVisited(carId: Int, countryCode: String, countryName: String, exteriorColor: String?, year: Int?)
    case whereWasI(carId: Int, timestamp: String, exteriorColor: String?)
    case trips(carId: Int, exteriorColor: String?)
    case createTrip(carId: Int, exteriorColor: String?)
    case tripDetail(carId: Int, tripStartDate: String, exteriorColor: String?)
    case sentryHistory(carId: Int, exteriorColor: String?)
}

public extension AppRoute {
    var title: String {
        switch self {
        case .settings:
            return "Settings"
        case .dashboard:
            return "Dashboard"
        case .palettePreview:
            return "Palette"
        case .charges:
            return "Charges"
        case .chargeDetail:
            return "Charge Detail"
        case .compareCharges:
            return "Compare Charges"
        case .currentCharge:
            return "Current Charge"
        case .activities:
            return "Activities"
        case .places:
            return "Place Insights"
        case .achievements:
            return "Achievements"
        case .drives:
            return "Drives"
        case .recentDrivingMap:
            return "Recent Driving Map"
        case .driveDetail:
            return "Drive Detail"
        case let .driveMetricDetail(_, _, metric, _):
            return "\(metric.title) Detail"
        case .compareDrives:
            return "Compare Drives"
        case .battery:
            return "Battery"
        case .mileage:
            return "Mileage"
        case .updates:
            return "Updates"
        case .stats:
            return "Stats"
        case .costReview:
            return "Vehicle Cost Review"
        case .drivingRecords:
            return "Driving Records"
        case .driveInsights:
            return "Drive Insights"
        case .environmentHistory:
            return "Environment History"
        case .topDrainLocations:
            return "Standby Hotspots"
        case .commuteRoutes:
            return "Commute Routes"
        case .countriesVisited:
            return "Countries Visited"
        case .regionsVisited:
            return "Regions Visited"
        case .whereWasI:
            return "Where Was I"
        case .trips:
            return "Trips"
        case .createTrip:
            return "Create Trip"
        case .tripDetail:
            return "Trip Detail"
        case .sentryHistory:
            return "Sentry"
        }
    }

    func title(language: AppLanguage) -> String {
        guard MateDroidUnitFormatter.usesChineseLabels(language: language) else {
            return title
        }

        switch self {
        case .settings:
            return "设置"
        case .dashboard:
            return "首页"
        case .palettePreview:
            return "车漆"
        case .charges:
            return "充电记录"
        case .chargeDetail:
            return "充电详情"
        case .compareCharges:
            return "比较充电"
        case .currentCharge:
            return "当前充电"
        case .activities:
            return "活动"
        case .places:
            return "地点洞察"
        case .achievements:
            return "成就"
        case .drives:
            return "行程"
        case .recentDrivingMap:
            return "近期行驶地图"
        case .driveDetail:
            return "行程详情"
        case let .driveMetricDetail(_, _, metric, _):
            return "\(metric.title(language: language))详情"
        case .compareDrives:
            return "比较行程"
        case .battery:
            return "电池"
        case .mileage:
            return "里程"
        case .updates:
            return "软件更新"
        case .stats:
            return "统计"
        case .costReview:
            return "用车成本回顾"
        case .drivingRecords:
            return "驾驶纪录"
        case .driveInsights:
            return "行程洞察"
        case .environmentHistory:
            return "环境与胎压"
        case .topDrainLocations:
            return "待机耗电热点"
        case .commuteRoutes:
            return "通勤路线"
        case .countriesVisited:
            return "到访国家"
        case .regionsVisited:
            return "到访地区"
        case .whereWasI:
            return "曾停位置"
        case .trips:
            return "路程"
        case .createTrip:
            return "创建路程"
        case .tripDetail:
            return "路程详情"
        case .sentryHistory:
            return "哨兵"
        }
    }
}
