import Combine
import Foundation

public struct AchievementsState: Equatable, Sendable {
    public var isLoading = true
    public var isRefreshing = false
    public var hasLoadedData = false
    public var errorMessage: String?
    public var achievements: [TeslaMateAchievement] = []
    public var summary: AchievementSummary?
    public var units: UnitPreferences?

    public init() {}
}

@MainActor
public final class AchievementsViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<AchievementsState>(
        maximumEntryCount: 4
    )

    @Published public private(set) var state: AchievementsState

    private let api: any AchievementsAPIProviding
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<AchievementsState>
    private var carId: Int?

    public init(
        api: any AchievementsAPIProviding,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<AchievementsState>? = nil,
        initialState: AchievementsState = AchievementsState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        self.api = api
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
    }

    public func load(carId: Int) async {
        guard !state.isRefreshing else { return }
        self.carId = carId
        state.isRefreshing = true
        state.isLoading = !state.hasLoadedData
        state.errorMessage = nil
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        switch await api.achievements(carId: carId) {
        case let .success(payload):
            state.achievements = payload.achievements.sorted(by: Self.sort)
            state.summary = payload.summary
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
            state.hasLoadedData = true
            saveCachedState()
        case let .failure(error):
            state.errorMessage = error.analyticsMessage
        }
    }

    public func refresh() async {
        guard let carId else { return }
        await load(carId: carId)
    }

    private func saveCachedState() {
        guard let cacheKey, state.hasLoadedData else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }

    private static func sort(_ lhs: TeslaMateAchievement, _ rhs: TeslaMateAchievement) -> Bool {
        let lhsUnlocked = lhs.tiers.contains(where: \.unlocked)
        let rhsUnlocked = rhs.tiers.contains(where: \.unlocked)
        if lhsUnlocked != rhsUnlocked { return lhsUnlocked }
        let lhsProgress = lhs.tiers.map { $0.progress ?? 0 }.max() ?? 0
        let rhsProgress = rhs.tiers.map { $0.progress ?? 0 }.max() ?? 0
        if lhsProgress != rhsProgress { return lhsProgress > rhsProgress }
        return lhs.id < rhs.id
    }
}

public struct AchievementDefinition: Equatable, Sendable {
    public let englishTitle: String
    public let chineseTitle: String
    public let englishDescription: String
    public let chineseDescription: String
    public let systemImage: String

    public static func definition(for id: String) -> AchievementDefinition {
        definitions[id] ?? AchievementDefinition(
            englishTitle: "New Achievement",
            chineseTitle: "新成就",
            englishDescription: "Progress calculated by the connected TeslaMate server.",
            chineseDescription: "进度由已连接的特斯拉数据服务计算。",
            systemImage: "medal"
        )
    }

    private static let definitions: [String: AchievementDefinition] = [
        "24h_mosaic": .init(englishTitle: "Around the Clock", chineseTitle: "全天足迹", englishDescription: "Drive during every hour of the day.", chineseDescription: "在一天的每个小时都留下驾驶记录。", systemImage: "clock"),
        "energy_inversion": .init(englishTitle: "Energy Returned", chineseTitle: "能量回馈", englishDescription: "Accumulate regenerated driving energy.", chineseDescription: "累计行驶过程中的能量回收。", systemImage: "arrow.uturn.backward.circle"),
        "equatorial_navigation": .init(englishTitle: "Around the Earth", chineseTitle: "环游地球", englishDescription: "Drive the equivalent of Earth's circumference.", chineseDescription: "累计行驶达到地球周长。", systemImage: "globe.asia.australia"),
        "genesis_moment": .init(englishTitle: "First Year", chineseTitle: "记录元年", englishDescription: "Keep TeslaMate recording for a full year.", chineseDescription: "持续使用特斯拉数据记录满一年。", systemImage: "calendar.badge.clock"),
        "perpetual_motion_2025": .init(englishTitle: "2025 Road Habit", chineseTitle: "2025 行驶习惯", englishDescription: "Record driving activity on most days of 2025.", chineseDescription: "在 2025 年的大多数日期留下行驶记录。", systemImage: "calendar"),
        "perpetual_motion_2026": .init(englishTitle: "2026 Road Habit", chineseTitle: "2026 行驶习惯", englishDescription: "Record driving activity on most days of 2026.", chineseDescription: "在 2026 年的大多数日期留下行驶记录。", systemImage: "calendar"),
        "precision_protocol": .init(englishTitle: "Precision Parking", chineseTitle: "精准停靠", englishDescription: "Complete short, precisely recorded parking events.", chineseDescription: "累计完成精确记录的短时停车。", systemImage: "parkingsign.circle"),
        "spacetime_ripple": .init(englishTitle: "Time on the Road", chineseTitle: "行驶时空", englishDescription: "Accumulate time spent driving.", chineseDescription: "累计车辆行驶时长。", systemImage: "hourglass"),
        "territory_mark": .init(englishTitle: "Regional Explorer", chineseTitle: "区域探索者", englishDescription: "Visit and record different regions.", chineseDescription: "到访并记录不同地区。", systemImage: "map"),
        "thermal_shock": .init(englishTitle: "Temperature Range", chineseTitle: "温差挑战", englishDescription: "Drive across a wide range of outside temperatures.", chineseDescription: "在更大的车外温度范围内驾驶。", systemImage: "thermometer.variable"),
        "urban_archivist": .init(englishTitle: "City Archivist", chineseTitle: "城市档案员", englishDescription: "Visit and record different local places.", chineseDescription: "到访并记录不同城市地点。", systemImage: "building.2"),
        "vertical_horizon": .init(englishTitle: "Vertical Horizon", chineseTitle: "垂直地平线", englishDescription: "Drive across a wide elevation range.", chineseDescription: "在更大的海拔跨度内驾驶。", systemImage: "mountain.2")
    ]
}
