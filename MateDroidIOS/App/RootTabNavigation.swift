import Foundation

public enum RootTab: Hashable, Sendable {
    case home
    case features
    case settings
}

public struct RootNavigationState: Equatable, Sendable {
    public var selectedTab: RootTab
    public var homePath: [AppRoute]
    public var featuresPath: [AppRoute]
    public var settingsPath: [AppRoute]

    public init(
        selectedTab: RootTab = .home,
        homePath: [AppRoute] = [],
        featuresPath: [AppRoute] = [],
        settingsPath: [AppRoute] = []
    ) {
        self.selectedTab = selectedTab
        self.homePath = homePath
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
                homePath.append(route)
            case .features:
                featuresPath.append(route)
            case .settings:
                settingsPath.append(route)
            }
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
