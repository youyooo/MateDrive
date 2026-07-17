# MateDrive Bottom Tab Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the dashboard's long feature grid with native Home, Features, and Settings tabs while keeping every page cached-first and preserving independent navigation state.

**Architecture:** `RootView` owns one shared `DashboardViewModel`, one native `TabView`, and a separate `NavigationStack` path for Home, Features, and Settings. A pure tab-routing state object handles shortcuts and cross-tab routes. `FeatureHubView` renders a static grouped catalog and never loads data itself; Home keeps the approved vehicle UI and adds only a compact cached overview strip.

**Tech Stack:** Swift 6.3, SwiftUI, Combine, XCTest, XcodeGen, iOS 18+.

## Global Constraints

- Preserve the approved vehicle title, battery/range ring, tyre-pressure layout, map, refresh behavior, cache warnings, and charging animation.
- Use native `TabView`; Settings is always the rightmost tab.
- Each tab owns an independent `NavigationStack` and path.
- Feature Hub performs no API, cache, timer, polling, or preload work.
- Home overview uses only existing `DashboardState` values.
- All visible text is localized in English and Simplified Chinese.
- Cards use an 8-point corner radius and a minimum 44-point touch target.
- Existing cached-first destination providers remain unchanged.

---

### Task 1: Add Pure Root Tab Routing

**Files:**
- Create: `MateDroidIOS/App/RootTabNavigation.swift`
- Create: `MateDroidIOSTests/App/RootTabNavigationTests.swift`

**Interfaces:**
- Produces: `RootTab`, `RootNavigationState.open(_:source:)`, `RootNavigationState.openShortcut(_:)`.
- Consumes: existing `AppRoute`.

- [ ] **Step 1: Write failing routing tests**

```swift
import XCTest
@testable import MateDroidIOS

final class RootTabNavigationTests: XCTestCase {
    func testDashboardAndSettingsSelectTheirRootTabs() {
        var state = RootNavigationState()
        state.open(.charges(carId: 1, exteriorColor: nil), source: .features)
        state.open(.dashboard, source: .features)
        XCTAssertEqual(state.selectedTab, .home)
        XCTAssertTrue(state.homePath.isEmpty)

        state.open(.settings, source: .home)
        XCTAssertEqual(state.selectedTab, .settings)
        XCTAssertTrue(state.settingsPath.isEmpty)
    }

    func testFeatureShortcutUsesFeatureStackWithoutDestroyingHomePath() {
        var state = RootNavigationState()
        state.open(.mileage(carId: 1, exteriorColor: nil, targetDay: nil), source: .home)
        state.openShortcut(.charges(carId: 1, exteriorColor: nil))
        XCTAssertEqual(state.selectedTab, .features)
        XCTAssertEqual(state.featuresPath, [.charges(carId: 1, exteriorColor: nil)])
        XCTAssertEqual(state.homePath.count, 1)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDroidIOSTests/RootTabNavigationTests test
```

Expected: compile failure because `RootNavigationState` does not exist.

- [ ] **Step 3: Implement the pure state contract**

```swift
import Foundation

public enum RootTab: Hashable, Sendable {
    case home
    case features
    case settings
}

public struct RootNavigationState: Equatable, Sendable {
    public var selectedTab: RootTab = .home
    public var homePath: [AppRoute] = []
    public var featuresPath: [AppRoute] = []
    public var settingsPath: [AppRoute] = []

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
            case .home: homePath.append(route)
            case .features: featuresPath.append(route)
            case .settings: settingsPath.append(route)
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
```

- [ ] **Step 4: Run `RootTabNavigationTests` and expect PASS**
- [ ] **Step 5: Commit only the new routing files with `feat: add root tab navigation state`**

### Task 2: Define The Static Feature Catalog

**Files:**
- Create: `MateDroidIOS/Features/FeatureHub/FeatureHubCatalog.swift`
- Create: `MateDroidIOSTests/Features/FeatureHubCatalogTests.swift`
- Modify: `MateDroidIOSTests/Smoke/AppRouteTests.swift`

**Interfaces:**
- Produces: `FeatureHubSection`, `FeatureHubItem`, `FeatureHubCatalog.sections(carId:exteriorColor:)`.
- Consumes: `AppRoute`, existing route titles, and SF Symbol names.

- [ ] **Step 1: Add failing coverage and order tests**

```swift
func testCatalogGroupsEveryApprovedTopLevelFeatureOnce() {
    let sections = FeatureHubCatalog.sections(carId: 7, exteriorColor: "PPSW")
    XCTAssertEqual(sections.map(\.id), ["common", "charging-driving", "insights", "records"])
    let routes = sections.flatMap(\.items).map(\.route)
    XCTAssertEqual(routes.count, Set(routes).count)
    XCTAssertTrue(routes.contains(.energyCycles(carId: 7, exteriorColor: "PPSW")))
    XCTAssertTrue(routes.contains(.commuteRoutes(carId: 7)))
    XCTAssertTrue(routes.contains(.sentryHistory(carId: 7, exteriorColor: "PPSW")))
}
```

