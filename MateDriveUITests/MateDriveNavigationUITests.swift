import Network
import XCTest

@MainActor
final class MateDriveNavigationUITests: XCTestCase {
    // Includes XCTest's accessibility polling cadence, not just app rendering time.
    private let cachedNavigationAutomationBudget: TimeInterval = 5
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchEnvironment["MATEDRIVE_UI_TEST_MODE"] = "1"
            app.launchEnvironment["MATEDRIVE_SKIP_LAUNCH_EXPERIENCE"] = "1"
            app.launch()
        }
    }

    func testFourRootTabsOpenWithoutBlocking() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))

        tapTab(identifier: "root_tab_activity", label: "动态")
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_features", label: "功能")
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_settings", label: "设置")
        XCTAssertTrue(element("settings_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_home", label: "首页")
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 2))
    }

    func testEnglishReleaseLanguageKeepsPrimaryJourneyNavigable() {
        relaunchWithLanguage("en")

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_activity", label: "Activity")
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_features", label: "Features")
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Current Charge"].waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_settings", label: "Settings")
        XCTAssertTrue(element("settings_view").waitForExistence(timeout: 2))
    }

    func testTraditionalChineseReleaseLanguageKeepsPrimaryJourneyNavigable() {
        relaunchWithLanguage("zh-Hant")

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["首頁"].waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_activity", label: "動態")
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_features", label: "功能")
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["當前充電"].waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_settings", label: "設定")
        XCTAssertTrue(element("settings_view").waitForExistence(timeout: 2))
    }

    func testLandscapeKeepsPrimaryNavigationReachable() {
        let device = XCUIDevice.shared
        device.orientation = .landscapeLeft
        defer { device.orientation = .portrait }

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let landscapeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { evaluatedObject, _ in
                guard let evaluatedWindow = evaluatedObject as? XCUIElement else { return false }
                return evaluatedWindow.frame.width > evaluatedWindow.frame.height
            },
            object: window
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeExpectation], timeout: 5), .completed)
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_activity", label: "动态")
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_features", label: "功能")
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        tapTab(identifier: "root_tab_settings", label: "设置")
        XCTAssertTrue(element("settings_view").waitForExistence(timeout: 2))
    }

    func testColdAndWarmLaunchPublishCachedDashboardWithinBudget() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: cachedNavigationAutomationBudget))

        app.terminate()
        app.launch()

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: cachedNavigationAutomationBudget))
    }

    func testOfflineDashboardKeepsCachedContentVisible() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        XCTAssertTrue(element("dashboard_error_banner").waitForExistence(timeout: 5))
        XCTAssertTrue(element("dashboard_offline_banner").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Model 3"].exists)
    }

    func testActivityFilterShowsExplicitEmptyState() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_activity", label: "动态", timeout: 5)
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))
        XCTAssertTrue(element("activity_session_ui-session-1").waitForExistence(timeout: 2))

        let chargeFilter = app.segmentedControls.buttons["充电"]
        XCTAssertTrue(chargeFilter.waitForExistence(timeout: 2))
        chargeFilter.tap()

        XCTAssertTrue(app.staticTexts["没有符合筛选的动态"].waitForExistence(timeout: 2))
        XCTAssertFalse(element("activity_session_ui-session-1").exists)
    }

    func testActivityNavigationTitleIsVisible() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_activity", label: "动态", timeout: 5)
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))

        let title = app.navigationBars.staticTexts["动态"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(title.isHittable)
        XCTAssertFalse(title.frame.isEmpty)
    }

    func testFourRootTabsPassSystemAccessibilityAudit() throws {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        try performVisibleContentAccessibilityAudit()

        tapTab(identifier: "root_tab_activity", label: "动态")
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))
        try performVisibleContentAccessibilityAudit()

        tapTab(identifier: "root_tab_features", label: "功能")
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        try performVisibleContentAccessibilityAudit()

        tapTab(identifier: "root_tab_settings", label: "设置")
        XCTAssertTrue(element("settings_view").waitForExistence(timeout: 2))
        try performVisibleContentAccessibilityAudit()
    }

    func testFeatureHubPassesSystemAccessibilityAudit() throws {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        try performVisibleContentAccessibilityAudit()
    }

    func testFeatureHubUsesSingleColumnAtAccessibilityTextSize() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        let standardTitle = app.staticTexts["当前充电"]
        XCTAssertTrue(standardTitle.waitForExistence(timeout: 2))
        let standardTitleHeight = standardTitle.frame.height
        let standardSubtitle = app.staticTexts["查看实时充电进度"]
        XCTAssertTrue(standardSubtitle.waitForExistence(timeout: 2))
        let standardSubtitleHeight = standardSubtitle.frame.height

        relaunchWithContentSizeCategory("UICTContentSizeCategoryAccessibilityXL")

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        let firstItem = element("feature_item_current-charge")
        XCTAssertTrue(firstItem.waitForExistence(timeout: 2))
        XCTAssertEqual(firstItem.label, "当前充电")
        let accessibilityTitle = app.staticTexts["当前充电"]
        XCTAssertTrue(accessibilityTitle.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(accessibilityTitle.frame.height, standardTitleHeight * 1.2)
        let accessibilitySubtitle = app.staticTexts["查看实时充电进度"]
        XCTAssertTrue(accessibilitySubtitle.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(accessibilitySubtitle.frame.height, standardSubtitleHeight * 1.2)

        let screenWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(firstItem.frame.width, screenWidth * 0.75)
    }

    func testSettingsInstructionsWrapAtAccessibilityTextSize() {
        relaunchWithContentSizeCategory("UICTContentSizeCategoryAccessibilityXL")

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_settings", label: "设置", timeout: 5)
        XCTAssertTrue(element("settings_view").waitForExistence(timeout: 2))

        let instructions = app.staticTexts["服务器无需 API 认证时使用此选项。"]
        for _ in 0..<3 where !instructions.exists {
            app.swipeUp()
        }
        XCTAssertTrue(instructions.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(instructions.frame.height, 40)
        XCTAssertLessThanOrEqual(instructions.frame.maxX, app.windows.firstMatch.frame.maxX)
    }

    func testBatteryMetricsUseSingleColumnAtAccessibilityTextSize() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        featureItem("battery").tap()
        XCTAssertTrue(element("battery_view").waitForExistence(timeout: 2))
        let standardCalibrationTitle = app.staticTexts["需要校准"]
        XCTAssertTrue(standardCalibrationTitle.waitForExistence(timeout: 2))
        let standardCalibrationTitleHeight = standardCalibrationTitle.frame.height

        relaunchWithContentSizeCategory("UICTContentSizeCategoryAccessibilityXL")

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("battery").tap()
        XCTAssertTrue(element("battery_view").waitForExistence(timeout: 2))
        XCTAssertTrue(element("battery_calibration_required").waitForExistence(timeout: 2))
        let accessibilityCalibrationTitle = app.staticTexts["需要校准"]
        XCTAssertTrue(accessibilityCalibrationTitle.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            accessibilityCalibrationTitle.frame.height,
            standardCalibrationTitleHeight * 1.2
        )

        let capacity = app.descendants(matching: .any)
            .matching(identifier: "battery_current_capacity")
            .firstMatch
        for _ in 0..<8 where !capacity.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(capacity.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(capacity.frame.width, app.windows.firstMatch.frame.width * 0.75)
        assertFitsWindowWidth("battery_current_capacity")
        assertFitsWindowWidth("battery_current_range")
    }

    func testCachedDriveSummaryAndDetailOpenWithinNavigationBudget() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        let listStarted = tapAndStartMeasurement("feature_item_drives")
        XCTAssertTrue(element("drives_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(listStarted),
            cachedNavigationAutomationBudget
        )

        let detailStarted = tapAndStartMeasurement("drive_row_101")
        XCTAssertTrue(element("drive_detail_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(detailStarted),
            cachedNavigationAutomationBudget
        )
    }

    func testCachedChargeSummaryAndDetailOpenWithinNavigationBudget() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        let listStarted = tapAndStartMeasurement("feature_item_charges")
        XCTAssertTrue(element("charges_view").waitForExistence(timeout: 2))
        XCTAssertEqual(element("charge_cost_status_201").label, "已记录")
        XCTAssertLessThan(
            Date().timeIntervalSince(listStarted),
            cachedNavigationAutomationBudget
        )

        let detailStarted = tapAndStartMeasurement("charge_row_201")
        XCTAssertTrue(element("charge_detail_view").waitForExistence(timeout: 2))
        XCTAssertTrue(element("charge_cost_explanation").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(detailStarted),
            cachedNavigationAutomationBudget
        )
    }

    func testChargeCostStatusFitsAtAccessibilityTextSize() {
        relaunchWithContentSizeCategory("UICTContentSizeCategoryAccessibilityXL")

        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        tap("feature_item_charges")
        XCTAssertTrue(element("charges_view").waitForExistence(timeout: 2))

        let row = element("charge_row_201")
        let status = element("charge_cost_status_201")
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        XCTAssertEqual(status.label, "已记录")
        XCTAssertLessThanOrEqual(row.frame.maxX, app.windows.firstMatch.frame.maxX)
        XCTAssertGreaterThanOrEqual(row.frame.minX, app.windows.firstMatch.frame.minX)
    }

    func testCachedActivitySessionDetailOpensWithinNavigationBudget() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))

        let timelineStarted = tapTabAndStartMeasurement(
            identifier: "root_tab_activity",
            label: "动态",
            timeout: 5
        )
        XCTAssertTrue(element("activity_timeline_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(timelineStarted),
            cachedNavigationAutomationBudget
        )

        let detailStarted = tapAndStartMeasurement("activity_session_ui-session-1")
        XCTAssertTrue(element("activity_session_detail_view").waitForExistence(timeout: 2))
        XCTAssertTrue(element("activity_classification_explanation").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(detailStarted),
            cachedNavigationAutomationBudget
        )
    }

    func testRepeatedTripDetailNavigationRestoresCachedContentImmediately() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("trips").tap()
        XCTAssertTrue(element("trips_view").waitForExistence(timeout: 2))

        let tripRowID = "trip_row_101"
        tap(tripRowID)
        XCTAssertTrue(element("trip_detail_view").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["测试通勤"].waitForExistence(timeout: 2))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()
        XCTAssertTrue(element("trips_view").waitForExistence(timeout: 2))

        let repeatedStarted = tapAndStartMeasurement(tripRowID)
        XCTAssertTrue(element("trip_detail_view").waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["测试通勤"].exists)
        XCTAssertLessThan(
            Date().timeIntervalSince(repeatedStarted),
            cachedNavigationAutomationBudget
        )
    }

    func testRepeatedChargeComparisonRestoresCachedContentImmediately() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        tap("feature_item_charges")
        XCTAssertTrue(element("charges_view").waitForExistence(timeout: 2))
        tap("charge_row_201")
        XCTAssertTrue(element("charge_detail_view").waitForExistence(timeout: 2))

        tapButton("charge_compare_button")
        XCTAssertTrue(element("compare_charges_view").waitForExistence(timeout: 2))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()
        XCTAssertTrue(element("charge_detail_view").waitForExistence(timeout: 2))

        let repeatedStarted = tapButtonAndStartMeasurement("charge_compare_button")
        XCTAssertTrue(element("compare_charges_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(repeatedStarted),
            cachedNavigationAutomationBudget
        )
    }

    func testCreateTripOpensFromCachedTripHistoryWithoutBlocking() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        let hubStarted = tapTabAndStartMeasurement(
            identifier: "root_tab_features",
            label: "功能",
            timeout: 5
        )
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: cachedNavigationAutomationBudget))
        XCTAssertLessThan(
            Date().timeIntervalSince(hubStarted),
            cachedNavigationAutomationBudget
        )

        tap("feature_item_trips")
        XCTAssertTrue(element("trips_view").waitForExistence(timeout: 2))

        let started = tapAndStartMeasurement("create_trip_button")
        XCTAssertTrue(element("create_trip_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            cachedNavigationAutomationBudget
        )
    }

    func testStandbyHotspotDrillsIntoCachedLocationAnalysisWithoutBlocking() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("standby-hotspots").tap()
        XCTAssertTrue(element("top_drain_locations_view").waitForExistence(timeout: 2))

        let row = element("standby_hotspot_row_0")
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()
        XCTAssertTrue(element("standby_hotspot_detail").waitForExistence(timeout: 2))

        let started = tapAndStartMeasurement("standby_analyze_location_button")
        XCTAssertTrue(element("standby_drain_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            cachedNavigationAutomationBudget
        )
    }

    func testWhereWasIOpensFromRecentMapActionsWithoutBlocking() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("recent-map").tap()
        XCTAssertTrue(element("recent_driving_map_view").waitForExistence(timeout: 2))

        tapButton("recent_map_actions")
        tapButton("recent_map_where_was_i")
        XCTAssertTrue(element("where_was_i_picker").waitForExistence(timeout: 2))

        let started = tapButtonAndStartMeasurement("where_was_i_confirm")
        XCTAssertTrue(element("where_was_i_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            cachedNavigationAutomationBudget
        )
    }

    func testDriveMetricsAndComparisonRemainAvailableFromCachedSummaryDetail() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("drives").tap()
        XCTAssertTrue(element("drives_view").waitForExistence(timeout: 2))
        tap("drive_row_101")
        XCTAssertTrue(element("drive_detail_view").waitForExistence(timeout: 2))

        let metric = scrollToButton("drive_metric_energy_button")
        let metricStarted = Date()
        metric.tap()
        XCTAssertTrue(element("drive_metric_detail_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(metricStarted),
            cachedNavigationAutomationBudget
        )
        XCTAssertTrue(app.staticTexts["3.7 kWh"].waitForExistence(timeout: 2))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()
        XCTAssertTrue(element("drive_detail_view").waitForExistence(timeout: 2))

        tapButton("drive_actions_button")
        let started = tapButtonAndStartMeasurement("drive_compare_button")
        XCTAssertTrue(element("compare_drives_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            cachedNavigationAutomationBudget
        )
    }

    func testStatsDrilldownsAndCountryRegionPathOpenWithoutBlocking() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("stats").tap()
        XCTAssertTrue(element("stats_view").waitForExistence(timeout: 2))

        assertScrollableDrilldown(
            buttonID: "stats_cost_review_button",
            destinationID: "cost_review_view"
        )
        assertScrollableDrilldown(
            buttonID: "stats_driving_records_button",
            destinationID: "driving_records_view"
        )

        let countries = scrollToButton("stats_countries_button")
        let countriesStarted = Date()
        countries.tap()
        XCTAssertTrue(element("countries_visited_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(countriesStarted),
            cachedNavigationAutomationBudget
        )
        XCTAssertTrue(app.staticTexts["中国大陆"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["China"].exists)

        let regionStarted = tapButtonAndStartMeasurement("country_row_CN")
        XCTAssertTrue(element("regions_visited_view").waitForExistence(timeout: 2))
        XCTAssertLessThan(
            Date().timeIntervalSince(regionStarted),
            cachedNavigationAutomationBudget
        )
        XCTAssertTrue(app.staticTexts["湖南"].waitForExistence(timeout: 2))
    }

    func testStatsHeatmapUsesOneAccessibleSummaryInsteadOfHundredsOfDailyCells() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("stats").tap()
        XCTAssertTrue(element("stats_view").waitForExistence(timeout: 2))
        XCTAssertTrue(element("stats_heatmap_summary").waitForExistence(timeout: 2))

        let zeroValueDay = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "0.0 km"))
            .firstMatch
        XCTAssertFalse(zeroValueDay.exists)
    }

    func testRapidRepeatedFeatureTapPushesOnlyOneDestination() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        let drives = element("feature_item_drives")
        XCTAssertTrue(drives.waitForExistence(timeout: 2))
        drives.doubleTap()
        XCTAssertTrue(element("drives_view").waitForExistence(timeout: 2))

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        XCTAssertFalse(element("drives_view").exists)
    }

    func testVehicleAndHistoryFeatureEntriesOpenWithoutBlocking() {
        assertFeatureEntriesOpen([
            ("current-charge", "current_charge_view"),
            ("drives", "drives_view"),
            ("battery", "battery_view"),
            ("charges", "charges_view"),
            ("recent-map", "recent_driving_map_view"),
            ("trips", "trips_view")
        ])
    }

    func testUnknownBatteryRecordingStartNeverAppearsAsLifetimeHealth() throws {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("battery").tap()
        XCTAssertTrue(element("battery_view").waitForExistence(timeout: 2))
        XCTAssertTrue(element("battery_calibration_required").waitForExistence(timeout: 2))
        XCTAssertTrue(element("battery_calibration_explanation").exists)
        XCTAssertTrue(element("battery_current_capacity").exists)
        XCTAssertTrue(element("battery_current_range").exists)
        XCTAssertFalse(element("battery_absolute_health_value").exists)
        XCTAssertFalse(app.staticTexts["99.3%"].exists)
        assertFitsWindowWidth("battery_calibration_required")
        assertFitsWindowWidth("battery_current_capacity")
        assertFitsWindowWidth("battery_current_range")

        try performVisibleContentAccessibilityAudit()

        let confidence = element("battery_health_confidence")
        for _ in 0..<8 where !confidence.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(confidence.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["记录起点未知"].exists)
    }

    func testInsightFeatureEntriesOpenWithoutBlocking() {
        assertFeatureEntriesOpen([
            ("energy-balance", "energy_cycles_view"),
            ("stats", "stats_view"),
            ("mileage", "mileage_view"),
            ("places", "place_insights_view"),
            ("drive-insights", "drive_insights_view"),
            ("environment", "environment_history_view")
        ])
    }

    func testSystemAndSafetyFeatureEntriesOpenWithoutBlocking() {
        assertFeatureEntriesOpen([
            ("standby-hotspots", "top_drain_locations_view"),
            ("commute-routes", "commute_routes_view"),
            ("achievements", "achievements_view"),
            ("updates", "software_updates_view"),
            ("sentry", "sentry_history_view")
        ])
    }

    func testSoftwareUpdatesEmptyStateScrollsClearOfPersistentTabBar() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        featureItem("updates").tap()
        XCTAssertTrue(element("software_updates_view").waitForExistence(timeout: 2))

        let emptyState = element("software_updates_empty_state")
        XCTAssertTrue(emptyState.waitForExistence(timeout: 2))
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists)
        for _ in 0..<4 where emptyState.frame.maxY > tabBar.frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(emptyState.isHittable)
        XCTAssertLessThanOrEqual(emptyState.frame.maxY, tabBar.frame.minY)
    }

    func testNetworkBackedFeatureErrorsOfferRetry() {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        let checks = [
            ("current-charge", "current_charge_view"),
            ("drive-insights", "drive_insights_view"),
            ("environment", "environment_history_view"),
            ("commute-routes", "commute_routes_view"),
            ("achievements", "achievements_view")
        ]

        for (itemID, destinationID) in checks {
            featureItem(itemID).tap()
            XCTAssertTrue(element(destinationID).waitForExistence(timeout: 2))
            XCTAssertTrue(app.buttons["重试"].waitForExistence(timeout: 2), "Missing retry action for \(itemID)")

            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 2))
            backButton.tap()
            XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        }
    }

    private func assertFeatureEntriesOpen(_ checks: [(String, String)]) {
        XCTAssertTrue(element("dashboard_view").waitForExistence(timeout: 5))
        tapTab(identifier: "root_tab_features", label: "功能", timeout: 5)
        XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))

        for (itemID, destinationID) in checks {
            let item = featureItem(itemID)
            let started = Date()
            item.tap()

            XCTAssertTrue(
                element(destinationID).waitForExistence(timeout: 2),
                "Feature \(itemID) did not open \(destinationID)"
            )
            XCTAssertLessThan(
                Date().timeIntervalSince(started),
                cachedNavigationAutomationBudget,
                "Feature \(itemID) exceeded the cached navigation budget"
            )

            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 2), "Missing back button for \(itemID)")
            backButton.tap()
            XCTAssertTrue(element("feature_hub_view").waitForExistence(timeout: 2))
        }
    }

    private func assertScrollableDrilldown(buttonID: String, destinationID: String) {
        let target = scrollToButton(buttonID)
        let started = Date()
        target.tap()
        XCTAssertTrue(
            element(destinationID).waitForExistence(timeout: 2),
            "\(buttonID) did not open \(destinationID)"
        )
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            cachedNavigationAutomationBudget,
            "\(buttonID) exceeded the cached navigation budget"
        )

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 2), "Missing back button for \(destinationID)")
        backButton.tap()
        XCTAssertTrue(element("stats_view").waitForExistence(timeout: 2))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func performVisibleContentAccessibilityAudit() throws {
        let tabBarFrame = app.tabBars.firstMatch.frame
        let windowFrame = app.windows.firstMatch.frame
        // The iOS 26.5 simulator reports random SwiftUI text nodes as non-scaling.
        // Dedicated accessibility-size tests below verify the actual type and layout changes.
        try app.performAccessibilityAudit(for: .all.subtracting(.dynamicType)) { issue in
            if issue.auditType == .contrast, issue.element == nil {
                return true
            }
            if issue.auditType == .textClipped,
               let elementType = issue.element?.elementType,
               elementType == .textField || elementType == .secureTextField {
                return true
            }
            if issue.auditType == .textClipped,
               let issueFrame = issue.element?.frame,
               !windowFrame.isEmpty,
               (issueFrame.minY <= windowFrame.minY
                   || (!tabBarFrame.isEmpty && issueFrame.maxY >= tabBarFrame.minY)) {
                return true
            }
            guard issue.auditType == .contrast,
                  let issueFrame = issue.element?.frame,
                  !tabBarFrame.isEmpty,
                  tabBarFrame.intersects(issueFrame)
            else {
                return false
            }
            return true
        }
    }

    private func assertFitsWindowWidth(
        _ identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = app.descendants(matching: .any)
            .matching(identifier: identifier)
            .firstMatch
        XCTAssertTrue(target.exists, file: file, line: line)
        let frame = target.frame
        let windowFrame = app.windows.firstMatch.frame
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX, file: file, line: line)
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 2) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing UI element \(identifier)")
        target.tap()
    }

    private func tapAndStartMeasurement(
        _ identifier: String,
        timeout: TimeInterval = 2
    ) -> Date {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing UI element \(identifier)")
        let started = Date()
        target.tap()
        return started
    }

    private func tapButton(_ identifier: String, timeout: TimeInterval = 2) {
        let target = app.buttons[identifier].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing button \(identifier)")
        target.tap()
    }

    private func tapButtonAndStartMeasurement(
        _ identifier: String,
        timeout: TimeInterval = 2
    ) -> Date {
        let target = app.buttons[identifier].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: timeout), "Missing button \(identifier)")
        let started = Date()
        target.tap()
        return started
    }

    private func featureItem(_ id: String) -> XCUIElement {
        let item = element("feature_item_\(id)")
        for _ in 0..<10 where !item.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(item.waitForExistence(timeout: 2), "Missing feature item \(id)")
        XCTAssertTrue(item.isHittable, "Feature item \(id) is not hittable")
        return item
    }

    private func relaunchWithContentSizeCategory(_ category: String) {
        app.terminate()
        if let argumentIndex = app.launchArguments.firstIndex(
            of: "-UIPreferredContentSizeCategoryName"
        ), app.launchArguments.indices.contains(argumentIndex + 1) {
            app.launchArguments[argumentIndex + 1] = category
        } else {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                category
            ]
        }
        app.launch()
    }

    private func relaunchWithLanguage(_ language: String) {
        app.terminate()
        app.launchEnvironment["MATEDRIVE_UI_TEST_LANGUAGE"] = language
        app.launch()
    }

    private func scrollToButton(_ identifier: String) -> XCUIElement {
        let target = app.buttons[identifier].firstMatch
        for _ in 0..<12 where !target.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(target.waitForExistence(timeout: 2), "Missing button \(identifier)")
        XCTAssertTrue(target.isHittable, "Button \(identifier) is not hittable")
        return target
    }

    private func tapTab(identifier: String, label: String, timeout: TimeInterval = 2) {
        let labeled = app.tabBars.buttons[label]
        if labeled.waitForExistence(timeout: timeout) {
            labeled.tap()
            return
        }
        let identified = element(identifier)
        XCTAssertTrue(identified.waitForExistence(timeout: timeout), "Missing tab \(label)")
        identified.tap()
    }

    private func tapTabAndStartMeasurement(
        identifier: String,
        label: String,
        timeout: TimeInterval = 2
    ) -> Date {
        let labeled = app.tabBars.buttons[label]
        if labeled.waitForExistence(timeout: timeout) {
            let started = Date()
            labeled.tap()
            return started
        }
        let identified = element(identifier)
        XCTAssertTrue(identified.waitForExistence(timeout: timeout), "Missing tab \(label)")
        let started = Date()
        identified.tap()
        return started
    }
}

