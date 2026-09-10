#!/usr/bin/env python3
import unittest
from pathlib import Path

from audit_app_store_submission import (
    accessibility_release_audit_blockers,
    app_version_blockers,
    automatic_charge_inference_blockers,
    cached_battery_page_blockers,
    cached_cost_hotspot_trips_blockers,
    cached_live_current_charge_blockers,
    cached_standby_create_trip_blockers,
    cached_software_updates_blockers,
    cached_system_safety_blockers,
    battery_ui_safety_blockers,
    cached_secondary_page_blockers,
    cached_tertiary_page_blockers,
    cached_geography_page_blockers,
    cached_analytics_page_blockers,
    cached_detail_currency_blockers,
    cached_where_was_i_blockers,
    charge_cost_transparency_blockers,
    charge_pricing_safety_blockers,
    cloudkit_release_blockers,
    connection_settings_transaction_blockers,
    credential_privacy_blockers,
    forced_crash_pattern_blockers,
    geofence_precedence_blockers,
    historical_tariff_transparency_blockers,
    history_pagination_blockers,
    in_app_support_link_blockers,
    launch_bootstrap_blockers,
    review_demo_api_blockers,
    review_demo_embedding_blockers,
    route_weather_privacy_blockers,
    submission_blockers,
    submission_metadata_blockers,
    support_contact_blockers,
    sync_cancellation_blockers,
)


class AppStoreSubmissionMetadataAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.submission = Path("docs/release/app-store-submission.md").read_text(encoding="utf-8")

    def test_accepts_current_submission_metadata(self) -> None:
        self.assertEqual(submission_metadata_blockers(self.submission), [])

    def test_requires_privacy_policy_section(self) -> None:
        text = self.submission.replace(
            "## Privacy Policy URL\n\nhttps://youyooo.github.io/MateDrive/privacy.html\n\n",
            "",
        )

        blockers = submission_metadata_blockers(text)

        self.assertIn("missing required section: ## Privacy Policy URL", blockers)
        self.assertIn("privacy policy URL must be a reachable https:// URL", blockers)

    def test_rejects_non_https_privacy_policy_url(self) -> None:
        text = self.submission.replace(
            "https://youyooo.github.io/MateDrive/privacy.html",
            "ftp://example.com/privacy.html",
        )

        self.assertIn(
            "privacy policy URL must be a reachable https:// URL",
            submission_metadata_blockers(text),
        )

    def test_enforces_app_store_text_limits(self) -> None:
        text = self.submission.replace(
            "TeslaMate dashboard for iPhone",
            "x" * 31,
        ).replace(
            "TeslaMate,Tesla,EV,charging,drives,mileage,battery,widget,vehicle,dashboard",
            "x" * 101,
        )

        blockers = submission_metadata_blockers(text)

        self.assertIn("subtitle must not exceed 30 characters", blockers)
        self.assertIn("keywords must contain 1 to 100 UTF-8 bytes", blockers)

    def test_requires_direct_support_contact(self) -> None:
        issues_only = "<a href='https://example.com/issues'>Issues</a>"
        self.assertEqual(support_contact_blockers(issues_only), [
            "support page must provide a direct email or telephone contact"
        ])
        self.assertEqual(submission_blockers(self.submission, issues_only), [
            "support page must provide a direct email or telephone contact"
        ])
        self.assertEqual(
            support_contact_blockers("<a href='mailto:support@example.com'>Email</a>"),
            [],
        )
        self.assertEqual(
            submission_blockers(
                self.submission,
                "<a href='mailto:support@example.com'>Email</a>",
            ),
            [],
        )

    def test_requires_in_app_support_and_privacy_links(self) -> None:
        links = """
        static let supportURLString = "https://youyooo.github.io/MateDrive/"
        static let privacyPolicyURLString = "https://youyooo.github.io/MateDrive/privacy.html"
        static var supportURL: URL?
        static var privacyPolicyURL: URL?
        """
        settings = """
        Link(destination: AppLinks.supportURL)
        Text("Support & Feedback")
        Link(destination: AppLinks.privacyPolicyURL)
        """
        privacy = "Link(destination: AppLinks.privacyPolicyURL)"

        self.assertEqual(in_app_support_link_blockers(settings, privacy, links), [])
        self.assertEqual(
            in_app_support_link_blockers(
                settings.replace("AppLinks.supportURL", "URL(string: fallback)"),
                privacy,
                links,
            ),
            ["Settings must provide a direct public support link"],
        )
        self.assertEqual(
            in_app_support_link_blockers(
                settings,
                privacy.replace("AppLinks.privacyPolicyURL", "URL(string: fallback)"),
                links,
            ),
            ["Settings and the privacy page must link to the public privacy policy"],
        )

    def test_requires_public_read_only_review_demo_api(self) -> None:
        generator = """
        MARKER = ".generated-review-demo-api"
        Refusing to replace unmarked directory
        synthetic read-only review data
        default=Path("docs/support/review-demo")
        """
        workflow = """
        cron: "17 2 * * *"
        run: python3 scripts/generate_review_demo_api.py
        path: docs/support
        """
        makefile = """
        review-demo-test:
            python3 scripts/test_review_demo_api.py
        """
        probe = 'curl_args=(-sS -L --max-redirs 3 --max-time 5)'
        tests = """
        test_generates_complete_parseable_api
        test_uses_recent_synthetic_data_without_sensitive_fields
        test_refuses_to_replace_unmarked_directory
        test_static_server_passes_probe_and_rejects_writes
        """
        native_tests = """
        testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN
        XCTAssertNil(car.carDetails?.vin)
        api.updateChargeCost(chargeId: chargeID, cost: 1)
        """
        makefile += """
        review-demo-native-test:
            -only-testing:MateDriveTests/LocalTeslamateIntegrationTests/testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN
        review-integration-test:
            -only-testing:MateDriveTests/LocalTeslamateIntegrationTests/testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN
        """
        submission = """
        https://youyooo.github.io/MateDrive/review-demo
        Authentication: None
        synthetic read-only data
        """

        self.assertEqual(
            review_demo_api_blockers(
                generator,
                workflow,
                makefile,
                probe,
                tests,
                native_tests,
                submission,
            ),
            [],
        )
        self.assertEqual(
            review_demo_api_blockers(
                generator,
                workflow.replace('cron: "17 2 * * *"', ""),
                makefile,
                probe,
                tests,
                native_tests,
                submission,
            ),
            [
                "App Review must retain the public, daily-refreshed, read-only synthetic TeslaMate API and its privacy/probe regression gate"
            ],
        )

    def test_rejects_review_demo_url_in_production_sources(self) -> None:
        self.assertEqual(
            review_demo_embedding_blockers(
                'static let supportURL = "https://youyooo.github.io/MateDrive/"'
            ),
            [],
        )
        self.assertEqual(
            review_demo_embedding_blockers(
                'let baseURL = "https://youyooo.github.io/MateDrive/review-demo"'
            ),
            [
                "Production app and widget sources must not embed the App Review synthetic TeslaMate API URL"
            ],
        )

    def test_accepts_numeric_versions_or_valid_project_version_substitution(self) -> None:
        project = """
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "11"
        """
        self.assertEqual(app_version_blockers("1.0", "11", project), [])
        self.assertEqual(
            app_version_blockers(
                "$(MARKETING_VERSION)",
                "$(CURRENT_PROJECT_VERSION)",
                project,
            ),
            [],
        )
        self.assertEqual(
            app_version_blockers(
                "$(MARKETING_VERSION)",
                "$(CURRENT_PROJECT_VERSION)",
                'MARKETING_VERSION: "release"\nCURRENT_PROJECT_VERSION: "next"',
            ),
            [
                "CFBundleShortVersionString must resolve to a numeric version",
                "CFBundleVersion must resolve to a numeric build",
            ],
        )

    def test_requires_cloudkit_production_schema_and_device_round_trip(self) -> None:
        entitlements = {
            "com.apple.developer.icloud-container-environment": "Production",
            "com.apple.developer.icloud-container-identifiers": [
                "iCloud.com.matedrive.ios"
            ],
            "com.apple.developer.icloud-services": ["CloudKit"],
        }
        schema = """
        RECORD TYPE MateDriveBackup (
            createdAt TIMESTAMP SORTABLE,
            databaseAsset ASSET,
            settingsData ENCRYPTED BYTES,
            GRANT READ, WRITE TO "_creator",
            GRANT CREATE TO "_icloud"
        );
        """
        project = """
        MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS: "$(MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS)"
        """
        integration_tests = """
        environment["MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS"] == "1"
        #if targetEnvironment(simulator)
        service.upload(
        service.listBackups()
        service.download(
        service.delete(
        """

        self.assertEqual(
            cloudkit_release_blockers(
                entitlements,
                schema,
                project,
                integration_tests,
            ),
            [],
        )
        self.assertEqual(
            cloudkit_release_blockers(
                {
                    **entitlements,
                    "com.apple.developer.icloud-container-environment": "Development",
                },
                schema.replace("settingsData ENCRYPTED BYTES", "settingsData BYTES"),
                project,
                integration_tests.replace("service.download(", ""),
            ),
            [
                "CloudKit release entitlements must target the MateDrive Production container",
                "CloudKit backup schema must retain encrypted settings, sortable metadata, assets, and private creator grants",
                "CloudKit release testing must retain the opt-in physical-device upload/list/download/delete round trip",
            ],
        )

    def test_rejects_forced_crash_patterns_without_flagging_normal_negation(self) -> None:
        valid_source = """
        guard !Task.isCancelled else { return }
        if value != nil { consume(value) }
        """
        self.assertEqual(forced_crash_pattern_blockers(valid_source), [])

        unsafe_source = """
        let response = try! decoder.decode(Response.self, from: data)
        let model = value as! Model
        let item = optional!
        fatalError("unreachable")
        preconditionFailure("invalid state")
        """
        self.assertEqual(
            forced_crash_pattern_blockers(unsafe_source),
            [
                "production Swift must avoid forced crash patterns: "
                "try!, as!, fatalError(, preconditionFailure(, forced optional unwrap"
            ],
        )

    def test_rejects_oversized_or_unguarded_history_fallbacks(self) -> None:
        valid_paginator = """
        public enum VehicleHistoryPaginator {
            public static let pageSize = 200
            static let maximumPageCount = 250
            // Task.isCancelled
            // addedCount == 0
        }
        """
        self.assertEqual(history_pagination_blockers(valid_paginator, "show: 200"), [])
        self.assertIn(
            "production pages must not request oversized history lists",
            history_pagination_blockers(valid_paginator, "show: 50_000"),
        )
        self.assertIn(
            "history fallback reads must use bounded cancellable pagination with a no-progress guard",
            history_pagination_blockers("public enum VehicleHistoryPaginator {}", "show: 200"),
        )

    def test_requires_cancellation_guards_before_sync_writes_and_error_state(self) -> None:
        valid_sync = """
        if !Task.isCancelled {
            markError()
        }
        if !Task.isCancelled {
            markError()
        }
        if !Task.isCancelled {
            markError()
        }
        switch await api.drives(carId: carId, page: page, show: 200) {
        case let .success(items):
            guard !Task.isCancelled else { return false }
        }
        switch await api.charges(carId: carId, page: page, show: 200) {
        case let .success(items):
            guard !Task.isCancelled else { return false }
        }
        return values
            }
            guard !Task.isCancelled else { return false }
        return values
            }
            guard !Task.isCancelled else { return false }
        """
        self.assertEqual(sync_cancellation_blockers(valid_sync), [])
        self.assertEqual(
            sync_cancellation_blockers(valid_sync.replace("if !Task.isCancelled {", "if true {", 1)),
            ["cancelled background synchronization must not persist late responses or report a false failure"],
        )
        self.assertEqual(
            sync_cancellation_blockers(
                valid_sync.replace(
                    "case let .success(items):\n            guard !Task.isCancelled else { return false }",
                    "case let .success(items):",
                    1,
                )
            ),
            ["cancelled background synchronization must not persist late responses or report a false failure"],
        )

    def test_requires_cached_first_launch_bootstrap_and_relaunch_coverage(self) -> None:
        settings = """
        public func loadEssentials() async {
            settings = await settingsStore.load()
        }
        public func refreshOperationalState() async {
            await refreshNotificationAuthorizationStatus()
        }
        """
        root = """
        seedLaunchConfigurationIfNeeded
        await settingsViewModel.loadEssentials()
        Task(priority: .utility) {
            if Self.isAutomatedTestMode { return }
            Self.isReservedTestServer
            host.hasSuffix(".invalid")
            environment["MATEDRIVE_AUTOMATED_TEST_MODE"] == "1"
            environment["XCTestConfigurationFilePath"]
            NSClassFromString("XCTestCase")
            await syncLifecycleController.appDidBecomeActive()
            seedDatabaseFixtureIfNeeded
            await settingsViewModel.refreshOperationalState()
        }
        """
        seeder = """
        seedLaunchConfigurationIfNeeded
        seedDatabaseFixtureIfNeeded
        """
        tests = """
        testEssentialLoadPublishesConfigurationBeforeOperationalChecks
        testUITestLaunchConfigurationCanSeedWithoutOpeningDatabase
        """
        ui_tests = """
        testColdAndWarmLaunchPublishCachedDashboardWithinBudget
        element("dashboard_view").waitForExistence(timeout: cachedNavigationAutomationBudget)
        """

        self.assertEqual(
            launch_bootstrap_blockers(root, settings, seeder, tests, ui_tests),
            [],
        )
        self.assertEqual(
            launch_bootstrap_blockers(
                root.replace("Task(priority: .utility)", "Group"),
                settings,
                seeder,
                tests,
                ui_tests,
            ),
            [
                "launch must publish cached configured UI before synchronization, database fixtures, notification, geography, or history health work, with cold and warm relaunch coverage"
            ],
        )

    def test_requires_bounded_charge_pricing_interpolation(self) -> None:
        valid_pricing = """
        maximumInterpolatedInterval: TimeInterval = 7 * 24 * 60 * 60
        guard !hasUnsafeInterpolationGap(
        sessionEnd < sessionStart
        sample.0.timeIntervalSince(previousDate) > maximumInterpolatedInterval
        residualDuration < 0 || residualDuration > maximumInterpolatedInterval
        """
        self.assertEqual(charge_pricing_safety_blockers(valid_pricing), [])
        self.assertEqual(
            charge_pricing_safety_blockers(
                valid_pricing.replace(
                    "sample.0.timeIntervalSince(previousDate) > maximumInterpolatedInterval",
                    "sample.0.timeIntervalSince(previousDate) > .infinity",
                )
            ),
            [
                "time-segmented charge pricing must reject invalid or unbounded energy interpolation"
            ],
        )

    def test_requires_shared_bounded_automatic_charge_inference(self) -> None:
        valid_resolver = """
        public enum ChargeLocationInferenceSource {
            case overnightACPattern
        }
        source: .savedGeofence
        confidence: min(confidence, 0.75)
        """
        valid_pricing_rule = "case inferredHome"
        valid_dashboard = "AutomaticChargeCostEstimator.resolve("
        valid_list = "AutomaticChargeCostEstimator.resolve("
        valid_detail = "AutomaticChargeCostEstimator.inferLocation("
        valid_activity = "AutomaticChargeCostEstimator.inferLocation("

        self.assertEqual(
            automatic_charge_inference_blockers(
                valid_resolver,
                valid_pricing_rule,
                valid_dashboard,
                valid_list,
                valid_detail,
                valid_activity,
            ),
            [],
        )
        self.assertEqual(
            automatic_charge_inference_blockers(
                valid_resolver.replace("0.75", "1.0"),
                valid_pricing_rule,
                valid_dashboard,
                valid_list,
                valid_detail,
                valid_activity,
            ),
            [
                "dashboard, charge list, charge detail, and activity indexing must share bounded automatic charge-location inference"
            ],
        )
        self.assertEqual(
            automatic_charge_inference_blockers(
                valid_resolver,
                valid_pricing_rule,
                valid_dashboard,
                "",
                valid_detail,
                valid_activity,
            ),
            [
                "dashboard, charge list, charge detail, and activity indexing must share bounded automatic charge-location inference"
            ],
        )

    def test_requires_deterministic_overlapping_geofence_precedence(self) -> None:
        valid_settings = """
        let lhsIsVehicleSpecific = lhs.rule.carId != nil
        if lhsIsVehicleSpecific != rhsIsVehicleSpecific
        abs(lhs.distance - rhs.distance) > 0.001
        lhs.rule.radiusMeters < rhs.rule.radiusMeters
        """
        valid_tests = """
        testOverlappingGeofencesPreferVehicleScopeThenNearestCenter
        """
        expected = [
            "overlapping geofences must prefer the current vehicle, then the nearest center and smallest radius"
        ]

        self.assertEqual(
            geofence_precedence_blockers(valid_settings, valid_tests),
            [],
        )
        self.assertEqual(
            geofence_precedence_blockers(
                valid_settings.replace(
                    "if lhsIsVehicleSpecific != rhsIsVehicleSpecific",
                    "",
                ),
                valid_tests,
            ),
            expected,
        )
        self.assertEqual(
            geofence_precedence_blockers(valid_settings, ""),
            expected,
        )

    def test_requires_visible_accessible_charge_cost_status(self) -> None:
        valid_view = """
        t("Cost Total", "费用合计")
        ChargeCostPresentation.status(
        accessibilityIdentifier("charge_cost_status_\\(row.chargeId)")
        dynamicTypeSize.isAccessibilitySize
        """
        valid_ui_tests = """
        testChargeCostStatusFitsAtAccessibilityTextSize
        element("charge_cost_status_201")
        XCTAssertEqual(status.label, "已记录")
        """

        self.assertEqual(
            charge_cost_transparency_blockers(valid_view, valid_ui_tests),
            [],
        )
        self.assertEqual(
            charge_cost_transparency_blockers(
                valid_view.replace("dynamicTypeSize.isAccessibilitySize", ""),
                valid_ui_tests,
            ),
            [
                "charge history must distinguish recorded, estimated, corrected, and missing costs with accessibility-size UI coverage"
            ],
        )

    def test_requires_expired_tariff_labels_on_every_cost_surface(self) -> None:
        catalog = """
        public func estimationRule(
        rule.id += "-reference-estimate"
        """
        pricing_rule = """
        public var isHistoricalReference: Bool
        case historicalReference
        localized("Historical reference", "历史参考"
        """
        resolver = """
        public let isHistoricalReference: Bool
        isHistoricalReference: estimate.rule.isHistoricalReference
        """
        detail = """
        factors.append(.historicalReference)
        catalog.localizedRuleName(
        """
        list_model = """
        public let isHistoricalReference: Bool
        isHistoricalReference: resolution?.isHistoricalReference == true
        """
        list_view = """
        AppText.localized("Historical reference", "历史参考"
        """
        dashboard_summary = """
        public let isCostHistoricalReference: Bool?
        """
        dashboard_presentation = """
        Self.text("Historical reference", "历史参考费用"
        """
        tests = """
        testExpiredTariffEstimateIsExplicitlyMarkedAndLocalizedAsHistoricalReference
        testHistoricalReferenceExplanationCannotBeMistakenForCurrentTariff
        testLatestChargeLabelsExpiredTariffAsHistoricalReference
        testChargeListUsesSameProbableHomeRegionalEstimateAsDashboard
        testChargeDetailUsesProbableHomeRegionalEstimateAndExplainsInference
        """
        expected = [
            "expired regional tariffs must remain explicit historical references across charge detail, history, and dashboard cost surfaces"
        ]

        self.assertEqual(
            historical_tariff_transparency_blockers(
                catalog,
                pricing_rule,
                resolver,
                detail,
                list_model,
                list_view,
                dashboard_summary,
                dashboard_presentation,
                tests,
            ),
            [],
        )
        self.assertEqual(
            historical_tariff_transparency_blockers(
                catalog,
                pricing_rule,
                resolver,
                detail,
                list_model,
                list_view,
                dashboard_summary,
                "",
                tests,
            ),
            expected,
        )
        self.assertEqual(
            historical_tariff_transparency_blockers(
                catalog,
                pricing_rule,
                resolver,
                detail,
                list_model,
                list_view,
                dashboard_summary,
                dashboard_presentation,
                tests.replace(
                    "testHistoricalReferenceExplanationCannotBeMistakenForCurrentTariff",
                    "",
                ),
            ),
            expected,
        )

    def test_requires_cached_first_secondary_pages(self) -> None:
        root = """
        cacheKey: vehiclePageCacheKey(carId: carId)
        cacheKey: vehiclePageCacheKey(carId: carId)
        cacheKey: vehiclePageCacheKey(carId: carId)
        cacheKey: vehiclePageCacheKey(carId: carId)
        private func vehiclePageCacheKey(carId: Int) -> VehiclePageCacheKey
        """
        cache = """
        public struct VehiclePageCacheKey
        public let serverURL: String
        public let carId: Int
        maximumEntryCount
        while recency.count > maximumEntryCount
        """
        recent = """
        state.isLoading = state.routes.isEmpty
        guard !state.isRefreshing else { return }
        """
        records = """
        state.isLoading = state.records.isEmpty
        guard !state.isRefreshing else { return }
        """
        insights = """
        state.isLoading = !hasContent
        guard !state.isRefreshing else { return }
        """
        view = """
        if viewModel.state.isLoading, !hasContent
        else if let error = viewModel.state.errorMessage, !hasContent
        """
        energy = """
        guard !isRefreshing else { return }
        Task.detached(priority: .userInitiated)
        stateCache.save(state, for: cacheKey)
        """
        tests = """
        testRepeatedEntryRestoresRoutesBeforeFailedRefresh
        testRepeatedEntryRestoresRecordsBeforeFailedRefresh
        testRepeatedEntryRestoresInsightsBeforeFailedRefresh
        testConcurrentLoadsShareOneRefresh
        testRepeatedEntryRestoresAnalysisAndFailedRefreshPreservesIt
        testConcurrentLoadsOnlyReadStoredHistoryOnce
        testSeparatesVehiclesAndServersAndEvictsLeastRecentlyUsedEntry
        """

        self.assertEqual(
            cached_secondary_page_blockers(
                root, cache, recent, records, insights, view, energy, tests
            ),
            [],
        )
        self.assertEqual(
            cached_secondary_page_blockers(
                root, cache, recent, records, insights, "", energy, tests
            ),
            [
                "recent map, driving records, drive insights, and energy balance must restore server-scoped cached state before background refresh"
            ],
        )

    def test_requires_cached_first_analytics_pages(self) -> None:
        root = "\n".join(
            ["cacheKey: vehiclePageCacheKey(carId: carId)"] * 7
        )
        stats_model = """
        VehiclePageStateCache<StatsPageSnapshot>(maximumEntryCount: 4)
        guard !isRefreshing else { return }
        state.isLoading = !hasVisibleContent
        """
        stats_view = """
        if viewModel.state.isLoading, !hasVisibleContent
        UserFacingErrorLocalizer.localized
        """
        mileage_model = """
        VehiclePageStateCache<MileagePageSnapshot>(maximumEntryCount: 4)
        guard !isRefreshing else { return }
        state.isLoading = state.years.isEmpty
        """
        mileage_view = """
        if viewModel.state.isLoading, viewModel.state.years.isEmpty
        UserFacingErrorLocalizer.localized
        """
        place_model = """
        VehiclePageStateCache<PlaceInsightsState>
        guard !isRefreshing else { return }
        state.isLoading = state.places.isEmpty
        Task.detached(priority: .userInitiated)
        """
        place_view = """
        if viewModel.state.isLoading, viewModel.state.places.isEmpty
        UserFacingErrorLocalizer.localized
        """
        tests = """
        testMileageRepeatedEntryRestoresDrilldownAndFailedRefreshPreservesIt
        testStatsRepeatedEntryRestoresFilterContextAndFailedRefreshPreservesIt
        testMileageConcurrentLoadsReadHistoryOnce
        testRepeatedEntryRestoresPlacesAndFailedRefreshPreservesThem
        testConcurrentPlaceLoadsStartOneServerRefresh
        """

        self.assertEqual(
            cached_analytics_page_blockers(
                root,
                stats_model,
                stats_view,
                mileage_model,
                mileage_view,
                place_model,
                place_view,
                tests,
            ),
            [],
        )
        self.assertEqual(
            cached_analytics_page_blockers(
                root,
                stats_model,
                stats_view,
                mileage_model,
                mileage_view,
                place_model,
                "",
                tests,
            ),
            [
                "stats, mileage, and place insights must restore scoped snapshots, preserve visible content on refresh failure, and suppress duplicate loads"
            ],
        )

    def test_requires_cached_first_tertiary_pages(self) -> None:
        root = "\n".join(
            ["cacheKey: vehiclePageCacheKey(carId: carId)"] * 9
        )
        commute_model = """
        VehiclePageStateCache<CommuteRoutesState>
        guard !state.isRefreshing else { return }
        state.isLoading = state.routes.isEmpty
        stateCache.save(snapshot, for: cacheKey)
        """
        commute_view = """
        if viewModel.state.isLoading, viewModel.state.routes.isEmpty
        UserFacingErrorLocalizer.localized
        """
        environment_model = """
        VehiclePageStateCache<EnvironmentHistoryState>
        guard !state.isRefreshing else { return }
        state.isLoading = state.response == nil
        stateCache.save(snapshot, for: cacheKey)
        """
        environment_view = """
        if viewModel.state.isLoading, viewModel.state.response == nil
        UserFacingErrorLocalizer.localized
        """
        tests = """
        testRepeatedEntryRestoresCommuteRoutesBeforeFailedRefresh
        testConcurrentLoadsStartOneCommuteRequest
        testRepeatedEntryRestoresLastRangeBeforeFailedRefresh
        testConcurrentLoadsStartOneEnvironmentRequest
        """

        self.assertEqual(
            cached_tertiary_page_blockers(
                root,
                commute_model,
                commute_view,
                environment_model,
                environment_view,
                tests,
            ),
            [],
        )
        self.assertEqual(
            cached_tertiary_page_blockers(
                root,
                commute_model,
                commute_view,
                environment_model.replace(
                    "guard !state.isRefreshing else { return }",
                    "",
                ),
                environment_view,
                tests,
            ),
            [
                "commute routes and environment history must restore server-scoped cached state, preserve visible content on refresh failure, and suppress duplicate loads"
            ],
        )

    def test_requires_scoped_cached_geography_pages(self) -> None:
        root = """
        scope: "countries:2026"
        scope: "regions:cn:2026"
        private func vehiclePageCacheKey(carId: Int, scope: String = "")
        """
        page_cache = """
        public let scope: String
        scope: String = ""
        self.scope = scope.trimmingCharacters
        """
        countries_model = """
        VehiclePageStateCache<CountriesVisitedState>
        guard !state.isRefreshing else { return }
        state.isLoading = state.countries.isEmpty
        resolvedLocations = state.enrichmentResult?.locations ?? [:]
        stateCache.save(snapshot, for: cacheKey)
        """
        countries_view = """
        if viewModel.state.isLoading, viewModel.state.countries.isEmpty
        UserFacingErrorLocalizer.localized
        """
        regions_model = """
        VehiclePageStateCache<RegionsVisitedState>
        guard !state.isRefreshing else { return }
        state.isLoading = state.regions.isEmpty
        state.enrichmentResult?.locations ?? [:]
        stateCache.save(snapshot, for: cacheKey)
        """
        regions_view = """
        if viewModel.state.isLoading, viewModel.state.regions.isEmpty
        UserFacingErrorLocalizer.localized
        """
        tests = """
        testSeparatesPageScopesForSameServerAndVehicle
        testCountryRepeatedEntryRestoresScopedStateAndPreservesItOnFailure
        testRegionRepeatedEntryRestoresScopedStateAndPreservesItOnFailure
        testCountryAndRegionConcurrentLoadsEachReadHistoryOnce
        """

        self.assertEqual(
            cached_geography_page_blockers(
                root,
                page_cache,
                countries_model,
                countries_view,
                regions_model,
                regions_view,
                tests,
            ),
            [],
        )
        self.assertEqual(
            cached_geography_page_blockers(
                root.replace('scope: "regions:cn:2026"', ""),
                page_cache,
                countries_model,
                countries_view,
                regions_model,
                regions_view,
                tests,
            ),
            [
                "country and region statistics must use year/country-scoped cached state, preserve resolved geography and visible rows on refresh failure, and suppress duplicate history reads"
            ],
        )

    def test_requires_timestamp_scoped_cached_where_was_i(self) -> None:
        root = 'scope: "where-was-i:\\(timestamp)"'
        model = """
        VehiclePageStateCache<WhereWasIState>(maximumEntryCount: 24)
        guard !state.isRefreshing else { return }
        state.isLoading = state.carState == nil
        stateCache.save(snapshot, for: cacheKey)
        """
        view = """
        if viewModel.state.isLoading, !hasVisibleContent
        else if let error = viewModel.state.errorMessage, !hasVisibleContent
        where_was_i_refresh_warning
        """
        tests = """
        testRepeatedEntryRestoresScopedStateAndPreservesItOnFailure
        testDifferentTimestampScopeDoesNotRestoreAnotherResult
        testOverlappingLoadsReadHistoryOnlyOnce
        """
        ui_tests = """
        testWhereWasIOpensFromRecentMapActionsWithoutBlocking
        element("where_was_i_view")
        """

        self.assertEqual(
            cached_where_was_i_blockers(root, model, view, tests, ui_tests),
            [],
        )
        self.assertEqual(
            cached_where_was_i_blockers(
                root,
                model.replace("guard !state.isRefreshing else { return }", ""),
                view,
                tests,
                ui_tests,
            ),
            [
                "Where Was I must restore timestamp-scoped cached state, preserve visible content on refresh failure, suppress duplicate history reads, and retain real navigation coverage"
            ],
        )

    def test_requires_scoped_cached_battery_state_and_atomic_calibration(self) -> None:
        root = """
        private func batteryViewModel(carId: Int, efficiency: Double?) {
            cacheKey: vehiclePageCacheKey(carId: carId)
            cacheKey: vehiclePageCacheKey(carId: carId)
        }
        """
        model = """
        VehiclePageStateCache<BatteryState>(maximumEntryCount: 4)
        guard !state.isRefreshing else { return }
        state.isLoading = state.stats == nil
        history = state.history
        stateCache.save(snapshot, for: cacheKey)
        settingsStore as? any AtomicSettingsUpdating
        atomicStore.updateAtomically
        Self.earliestValidOdometer(
        """
        view = """
        if viewModel.state.isLoading, viewModel.state.stats == nil
        else if let stats = viewModel.state.stats
        accessibilityIdentifier("battery_refresh_warning")
        """
        tests = """
        testBatteryRepeatedEntryRestoresStateAndFailedRefreshPreservesIt
        testBatteryOptionalHistoryFailureKeepsCachedTrendWhileRefreshingHealth
        testBatteryOverlappingLoadsStartOneRefresh
        testBatteryDetectedRecordingStartUsesAtomicSettingsUpdate
        """
        ui_tests = """
        testUnknownBatteryRecordingStartNeverAppearsAsLifetimeHealth
        element("battery_view")
        """

        self.assertEqual(
            cached_battery_page_blockers(root, model, view, tests, ui_tests),
            [],
        )
        self.assertEqual(
            cached_battery_page_blockers(
                root,
                model.replace("history = state.history", ""),
                view,
                tests,
                ui_tests,
            ),
            [
                "battery must restore server-and-vehicle-scoped cached state, preserve visible history on refresh failure, suppress duplicate loads, and atomically merge detected calibration"
            ],
        )

    def test_requires_cached_first_software_updates(self) -> None:
        root = """
        SoftwareUpdatesViewModel(
        snapshotStore: SoftwareUpdateSnapshotStore.shared,
        cacheKey: vehiclePageCacheKey(carId: carId)
        """
        model = """
        VehiclePageStateCache<SoftwareUpdatesPageSnapshot>
        maximumEntryCount: 4
        guard !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        snapshotStore.load(serverURL: serverURL, carId: carId)
        stateCache.save(
        restored?.allUpdates ?? []
        state.filterMonths = months
        saveCachedState()
        state.errorMessage = error.analyticsMessage
        """
        view = """
        if viewModel.state.isLoading, !viewModel.state.hasLoadedData
        accessibilityIdentifier("software_updates_refresh_warning")
        .refreshable
        """
        tests = """
        testSoftwareUpdatesRepeatedEntryRestoresFilterAndFailedRefreshPreservesRows
        testSoftwareUpdatesOverlappingLoadsStartOneServerRequest
        testSoftwareUpdatesCacheSuccessfulEmptyResultWithoutReopeningLoader
        testSoftwareUpdateSnapshotsAreIsolatedByServerAndVehicle
        """
        ui_tests = """
        testSystemAndSafetyFeatureEntriesOpenWithoutBlocking
        ("updates", "software_updates_view")
        """

        self.assertEqual(
            cached_software_updates_blockers(root, model, view, tests, ui_tests),
            [],
        )
        self.assertEqual(
            cached_software_updates_blockers(
                root,
                model.replace("state.isLoading = !state.hasLoadedData", ""),
                view,
                tests,
                ui_tests,
            ),
            [
                "software updates must restore server-and-vehicle-scoped memory and persisted snapshots, preserve filters and visible rows on refresh failure, cache empty results, and suppress duplicate loads"
            ],
        )

    def test_requires_cached_achievements_and_single_read_sentry_history(self) -> None:
        root = """
        AchievementsViewModel(api:
        ), cacheKey: vehiclePageCacheKey(carId: carId))
        SentryHistoryViewModel(
        store: sentryStore(),
        cacheKey: vehiclePageCacheKey(carId: carId)
        """
        achievements_model = """
        VehiclePageStateCache<AchievementsState>
        maximumEntryCount: 4
        guard !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        stateCache.save(snapshot, for: cacheKey)
        """
        achievements_view = """
        if viewModel.state.isLoading, !viewModel.state.hasLoadedData
        accessibilityIdentifier("achievements_refresh_warning")
        t("No achievements available", "暂无成就数据")
        .refreshable
        """
        sentry_model = """
        VehiclePageStateCache<SentryHistoryState>
        maximumEntryCount: 4
        guard !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        stateCache.save(snapshot, for: cacheKey)
        heatmap(alerts: alerts, now: now)
        """
        sentry_view = """
        if viewModel.state.isLoading, !viewModel.state.hasLoadedData
        accessibilityIdentifier("sentry_history_refresh_warning")
        .refreshable
        """
        tests = """
        testAchievementsRepeatedEntryRestoresRowsAndFailedRefreshPreservesThem
        testAchievementsOverlappingLoadsStartOneRequest
        testAchievementsCacheSuccessfulEmptyResult
        testSentryHistoryRepeatedEntryRestoresRowsAndFailedRefreshPreservesThem
        testSentryHistoryOverlappingLoadsReadStoreOnceAndReuseRowsForHeatmap
        testSentryHistoryCachesSuccessfulEmptyResult
        """
        ui_tests = """
        testSystemAndSafetyFeatureEntriesOpenWithoutBlocking
        ("achievements", "achievements_view")
        ("sentry", "sentry_history_view")
        """

        self.assertEqual(
            cached_system_safety_blockers(
                root,
                achievements_model,
                achievements_view,
                sentry_model,
                sentry_view,
                tests,
                ui_tests,
            ),
            [],
        )
        self.assertEqual(
            cached_system_safety_blockers(
                root,
                achievements_model,
                achievements_view,
                sentry_model + "\nstore.hourlyCounts",
                sentry_view,
                tests,
                ui_tests,
            ),
            [
                "achievements and sentry history must restore server-and-vehicle-scoped state, preserve visible or empty results on refresh failure, suppress duplicate loads, and build the sentry heatmap without rereading history"
            ],
        )

    def test_requires_cached_cost_hotspots_and_trips(self) -> None:
        root = "\n".join(
            ["cacheKey: vehiclePageCacheKey(carId: carId)"] * 10
        )
        cost_model = """
        VehiclePageStateCache<CostReviewPageSnapshot>
        responsesByRange
        guard state.range != range, !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        state.errorMessage = error.analyticsMessage
        """
        cost_view = """
        .disabled(viewModel.state.isRefreshing)
        accessibilityIdentifier("cost_review_refresh_warning")
        """
        hotspot_model = """
        VehiclePageStateCache<TopDrainLocationsState>
        guard !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        state.errorMessage = error.analyticsMessage
        """
        hotspot_view = """
        accessibilityIdentifier("top_drain_locations_refresh_warning")
        """
        trips_model = """
        VehiclePageStateCache<TripsPageSnapshot>
        sourceData:
        allTrips:
        guard !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        state.errorMessage = error.analyticsMessage
        """
        trips_view = """
        accessibilityIdentifier("trips_refresh_warning")
        """
        tests = """
        testRepeatedEntryRestoresSelectedRangeAndCachedRangesSurviveFailure
        testOverlappingCostReviewLoadsStartOneRequest
        testRangeSelectionIsIgnoredWhileRefreshIsInFlight
        testRepeatedEntryRestoresHotspotsAndFailedRefreshPreservesThem
        testOverlappingHotspotLoadsStartOneRequest
        testSuccessfulEmptyHotspotsAreCached
        testTripsRepeatedEntryRestoresYearAndFailedRefreshPreservesTrips
        testTripsOverlappingLoadsReadSourceOnce
        testTripsCacheSuccessfulEmptyResult
        """
        ui_tests = """
        testStatsDrilldownsAndCountryRegionPathOpenWithoutBlocking
        destinationID: "cost_review_view"
        testSystemAndSafetyFeatureEntriesOpenWithoutBlocking
        ("standby-hotspots", "top_drain_locations_view")
        testVehicleAndHistoryFeatureEntriesOpenWithoutBlocking
        ("trips", "trips_view")
        """

        self.assertEqual(
            cached_cost_hotspot_trips_blockers(
                root,
                cost_model,
                cost_view,
                hotspot_model,
                hotspot_view,
                trips_model,
                trips_view,
                tests,
                ui_tests,
            ),
            [],
        )
        self.assertEqual(
            cached_cost_hotspot_trips_blockers(
                root,
                cost_model.replace(
                    "guard state.range != range, !state.isRefreshing else { return }",
                    "",
                ),
                cost_view,
                hotspot_model,
                hotspot_view,
                trips_model,
                trips_view,
                tests,
                ui_tests,
            ),
            [
                "cost review, standby hotspots, and trips must restore server-and-vehicle-scoped state, preserve visible or empty results on refresh failure, suppress duplicate loads, and pass real navigation coverage"
            ],
        )

    def test_requires_cached_live_current_charge(self) -> None:
        root = """
        CurrentChargeViewModel(
        cacheKey: vehiclePageCacheKey(carId: carId)
        """
        model = """
        VehiclePageStateCache<CurrentChargeState>
        maximumEntryCount: 4
        state.isLoading = !state.hasLoadedData
        state.isRefreshing = state.hasLoadedData
        guard !requestIsRunning else { return }
        stateCache.save(snapshot, for: cacheKey)
        state.errorMessage = error.chargeMessage
        """
        view = """
        if viewModel.state.isLoading, !viewModel.state.hasLoadedData
        .task(id: carId)
        while !Task.isCancelled
        Task.sleep(for: viewModel.automaticRefreshInterval)
        forceRefresh: true
        accessibilityIdentifier("current_charge_refresh_warning")
        """
        tests = """
        testRepeatedEntryRestoresActiveChargeAndFailedRefreshPreservesIt
        testSuccessfulNoActiveChargeIsCachedAsResolvedState
        testOverlappingLoadsStartOnlyOneStatusAndChargeRequest
        testCurrentChargeCacheIsIsolatedByServerAndVehicle
        testForcedRefreshUsesLiveStatusAndChargeEndpoints
        testAutomaticRefreshUsesFiveSecondsOnlyWhileCharging
        """
        ui_tests = """
        testVehicleAndHistoryFeatureEntriesOpenWithoutBlocking
        ("current-charge", "current_charge_view")
        """

        self.assertEqual(
            cached_live_current_charge_blockers(
                root,
                model,
                view,
                tests,
                ui_tests,
            ),
            [],
        )
        self.assertEqual(
            cached_live_current_charge_blockers(
                root,
                model,
                view.replace("while !Task.isCancelled", ""),
                tests,
                ui_tests,
            ),
            [
                "current charge must restore server-and-vehicle-scoped state, preserve resolved active or idle content on refresh failure, suppress duplicate requests, and poll live endpoints only while visible"
            ],
        )

    def test_requires_cached_single_location_standby_and_create_trip_draft(self) -> None:
        root = """
        standbyDrainCacheKey: { latitude, longitude in
        scope: StandbyDrainViewModel.cacheScope(
        scope: "create-trip"
        """
        standby_model = """
        VehiclePageStateCache<StandbyDrainState>
        maximumEntryCount: 12
        guard !state.isRefreshing else { return }
        state.isLoading = !state.hasLoadedData
        stateCache.save(snapshot, for: cacheKey)
        return "standby:\\(latitudeE5):\\(longitudeE5)"
        """
        standby_view = """
        accessibilityIdentifier("standby_drain_refresh_warning")
        """
        hotspot_view = """
        accessibilityIdentifier("standby_hotspot_row_\\(index)")
        accessibilityIdentifier("standby_analyze_location_button")
        """
        create_model = """
        VehiclePageStateCache<CreateTripPageSnapshot>
        maximumEntryCount: 4
        guard let dataProvider, !state.isRefreshing else { return }
        used = try await tripStore.savedTrips(carId: carId)
        state.draftLegs = state.draftLegs.filter
        saveCachedState()
        stateCache.remove(for: cacheKey)
        """
        create_view = """
        accessibilityIdentifier("create_trip_refresh_warning")
        """
        tests = """
        testStandbyDrainRepeatedEntryRestoresDataAndFailedRefreshPreservesIt
        testStandbyDrainCachesResolvedEmptyResponse
        testOverlappingStandbyDrainLoadsStartOneRequest
        testStandbyDrainCacheScopeSeparatesNearbyLocations
        testCreateTripRepeatedEntryRestoresDraftAndFailedRefreshPreservesIt
        testCreateTripOverlappingLoadsReadSourceOnce
        testCreateTripDoesNotExposeCandidatesWhenUsedLegReadFails
        testSuccessfulTripSaveInvalidatesCachedDraft
        testRemoveInvalidatesOnlyRequestedEntry
        """
        ui_tests = """
        testStandbyHotspotDrillsIntoCachedLocationAnalysisWithoutBlocking
        element("standby_hotspot_row_0")
        tapAndStartMeasurement("standby_analyze_location_button")
        element("standby_drain_view")
        testCreateTripOpensFromCachedTripHistoryWithoutBlocking
        element("create_trip_view")
        """

        self.assertEqual(
            cached_standby_create_trip_blockers(
                root,
                standby_model,
                standby_view,
                hotspot_view,
                create_model,
                create_view,
                tests,
                ui_tests,
            ),
            [],
        )
        self.assertEqual(
            cached_standby_create_trip_blockers(
                root,
                standby_model,
                standby_view,
                hotspot_view,
                create_model.replace(
                    "used = try await tripStore.savedTrips(carId: carId)",
                    "(try? await tripStore.savedTrips(carId: carId)) ?? []",
                ),
                create_view,
                tests,
                ui_tests,
            ),
            [
                "single-location standby analysis and trip creation must restore scoped cached state, preserve visible data or drafts on refresh failure, suppress duplicate loads, and pass nested navigation coverage"
            ],
        )

    def test_requires_unknown_recording_start_battery_ui_safety(self) -> None:
        valid_debug_seeder = """
        #if DEBUG
        struct DebugUITestAnalyticsAPI {}
        #endif
        """
        valid_root = """
        environment["MATEDRIVE_UI_TEST_MODE"] == "1"
        DebugUITestAnalyticsAPI()
        """
        valid_battery_view = """
        .frame(width: 44, height: 44)
        if !stats.showsAbsoluteHealth {}
        "battery_calibration_required"
        "battery_absolute_health_value"
        "battery_health_confidence"
        """
        valid_metric_card = """
        .accessibilityHidden(true)
        .foregroundStyle(.primary.opacity(0.8))
        """
        valid_ui_tests = """
        testUnknownBatteryRecordingStartNeverAppearsAsLifetimeHealth
        element("battery_absolute_health_value").exists
        app.staticTexts["99.3%"].exists
        """

        self.assertEqual(
            battery_ui_safety_blockers(
                valid_debug_seeder,
                valid_root,
                valid_battery_view,
                valid_metric_card,
                valid_ui_tests,
            ),
            [],
        )

    def test_rejects_broad_dynamic_type_accessibility_audit_bypasses(self) -> None:
        valid_ui_tests = """
        func testFourRootTabsPassSystemAccessibilityAudit() throws {}
        func testFeatureHubPassesSystemAccessibilityAudit() throws {}
        func testFeatureHubUsesSingleColumnAtAccessibilityTextSize() {}
        func testBatteryMetricsUseSingleColumnAtAccessibilityTextSize() {}
        func performVisibleContentAccessibilityAudit() throws {
            try app.performAccessibilityAudit { issue in
                issue.auditType == .contrast && issue.element == nil
            }
        }
        """
        self.assertEqual(
            accessibility_release_audit_blockers(valid_ui_tests),
            [],
        )

        for bypass in (
            "let ignoringDynamicTypeIn = [featureHub]",
            "if issue.auditType == .dynamicType { return true }",
            (
                "if issue.auditType == XCUIAccessibilityAuditType.dynamicType "
                "{ return true }"
            ),
            "if .dynamicType == issue.auditType { return true }",
        ):
            with self.subTest(bypass=bypass):
                self.assertEqual(
                    accessibility_release_audit_blockers(
                        valid_ui_tests + "\n" + bypass
                    ),
                    [
                        "release accessibility audits must not broadly ignore Dynamic Type failures"
                    ],
                )

        self.assertEqual(
            accessibility_release_audit_blockers(
                valid_ui_tests.replace(
                    "func testFeatureHubPassesSystemAccessibilityAudit() throws {}",
                    "",
                )
            ),
            [
                "release UI tests must retain root, feature, and battery accessibility and large-text coverage"
            ],
        )

    def test_requires_regional_currency_and_cached_detail_refresh_guards(self) -> None:
        valid_formatter = """
        public static func automaticSymbol(locale: Locale = .autoupdatingCurrent)
        symbol(for: systemCurrencyCode(locale: locale))
        case automaticCode: return automaticSymbol()
        """
        valid_production = """
        currencySymbol: String = MateDriveCurrencyFormatter.automaticSymbol()
        private var currencyCode = MateDriveCurrencyFormatter.systemCurrencyCode()
        """
        valid_charges = """
        guard !state.isRefreshing else { return }
        state.isLoading = state.rows.isEmpty
        defer {
            state.isRefreshing = false
        }
        if state.rows.isEmpty {
        }
        """
        valid_trip_detail = """
        public var isRefreshing: Bool
        snapshot.isRefreshing = false
        guard !state.isRefreshing else { return }
        state.isLoading = state.trip == nil
        state.isRefreshing = false
        """
        valid_tests = """
        testAutomaticCurrencyUsesDeviceRegion
        testFeatureStateDefaultsUseAutomaticDeviceCurrency
        testRepeatedChargeListLoadKeepsCachedContentAndStartsOneRefresh
        testTripDetailCoalescesRepeatedLoadsWhileRefreshIsInFlight
        """
        expected = [
            "currency defaults, charge history, and trip detail must use the device region, preserve cached content, and suppress duplicate refreshes"
        ]

        self.assertEqual(
            cached_detail_currency_blockers(
                valid_formatter,
                valid_production,
                valid_charges,
                valid_trip_detail,
                valid_tests,
            ),
            [],
        )
        self.assertEqual(
            cached_detail_currency_blockers(
                valid_formatter,
                valid_production + '\ncurrencySymbol: String = "€"',
                valid_charges,
                valid_trip_detail,
                valid_tests,
            ),
            expected,
        )
        self.assertEqual(
            cached_detail_currency_blockers(
                valid_formatter,
                valid_production,
                valid_charges.replace(
                    "guard !state.isRefreshing else { return }",
                    "",
                ),
                valid_trip_detail,
                valid_tests,
            ),
            expected,
        )
        self.assertEqual(
            cached_detail_currency_blockers(
                valid_formatter,
                valid_production,
                valid_charges,
                valid_trip_detail,
                valid_tests.replace(
                    "testTripDetailCoalescesRepeatedLoadsWhileRefreshIsInFlight",
                    "",
                ),
            ),
            expected,
        )

    def test_requires_transactional_connection_settings(self) -> None:
        settings_store = """
        public func saveThrowing(_ settings: AppSettings) async throws {
            try saveEncoded(settings)
        }
        """
        settings_view_model = """
        guard !isSaving else { return false }
        let didChangeConnectionConfiguration = true
        await syncController?.suspendAndWait()
        try await settingsStore.saveThrowing(updated)
        try await restoreAuthenticationSecrets(previousSecrets)
        await syncController?.resume()
        committedSettings = try await atomicSettingsStore.updateAtomically { current in
            Self.mergeFormSettings(formSettings, into: current)
        }
        private func updateSettingsAtomically(
            _ transform: @escaping @Sendable (AppSettings) -> AppSettings
        ) async -> Bool {
            settingsMutationGeneration &+= 1
            if mutationGeneration == settingsMutationGeneration {
                settings = committedSettings
            }
            recordSettingsUpdateFailure()
        }
        connectionConfigurationRevision &+= 1
        """
        root_view = """
        .onChange(of: settingsViewModel.connectionConfigurationRevision) {
            Task {
                await syncLifecycleController.serverConfigurationDidChange()
            }
        }
        """
        tests = """
        testSettingsPersistenceFailureRestoresSecretsAndResumesOldSync
        testCredentialChangeOnSameServerRestartsSyncAndPublishesRevision
        testConcurrentSettingsSaveIsRejectedWhileFirstSaveIsPending
        testFullSettingsSavePreservesConcurrentlyLearnedPricingRule
        testIndependentSettingMutationsMergeWithoutClobberingEachOther
        testIndependentSettingFailureRestoresPersistedStateAndReportsError
        """

        self.assertEqual(
            connection_settings_transaction_blockers(
                settings_store,
                settings_view_model,
                root_view,
                tests,
            ),
            [],
        )
        self.assertEqual(
            connection_settings_transaction_blockers(
                settings_store,
                settings_view_model.replace(
                    "try await restoreAuthenticationSecrets(previousSecrets)",
                    "",
                ),
                root_view,
                tests,
            ),
            [
                "settings must save transactionally, merge independent fields atomically, roll back failures, preserve concurrent learned data, and restart same-server authentication changes"
            ],
        )

    def test_requires_device_only_credentials_and_private_network_boundaries(self) -> None:
        http_client = """
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        public enum HTTPRedirectPolicy
        sourceHost == destinationHost
        sourceScheme == "http" && destinationScheme == "https"
        return sourcePort == destinationPort
        """
        diagnostic_export = """
        redaction_profile: strict-v2
        [REDACTED_URL]
        [REDACTED_CREDENTIAL]
        [^,;|]+
        """
        keychain_store = """
        kSecClassGenericPassword
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        """
        backup_provider = """
        FileProtectionType.complete
        backupSettings.serverURL = Self.backupSafeURL(
        backupSettings.secondaryServerURL = Self.backupSafeURL(
        backupSettings.teslamateBaseURL = Self.backupSafeURL(
        TeslaMateServerURLPolicy.containsEmbeddedSecrets(value) ? "" : value
        """
        tests = """
        testRedirectPolicyNeverSendsCredentialsAcrossOriginsOrHttpsDowngrades
        testDiagnosticExportRedactsCredentialsHostsAndCoordinates
        testSetGetAndRemoveSecret
        testSettingsPayloadDropsLegacyURLsContainingEmbeddedSecrets
        """
        expected = [
            "credentials must stay in the device-only Keychain and must not leak through redirects, shared sessions, diagnostics, or CloudKit settings"
        ]

        self.assertEqual(
            credential_privacy_blockers(
                http_client,
                diagnostic_export,
                keychain_store,
                backup_provider,
                tests,
            ),
            [],
        )
        self.assertEqual(
            credential_privacy_blockers(
                http_client.replace(
                    "sourceHost == destinationHost",
                    "",
                ),
                diagnostic_export,
                keychain_store,
                backup_provider,
                tests,
            ),
            expected,
        )
        self.assertEqual(
            credential_privacy_blockers(
                http_client,
                diagnostic_export.replace("[^,;|]+", ""),
                keychain_store,
                backup_provider,
                tests,
            ),
            expected,
        )
        self.assertEqual(
            credential_privacy_blockers(
                http_client,
                diagnostic_export,
                keychain_store,
                backup_provider,
                tests.replace(
                    "testSettingsPayloadDropsLegacyURLsContainingEmbeddedSecrets",
                    "",
                ),
            ),
            expected,
        )

    def test_requires_explicit_route_weather_consent_revocation_and_deletion(self) -> None:
        app_settings = """
        allowsThirdPartyRouteWeather: Bool = false
        decodeIfPresent(Bool.self, forKey: .allowsThirdPartyRouteWeather) ?? false
        """
        view_model = """
        state.allowsThirdPartyRouteWeather = await routeWeatherPermission()
        if state.allowsThirdPartyRouteWeather {
        public func enableRouteWeather() async
        updated.allowsThirdPartyRouteWeather = true
        """
        drive_view = """
        accessibilityIdentifier("route_weather_enable_button")
        """
        privacy_view = """
        accessibilityIdentifier("route_weather_privacy_toggle")
        await settingsViewModel.loadEssentials()
        saveThirdPartyRouteWeatherPermission
        weatherCache.removeAll()
        """
        privacy_policy = """
        路线天气默认关闭
        一个代表性的精确路线坐标和行程时间
        停止后续 Open-Meteo 请求
        """
        tests = """
        testRouteWeatherRequiresConsentAndLoadsImmediatelyAfterPermissionIsSaved
        testRouteWeatherPermissionDefaultsOffAndPersistsWithoutChangingServerSettings
        """
        expected = [
            "third-party route weather must default off, require explicit consent, support revocation/cache deletion, and stay covered by privacy tests"
        ]

        self.assertEqual(
            route_weather_privacy_blockers(
                app_settings,
                view_model,
                drive_view,
                privacy_view,
                privacy_policy,
                tests,
            ),
            [],
        )
        self.assertEqual(
            route_weather_privacy_blockers(
                app_settings.replace(
                    "allowsThirdPartyRouteWeather: Bool = false",
                    "allowsThirdPartyRouteWeather: Bool = true",
                ),
                view_model,
                drive_view,
                privacy_view,
                privacy_policy,
                tests,
            ),
            expected,
        )

        blockers = battery_ui_safety_blockers("", "", "", "", "")

        self.assertIn("battery UI test analytics must remain excluded from Release builds", blockers)
        self.assertIn(
            "battery UI must distinguish calibration-required retention from lifetime health",
            blockers,
        )
        self.assertIn("battery share control must retain a 44-point touch target", blockers)
        self.assertIn(
            "metric cards must keep decorative icons hidden and captions readable",
            blockers,
        )
        self.assertIn(
            "UI tests must prove unknown recording start never appears as lifetime health",
            blockers,
        )


if __name__ == "__main__":
    unittest.main()