- [ ] **Step 2: Run `FeatureHubCatalogTests`; expect compile failure**
- [ ] **Step 3: Implement stable models and sections**

```swift
public struct FeatureHubItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let titleKey: String
    public let subtitleEnglish: String
    public let subtitleChinese: String
    public let systemImage: String
    public let route: AppRoute
}

public struct FeatureHubSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let titleEnglish: String
    public let titleChinese: String
    public let items: [FeatureHubItem]
}
```

Populate the exact spec order. Use unique semantic IDs such as `current-charge`, `activities`, `drives`, `battery`, `charges`, `recent-map`, `trips`, `energy-balance`, `stats`, `mileage`, `places`, `drive-insights`, `environment`, `standby-hotspots`, `commute-routes`, `achievements`, `updates`, and `sentry`.

- [ ] **Step 4: Replace the old dashboard-route coverage assertion with catalog coverage**
- [ ] **Step 5: Run `FeatureHubCatalogTests` and `AppRouteTests`; expect PASS**
- [ ] **Step 6: Commit with `feat: define grouped feature catalog`**

### Task 3: Build The Features Tab UI

**Files:**
- Create: `MateDroidIOS/Features/FeatureHub/FeatureHubView.swift`
- Create: `MateDroidIOS/Features/FeatureHub/FeatureHubPresentation.swift`
- Create: `MateDroidIOSTests/Features/FeatureHubPresentationTests.swift`
- Modify: `MateDroidIOS/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: shared `DashboardViewModel`, `FeatureHubCatalog`, `(AppRoute) -> Void`.
- Produces: `FeatureHubView` with no asynchronous loading lifecycle.

- [ ] **Step 1: Add failing presentation tests**

Test selected-car name, multi-car selector visibility, no-car empty state, Chinese/English section labels, and route construction using the current exterior color.

- [ ] **Step 2: Run `FeatureHubPresentationTests`; expect failure**
- [ ] **Step 3: Implement a pure presentation mapper**

```swift
struct FeatureHubPresentation: Equatable {
    let vehicleName: String
    let showsVehiclePicker: Bool
    let sections: [FeatureHubSection]
    let isAvailable: Bool