@MainActor
final class MateDriveFirstRunUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MATEDRIVE_UI_TEST_MODE"] = "1"
        app.launchEnvironment["MATEDRIVE_UI_TEST_FRESH_SETUP"] = "1"
        app.launchEnvironment["MATEDRIVE_SKIP_LAUNCH_EXPERIENCE"] = "1"
    }

    func testFreshInstallShowsFocusedConnectionSetup() {
        app.launch()
        let setup = app.descendants(matching: .any)
            .matching(identifier: "initial_connection_setup")
            .firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["连接 TeslaMate"].exists)
        XCTAssertTrue(app.textFields["setup_server_url"].exists)

        let complete = app.buttons["setup_complete_button"].firstMatch
        XCTAssertTrue(complete.exists)
        XCTAssertFalse(complete.isEnabled)
        XCTAssertFalse(app.staticTexts["地理数据质量"].exists)
    }

    func testFailedVerificationStaysOnSetupAndShowsRecoveryReport() {
        app.launchEnvironment["MATEDRIVE_UI_TEST_SETUP_SERVER_URL"] = "http://127.0.0.1:1"
        app.launch()

        let complete = app.buttons["setup_complete_button"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(complete.isEnabled)
        complete.tap()

        let failedSummary = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "连接测试失败"))
            .firstMatch
        XCTAssertTrue(failedSummary.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["initial_connection_setup"].exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let reportScreenshot = XCTAttachment(screenshot: app.screenshot())
        reportScreenshot.name = "First run failed connection report"
        reportScreenshot.lifetime = .keepAlways
        add(reportScreenshot)

        let failedDetail = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "车辆列表失败"))
            .firstMatch
        app.swipeUp()
        XCTAssertTrue(failedDetail.waitForExistence(timeout: 2))
        let visibleDetailFrame = failedDetail.frame.intersection(app.windows.firstMatch.frame)
        XCTAssertFalse(visibleDetailFrame.isNull)
        XCTAssertGreaterThan(visibleDetailFrame.height, 0)

        let detailScreenshot = XCTAttachment(screenshot: app.screenshot())
        detailScreenshot.name = "First run failed connection details"
        detailScreenshot.lifetime = .keepAlways
        add(detailScreenshot)
    }

    func testSuccessfulVerificationSavesServerAndSurvivesRelaunch() throws {
        let server = try LocalTeslaMateHTTPServer()
        defer { server.stop() }
        app.launchEnvironment["MATEDRIVE_UI_TEST_SETUP_SERVER_URL"] = server.baseURL
        app.launch()

        let complete = app.buttons["setup_complete_button"].firstMatch
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        XCTAssertTrue(complete.isEnabled)
        complete.tap()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard_view"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["initial_connection_setup"].exists)
        XCTAssertTrue(app.staticTexts["Blue 3"].waitForExistence(timeout: 20))

        let successScreenshot = XCTAttachment(screenshot: app.screenshot())
        successScreenshot.name = "First run successful connection landing"
        successScreenshot.lifetime = .keepAlways
        add(successScreenshot)

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "MATEDRIVE_UI_TEST_FRESH_SETUP")
        app.launchEnvironment.removeValue(forKey: "MATEDRIVE_UI_TEST_SETUP_SERVER_URL")
        app.launchEnvironment["MATEDRIVE_UI_TEST_PRESERVE_SETTINGS"] = "1"
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["dashboard_view"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["设置"].waitForExistence(timeout: 2))
        app.tabBars.buttons["设置"].tap()

        let savedServerURL = app.textFields["settings_server_url"].firstMatch
        XCTAssertTrue(savedServerURL.waitForExistence(timeout: 5))
        XCTAssertEqual(savedServerURL.value as? String, server.baseURL)
    }
}

