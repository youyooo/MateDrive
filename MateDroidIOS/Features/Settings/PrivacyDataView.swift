import SwiftUI

public struct PrivacyDataView: View {
    @Environment(\.appLanguage) private var appLanguage
    @State private var isClearing = false
    @State private var snapshotCount = 0
    @State private var showsClearConfirmation = false
    @State private var showsClearedAlert = false

    private let snapshotStore: DashboardSnapshotStore

    public init(snapshotStore: DashboardSnapshotStore = .shared) {
        self.snapshotStore = snapshotStore
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
                        "Apple map and geocoding services process map locations. When route weather is requested, the required route coordinates are sent to Open-Meteo to retrieve weather samples.",
                        "苹果地图和地理编码服务会处理地图位置。请求沿途天气时，应用会将所需路线坐标发送给第三方开放气象服务以获取天气样本。"
                    )
                )
            }

            Section(t("Local Data", "本地数据")) {
                LabeledContent(t("Offline Dashboard Snapshots", "离线首页快照"), value: String(snapshotCount))
                Text(t(
                    "Recent dashboard status is stored for up to 30 days so the last known state remains available during a temporary server outage. Snapshots are isolated by server and vehicle.",
                    "最近首页状态最多保留 30 天，以便服务器暂时离线时查看最后已知状态。快照按服务器和车辆隔离。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Label(t("Clear Offline Dashboard Data", "清除离线首页数据"), systemImage: "trash")
                }
                .disabled(isClearing || snapshotCount == 0)
            }

            Section(t("Sharing", "分享")) {
                Text(t(
                    "Data leaves the app only when you explicitly export or share it. Review addresses, routes, notes, and other personal details before sharing.",
                    "只有在你主动导出或分享时，数据才会离开应用。分享前请检查地址、路线、备注和其他个人信息。"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(t("Privacy & Local Data", "隐私与本地数据"))
        .task { snapshotCount = await snapshotStore.snapshotCount() }
        .confirmationDialog(
            t("Clear all offline dashboard snapshots?", "清除全部离线首页快照？"),
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("Clear Offline Data", "清除离线数据"), role: .destructive) { clearSnapshots() }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t(
                "Server settings and Keychain credentials will not be removed.",
                "服务器设置和钥匙串凭据不会被删除。"
            ))
        }
        .alert(t("Offline Data Cleared", "离线数据已清除"), isPresented: $showsClearedAlert) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
    }

    private func clearSnapshots() {
        isClearing = true
        Task {
            await snapshotStore.clearAll()
            snapshotCount = await snapshotStore.snapshotCount()
            isClearing = false
            showsClearedAlert = true
        }
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