    init(state: DashboardState) {
        vehicleName = state.carName
        showsVehiclePicker = state.cars.count > 1
        isAvailable = state.selectedCarId != nil
        sections = state.selectedCarId.map {
            FeatureHubCatalog.sections(carId: $0, exteriorColor: state.exteriorColor)
        } ?? []
    }
}
```

- [ ] **Step 4: Implement `FeatureHubView`**

Use `ScrollView`, section headers, and a two-column `LazyVGrid`. Each card is a plain `Button` with one SF Symbol, title, localized supporting line, and chevron; use `secondarySystemBackground`, 8-point corners, and at least 92 points of stable height. The view must not contain `.task`, `.onAppear`, `.refreshable`, or a network/cache dependency.

When multiple cars exist, use the same segmented selection binding as Home and call `await viewModel.selectCar(id:)`. When no car is selected, show `ContentUnavailableView` and a button that calls `navigate(.settings)`.

- [ ] **Step 5: Add complete English and Simplified Chinese strings and run `make localization-audit`**
- [ ] **Step 6: Run presentation and localization tests; expect PASS**
- [ ] **Step 7: Commit with `feat: add cached-first feature hub`**

### Task 4: Reduce Home To High-Frequency Data

**Files:**
- Modify: `MateDroidIOS/Features/Dashboard/DashboardView.swift`
- Create: `MateDroidIOS/Features/Dashboard/DashboardOverviewPresentation.swift`
- Create: `MateDroidIOSTests/Features/DashboardOverviewPresentationTests.swift`
- Modify: `MateDroidIOSTests/Features/DashboardViewModelTests.swift`

**Interfaces:**
- Produces: `DashboardOverviewPresentation` with Odometer, Drives, and Charges values/routes.
- Consumes: existing `DashboardState`, unit preferences, language.

- [ ] **Step 1: Add failing overview tests**

```swift
func testOverviewUsesOnlyExistingDashboardState() {
    let state = DashboardState(selectedCarId: 9, odometer: 118_859, totalCharges: 15, totalDrives: 88)
    let result = DashboardOverviewPresentation(
        state: state,
        units: UnitPreferences(length: .kilometers),
        language: .chinese
    )
    XCTAssertEqual(result.items.map(\.value), ["118,859 km", "88", "15"])
    XCTAssertEqual(result.items.map(\.route), [
        .mileage(carId: 9, exteriorColor: nil, targetDay: nil),
        .activities(carId: 9, exteriorColor: nil),
        .charges(carId: 9, exteriorColor: nil)
    ])
}
```

- [ ] **Step 2: Run the focused tests; expect compile failure**
- [ ] **Step 3: Implement the pure overview mapper and placeholder behavior**
- [ ] **Step 4: Replace `summaryGrid` and `navigationGrid` with `vehicleOverviewStrip` after the map**

The strip is one three-column surface with internal dividers. Each column is a full button. Remove the top-left Settings toolbar item and keep only Refresh on the top right. Delete the old dashboard feature-grid rendering and `DashboardNavigation` model after catalog tests have moved to `FeatureHubCatalog`.

- [ ] **Step 5: Change `DashboardView` from owning the view model with `@StateObject` to observing the Root-owned model with `@ObservedObject`**
- [ ] **Step 6: Run dashboard tests; expect PASS**
- [ ] **Step 7: Commit with `feat: focus dashboard on vehicle data`**

### Task 5: Install Three Independent Navigation Stacks

**Files:**
- Modify: `MateDroidIOS/App/RootView.swift`
- Modify: `MateDroidIOS/App/AppDataSyncLifecycleController.swift`
- Modify: `MateDroidIOSTests/App/RootTabNavigationTests.swift`
- Modify: `MateDroidIOSTests/App/AppShortcutTests.swift`
- Modify: `MateDroidIOSTests/Smoke/AppStoreReadinessTests.swift`

**Interfaces:**
- Consumes: `RootNavigationState`, `FeatureHubView`, one shared `DashboardViewModel`.
- Produces: configured `TabView`; unconfigured standalone Settings flow.

- [ ] **Step 1: Extend routing tests for independent path preservation and shortcut selection**
- [ ] **Step 2: Run focused tests and confirm the new source-level readiness assertions fail**
- [ ] **Step 3: Move dashboard view-model ownership to `RootView`**

Initialize one `@StateObject private var dashboardViewModel` in `RootView.init` using the existing cache-only dashboard API, settings store, notification service, sentry store, and location resolver. Pass the same object to Home and Features.

- [ ] **Step 4: Replace the single configured NavigationStack with native TabView**

```swift
TabView(selection: $navigation.selectedTab) {
    NavigationStack(path: $navigation.homePath) {
        DashboardView(viewModel: dashboardViewModel) { open($0, source: .home) }
            .navigationDestination(for: AppRoute.self) { destination(for: $0) }
    }
    .tabItem { Label(t("Home", "首页"), systemImage: "house.fill") }
    .tag(RootTab.home)

    NavigationStack(path: $navigation.featuresPath) {
        FeatureHubView(viewModel: dashboardViewModel) { open($0, source: .features) }
            .navigationDestination(for: AppRoute.self) { destination(for: $0) }
    }
    .tabItem { Label(t("Features", "功能"), systemImage: "square.grid.2x2.fill") }
    .tag(RootTab.features)

    NavigationStack(path: $navigation.settingsPath) {
        SettingsView(viewModel: settingsViewModel)
            .navigationDestination(for: AppRoute.self) { destination(for: $0) }
    }
    .tabItem { Label(t("Settings", "设置"), systemImage: "gearshape.fill") }
    .tag(RootTab.settings)
}
```

Keep the current standalone `SettingsView` branch when `settings.isConfigured == false`. Apply app language and unit environments above both branches.

- [ ] **Step 5: Route shortcuts through `navigation.openShortcut(route)`**

Dashboard shortcuts select Home; Settings selects Settings; all vehicle-feature shortcuts select Features and replace only the Features path. Preserve fallback-car logic.

- [ ] **Step 6: Ensure a cache revision reloads shared Dashboard state once without rebuilding destination stacks**

Add a single `onChange(of: syncLifecycleController.cacheRevision)` that calls `await dashboardViewModel.load()` from cache. Do not apply `.id(cacheRevision)` to TabView or NavigationStack.

- [ ] **Step 7: Run Root, shortcut, route, readiness, and dashboard tests; expect PASS**
- [ ] **Step 8: Commit with `feat: add home features settings tabs`**

### Task 6: Verify Tab Performance And Accessibility

**Files:**
- Modify: `MateDroidIOSTests/Localization/LocalizationCoverageTests.swift`
- Create: `docs/qa/bottom-tabs-2026-07.md`

**Interfaces:**
- Consumes: completed tabs and existing cached-first providers.
- Produces: recorded simulator/phone evidence.

- [ ] **Step 1: Add localization source coverage for `FeatureHubView` and tab labels**
- [ ] **Step 2: Run `make localization-audit`, focused tests, and `make test-build`; expect PASS**
- [ ] **Step 3: Run full `make test`; record total pass/skip counts**
- [ ] **Step 4: Launch iPhone 17 and one smaller simulator; inspect light/dark, English/Chinese, Dynamic Type, and metric/imperial layouts**
- [ ] **Step 5: Repeatedly open the same second- and third-level pages, switch tabs, and return. Confirm cached content appears immediately, no duplicate API request is started, paths remain intact, and toolbar buttons do not overlap**
- [ ] **Step 6: Install on the connected iPhone with `make install-device` and repeat the navigation/cache checks**
- [ ] **Step 7: Record results in the QA document and commit with `test: verify bottom tab navigation performance`**
