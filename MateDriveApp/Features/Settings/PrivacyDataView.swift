import Foundation
import SwiftUI
import WidgetKit

public struct SmartActivityPrivacyDataController: Sendable {
    private let sessionStore: any SmartActivitySessionStoring
    private let labelStore: any ActivityLabelOverrideStoring
    private let pricingObservationStore: any ChargePricingObservationStoring

    public init(
        sessionStore: any SmartActivitySessionStoring,
        labelStore: any ActivityLabelOverrideStoring,
        pricingObservationStore: any ChargePricingObservationStoring
    ) {
        self.sessionStore = sessionStore
        self.labelStore = labelStore
        self.pricingObservationStore = pricingObservationStore
    }

    public static let live = SmartActivityPrivacyDataController(
        sessionStore: DatabaseBackedSmartActivityStore(
            databaseProvider: AppEnvironment.live.databaseProvider
        ),
        labelStore: DatabaseBackedActivityLabelOverrideStore(
            databaseProvider: AppEnvironment.live.databaseProvider
        ),
        pricingObservationStore: DatabaseBackedChargePricingObservationStore(
            databaseProvider: AppEnvironment.live.databaseProvider
        )
    )

    public func clearDerivedData() async throws {
        try await sessionStore.removeDerivedSessions()
    }

    public func clearLearnedData() async throws {
        try await labelStore.removeAll()
        try await pricingObservationStore.removeAll()
        try await sessionStore.removeDerivedSessions()
    }
}

@MainActor
public struct PrivacyDataView: View {
    @Environment(\.appLanguage) private var appLanguage
    @ObservedObject private var settingsViewModel: SettingsViewModel
    @State private var isClearing = false
    @State private var routeWeatherEnabled: Bool
    @State private var snapshotCount = 0
    @State private var activitySnapshotCount = 0
    @State private var widgetSnapshotCount = 0
    @State private var apiCacheStatistics = HTTPResponseCacheStatistics.empty
    @State private var showsClearConfirmation = false
    @State private var showsAPICacheClearConfirmation = false
    @State private var showsLearnedDataClearConfirmation = false
    @State private var showsWeatherCacheClearConfirmation = false
    @State private var showsClearedAlert = false
    @State private var showsAPICacheClearedAlert = false
    @State private var showsLearnedDataClearedAlert = false
    @State private var showsWeatherCacheClearedAlert = false
    @State private var clearErrorMessage: String?

    private let snapshotStore: DashboardSnapshotStore
    private let widgetSnapshotStore: WidgetSnapshotStore
    private let responseCache: HTTPResponseCache
    private let weatherCache: WeatherCache
    private let smartActivityController: SmartActivityPrivacyDataController

    public init(
        settingsViewModel: SettingsViewModel,
        snapshotStore: DashboardSnapshotStore = .shared,
        widgetSnapshotStore: WidgetSnapshotStore = .shared,
        responseCache: HTTPResponseCache = .shared,
        weatherCache: WeatherCache = .shared,
        smartActivityController: SmartActivityPrivacyDataController = .live
    ) {
        self.settingsViewModel = settingsViewModel
        _routeWeatherEnabled = State(
            initialValue: settingsViewModel.settings.allowsThirdPartyRouteWeather
        )
        self.snapshotStore = snapshotStore
        self.widgetSnapshotStore = widgetSnapshotStore
        self.responseCache = responseCache
        self.weatherCache = weatherCache
        self.smartActivityController = smartActivityController
    }

