import Foundation

public enum RootTab: Hashable, Sendable {
    case home
    case activity
    case features
    case settings
}

public struct RootNavigationState: Equatable, Sendable {
    public var selectedTab: RootTab
    public var homePath: [AppRoute]
    public var activityPath: [AppRoute]
    public var featuresPath: [AppRoute]
    public var settingsPath: [AppRoute]

    public init(
        selectedTab: RootTab = .home,
        homePath: [AppRoute] = [],
        activityPath: [AppRoute] = [],
        featuresPath: [AppRoute] = [],
        settingsPath: [AppRoute] = []
    ) {
        self.selectedTab = selectedTab
        self.homePath = homePath
        self.activityPath = activityPath
        self.featuresPath = featuresPath
        self.settingsPath = settingsPath
    }

    public mutating func open(_ route: AppRoute, source: RootTab) {
        switch route {
        case .dashboard:
            selectedTab = .home
            homePath.removeAll()
        case .settings:
            selectedTab = .settings
            settingsPath.removeAll()
        default:
            selectedTab = source
            switch source {
            case .home:
                if homePath.last != route {
                    homePath.append(route)
                }
            case .activity:
                if activityPath.last != route {
                    activityPath.append(route)
                }
            case .features:
                if featuresPath.last != route {
                    featuresPath.append(route)
                }
            case .settings:
                if settingsPath.last != route {
                    settingsPath.append(route)
                }
            }
        }
    }

    public mutating func selectTab(_ tab: RootTab) {
        selectedTab = tab
        if tab == .settings {
            settingsPath.removeAll()
        }
    }

    public mutating func openShortcut(_ route: AppRoute) {
        switch route {
        case .dashboard, .settings:
            open(route, source: selectedTab)
        default:
            selectedTab = .features
            featuresPath = [route]
        }
    }
}

struct ServerConfigurationNavigationGate: Equatable, Sendable {
    private var observedServerIdentity: String?
    private var isInitialized = false

    mutating func synchronize(serverURL: String) -> Bool {
        let currentIdentity = Self.serverIdentity(serverURL)
        guard isInitialized else {
            observedServerIdentity = currentIdentity
            isInitialized = true
            return false
        }
        guard currentIdentity != observedServerIdentity else {
            return false
        }
        observedServerIdentity = currentIdentity
        return true
    }

    private static func serverIdentity(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              url.scheme != nil,
              url.host != nil
        else { return nil }
        return TeslaMateServerIdentity.key(for: url)
    }
}