private final class LocalTeslaMateHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "MateDriveUITests.LocalTeslaMateHTTPServer")
    private let ready = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var startupError: NWError?

    var baseURL: String {
        "http://127.0.0.1:\(listener.port?.rawValue ?? 0)"
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                ready.signal()
            case let .failed(error):
                stateLock.lock()
                startupError = error
                stateLock.unlock()
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success else {
            listener.cancel()
            throw LocalServerError.startTimedOut
        }
        stateLock.lock()
        let error = startupError
        stateLock.unlock()
        if let error {
            listener.cancel()
            throw error
        }
        guard listener.port != nil else {
            listener.cancel()
            throw LocalServerError.missingPort
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var request = accumulated
            if let data {
                request.append(data)
            }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                sendResponse(for: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receiveRequest(on: connection, accumulated: request)
            }
        }
    }

    private func sendResponse(for request: Data, on connection: NWConnection) {
        let requestLine = String(data: request, encoding: .utf8)?
            .components(separatedBy: "\r\n")
            .first
        let rawTarget = requestLine?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let path = String(rawTarget.split(separator: "?", maxSplits: 1).first ?? "/")
        let route = Self.route(for: path)
        let body = Data(route.body.utf8)
        let header = "HTTP/1.1 \(route.status) \(route.reason)\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func route(for path: String) -> (status: Int, reason: String, body: String) {
        switch path {
        case "/api/v1/version":
            return (200, "OK", #"{"api_version":"2.5.0","mt_api_version":"2.5.0","build_info":"MateDrive UI test"}"#)
        case "/api/v1/cars":
            return (200, "OK", #"{"data":{"cars":[{"car_id":1,"display_name":"Blue 3","car_details":{"model":"3"},"car_exterior":{"exterior_color":"PBSB","wheel_type":"W39B"}}]}}"#)
        case "/api/v1/cars/1/status":
            return (200, "OK", #"{"data":{"status":{"display_name":"Blue 3","battery_details":{"battery_level":50},"locked":true},"units":{"unit_of_length":"km","unit_of_temperature":"C"}}}"#)
        case "/api/v1/globalsettings":
            return (200, "OK", #"{"data":{"settings":{"unit_of_length":"km","unit_of_temperature":"C","preferred_range":"rated"}}}"#)
        case "/api/v1/cars/1/drives":
            return (200, "OK", #"{"data":{"drives":[]}}"#)
        case "/api/v1/cars/1/charges":
            return (200, "OK", #"{"data":{"charges":[]}}"#)
        case "/api/v1/cars/1/environment-history":
            return (200, "OK", #"{"data":{"series":[],"summary":{"point_count":0,"sample_count":0},"temperature_energy_buckets":[],"leak_observations":[]}}"#)
        case "/api/v1/cars/1/battery-health":
            return (200, "OK", #"{"data":{"battery_health":{"battery_health_percentage":92,"current_range":455}}}"#)
        case "/api/v1/cars/1/updates":
            return (200, "OK", #"{"data":{"updates":[]}}"#)
        case "/api/v1/cars/1/charges/current":
            return (204, "No Content", "")
        default:
            return (404, "Not Found", #"{"error":"not found"}"#)
        }
    }

    private enum LocalServerError: Error {
        case startTimedOut
        case missingPort
    }
}