    public var body: some View {
        List {
            Section(t("Data Flow", "数据流向")) {
                privacyRow(
                    icon: "server.rack",
                    title: t("Your TeslaMate Server", "你的 TeslaMate 服务器"),
                    detail: t(
                        "Vehicle, drive, charging, battery, and location data are read directly from the server you configure.",
                        "车辆、行程、充电、电池和位置数据直接读取自你配置的服务器。"
                    )
                )
                privacyRow(
                    icon: "key.fill",
                    title: t("Credentials", "认证凭据"),
                    detail: t(
                        "API tokens and authentication secrets are stored in the iOS Keychain and are not included in diagnostics or exports.",
                        "接口令牌和认证密钥保存在 iOS 钥匙串中，不会写入诊断信息或导出文件。"
                    )
                )
                privacyRow(
                    icon: "hand.raised.fill",
                    title: t("No Developer Collection", "开发者不收集数据"),
                    detail: t(
                        "MateDrive has no developer-operated analytics or vehicle-data backend and does not track you across apps.",
                        "MateDrive 不接入开发者运营的分析或车辆数据后台，也不会跨应用跟踪你。"
                    )
                )
                privacyRow(
                    icon: "map.fill",
                    title: t("Maps & Weather", "地图与天气服务"),
                    detail: t(
                        "Apple map and geocoding services process map locations. Route weather stays off until you enable it. When enabled, one representative precise route coordinate and the drive time are sent to Open-Meteo. Open-Meteo may retain request logs for up to 90 days and states that it does not link them to user identities or use them for tracking.",
                        "苹果地图和地理编码服务会处理地图位置。路线天气默认关闭，只有你主动启用后，应用才会向 Open-Meteo 发送一个代表性的精确路线坐标和行程时间。该服务可能将请求日志保留最长 90 天，并声明不会将其关联到用户身份或用于跟踪。"
                    )
                )
            }

            Section(t("Route Weather", "路线天气")) {
                Toggle(
                    t("Allow Open-Meteo Route Weather", "允许 Open-Meteo 路线天气"),
                    isOn: $routeWeatherEnabled
                )
                .accessibilityIdentifier("route_weather_privacy_toggle")
                .onChange(of: routeWeatherEnabled) { _, newValue in
                    Task {
                        let didSave = await settingsViewModel
                            .saveThirdPartyRouteWeatherPermission(newValue)
                        if !didSave {
                            routeWeatherEnabled = settingsViewModel.settings
                                .allowsThirdPartyRouteWeather
                        } else if !newValue {
                            DriveDetailStateCache.shared.removeAll()
                        }
                    }
                }

                Text(t(
                    "Turning this off stops future Open-Meteo requests. Previously saved weather remains on this device until you clear it below.",
                    "关闭后将停止后续 Open-Meteo 请求。此前保存的天气仍保留在本机，直到你在下方清除。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showsWeatherCacheClearConfirmation = true
                } label: {
                    Label(t("Clear Saved Route Weather", "清除已保存路线天气"), systemImage: "cloud.slash")
                }
                .disabled(isClearing)
            }

            if let privacyPolicyURL = AppLinks.privacyPolicyURL {
                Section {
                    Link(destination: privacyPolicyURL) {
                        Label(t("Privacy Policy", "隐私政策"), systemImage: "hand.raised.fill")
                    }
                }
            }

            Section(t("Local Data", "本地数据")) {
                LabeledContent(t("Offline Dashboard Snapshots", "离线首页快照"), value: String(snapshotCount))
                LabeledContent(t("Offline Activity Timelines", "离线活动时间线"), value: String(activitySnapshotCount))
                LabeledContent(t("Widget Vehicle Snapshots", "小组件车辆快照"), value: String(widgetSnapshotCount))
                Text(t(
                    "Recent dashboard status, complete activity timelines, and aggregated widget trends are stored so pages remain available during a temporary server outage. Widget trends exclude locations and exact event times. Snapshots are isolated by server and vehicle.",
                    "最近首页状态、完整活动时间线和小组件聚合趋势会保存在本机，以便服务器暂时离线时继续查看。小组件趋势不包含位置和事件精确时间，快照按服务器和车辆隔离。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label(t("Clear Offline Snapshots", "清除离线快照"), systemImage: "trash")
                }
                .disabled(isClearing)

                LabeledContent(
                    t("Cached API Responses", "API 响应缓存"),
                    value: String(apiCacheStatistics.recordCount)
                )
                LabeledContent(
                    t("API Cache Size", "API 缓存大小"),
                    value: Self.formattedBytes(apiCacheStatistics.byteCount)
                )
                if let newestStoredAt = apiCacheStatistics.newestStoredAt {
                    LabeledContent(t("Last Cache Update", "缓存最近更新")) {
                        Text(newestStoredAt, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                Text(t(
                    "Read-only responses remain available for up to 30 days. Pages show cached data immediately and refresh it in the background, including after the app restarts. Cache filenames contain only a one-way hash, and files use iOS data protection.",
                    "只读响应最多保留 30 天。页面会立即显示缓存并在后台更新，应用重启后同样有效。缓存文件名只包含单向哈希，文件使用 iOS 数据保护。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showsAPICacheClearConfirmation = true
                } label: {
                    Label(t("Clear Cached API Responses", "清除 API 响应缓存"), systemImage: "externaldrive.badge.xmark")
                }
                .disabled(isClearing || apiCacheStatistics.recordCount == 0)
            }

            Section(t("Smart Activity Privacy", "智能动态隐私")) {
                privacyRow(
                    icon: "iphone.gen3",
                    title: t("On-device classification", "设备端分类"),
                    detail: t(
                        "Activity classification runs on this device from vehicle coordinates recorded by your TeslaMate server. MateDrive does not request the phone's location.",
                        "动态分类仅在本机根据 TeslaMate 服务器记录的车辆坐标运行，MateDrive 不会请求手机定位。"
                    )
                )
                privacyRow(
                    icon: "creditcard.fill",
                    title: t("Charging cost estimates", "充电费用估算"),
                    detail: t(
                        "Tariff and charging-cost results are estimates for reference, not invoices. Confirm them against the charger operator's bill.",
                        "电价与充电费用结果仅供估算参考，不是账单；请以充电运营商账单为准。"
                    )
                )
                privacyRow(
                    icon: "icloud.fill",
                    title: t("iCloud backup", "iCloud 备份"),
                    detail: t(
                        "Confirmed activity labels and charging prices are included in MateDrive iCloud backups. Keychain credentials are never included.",
                        "已确认的动态标签和充电价格会包含在 MateDrive 的 iCloud 备份中，钥匙串凭据永远不会包含在内。"
                    )
                )

                Button(role: .destructive) {
                    showsLearnedDataClearConfirmation = true
                } label: {
                    Label(t("Clear Learned Labels & Prices", "清除学习标签与价格"), systemImage: "brain.head.profile")
                }
                .disabled(isClearing)
            }

            Section(t("Sharing", "分享")) {
                Text(t(
                    "Data leaves the app only when you explicitly export or share it. Review addresses, routes, notes, and other personal details before sharing.",
                    "只有在你主动导出或分享时，数据才会离开应用。分享前请检查地址、路线、备注和其他个人信息。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section(t("Independent App", "独立应用声明")) {
                Text(t(
                    "MateDrive is an independently developed, unofficial iOS app. It is not affiliated with, sponsored by, or endorsed by Tesla, Inc., TeslaMate, or any other service provider. Product and service names are used only to describe compatibility.",
                    "MateDrive 是独立开发的非官方 iOS 应用，与特斯拉公司、TeslaMate 或其他服务提供方不存在隶属、赞助或官方认可关系。产品与服务名称仅用于说明兼容性，相关商标归各自权利人所有。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(t("Privacy & Local Data", "隐私与本地数据"))
        .task {
            await settingsViewModel.loadEssentials()
            routeWeatherEnabled = settingsViewModel.settings.allowsThirdPartyRouteWeather
            await refreshLocalDataStatistics()
        }
        .confirmationDialog(
            t("Clear all offline vehicle snapshots?", "清除全部离线车辆快照？"),
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Clear Offline Snapshots", "清除离线快照"), role: .destructive) { clearSnapshots() }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t(
                "Derived activity sessions and dashboard, activity, software-update, and widget snapshots will be cleared. Synchronized drive, charging, and location history, confirmed labels, prices, server settings, and Keychain credentials will remain.",
                "派生动态以及首页、动态、软件更新和小组件快照会被清除。已同步的行程、充电和位置历史、已确认标签、价格、服务器设置和钥匙串凭据会保留。"
            ))
        }
        .alert(t("Offline Snapshots Cleared", "离线快照已清除"), isPresented: $showsClearedAlert) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
        .confirmationDialog(
            t("Clear all cached API responses?", "清除全部 API 响应缓存？"),
            isPresented: $showsAPICacheClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Clear API Cache", "清除 API 缓存"), role: .destructive) { clearAPIResponses() }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t(
                "Pages will request fresh data from your server the next time they open. Server settings and Keychain credentials will not be removed.",
                "下次打开页面时会重新从服务器获取数据。服务器设置和钥匙串凭据不会被删除。"
            ))
        }
        .alert(t("API Cache Cleared", "API 缓存已清除"), isPresented: $showsAPICacheClearedAlert) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
        .confirmationDialog(
            t("Clear all saved route weather?", "清除全部已保存路线天气？"),
            isPresented: $showsWeatherCacheClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Clear Route Weather", "清除路线天气"), role: .destructive) {
                clearRouteWeather()
            }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t(
                "Saved Open-Meteo results will be removed from this device. Your route-weather permission and TeslaMate data will not change.",
                "本机保存的 Open-Meteo 天气结果将被删除。路线天气授权状态和 TeslaMate 数据不会改变。"
            ))
        }
        .alert(t("Route Weather Cleared", "路线天气已清除"), isPresented: $showsWeatherCacheClearedAlert) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
        .confirmationDialog(
            t("Delete learned labels and charging prices?", "删除学习标签和充电价格？"),
            isPresented: $showsLearnedDataClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Delete Learned Data", "删除学习数据"), role: .destructive) { clearLearnedData() }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t(
                "This permanently deletes confirmed activity labels and charging-price observations, then clears derived activity sessions. Original TeslaMate data, server settings, and Keychain credentials are not removed.",
                "此操作会永久删除已确认的动态标签和充电价格观察，并清除派生动态。TeslaMate 原始数据、服务器设置和钥匙串凭据不会被删除。"
            ))
        }
        .alert(t("Learned Data Cleared", "学习数据已清除"), isPresented: $showsLearnedDataClearedAlert) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
        .alert(
            t("Could Not Clear Data", "无法清除数据"),
            isPresented: Binding(
                get: { clearErrorMessage != nil },
                set: { if !$0 { clearErrorMessage = nil } }
            )
        ) {
            Button(t("OK", "确定"), role: .cancel) {}
        } message: {
            Text(clearErrorMessage ?? "")
        }
    }

    private func clearSnapshots() {
        isClearing = true
        Task {
            do {
                try await smartActivityController.clearDerivedData()
                await snapshotStore.clearAll()
                await ActivitiesStateCache.shared.removeAll()
                await SoftwareUpdateSnapshotStore.shared.removeAll()
                widgetSnapshotStore.remove()
                WidgetCenter.shared.reloadAllTimelines()
                snapshotCount = await snapshotStore.snapshotCount()
                activitySnapshotCount = await ActivitiesStateCache.shared.snapshotCount()
                widgetSnapshotCount = widgetSnapshotStore.vehicleSnapshots().count
                showsClearedAlert = true
            } catch {
                clearErrorMessage = UserFacingErrorLocalizer.localized(
                    error.localizedDescription,
                    language: appLanguage
                )
            }
            isClearing = false
        }
    }

    private func clearLearnedData() {
        isClearing = true
        Task {
            do {
                try await smartActivityController.clearLearnedData()
                showsLearnedDataClearedAlert = true
            } catch {
                clearErrorMessage = UserFacingErrorLocalizer.localized(
                    error.localizedDescription,
                    language: appLanguage
                )
            }
            isClearing = false
        }
    }

    private func clearAPIResponses() {
        isClearing = true
        Task {
            await responseCache.removeAll()
            apiCacheStatistics = await responseCache.statistics()
            isClearing = false
            showsAPICacheClearedAlert = true
        }
    }

    private func clearRouteWeather() {
        isClearing = true
        Task {
            await weatherCache.removeAll()
            DriveDetailStateCache.shared.removeAll()
            isClearing = false
            showsWeatherCacheClearedAlert = true
        }
    }

    private func refreshLocalDataStatistics() async {
        async let snapshots = snapshotStore.snapshotCount()
        async let activitySnapshots = ActivitiesStateCache.shared.snapshotCount()
        async let cacheStatistics = responseCache.statistics()
        snapshotCount = await snapshots
        activitySnapshotCount = await activitySnapshots
        widgetSnapshotCount = widgetSnapshotStore.vehicleSnapshots().count
        apiCacheStatistics = await cacheStatistics
    }

    private static func formattedBytes(_ byteCount: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(byteCount))
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(.blue)
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
