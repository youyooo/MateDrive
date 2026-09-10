#!/usr/bin/env python3
import argparse
import json
import plistlib
import re
import struct
import sys
from pathlib import Path


SUBMISSION_PATH = Path("docs/release/app-store-submission.md")
REQUIRED_SECTIONS = [
    "## App Name",
    "## Submission Status",
    "## Subtitle",
    "## Description",
    "## Keywords",
    "## Promotional Text",
    "## Support URL",
    "## Marketing URL",
    "## Privacy Policy URL",
    "## Review Notes",
    "## Pre-Submission Verification",
    "## Demo Account And Server",
    "## Privacy Summary",
    "## App Privacy Questionnaire Draft",
    "## Export Compliance",
    "## Screenshot Checklist",
]
FORBIDDEN_READY_MARKERS = [
    "Not ready for App Store submission yet.",
    "TBD",
]
SUPPORT_PLACEHOLDER_MARKERS = [
    "Before publishing this page",
    "Before publishing this policy",
]
PRIVATE_ENDPOINT_PATTERN = re.compile(
    r"(http://|localhost|127\.0\.0\.1|\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|"
    r"\b172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3}\b|"
    r"\b192\.168\.\d{1,3}\.\d{1,3}\b)"
)


def section_body(text: str, section: str) -> str:
    start = text.find(section)
    if start == -1:
        return ""
    rest = text[start + len(section):]
    next_section = rest.find("\n## ")
    if next_section == -1:
        return rest.strip()
    return rest[:next_section].strip()


def submission_metadata_blockers(text: str) -> list[str]:
    blockers = []

    for section in REQUIRED_SECTIONS:
        if section not in text:
            blockers.append(f"missing required section: {section}")

    for marker in FORBIDDEN_READY_MARKERS:
        if marker in text:
            blockers.append(f"replace/remove placeholder before submission: {marker}")
    for marker in SUPPORT_PLACEHOLDER_MARKERS:
        for path in [Path("docs/support/index.html"), Path("docs/support/privacy.html")]:
            if marker in path.read_text(encoding="utf-8"):
                blockers.append(f"replace support contact placeholder in {path}")

    for section, label in [
        ("## Support URL", "support URL"),
        ("## Privacy Policy URL", "privacy policy URL"),
    ]:
        if not re.search(r"https://[^\s]+", section_body(text, section)):
            blockers.append(f"{label} must be a reachable https:// URL")

    app_name = section_body(text, "## App Name")
    subtitle = section_body(text, "## Subtitle")
    promotional_text = section_body(text, "## Promotional Text")
    description = section_body(text, "## Description")
    keywords = section_body(text, "## Keywords")
    if not 2 <= len(app_name) <= 30:
        blockers.append("app name must contain 2 to 30 characters")
    if len(subtitle) > 30:
        blockers.append("subtitle must not exceed 30 characters")
    if len(promotional_text) > 170:
        blockers.append("promotional text must not exceed 170 characters")
    if not description or len(description) > 4_000:
        blockers.append("description must contain 1 to 4000 characters")
    if not keywords or len(keywords.encode("utf-8")) > 100:
        blockers.append("keywords must contain 1 to 100 UTF-8 bytes")

    demo = section_body(text, "## Demo Account And Server")
    if "TeslaMate API base URL:" not in demo:
        blockers.append("demo server section must include TeslaMate API base URL")
    if "API token:" not in demo and "Basic Auth username:" not in demo and "Authentication:" not in demo:
        blockers.append("demo server section must include reviewer authentication guidance")

    if PRIVATE_ENDPOINT_PATTERN.search(text):
        blockers.append("submission copy must not contain local or private network URLs")
    if re.search(r"\bsk-[A-Za-z0-9_-]+", text):
        blockers.append("submission copy must not contain API-looking secrets")
    return blockers


def support_contact_blockers(html: str) -> list[str]:
    if "mailto:" in html or "tel:" in html:
        return []
    return ["support page must provide a direct email or telephone contact"]


def in_app_support_link_blockers(
    settings_view: str,
    privacy_view: str,
    app_links: str,
) -> list[str]:
    blockers = []
    if (
        "https://youyooo.github.io/MateDrive/" not in app_links
        or "supportURL" not in app_links
        or "AppLinks.supportURL" not in settings_view
        or "Support & Feedback" not in settings_view
    ):
        blockers.append("Settings must provide a direct public support link")
    if (
        "https://youyooo.github.io/MateDrive/privacy.html" not in app_links
        or "privacyPolicyURL" not in app_links
        or "AppLinks.privacyPolicyURL" not in settings_view
        or "AppLinks.privacyPolicyURL" not in privacy_view
    ):
        blockers.append("Settings and the privacy page must link to the public privacy policy")
    return blockers


def review_demo_api_blockers(
    generator: str,
    pages_workflow: str,
    makefile: str,
    probe_script: str,
    regression_tests: str,
    native_integration_tests: str,
    submission_copy: str,
) -> list[str]:
    generator_is_synthetic_and_guarded = all(
        marker in generator
        for marker in (
            'MARKER = ".generated-review-demo-api"',
            "Refusing to replace unmarked directory",
            "synthetic read-only review data",
            'default=Path("docs/support/review-demo")',
        )
    )
    deployment_regenerates_daily = all(
        marker in pages_workflow
        for marker in (
            'cron: "17 2 * * *"',
            "python3 scripts/generate_review_demo_api.py",
            "path: docs/support",
        )
    )
    verification_is_part_of_the_gate = all(
        marker in makefile
        for marker in (
            "review-demo-test:",
            "python3 scripts/test_review_demo_api.py",
        )
    )
    static_redirects_are_followed = (
        "-L --max-redirs 3" in probe_script
    )
    tests_cover_privacy_and_read_only_hosting = all(
        marker in regression_tests
        for marker in (
            "test_generates_complete_parseable_api",
            "test_uses_recent_synthetic_data_without_sensitive_fields",
            "test_refuses_to_replace_unmarked_directory",
            "test_static_server_passes_probe_and_rejects_writes",
        )
    )
    native_models_decode_every_read_only_endpoint = (
        "review-demo-native-test:" in makefile
        and "review-integration-test:" in makefile
        and "testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN"
        in makefile
        and makefile.count(
            "-only-testing:MateDriveTests/LocalTeslamateIntegrationTests/testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN"
        )
        >= 2
        and "testReviewDemoDatasetDecodesEveryReadOnlyEndpointWithoutVIN"
        in native_integration_tests
        and "XCTAssertNil(car.carDetails?.vin)" in native_integration_tests
        and "api.updateChargeCost(chargeId: chargeID, cost: 1)"
        in native_integration_tests
    )
    review_copy_uses_public_no_auth_endpoint = all(
        marker in submission_copy
        for marker in (
            "https://youyooo.github.io/MateDrive/review-demo",
            "Authentication: None",
            "synthetic",
            "read-only",
        )
    )
    if (
        not generator_is_synthetic_and_guarded
        or not deployment_regenerates_daily
        or not verification_is_part_of_the_gate
        or not static_redirects_are_followed
        or not tests_cover_privacy_and_read_only_hosting
        or not native_models_decode_every_read_only_endpoint
        or not review_copy_uses_public_no_auth_endpoint
    ):
        return [
            "App Review must retain the public, daily-refreshed, read-only synthetic TeslaMate API and its privacy/probe regression gate"
        ]
    return []


def review_demo_embedding_blockers(production_sources: str) -> list[str]:
    if "https://youyooo.github.io/MateDrive/review-demo" in production_sources:
        return [
            "Production app and widget sources must not embed the App Review synthetic TeslaMate API URL"
        ]
    return []


def submission_blockers(text: str, support_html: str) -> list[str]:
    return submission_metadata_blockers(text) + support_contact_blockers(support_html)


def forced_crash_pattern_blockers(production_swift: str) -> list[str]:
    forbidden_patterns = {
        r"\btry!": "try!",
        r"\bas!": "as!",
        r"\bfatalError\s*\(": "fatalError(",
        r"\bpreconditionFailure\s*\(": "preconditionFailure(",
        (
            r"\b[A-Za-z_][A-Za-z0-9_]*"
            r"(?:\[[^\]\n]+\]|\.[A-Za-z_][A-Za-z0-9_]*)*"
            r"!(?=[\s\.,\)\]\?:]|$)"
        ): "forced optional unwrap",
    }
    found = [
        label
        for pattern, label in forbidden_patterns.items()
        if re.search(pattern, production_swift)
    ]
    if found:
        return [
            "production Swift must avoid forced crash patterns: " + ", ".join(found)
        ]
    return []


def app_version_blockers(
    short_version: str,
    build_version: str,
    project: str,
) -> list[str]:
    numeric = r"\d+(?:\.\d+){0,2}"
    resolved_short_version = bool(re.fullmatch(numeric, short_version)) or (
        short_version == "$(MARKETING_VERSION)"
        and re.search(rf'MARKETING_VERSION:\s*"{numeric}"', project) is not None
    )
    resolved_build_version = bool(re.fullmatch(numeric, build_version)) or (
        build_version == "$(CURRENT_PROJECT_VERSION)"
        and re.search(rf'CURRENT_PROJECT_VERSION:\s*"{numeric}"', project) is not None
    )
    blockers = []
    if not resolved_short_version:
        blockers.append("CFBundleShortVersionString must resolve to a numeric version")
    if not resolved_build_version:
        blockers.append("CFBundleVersion must resolve to a numeric build")
    return blockers


def cloudkit_release_blockers(
    entitlements: dict,
    schema: str,
    project: str,
    integration_tests: str,
) -> list[str]:
    containers = entitlements.get(
        "com.apple.developer.icloud-container-identifiers",
        [],
    )
    production_configuration = (
        entitlements.get("com.apple.developer.icloud-container-environment") == "Production"
        and "iCloud.com.matedrive.ios" in containers
        and "CloudKit" in entitlements.get("com.apple.developer.icloud-services", [])
    )
    schema_contract = all(
        marker in schema
        for marker in (
            "RECORD TYPE MateDriveBackup",
            "createdAt TIMESTAMP SORTABLE",
            "databaseAsset ASSET",
            "settingsData ENCRYPTED BYTES",
            'GRANT READ, WRITE TO "_creator"',
            'GRANT CREATE TO "_icloud"',
        )
    )
    gated_device_round_trip = all(
        marker in integration_tests
        for marker in (
            'environment["MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS"] == "1"',
            "#if targetEnvironment(simulator)",
            "service.upload(",
            "service.listBackups()",
            "service.download(",
            "service.delete(",
        )
    ) and 'MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS: "$(MATEDRIVE_RUN_CLOUDKIT_PRODUCTION_TESTS)"' in project

    blockers = []
    if not production_configuration:
        blockers.append(
            "CloudKit release entitlements must target the MateDrive Production container"
        )
    if not schema_contract:
        blockers.append(
            "CloudKit backup schema must retain encrypted settings, sortable metadata, assets, and private creator grants"
        )
    if not gated_device_round_trip:
        blockers.append(
            "CloudKit release testing must retain the opt-in physical-device upload/list/download/delete round trip"
        )
    return blockers


def history_pagination_blockers(history_paginator: str, production_swift: str) -> list[str]:
    blockers = []
    if re.search(r"show:\s*(?:50_000|50000)\b", production_swift):
        blockers.append("production pages must not request oversized history lists")
    if (
        "public enum VehicleHistoryPaginator" not in history_paginator
        or "public static let pageSize = 200" not in history_paginator
        or "maximumPageCount" not in history_paginator
        or "addedCount == 0" not in history_paginator
        or "Task.isCancelled" not in history_paginator
    ):
        blockers.append("history fallback reads must use bounded cancellable pagination with a no-progress guard")
    return blockers


def sync_cancellation_blockers(history_sync: str) -> list[str]:
    summary_write_guards = (
        re.search(
            r"switch await api\.drives(?:(?!switch await api\.)[\s\S])*?case let \.success\(items\):\s+guard !Task\.isCancelled else \{ return false \}",
            history_sync,
        )
        and re.search(
            r"switch await api\.charges(?:(?!switch await api\.)[\s\S])*?case let \.success\(items\):\s+guard !Task\.isCancelled else \{ return false \}",
            history_sync,
        )
    )
    detail_write_guards = history_sync.count(
        "return values\n            }\n            guard !Task.isCancelled else { return false }"
    )
    cancellation_error_guards = history_sync.count("if !Task.isCancelled {")

    if not summary_write_guards or detail_write_guards < 2 or cancellation_error_guards < 3:
        return ["cancelled background synchronization must not persist late responses or report a false failure"]
    return []


def charge_pricing_safety_blockers(charge_pricing_rule: str) -> list[str]:
    required_guards = (
        "maximumInterpolatedInterval: TimeInterval = 7 * 24 * 60 * 60",
        "guard !hasUnsafeInterpolationGap(",
        "sessionEnd < sessionStart",
        "sample.0.timeIntervalSince(previousDate) > maximumInterpolatedInterval",
        "residualDuration < 0 || residualDuration > maximumInterpolatedInterval",
    )
    if any(guard not in charge_pricing_rule for guard in required_guards):
        return [
            "time-segmented charge pricing must reject invalid or unbounded energy interpolation"
        ]
    return []


def automatic_charge_inference_blockers(
    charge_cost_resolver: str,
    charge_pricing_rule: str,
    dashboard_summary_provider: str,
    charges_view_model: str,
    charge_detail_view_model: str,
    smart_activity_indexer: str,
) -> list[str]:
    inference_guards = (
        "public enum ChargeLocationInferenceSource" in charge_cost_resolver
        and "case overnightACPattern" in charge_cost_resolver
        and "source: .savedGeofence" in charge_cost_resolver
        and "confidence: min(confidence, 0.75)" in charge_cost_resolver
        and "case inferredHome" in charge_pricing_rule
    )
    shared_resolution = (
        "AutomaticChargeCostEstimator.resolve(" in dashboard_summary_provider
        and "AutomaticChargeCostEstimator.resolve(" in charges_view_model
        and "AutomaticChargeCostEstimator.inferLocation(" in charge_detail_view_model
        and "AutomaticChargeCostEstimator.inferLocation(" in smart_activity_indexer
    )
    if not inference_guards or not shared_resolution:
        return [
            "dashboard, charge list, charge detail, and activity indexing must share bounded automatic charge-location inference"
        ]
    return []


def geofence_precedence_blockers(app_settings: str, regression_tests: str) -> list[str]:
    deterministic_precedence = all(
        marker in app_settings
        for marker in (
            "let lhsIsVehicleSpecific = lhs.rule.carId != nil",
            "if lhsIsVehicleSpecific != rhsIsVehicleSpecific",
            "abs(lhs.distance - rhs.distance) > 0.001",
            "lhs.rule.radiusMeters < rhs.rule.radiusMeters",
        )
    )
    if (
        not deterministic_precedence
        or "testOverlappingGeofencesPreferVehicleScopeThenNearestCenter"
        not in regression_tests
    ):
        return [
            "overlapping geofences must prefer the current vehicle, then the nearest center and smallest radius"
        ]
    return []


def credential_privacy_blockers(
    http_client: str,
    diagnostic_export: str,
    keychain_store: str,
    backup_provider: str,
    regression_tests: str,
) -> list[str]:
    network_session_is_private = all(
        marker in http_client
        for marker in (
            "URLSessionConfiguration.ephemeral",
            "configuration.httpCookieAcceptPolicy = .never",
            "configuration.httpShouldSetCookies = false",
            "configuration.urlCache = nil",
            "public enum HTTPRedirectPolicy",
            "sourceHost == destinationHost",
            'sourceScheme == "http" && destinationScheme == "https"',
            "return sourcePort == destinationPort",
        )
    )
    diagnostics_are_strictly_redacted = all(
        marker in diagnostic_export
        for marker in (
            "redaction_profile: strict-v2",
            "[REDACTED_URL]",
            "[REDACTED_CREDENTIAL]",
            "[^,;|]+",
        )
    )
    secrets_stay_device_only = (
        "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" in keychain_store
        and "kSecClassGenericPassword" in keychain_store
    )
    cloud_backup_excludes_embedded_url_secrets = all(
        marker in backup_provider
        for marker in (
            "FileProtectionType.complete",
            "backupSettings.serverURL = Self.backupSafeURL(",
            "backupSettings.secondaryServerURL = Self.backupSafeURL(",
            "backupSettings.teslamateBaseURL = Self.backupSafeURL(",
            "TeslaMateServerURLPolicy.containsEmbeddedSecrets(value) ? \"\" : value",
        )
    )
    regression_coverage = all(
        name in regression_tests
        for name in (
            "testRedirectPolicyNeverSendsCredentialsAcrossOriginsOrHttpsDowngrades",
            "testDiagnosticExportRedactsCredentialsHostsAndCoordinates",
            "testSetGetAndRemoveSecret",
            "testSettingsPayloadDropsLegacyURLsContainingEmbeddedSecrets",
        )
    )
    if (
        not network_session_is_private
        or not diagnostics_are_strictly_redacted
        or not secrets_stay_device_only
        or not cloud_backup_excludes_embedded_url_secrets
        or not regression_coverage
    ):
        return [
            "credentials must stay in the device-only Keychain and must not leak through redirects, shared sessions, diagnostics, or CloudKit settings"
        ]
    return []


def route_weather_privacy_blockers(
    app_settings: str,
    drive_detail_view_model: str,
    drive_detail_view: str,
    privacy_view: str,
    privacy_policy: str,
    regression_tests: str,
) -> list[str]:
    consent_defaults_off = all(
        marker in app_settings
        for marker in (
            "allowsThirdPartyRouteWeather: Bool = false",
            "decodeIfPresent(Bool.self, forKey: .allowsThirdPartyRouteWeather) ?? false",
        )
    )
    network_request_is_guarded = all(
        marker in drive_detail_view_model
        for marker in (
            "state.allowsThirdPartyRouteWeather = await routeWeatherPermission()",
            "if state.allowsThirdPartyRouteWeather {",
            "public func enableRouteWeather() async",
            "updated.allowsThirdPartyRouteWeather = true",
        )
    )
    consent_and_revocation_are_visible = all(
        marker in drive_detail_view + privacy_view
        for marker in (
            'accessibilityIdentifier("route_weather_enable_button")',
            'accessibilityIdentifier("route_weather_privacy_toggle")',
            "await settingsViewModel.loadEssentials()",
            "saveThirdPartyRouteWeatherPermission",
            "weatherCache.removeAll()",
        )
    )
    disclosure_is_current = all(
        marker in privacy_policy
        for marker in (
            "路线天气默认关闭",
            "一个代表性的精确路线坐标和行程时间",
            "停止后续 Open-Meteo 请求",
        )
    )
    regression_coverage = all(
        marker in regression_tests
        for marker in (
            "testRouteWeatherRequiresConsentAndLoadsImmediatelyAfterPermissionIsSaved",
            "testRouteWeatherPermissionDefaultsOffAndPersistsWithoutChangingServerSettings",
        )
    )
    if (
        not consent_defaults_off
        or not network_request_is_guarded
        or not consent_and_revocation_are_visible
        or not disclosure_is_current
        or not regression_coverage
    ):
        return [
            "third-party route weather must default off, require explicit consent, support revocation/cache deletion, and stay covered by privacy tests"
        ]
    return []


def charge_cost_transparency_blockers(charges_view: str, ui_tests: str) -> list[str]:
    required_view_guards = (
        't("Cost Total", "费用合计")',
        "ChargeCostPresentation.status(",
        'accessibilityIdentifier("charge_cost_status_\\(row.chargeId)")',
        "dynamicTypeSize.isAccessibilitySize",
    )
    required_ui_guards = (
        "testChargeCostStatusFitsAtAccessibilityTextSize",
        'element("charge_cost_status_201")',
        'XCTAssertEqual(status.label, "已记录")',
    )
    if (
        any(guard not in charges_view for guard in required_view_guards)
        or any(guard not in ui_tests for guard in required_ui_guards)
    ):
        return [
            "charge history must distinguish recorded, estimated, corrected, and missing costs with accessibility-size UI coverage"
        ]
    return []


def historical_tariff_transparency_blockers(
    regional_tariff_catalog: str,
    charge_pricing_rule: str,
    charge_cost_resolver: str,
    charge_detail_view_model: str,
    charges_view_model: str,
    charges_view: str,
    dashboard_summary_provider: str,
    dashboard_presentation: str,
    regression_tests: str,
) -> list[str]:
    semantic_reference = all(
        marker in source
        for source, marker in (
            (regional_tariff_catalog, "public func estimationRule("),
            (regional_tariff_catalog, 'rule.id += "-reference-estimate"'),
            (charge_pricing_rule, "public var isHistoricalReference: Bool"),
            (charge_pricing_rule, "case historicalReference"),
            (charge_pricing_rule, 'localized("Historical reference", "历史参考"'),
            (charge_cost_resolver, "public let isHistoricalReference: Bool"),
            (
                charge_cost_resolver,
                "isHistoricalReference: estimate.rule.isHistoricalReference",
            ),
        )
    )
    every_cost_surface_is_labeled = all(
        marker in source
        for source, marker in (
            (charge_detail_view_model, "factors.append(.historicalReference)"),
            (charge_detail_view_model, "catalog.localizedRuleName("),
            (charges_view_model, "public let isHistoricalReference: Bool"),
            (
                charges_view_model,
                "isHistoricalReference: resolution?.isHistoricalReference == true",
            ),
            (charges_view, 'AppText.localized("Historical reference", "历史参考"'),
            (
                dashboard_summary_provider,
                "public let isCostHistoricalReference: Bool?",
            ),
            (
                dashboard_presentation,
                'Self.text("Historical reference", "历史参考费用"',
            ),
        )
    )
    tests_cover_reference_semantics = all(
        name in regression_tests
        for name in (
            "testExpiredTariffEstimateIsExplicitlyMarkedAndLocalizedAsHistoricalReference",
            "testHistoricalReferenceExplanationCannotBeMistakenForCurrentTariff",
            "testLatestChargeLabelsExpiredTariffAsHistoricalReference",
            "testChargeListUsesSameProbableHomeRegionalEstimateAsDashboard",
            "testChargeDetailUsesProbableHomeRegionalEstimateAndExplainsInference",
        )
    )
    if (
        not semantic_reference
        or not every_cost_surface_is_labeled
        or not tests_cover_reference_semantics
    ):
        return [
            "expired regional tariffs must remain explicit historical references across charge detail, history, and dashboard cost surfaces"
        ]
    return []


def cached_secondary_page_blockers(
    root_view: str,
    page_cache: str,
    recent_map_view_model: str,
    driving_records_view_model: str,
    drive_insights_view_model: str,
    drive_insights_view: str,
    energy_cycles_view_model: str,
    regression_tests: str,
) -> list[str]:
    cache_is_bounded_and_scoped = (
        "public struct VehiclePageCacheKey" in page_cache
        and "public let serverURL: String" in page_cache
        and "public let carId: Int" in page_cache
        and "maximumEntryCount" in page_cache
        and "while recency.count > maximumEntryCount" in page_cache
    )
    root_uses_scoped_cache = (
        root_view.count("cacheKey: vehiclePageCacheKey(carId: carId)") >= 4
        and "private func vehiclePageCacheKey(carId: Int" in root_view
        and "-> VehiclePageCacheKey" in root_view
    )
    models_preserve_visible_content = (
        "state.isLoading = state.routes.isEmpty" in recent_map_view_model
        and "guard !state.isRefreshing else { return }" in recent_map_view_model
        and "state.isLoading = state.records.isEmpty" in driving_records_view_model
        and "guard !state.isRefreshing else { return }" in driving_records_view_model
        and "state.isLoading = !hasContent" in drive_insights_view_model
        and "guard !state.isRefreshing else { return }" in drive_insights_view_model
        and "if viewModel.state.isLoading, !hasContent" in drive_insights_view
        and "else if let error = viewModel.state.errorMessage, !hasContent" in drive_insights_view
        and "guard !isRefreshing else { return }" in energy_cycles_view_model
        and "Task.detached(priority: .userInitiated)" in energy_cycles_view_model
        and "stateCache.save(state, for: cacheKey)" in energy_cycles_view_model
    )
    tests_cover_reentry_and_isolation = all(
        name in regression_tests
        for name in (
            "testRepeatedEntryRestoresRoutesBeforeFailedRefresh",
            "testRepeatedEntryRestoresRecordsBeforeFailedRefresh",
            "testRepeatedEntryRestoresInsightsBeforeFailedRefresh",
            "testConcurrentLoadsShareOneRefresh",
            "testRepeatedEntryRestoresAnalysisAndFailedRefreshPreservesIt",
            "testConcurrentLoadsOnlyReadStoredHistoryOnce",
            "testSeparatesVehiclesAndServersAndEvictsLeastRecentlyUsedEntry",
        )
    )
    if (
        not cache_is_bounded_and_scoped
        or not root_uses_scoped_cache
        or not models_preserve_visible_content
        or not tests_cover_reentry_and_isolation
    ):
        return [
            "recent map, driving records, drive insights, and energy balance must restore server-scoped cached state before background refresh"
        ]
    return []


def cached_tertiary_page_blockers(
    root_view: str,
    commute_view_model: str,
    commute_view: str,
    environment_view_model: str,
    environment_view: str,
    regression_tests: str,
) -> list[str]:
    root_uses_scoped_cache = (
        root_view.count("cacheKey: vehiclePageCacheKey(carId: carId)") >= 9
    )
    commute_is_cached_first = (
        "VehiclePageStateCache<CommuteRoutesState>" in commute_view_model
        and "guard !state.isRefreshing else { return }" in commute_view_model
        and "state.isLoading = state.routes.isEmpty" in commute_view_model
        and "stateCache.save(snapshot, for: cacheKey)" in commute_view_model
        and "if viewModel.state.isLoading, viewModel.state.routes.isEmpty" in commute_view
        and "UserFacingErrorLocalizer.localized" in commute_view
    )
    environment_is_cached_first = (
        "VehiclePageStateCache<EnvironmentHistoryState>" in environment_view_model
        and "guard !state.isRefreshing else { return }" in environment_view_model
        and "state.isLoading = state.response == nil" in environment_view_model
        and "stateCache.save(snapshot, for: cacheKey)" in environment_view_model
        and "if viewModel.state.isLoading, viewModel.state.response == nil" in environment_view
        and "UserFacingErrorLocalizer.localized" in environment_view
    )
    tests_cover_reentry_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testRepeatedEntryRestoresCommuteRoutesBeforeFailedRefresh",
            "testConcurrentLoadsStartOneCommuteRequest",
            "testRepeatedEntryRestoresLastRangeBeforeFailedRefresh",
            "testConcurrentLoadsStartOneEnvironmentRequest",
        )
    )
    if (
        not root_uses_scoped_cache
        or not commute_is_cached_first
        or not environment_is_cached_first
        or not tests_cover_reentry_and_duplicate_loads
    ):
        return [
            "commute routes and environment history must restore server-scoped cached state, preserve visible content on refresh failure, and suppress duplicate loads"
        ]
    return []


def cached_geography_page_blockers(
    root_view: str,
    page_cache: str,
    countries_view_model: str,
    countries_view: str,
    regions_view_model: str,
    regions_view: str,
    regression_tests: str,
) -> list[str]:
    cache_scope_is_part_of_identity = (
        "public let scope: String" in page_cache
        and "scope: String = \"\"" in page_cache
        and "self.scope = scope.trimmingCharacters" in page_cache
        and 'scope: "countries:' in root_view
        and 'scope: "regions:' in root_view
        and "private func vehiclePageCacheKey(carId: Int, scope: String = \"\")" in root_view
    )
    countries_are_cached_first = (
        "VehiclePageStateCache<CountriesVisitedState>" in countries_view_model
        and "guard !state.isRefreshing else { return }" in countries_view_model
        and "state.isLoading = state.countries.isEmpty" in countries_view_model
        and "resolvedLocations = state.enrichmentResult?.locations ?? [:]" in countries_view_model
        and "stateCache.save(snapshot, for: cacheKey)" in countries_view_model
        and "if viewModel.state.isLoading, viewModel.state.countries.isEmpty" in countries_view
        and "UserFacingErrorLocalizer.localized" in countries_view
    )
    regions_are_cached_first = (
        "VehiclePageStateCache<RegionsVisitedState>" in regions_view_model
        and "guard !state.isRefreshing else { return }" in regions_view_model
        and "state.isLoading = state.regions.isEmpty" in regions_view_model
        and "state.enrichmentResult?.locations ?? [:]" in regions_view_model
        and "stateCache.save(snapshot, for: cacheKey)" in regions_view_model
        and "if viewModel.state.isLoading, viewModel.state.regions.isEmpty" in regions_view
        and "UserFacingErrorLocalizer.localized" in regions_view
    )
    tests_cover_scoping_reentry_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testSeparatesPageScopesForSameServerAndVehicle",
            "testCountryRepeatedEntryRestoresScopedStateAndPreservesItOnFailure",
            "testRegionRepeatedEntryRestoresScopedStateAndPreservesItOnFailure",
            "testCountryAndRegionConcurrentLoadsEachReadHistoryOnce",
        )
    )
    if (
        not cache_scope_is_part_of_identity
        or not countries_are_cached_first
        or not regions_are_cached_first
        or not tests_cover_scoping_reentry_and_duplicate_loads
    ):
        return [
            "country and region statistics must use year/country-scoped cached state, preserve resolved geography and visible rows on refresh failure, and suppress duplicate history reads"
        ]
    return []


def cached_where_was_i_blockers(
    root_view: str,
    view_model: str,
    view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_timestamp_scope = (
        'scope: "where-was-i:\\(timestamp)"' in root_view
    )
    model_is_cached_first = (
        "VehiclePageStateCache<WhereWasIState>(maximumEntryCount: 24)" in view_model
        and "guard !state.isRefreshing else { return }" in view_model
        and "state.isLoading = state.carState == nil" in view_model
        and "stateCache.save(snapshot, for: cacheKey)" in view_model
    )
    view_preserves_visible_content = (
        "if viewModel.state.isLoading, !hasVisibleContent" in view
        and "else if let error = viewModel.state.errorMessage, !hasVisibleContent" in view
        and "where_was_i_refresh_warning" in view
    )
    tests_cover_reentry_scope_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testRepeatedEntryRestoresScopedStateAndPreservesItOnFailure",
            "testDifferentTimestampScopeDoesNotRestoreAnotherResult",
            "testOverlappingLoadsReadHistoryOnlyOnce",
        )
    )
    ui_covers_real_navigation = (
        "testWhereWasIOpensFromRecentMapActionsWithoutBlocking" in ui_tests
        and 'element("where_was_i_view")' in ui_tests
    )
    if (
        not root_uses_timestamp_scope
        or not model_is_cached_first
        or not view_preserves_visible_content
        or not tests_cover_reentry_scope_and_duplicate_loads
        or not ui_covers_real_navigation
    ):
        return [
            "Where Was I must restore timestamp-scoped cached state, preserve visible content on refresh failure, suppress duplicate history reads, and retain real navigation coverage"
        ]
    return []


def cached_battery_page_blockers(
    root_view: str,
    view_model: str,
    view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_vehicle_scope = (
        "private func batteryViewModel(carId: Int, efficiency: Double?)" in root_view
        and root_view.count("cacheKey: vehiclePageCacheKey(carId: carId)") >= 2
    )
    model_is_cached_first = (
        "VehiclePageStateCache<BatteryState>(maximumEntryCount: 4)" in view_model
        and "guard !state.isRefreshing else { return }" in view_model
        and "state.isLoading = state.stats == nil" in view_model
        and "history = state.history" in view_model
        and "stateCache.save(snapshot, for: cacheKey)" in view_model
    )
    detected_calibration_is_atomic = (
        "settingsStore as? any AtomicSettingsUpdating" in view_model
        and "atomicStore.updateAtomically" in view_model
        and "Self.earliestValidOdometer(" in view_model
    )
    view_preserves_visible_content = (
        "if viewModel.state.isLoading, viewModel.state.stats == nil" in view
        and "else if let stats = viewModel.state.stats" in view
        and 'accessibilityIdentifier("battery_refresh_warning")' in view
    )
    tests_cover_reentry_history_atomicity_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testBatteryRepeatedEntryRestoresStateAndFailedRefreshPreservesIt",
            "testBatteryOptionalHistoryFailureKeepsCachedTrendWhileRefreshingHealth",
            "testBatteryOverlappingLoadsStartOneRefresh",
            "testBatteryDetectedRecordingStartUsesAtomicSettingsUpdate",
        )
    )
    ui_covers_real_battery_navigation = (
        "testUnknownBatteryRecordingStartNeverAppearsAsLifetimeHealth" in ui_tests
        and 'element("battery_view")' in ui_tests
    )
    if (
        not root_uses_vehicle_scope
        or not model_is_cached_first
        or not detected_calibration_is_atomic
        or not view_preserves_visible_content
        or not tests_cover_reentry_history_atomicity_and_duplicate_loads
        or not ui_covers_real_battery_navigation
    ):
        return [
            "battery must restore server-and-vehicle-scoped cached state, preserve visible history on refresh failure, suppress duplicate loads, and atomically merge detected calibration"
        ]
    return []


def cached_software_updates_blockers(
    root_view: str,
    view_model: str,
    view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_vehicle_scope = (
        "SoftwareUpdatesViewModel(" in root_view
        and "snapshotStore: SoftwareUpdateSnapshotStore.shared" in root_view
        and "cacheKey: vehiclePageCacheKey(carId: carId)" in root_view
    )
    model_uses_memory_and_persisted_cache = (
        "VehiclePageStateCache<SoftwareUpdatesPageSnapshot>" in view_model
        and "maximumEntryCount: 4" in view_model
        and "guard !state.isRefreshing else { return }" in view_model
        and "state.isLoading = !state.hasLoadedData" in view_model
        and "snapshotStore.load(serverURL: serverURL, carId: carId)" in view_model
        and "stateCache.save(" in view_model
    )
    model_preserves_filter_and_visible_data = (
        "restored?.allUpdates ?? []" in view_model
        and "state.filterMonths = months" in view_model
        and "saveCachedState()" in view_model
        and "state.errorMessage = error.analyticsMessage" in view_model
    )
    view_keeps_cached_content = (
        "if viewModel.state.isLoading, !viewModel.state.hasLoadedData" in view
        and 'accessibilityIdentifier("software_updates_refresh_warning")' in view
        and ".refreshable" in view
    )
    tests_cover_reentry_empty_results_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testSoftwareUpdatesRepeatedEntryRestoresFilterAndFailedRefreshPreservesRows",
            "testSoftwareUpdatesOverlappingLoadsStartOneServerRequest",
            "testSoftwareUpdatesCacheSuccessfulEmptyResultWithoutReopeningLoader",
            "testSoftwareUpdateSnapshotsAreIsolatedByServerAndVehicle",
        )
    )
    ui_covers_real_navigation = (
        "testSystemAndSafetyFeatureEntriesOpenWithoutBlocking" in ui_tests
        and '("updates", "software_updates_view")' in ui_tests
    )
    if (
        not root_uses_vehicle_scope
        or not model_uses_memory_and_persisted_cache
        or not model_preserves_filter_and_visible_data
        or not view_keeps_cached_content
        or not tests_cover_reentry_empty_results_and_duplicate_loads
        or not ui_covers_real_navigation
    ):
        return [
            "software updates must restore server-and-vehicle-scoped memory and persisted snapshots, preserve filters and visible rows on refresh failure, cache empty results, and suppress duplicate loads"
        ]
    return []


def cached_system_safety_blockers(
    root_view: str,
    achievements_model: str,
    achievements_view: str,
    sentry_model: str,
    sentry_view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_vehicle_scope = (
        "AchievementsViewModel(api:" in root_view
        and "), cacheKey: vehiclePageCacheKey(carId: carId))" in root_view
        and "SentryHistoryViewModel(" in root_view
        and "store: sentryStore()," in root_view
        and "cacheKey: vehiclePageCacheKey(carId: carId)" in root_view
    )
    achievements_are_cached_first = (
        "VehiclePageStateCache<AchievementsState>" in achievements_model
        and "maximumEntryCount: 4" in achievements_model
        and "guard !state.isRefreshing else { return }" in achievements_model
        and "state.isLoading = !state.hasLoadedData" in achievements_model
        and "stateCache.save(snapshot, for: cacheKey)" in achievements_model
        and "state.achievements = []" not in achievements_model
    )
    sentry_is_cached_first_and_single_read = (
        "VehiclePageStateCache<SentryHistoryState>" in sentry_model
        and "maximumEntryCount: 4" in sentry_model
        and "guard !state.isRefreshing else { return }" in sentry_model
        and "state.isLoading = !state.hasLoadedData" in sentry_model
        and "stateCache.save(snapshot, for: cacheKey)" in sentry_model
        and "heatmap(alerts: alerts, now: now)" in sentry_model
        and "store.hourlyCounts" not in sentry_model
    )
    views_preserve_cached_content = (
        "if viewModel.state.isLoading, !viewModel.state.hasLoadedData" in achievements_view
        and 'accessibilityIdentifier("achievements_refresh_warning")' in achievements_view
        and 't("No achievements available", "暂无成就数据")' in achievements_view
        and "if viewModel.state.isLoading, !viewModel.state.hasLoadedData" in sentry_view
        and 'accessibilityIdentifier("sentry_history_refresh_warning")' in sentry_view
        and ".refreshable" in achievements_view
        and ".refreshable" in sentry_view
    )
    tests_cover_reentry_empty_results_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testAchievementsRepeatedEntryRestoresRowsAndFailedRefreshPreservesThem",
            "testAchievementsOverlappingLoadsStartOneRequest",
            "testAchievementsCacheSuccessfulEmptyResult",
            "testSentryHistoryRepeatedEntryRestoresRowsAndFailedRefreshPreservesThem",
            "testSentryHistoryOverlappingLoadsReadStoreOnceAndReuseRowsForHeatmap",
            "testSentryHistoryCachesSuccessfulEmptyResult",
        )
    )
    ui_covers_real_navigation = (
        "testSystemAndSafetyFeatureEntriesOpenWithoutBlocking" in ui_tests
        and '("achievements", "achievements_view")' in ui_tests
        and '("sentry", "sentry_history_view")' in ui_tests
    )
    if (
        not root_uses_vehicle_scope
        or not achievements_are_cached_first
        or not sentry_is_cached_first_and_single_read
        or not views_preserve_cached_content
        or not tests_cover_reentry_empty_results_and_duplicate_loads
        or not ui_covers_real_navigation
    ):
        return [
            "achievements and sentry history must restore server-and-vehicle-scoped state, preserve visible or empty results on refresh failure, suppress duplicate loads, and build the sentry heatmap without rereading history"
        ]
    return []


def cached_analytics_page_blockers(
    root_view: str,
    stats_view_model: str,
    stats_view: str,
    mileage_view_model: str,
    mileage_view: str,
    place_view_model: str,
    place_view: str,
    regression_tests: str,
) -> list[str]:
    root_uses_scoped_cache = (
        root_view.count("cacheKey: vehiclePageCacheKey(carId: carId)") >= 7
    )
    models_restore_and_preserve = (
        "VehiclePageStateCache<StatsPageSnapshot>(maximumEntryCount: 4)" in stats_view_model
        and "guard !isRefreshing else { return }" in stats_view_model
        and (
            "state.isLoading = !hasVisibleContent" in stats_view_model
            or (
                "let hadVisibleContent = hasVisibleContent" in stats_view_model
                and "state.isLoading = !hadVisibleContent" in stats_view_model
            )
        )
        and "VehiclePageStateCache<MileagePageSnapshot>(maximumEntryCount: 4)" in mileage_view_model
        and "guard !isRefreshing else { return }" in mileage_view_model
        and "state.isLoading = state.years.isEmpty" in mileage_view_model
        and "VehiclePageStateCache<PlaceInsightsState>" in place_view_model
        and "guard !isRefreshing else { return }" in place_view_model
        and "state.isLoading = state.places.isEmpty" in place_view_model
        and "Task.detached(priority: .userInitiated)" in place_view_model
    )
    views_keep_cached_content = (
        "if viewModel.state.isLoading, !hasVisibleContent" in stats_view
        and "if viewModel.state.isLoading, viewModel.state.years.isEmpty" in mileage_view
        and "if viewModel.state.isLoading, viewModel.state.places.isEmpty" in place_view
        and all(
            "UserFacingErrorLocalizer.localized" in source
            for source in (stats_view, mileage_view, place_view)
        )
    )
    tests_cover_reentry_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testMileageRepeatedEntryRestoresDrilldownAndFailedRefreshPreservesIt",
            "testStatsRepeatedEntryRestoresFilterContextAndFailedRefreshPreservesIt",
            "testMileageConcurrentLoadsReadHistoryOnce",
            "testRepeatedEntryRestoresPlacesAndFailedRefreshPreservesThem",
            "testConcurrentPlaceLoadsStartOneServerRefresh",
        )
    )
    if (
        not root_uses_scoped_cache
        or not models_restore_and_preserve
        or not views_keep_cached_content
        or not tests_cover_reentry_and_duplicate_loads
    ):
        return [
            "stats, mileage, and place insights must restore scoped snapshots, preserve visible content on refresh failure, and suppress duplicate loads"
        ]
    return []


def cached_cost_hotspot_trips_blockers(
    root_view: str,
    cost_model: str,
    cost_view: str,
    hotspot_model: str,
    hotspot_view: str,
    trips_model: str,
    trips_view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_scoped_cache = (
        root_view.count("cacheKey: vehiclePageCacheKey(carId: carId)") >= 10
    )
    cost_is_cached_first = (
        "VehiclePageStateCache<CostReviewPageSnapshot>" in cost_model
        and "responsesByRange" in cost_model
        and "guard state.range != range, !state.isRefreshing else { return }" in cost_model
        and "state.isLoading = !state.hasLoadedData" in cost_model
        and "state.errorMessage = error.analyticsMessage" in cost_model
        and ".disabled(viewModel.state.isRefreshing)" in cost_view
        and 'accessibilityIdentifier("cost_review_refresh_warning")' in cost_view
    )
    hotspot_is_cached_first = (
        "VehiclePageStateCache<TopDrainLocationsState>" in hotspot_model
        and "guard !state.isRefreshing else { return }" in hotspot_model
        and "state.isLoading = !state.hasLoadedData" in hotspot_model
        and "state.errorMessage = error.analyticsMessage" in hotspot_model
        and 'accessibilityIdentifier("top_drain_locations_refresh_warning")' in hotspot_view
    )
    trips_are_cached_first = (
        "VehiclePageStateCache<TripsPageSnapshot>" in trips_model
        and "sourceData:" in trips_model
        and "allTrips:" in trips_model
        and "guard !state.isRefreshing else { return }" in trips_model
        and "state.isLoading = !state.hasLoadedData" in trips_model
        and "state.errorMessage =" in trips_model
        and 'accessibilityIdentifier("trips_refresh_warning")' in trips_view
    )
    tests_cover_reentry_empty_results_and_duplicate_loads = all(
        name in regression_tests
        for name in (
            "testRepeatedEntryRestoresSelectedRangeAndCachedRangesSurviveFailure",
            "testOverlappingCostReviewLoadsStartOneRequest",
            "testRangeSelectionIsIgnoredWhileRefreshIsInFlight",
            "testRepeatedEntryRestoresHotspotsAndFailedRefreshPreservesThem",
            "testOverlappingHotspotLoadsStartOneRequest",
            "testSuccessfulEmptyHotspotsAreCached",
            "testTripsRepeatedEntryRestoresYearAndFailedRefreshPreservesTrips",
            "testTripsOverlappingLoadsReadSourceOnce",
            "testTripsCacheSuccessfulEmptyResult",
        )
    )
    ui_covers_real_navigation = (
        "testStatsDrilldownsAndCountryRegionPathOpenWithoutBlocking" in ui_tests
        and 'destinationID: "cost_review_view"' in ui_tests
        and "testSystemAndSafetyFeatureEntriesOpenWithoutBlocking" in ui_tests
        and '("standby-hotspots", "top_drain_locations_view")' in ui_tests
        and "testVehicleAndHistoryFeatureEntriesOpenWithoutBlocking" in ui_tests
        and '("trips", "trips_view")' in ui_tests
    )
    if (
        not root_uses_scoped_cache
        or not cost_is_cached_first
        or not hotspot_is_cached_first
        or not trips_are_cached_first
        or not tests_cover_reentry_empty_results_and_duplicate_loads
        or not ui_covers_real_navigation
    ):
        return [
            "cost review, standby hotspots, and trips must restore server-and-vehicle-scoped state, preserve visible or empty results on refresh failure, suppress duplicate loads, and pass real navigation coverage"
        ]
    return []


def cached_live_current_charge_blockers(
    root_view: str,
    view_model: str,
    view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_scoped_cache = (
        "CurrentChargeViewModel(" in root_view
        and "cacheKey: vehiclePageCacheKey(carId: carId)" in root_view
    )
    model_restores_and_preserves = (
        "VehiclePageStateCache<CurrentChargeState>" in view_model
        and "maximumEntryCount: 4" in view_model
        and "state.isLoading = !state.hasLoadedData" in view_model
        and "state.isRefreshing = state.hasLoadedData" in view_model
        and "guard !requestIsRunning else { return }" in view_model
        and "stateCache.save(snapshot, for: cacheKey)" in view_model
        and "state.errorMessage = error.chargeMessage" in view_model
    )
    view_is_live_and_non_destructive = (
        "if viewModel.state.isLoading, !viewModel.state.hasLoadedData" in view
        and ".task(id: carId)" in view
        and "while !Task.isCancelled" in view
        and "Task.sleep(for: viewModel.automaticRefreshInterval)" in view
        and "forceRefresh: true" in view
        and 'accessibilityIdentifier("current_charge_refresh_warning")' in view
    )
    tests_cover_cache_failure_empty_overlap_and_isolation = all(
        name in regression_tests
        for name in (
            "testRepeatedEntryRestoresActiveChargeAndFailedRefreshPreservesIt",
            "testSuccessfulNoActiveChargeIsCachedAsResolvedState",
            "testOverlappingLoadsStartOnlyOneStatusAndChargeRequest",
            "testCurrentChargeCacheIsIsolatedByServerAndVehicle",
            "testForcedRefreshUsesLiveStatusAndChargeEndpoints",
            "testAutomaticRefreshUsesFiveSecondsOnlyWhileCharging",
        )
    )
    ui_covers_real_navigation = (
        "testVehicleAndHistoryFeatureEntriesOpenWithoutBlocking" in ui_tests
        and '("current-charge", "current_charge_view")' in ui_tests
    )
    if (
        not root_uses_scoped_cache
        or not model_restores_and_preserves
        or not view_is_live_and_non_destructive
        or not tests_cover_cache_failure_empty_overlap_and_isolation
        or not ui_covers_real_navigation
    ):
        return [
            "current charge must restore server-and-vehicle-scoped state, preserve resolved active or idle content on refresh failure, suppress duplicate requests, and poll live endpoints only while visible"
        ]
    return []


def cached_standby_create_trip_blockers(
    root_view: str,
    standby_model: str,
    standby_view: str,
    hotspot_view: str,
    create_trip_model: str,
    create_trip_view: str,
    regression_tests: str,
    ui_tests: str,
) -> list[str]:
    root_uses_scoped_caches = (
        "standbyDrainCacheKey: { latitude, longitude in" in root_view
        and "scope: StandbyDrainViewModel.cacheScope(" in root_view
        and 'scope: "create-trip"' in root_view
    )
    standby_is_location_scoped_and_non_destructive = (
        "VehiclePageStateCache<StandbyDrainState>" in standby_model
        and "maximumEntryCount: 12" in standby_model
        and "guard !state.isRefreshing else { return }" in standby_model
        and "state.isLoading = !state.hasLoadedData" in standby_model
        and "stateCache.save(snapshot, for: cacheKey)" in standby_model
        and 'return "standby:\\(latitudeE5):\\(longitudeE5)"' in standby_model
        and 'accessibilityIdentifier("standby_drain_refresh_warning")' in standby_view
    )
    create_trip_restores_drafts_safely = (
        "VehiclePageStateCache<CreateTripPageSnapshot>" in create_trip_model
        and "maximumEntryCount: 4" in create_trip_model
        and "guard let dataProvider, !state.isRefreshing else { return }" in create_trip_model
        and "used = try await tripStore.savedTrips(carId: carId)" in create_trip_model
        and "(try? await tripStore.savedTrips" not in create_trip_model
        and "state.draftLegs = state.draftLegs.filter" in create_trip_model
        and "saveCachedState()" in create_trip_model
        and "stateCache.remove(for: cacheKey)" in create_trip_model
        and 'accessibilityIdentifier("create_trip_refresh_warning")' in create_trip_view
    )
    tests_cover_isolation_empty_overlap_drafts_and_invalidation = all(
        name in regression_tests
        for name in (
            "testStandbyDrainRepeatedEntryRestoresDataAndFailedRefreshPreservesIt",
            "testStandbyDrainCachesResolvedEmptyResponse",
            "testOverlappingStandbyDrainLoadsStartOneRequest",
            "testStandbyDrainCacheScopeSeparatesNearbyLocations",
            "testCreateTripRepeatedEntryRestoresDraftAndFailedRefreshPreservesIt",
            "testCreateTripOverlappingLoadsReadSourceOnce",
            "testCreateTripDoesNotExposeCandidatesWhenUsedLegReadFails",
            "testSuccessfulTripSaveInvalidatesCachedDraft",
            "testRemoveInvalidatesOnlyRequestedEntry",
        )
    )
    ui_covers_nested_standby_and_create_trip = (
        "testStandbyHotspotDrillsIntoCachedLocationAnalysisWithoutBlocking" in ui_tests
        and 'element("standby_hotspot_row_0")' in ui_tests
        and 'tapAndStartMeasurement("standby_analyze_location_button")' in ui_tests
        and 'element("standby_drain_view")' in ui_tests
        and "testCreateTripOpensFromCachedTripHistoryWithoutBlocking" in ui_tests
        and 'element("create_trip_view")' in ui_tests
        and 'accessibilityIdentifier("standby_hotspot_row_\\(index)")' in hotspot_view
        and 'accessibilityIdentifier("standby_analyze_location_button")' in hotspot_view
    )
    if (
        not root_uses_scoped_caches
        or not standby_is_location_scoped_and_non_destructive
        or not create_trip_restores_drafts_safely
        or not tests_cover_isolation_empty_overlap_drafts_and_invalidation
        or not ui_covers_nested_standby_and_create_trip
    ):
        return [
            "single-location standby analysis and trip creation must restore scoped cached state, preserve visible data or drafts on refresh failure, suppress duplicate loads, and pass nested navigation coverage"
        ]
    return []


def launch_bootstrap_blockers(
    root_view: str,
    settings_view_model: str,
    debug_seeder: str,
    settings_tests: str,
    ui_tests: str,
) -> list[str]:
    settings_publish_before_operational_checks = (
        "public func loadEssentials() async" in settings_view_model
        and "public func refreshOperationalState() async" in settings_view_model
        and settings_view_model.find("settings = await settingsStore.load()")
        < settings_view_model.find("await refreshNotificationAuthorizationStatus()")
    )
    essential_index = root_view.find("await settingsViewModel.loadEssentials()")
    sync_index = root_view.find("await syncLifecycleController.appDidBecomeActive()")
    operational_index = root_view.find("await settingsViewModel.refreshOperationalState()")
    root_publishes_cached_ui_first = (
        essential_index >= 0
        and sync_index > essential_index
        and operational_index > essential_index
        and "Task(priority: .utility)" in root_view[essential_index:operational_index]
    )
    debug_fixture_does_not_block_database_on_launch = (
        "seedLaunchConfigurationIfNeeded" in debug_seeder
        and "seedDatabaseFixtureIfNeeded" in debug_seeder
        and root_view.find("seedLaunchConfigurationIfNeeded")
        < root_view.find("await settingsViewModel.loadEssentials()")
        < root_view.find("seedDatabaseFixtureIfNeeded")
    )
    tests_cover_bootstrap_and_real_relaunch = (
        "testEssentialLoadPublishesConfigurationBeforeOperationalChecks" in settings_tests
        and "testUITestLaunchConfigurationCanSeedWithoutOpeningDatabase" in settings_tests
        and "testColdAndWarmLaunchPublishCachedDashboardWithinBudget" in ui_tests
        and 'element("dashboard_view").waitForExistence(timeout: cachedNavigationAutomationBudget)' in ui_tests
    )
    automated_tests_do_not_start_background_work = (
        "Self.isAutomatedTestMode" in root_view
        and "Self.isReservedTestServer" in root_view
        and 'host.hasSuffix(".invalid")' in root_view
        and 'environment["MATEDRIVE_AUTOMATED_TEST_MODE"] == "1"' in root_view
        and 'environment["XCTestConfigurationFilePath"]' in root_view
        and 'NSClassFromString("XCTestCase")' in root_view
    )
    if (
        not settings_publish_before_operational_checks
        or not root_publishes_cached_ui_first
        or not debug_fixture_does_not_block_database_on_launch
        or not tests_cover_bootstrap_and_real_relaunch
        or not automated_tests_do_not_start_background_work
    ):
        return [
            "launch must publish cached configured UI before synchronization, database fixtures, notification, geography, or history health work, with cold and warm relaunch coverage"
        ]
    return []


def connection_settings_transaction_blockers(
    settings_store: str,
    settings_view_model: str,
    root_view: str,
    regression_tests: str,
) -> list[str]:
    has_throwing_persistence = (
        "public func saveThrowing(_ settings: AppSettings) async throws" in settings_store
        and "try saveEncoded(settings)" in settings_store
    )
    has_transaction_and_rollback = (
        "guard !isSaving else { return false }" in settings_view_model
        and "try await settingsStore.saveThrowing(updated)" in settings_view_model
        and "restoreAuthenticationSecrets(previousSecrets)" in settings_view_model
        and "didChangeConnectionConfiguration" in settings_view_model
        and "syncController?.suspendAndWait()" in settings_view_model
        and "syncController?.resume()" in settings_view_model
    )
    preserves_concurrent_settings = (
        "atomicSettingsStore.updateAtomically" in settings_view_model
        and "mergeFormSettings(formSettings, into: current)" in settings_view_model
    )
    independent_settings_are_atomic = (
        "private func updateSettingsAtomically(" in settings_view_model
        and "settingsMutationGeneration &+= 1" in settings_view_model
        and "if mutationGeneration == settingsMutationGeneration" in settings_view_model
        and "recordSettingsUpdateFailure()" in settings_view_model
        and "await settingsStore.save(updated)" not in settings_view_model
    )
    restarts_same_server_configuration = (
        "connectionConfigurationRevision &+= 1" in settings_view_model
        and ".onChange(of: settingsViewModel.connectionConfigurationRevision)" in root_view
        and "syncLifecycleController.serverConfigurationDidChange()" in root_view
    )
    tests_cover_transaction = all(
        name in regression_tests
        for name in (
            "testSettingsPersistenceFailureRestoresSecretsAndResumesOldSync",
            "testCredentialChangeOnSameServerRestartsSyncAndPublishesRevision",
            "testConcurrentSettingsSaveIsRejectedWhileFirstSaveIsPending",
            "testFullSettingsSavePreservesConcurrentlyLearnedPricingRule",
            "testIndependentSettingMutationsMergeWithoutClobberingEachOther",
            "testIndependentSettingFailureRestoresPersistedStateAndReportsError",
        )
    )
    if (
        not has_throwing_persistence
        or not has_transaction_and_rollback
        or not preserves_concurrent_settings
        or not independent_settings_are_atomic
        or not restarts_same_server_configuration
        or not tests_cover_transaction
    ):
        return [
            "settings must save transactionally, merge independent fields atomically, roll back failures, preserve concurrent learned data, and restart same-server authentication changes"
        ]
    return []


def battery_ui_safety_blockers(
    debug_seeder: str,
    root_view: str,
    battery_view: str,
    metric_card: str,
    ui_tests: str,
) -> list[str]:
    blockers = []
    if (
        "#if DEBUG" not in debug_seeder
        or "struct DebugUITestAnalyticsAPI" not in debug_seeder
        or "#endif" not in debug_seeder
    ):
        blockers.append("battery UI test analytics must remain excluded from Release builds")
    if (
        'environment["MATEDRIVE_UI_TEST_MODE"] == "1"' not in root_view
        or "DebugUITestAnalyticsAPI()" not in root_view
    ):
        blockers.append("battery UI test mode must inject the unknown-recording-start fixture")
    if (
        "if !stats.showsAbsoluteHealth" not in battery_view
        or '"battery_calibration_required"' not in battery_view
        or '"battery_absolute_health_value"' not in battery_view
        or '"battery_health_confidence"' not in battery_view
    ):
        blockers.append("battery UI must distinguish calibration-required retention from lifetime health")
    if ".frame(width: 44, height: 44)" not in battery_view:
        blockers.append("battery share control must retain a 44-point touch target")
    if (
        ".accessibilityHidden(true)" not in metric_card
        or ".foregroundStyle(.primary.opacity(0.8))" not in metric_card
    ):
        blockers.append("metric cards must keep decorative icons hidden and captions readable")
    if (
        "testUnknownBatteryRecordingStartNeverAppearsAsLifetimeHealth" not in ui_tests
        or 'element("battery_absolute_health_value").exists' not in ui_tests
        or 'app.staticTexts["99.3%"].exists' not in ui_tests
    ):
        blockers.append("UI tests must prove unknown recording start never appears as lifetime health")
    return blockers


def accessibility_release_audit_blockers(ui_tests: str) -> list[str]:
    blockers = []
    required_coverage = (
        "testFourRootTabsPassSystemAccessibilityAudit",
        "testFeatureHubPassesSystemAccessibilityAudit",
        "testFeatureHubUsesSingleColumnAtAccessibilityTextSize",
        "testBatteryMetricsUseSingleColumnAtAccessibilityTextSize",
        "performVisibleContentAccessibilityAudit",
        "app.performAccessibilityAudit",
    )
    if not all(marker in ui_tests for marker in required_coverage):
        blockers.append(
            "release UI tests must retain root, feature, and battery accessibility and large-text coverage"
        )

    dynamic_type_bypasses = (
        "ignoringDynamicTypeIn" in ui_tests
        or re.search(
            r"\bissue\s*\.\s*auditType\s*==\s*"
            r"(?:XCUIAccessibilityAuditType\s*)?\.\s*dynamicType\b",
            ui_tests,
        )
        or re.search(
            r"(?:XCUIAccessibilityAuditType\s*)?\.\s*dynamicType\s*==\s*"
            r"issue\s*\.\s*auditType\b",
            ui_tests,
        )
    )
    if dynamic_type_bypasses:
        blockers.append(
            "release accessibility audits must not broadly ignore Dynamic Type failures"
        )
    return blockers


def cached_detail_currency_blockers(
    currency_formatter: str,
    production_swift: str,
    charges_view_model: str,
    trip_detail_view_model: str,
    regression_tests: str,
) -> list[str]:
    formatter_uses_device_region = all(
        token in currency_formatter
        for token in (
            "public static func automaticSymbol(locale: Locale = .autoupdatingCurrent)",
            "symbol(for: systemCurrencyCode(locale: locale))",
            "case automaticCode: return automaticSymbol()",
        )
    )
    no_legacy_currency_defaults = all(
        token not in production_swift
        for token in (
            'currencySymbol: String = "€"',
            'currencySymbol = "€"',
            'private var currencyCode = "EUR"',
        )
    )
    charge_list_preserves_cache_and_coalesces_refresh = all(
        token in charges_view_model
        for token in (
            "guard !state.isRefreshing else { return }",
            "state.isLoading = state.rows.isEmpty",
            "defer {",
            "state.isRefreshing = false",
            "if state.rows.isEmpty {",
        )
    )
    trip_detail_preserves_cache_and_coalesces_refresh = all(
        token in trip_detail_view_model
        for token in (
            "public var isRefreshing: Bool",
            "snapshot.isRefreshing = false",
            "guard !state.isRefreshing else { return }",
            "state.isLoading = state.trip == nil",
            "state.isRefreshing = false",
        )
    )
    regression_coverage = all(
        name in regression_tests
        for name in (
            "testAutomaticCurrencyUsesDeviceRegion",
            "testFeatureStateDefaultsUseAutomaticDeviceCurrency",
            "testRepeatedChargeListLoadKeepsCachedContentAndStartsOneRefresh",
            "testTripDetailCoalescesRepeatedLoadsWhileRefreshIsInFlight",
        )
    )
    if (
        not formatter_uses_device_region
        or not no_legacy_currency_defaults
        or not charge_list_preserves_cache_and_coalesces_refresh
        or not trip_detail_preserves_cache_and_coalesces_refresh
        or not regression_coverage
    ):
        return [
            "currency defaults, charge history, and trip detail must use the device region, preserve cached content, and suppress duplicate refreshes"
        ]
    return []


def png_metadata(path: Path) -> tuple[int, int, bool]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    width, height, _, color_type = struct.unpack(">IIBB", data[16:26])
    has_alpha = color_type in (4, 6) or b"tRNS" in data
    return width, height, has_alpha


def technical_blockers() -> list[str]:
    blockers = []
    info = plistlib.loads(Path("MateDriveApp/Info.plist").read_bytes())
    privacy = plistlib.loads(Path("MateDriveApp/PrivacyInfo.xcprivacy").read_bytes())
    widget_privacy = plistlib.loads(Path("MateDriveWidget/PrivacyInfo.xcprivacy").read_bytes())
    entitlements = plistlib.loads(
        Path("MateDriveApp/MateDriveApp.entitlements").read_bytes()
    )
    project = Path("project.yml").read_text(encoding="utf-8")
    cloudkit_schema = Path("docs/release/cloudkit/MateDrive.ckdb").read_text(
        encoding="utf-8"
    )
    cloudkit_integration_tests = Path(
        "MateDriveTests/Backup/CloudKitProductionIntegrationTests.swift"
    ).read_text(encoding="utf-8")
    server_policy = Path(
        "MateDriveApp/Core/API/SettingsBackedTeslamateAPIFactory.swift"
    ).read_text(encoding="utf-8")
    response_cache = Path("MateDriveApp/Core/API/HTTPResponseCache.swift").read_text(encoding="utf-8")
    database_provider = Path(
        "MateDriveApp/Core/Persistence/AppDatabaseProvider.swift"
    ).read_text(encoding="utf-8")
    app_environment = Path("MateDriveApp/App/AppEnvironment.swift").read_text(encoding="utf-8")
    root_view = Path("MateDriveApp/App/RootView.swift").read_text(encoding="utf-8")
    settings_store = Path(
        "MateDriveApp/Features/Settings/SettingsStore.swift"
    ).read_text(encoding="utf-8")
    app_settings = Path(
        "MateDriveApp/Features/Settings/AppSettings.swift"
    ).read_text(encoding="utf-8")
    settings_view_model = Path(
        "MateDriveApp/Features/Settings/SettingsViewModel.swift"
    ).read_text(encoding="utf-8")
    page_cache = Path(
        "MateDriveApp/Core/Persistence/VehiclePageStateCache.swift"
    ).read_text(encoding="utf-8")
    recent_map_view_model = Path(
        "MateDriveApp/Features/Drives/RecentDrivingMapViewModel.swift"
    ).read_text(encoding="utf-8")
    driving_records_view_model = Path(
        "MateDriveApp/Features/Stats/DrivingRecordsViewModel.swift"
    ).read_text(encoding="utf-8")
    drive_insights_view_model = Path(
        "MateDriveApp/Features/DriveInsights/DriveInsightsViewModel.swift"
    ).read_text(encoding="utf-8")
    drive_insights_view = Path(
        "MateDriveApp/Features/DriveInsights/DriveInsightsView.swift"
    ).read_text(encoding="utf-8")
    energy_cycles_view_model = Path(
        "MateDriveApp/Features/Charges/EnergyCyclesViewModel.swift"
    ).read_text(encoding="utf-8")
    commute_view_model = Path(
        "MateDriveApp/Features/DriveInsights/CommuteRoutesViewModel.swift"
    ).read_text(encoding="utf-8")
    commute_view = Path(
        "MateDriveApp/Features/DriveInsights/CommuteRoutesView.swift"
    ).read_text(encoding="utf-8")
    environment_view_model = Path(
        "MateDriveApp/Features/EnvironmentHistory/EnvironmentHistoryViewModel.swift"
    ).read_text(encoding="utf-8")
    environment_view = Path(
        "MateDriveApp/Features/EnvironmentHistory/EnvironmentHistoryView.swift"
    ).read_text(encoding="utf-8")
    stats_view_model = Path("MateDriveApp/Features/Stats/StatsViewModel.swift").read_text(
        encoding="utf-8"
    )
    stats_view = Path("MateDriveApp/Features/Stats/StatsView.swift").read_text(
        encoding="utf-8"
    )
    mileage_view_model = Path(
        "MateDriveApp/Features/Mileage/MileageViewModel.swift"
    ).read_text(encoding="utf-8")
    mileage_view = Path("MateDriveApp/Features/Mileage/MileageView.swift").read_text(
        encoding="utf-8"
    )
    place_view_model = Path(
        "MateDriveApp/Features/Places/PlaceInsightsViewModel.swift"
    ).read_text(encoding="utf-8")
    place_view = Path(
        "MateDriveApp/Features/Places/PlaceInsightsView.swift"
    ).read_text(encoding="utf-8")
    activities_cache = Path(
        "MateDriveApp/Features/Activities/ActivitiesStateCache.swift"
    ).read_text(encoding="utf-8")
    data_preloader = Path("MateDriveApp/Core/Sync/AppDataPreloader.swift").read_text(encoding="utf-8")
    history_sync = Path("MateDriveApp/Core/Sync/SyncCoordinator.swift").read_text(encoding="utf-8")
    charge_pricing_rule = Path(
        "MateDriveApp/Features/Charges/ChargePricingRule.swift"
    ).read_text(encoding="utf-8")
    regional_tariff_catalog = Path(
        "MateDriveApp/Features/Charges/RegionalChargingTariff.swift"
    ).read_text(encoding="utf-8")
    charge_cost_resolver = Path(
        "MateDriveApp/Features/Charges/ChargeCostResolver.swift"
    ).read_text(encoding="utf-8")
    dashboard_summary_provider = Path(
        "MateDriveApp/Features/Dashboard/DashboardSummaryProvider.swift"
    ).read_text(encoding="utf-8")
    dashboard_presentation = Path(
        "MateDriveApp/Features/Dashboard/DashboardOverviewPresentation.swift"
    ).read_text(encoding="utf-8")
    charges_view_model = Path(
        "MateDriveApp/Features/Charges/ChargesViewModel.swift"
    ).read_text(encoding="utf-8")
    charge_detail_view_model = Path(
        "MateDriveApp/Features/Charges/ChargeDetailViewModel.swift"
    ).read_text(encoding="utf-8")
    trip_detail_view_model = Path(
        "MateDriveApp/Features/Trips/TripDetailViewModel.swift"
    ).read_text(encoding="utf-8")
    currency_formatter = Path(
        "MateDriveApp/Core/Domain/MateDriveCurrencyFormatter.swift"
    ).read_text(encoding="utf-8")
    charges_view = Path(
        "MateDriveApp/Features/Charges/ChargesView.swift"
    ).read_text(encoding="utf-8")
    smart_activity_indexer = Path(
        "MateDriveApp/Core/Sync/SmartActivityIndexer.swift"
    ).read_text(encoding="utf-8")
    history_paginator = Path("MateDriveApp/Core/API/APIResult.swift").read_text(encoding="utf-8")
    production_swift = "\n".join(
        path.read_text(encoding="utf-8")
        for root in [Path("MateDriveApp"), Path("MateDriveWidget")]
        for path in root.rglob("*.swift")
    )
    production_bundle_sources = "\n".join(
        [project]
        + [
            path.read_text(encoding="utf-8")
            for root in [Path("MateDriveApp"), Path("MateDriveWidget")]
            for path in root.rglob("*")
            if path.is_file()
            and path.suffix.lower()
            in {
                ".entitlements",
                ".json",
                ".plist",
                ".swift",
                ".xcprivacy",
                ".xcstrings",
            }
        ]
    )
    drive_summary_store = Path(
        "MateDriveApp/Core/Persistence/Stores/DriveSummaryStore.swift"
    ).read_text(encoding="utf-8")
    charge_summary_store = Path(
        "MateDriveApp/Core/Persistence/Stores/ChargeSummaryStore.swift"
    ).read_text(encoding="utf-8")
    software_updates = Path(
        "MateDriveApp/Features/Updates/SoftwareUpdatesViewModel.swift"
    ).read_text(encoding="utf-8")
    mileage_view_model = Path(
        "MateDriveApp/Features/Mileage/MileageViewModel.swift"
    ).read_text(encoding="utf-8")
    geography_enricher = Path(
        "MateDriveApp/Features/Stats/CountriesVisitedViewModel.swift"
    ).read_text(encoding="utf-8")
    countries_view = Path(
        "MateDriveApp/Features/Stats/CountriesVisitedView.swift"
    ).read_text(encoding="utf-8")
    regions_view_model = Path(
        "MateDriveApp/Features/Stats/RegionsVisitedViewModel.swift"
    ).read_text(encoding="utf-8")
    regions_view = Path(
        "MateDriveApp/Features/Stats/RegionsVisitedView.swift"
    ).read_text(encoding="utf-8")
    where_was_i_view_model = Path(
        "MateDriveApp/Features/WhereWasI/WhereWasIViewModel.swift"
    ).read_text(encoding="utf-8")
    where_was_i_view = Path(
        "MateDriveApp/Features/WhereWasI/WhereWasIView.swift"
    ).read_text(encoding="utf-8")
    trip_data_provider = Path(
        "MateDriveApp/Features/Trips/TripDataProvider.swift"
    ).read_text(encoding="utf-8")
    battery_view_model = Path(
        "MateDriveApp/Features/Battery/BatteryViewModel.swift"
    ).read_text(encoding="utf-8")
    debug_seeder = Path("MateDriveApp/App/DebugLocalTeslamateSeeder.swift").read_text(
        encoding="utf-8"
    )
    battery_view = Path("MateDriveApp/Features/Battery/BatteryView.swift").read_text(
        encoding="utf-8"
    )
    metric_card = Path("MateDriveApp/SharedUI/MetricCard.swift").read_text(encoding="utf-8")
    ui_tests = Path("MateDriveUITests/MateDriveNavigationUITests.swift").read_text(
        encoding="utf-8"
    )
    cached_page_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/RecentDrivingMapViewModelTests.swift",
            "MateDriveTests/Features/DrivingRecordsViewModelTests.swift",
            "MateDriveTests/Features/DriveInsightsViewModelTests.swift",
            "MateDriveTests/Features/EnergyCyclesViewModelTests.swift",
            "MateDriveTests/Persistence/VehiclePageStateCacheTests.swift",
        )
    )
    cached_analytics_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/AnalyticalViewModelTests.swift",
            "MateDriveTests/Features/PlaceInsightsViewModelTests.swift",
        )
    )
    cached_tertiary_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/CommuteRoutesViewModelTests.swift",
            "MateDriveTests/Features/EnvironmentHistoryViewModelTests.swift",
        )
    )
    cached_geography_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/GeographyStatsTests.swift",
            "MateDriveTests/Persistence/VehiclePageStateCacheTests.swift",
        )
    )
    cached_where_was_i_tests = Path(
        "MateDriveTests/Features/WhereWasICacheFirstTests.swift"
    ).read_text(encoding="utf-8")
    cached_battery_tests = Path(
        "MateDriveTests/Features/AnalyticalViewModelTests.swift"
    ).read_text(encoding="utf-8")
    cached_system_safety_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/AchievementsViewModelTests.swift",
            "MateDriveTests/Features/SentryHistoryViewModelTests.swift",
        )
    )
    cached_cost_hotspot_trips_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/CostReviewViewModelTests.swift",
            "MateDriveTests/Features/TopDrainLocationsViewModelTests.swift",
            "MateDriveTests/Features/TripsViewModelTests.swift",
        )
    )
    cached_detail_currency_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Domain/UnitFormatterTests.swift",
            "MateDriveTests/Features/ChargesViewModelTests.swift",
            "MateDriveTests/Features/TripDetailViewModelTests.swift",
        )
    )
    historical_tariff_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/RegionalChargingTariffTests.swift",
            "MateDriveTests/Features/ChargePricingRuleTests.swift",
            "MateDriveTests/Features/DashboardOverviewPresentationTests.swift",
            "MateDriveTests/Features/ChargesViewModelTests.swift",
            "MateDriveTests/Features/ChargeDetailViewModelTests.swift",
        )
    )
    credential_privacy_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/API/APIClientTests.swift",
            "MateDriveTests/API/TeslaMateConnectionDiagnosticTests.swift",
            "MateDriveTests/Security/KeychainStoreTests.swift",
            "MateDriveTests/Backup/DatabaseBackupProviderTests.swift",
        )
    )
    route_weather_privacy_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/DriveDetailViewModelTests.swift",
            "MateDriveTests/Features/SettingsViewModelTests.swift",
        )
    )
    current_charge_tests = Path(
        "MateDriveTests/Features/CurrentChargeViewModelTests.swift"
    ).read_text(encoding="utf-8")
    standby_create_trip_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/ActivitiesViewModelTests.swift",
            "MateDriveTests/Features/TripsViewModelTests.swift",
            "MateDriveTests/Persistence/VehiclePageStateCacheTests.swift",
        )
    )
    settings_transaction_tests = Path(
        "MateDriveTests/Features/SettingsViewModelTests.swift"
    ).read_text(encoding="utf-8")
    launch_bootstrap_tests = "\n".join(
        Path(path).read_text(encoding="utf-8")
        for path in (
            "MateDriveTests/Features/SettingsViewModelTests.swift",
            "MateDriveTests/App/DebugLocalTeslamateSeederTests.swift",
        )
    )
    support_page = Path("docs/support/index.html")
    privacy_page = Path("docs/support/privacy.html")
    app_links = Path("MateDriveApp/Core/Domain/AppLinks.swift")
    settings_view = Path("MateDriveApp/Features/Settings/SettingsView.swift")
    privacy_view = Path("MateDriveApp/Features/Settings/PrivacyDataView.swift")
    review_demo_generator = Path("scripts/generate_review_demo_api.py")
    pages_workflow = Path(".github/workflows/pages.yml")
    makefile = Path("Makefile")
    probe_script = Path("scripts/probe_teslamate_integration.sh")
    review_demo_tests = Path("scripts/test_review_demo_api.py")

    if info.get("CFBundleDisplayName") != "MateDrive":
        blockers.append("CFBundleDisplayName must be MateDrive")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        blockers.append("ITSAppUsesNonExemptEncryption must be false")
    launch = info.get("UILaunchScreen", {})
    if launch.get("UIColorName") != "LaunchBackground" or launch.get("UIImageName") != "LaunchWordmark":
        blockers.append("UILaunchScreen must use the packaged MateDrive launch assets")
    blockers.extend(
        app_version_blockers(
            str(info.get("CFBundleShortVersionString", "")),
            str(info.get("CFBundleVersion", "")),
            project,
        )
    )
    if privacy.get("NSPrivacyTracking") is not False:
        blockers.append("privacy manifest must declare tracking false")
    reasons = {
        item.get("NSPrivacyAccessedAPIType"): item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in privacy.get("NSPrivacyAccessedAPITypes", [])
    }
    if "CA92.1" not in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", []):
        blockers.append("privacy manifest must declare UserDefaults reason CA92.1")
    if "C617.1" not in reasons.get("NSPrivacyAccessedAPICategoryFileTimestamp", []):
        blockers.append("privacy manifest must declare app-container file metadata reason C617.1")
    if "35F9.1" not in reasons.get("NSPrivacyAccessedAPICategorySystemBootTime", []):
        blockers.append("privacy manifest must declare elapsed-time measurement reason 35F9.1")
    widget_reasons = {
        item.get("NSPrivacyAccessedAPIType"): item.get("NSPrivacyAccessedAPITypeReasons", [])
        for item in widget_privacy.get("NSPrivacyAccessedAPITypes", [])
    }
    if "CA92.1" not in widget_reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", []):
        blockers.append("widget privacy manifest must declare UserDefaults reason CA92.1")
    if widget_privacy.get("NSPrivacyCollectedDataTypes") != []:
        blockers.append("widget privacy manifest must not declare data collection")
    if project.count('TARGETED_DEVICE_FAMILY: "1"') < 2:
        blockers.append("app and widget must explicitly target iPhone")
    if not support_page.exists() or "MateDrive Support" not in support_page.read_text(encoding="utf-8"):
        blockers.append("publishable MateDrive support page artifact is missing")
    if not privacy_page.exists() or "MateDrive Privacy Policy" not in privacy_page.read_text(encoding="utf-8"):
        blockers.append("publishable MateDrive privacy policy artifact is missing")
    if app_links.exists() and settings_view.exists() and privacy_view.exists():
        blockers.extend(
            in_app_support_link_blockers(
                settings_view.read_text(encoding="utf-8"),
                privacy_view.read_text(encoding="utf-8"),
                app_links.read_text(encoding="utf-8"),
            )
        )
    else:
        blockers.append("in-app support and privacy link sources are missing")
    if all(
        path.exists()
        for path in (
            review_demo_generator,
            pages_workflow,
            makefile,
            probe_script,
            review_demo_tests,
        )
    ):
        blockers.extend(
            review_demo_api_blockers(
                review_demo_generator.read_text(encoding="utf-8"),
                pages_workflow.read_text(encoding="utf-8"),
                makefile.read_text(encoding="utf-8"),
                probe_script.read_text(encoding="utf-8"),
                review_demo_tests.read_text(encoding="utf-8"),
                Path(
                    "MateDriveTests/API/LocalTeslamateIntegrationTests.swift"
                ).read_text(encoding="utf-8"),
                SUBMISSION_PATH.read_text(encoding="utf-8"),
            )
        )
    else:
        blockers.append("App Review synthetic API generation or verification sources are missing")
    blockers.extend(review_demo_embedding_blockers(production_bundle_sources))
    if "containsEmbeddedSecrets" not in server_policy or "containsSensitiveComponents" not in server_policy:
        blockers.append("server URL policy must reject embedded credentials and sensitive URL components")
    blockers.extend(
        credential_privacy_blockers(
            Path("MateDriveApp/Core/API/HTTPClient.swift").read_text(encoding="utf-8"),
            Path("MateDriveApp/Core/API/TeslaMateDiagnosticExport.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Core/Security/KeychainStore.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Core/Backup/DatabaseBackupProvider.swift").read_text(
                encoding="utf-8"
            ),
            credential_privacy_tests,
        )
    )
    blockers.extend(
        route_weather_privacy_blockers(
            app_settings,
            Path(
                "MateDriveApp/Features/Drives/DriveDetailViewModel.swift"
            ).read_text(encoding="utf-8"),
            Path("MateDriveApp/Features/Drives/DriveDetailView.swift").read_text(
                encoding="utf-8"
            ),
            privacy_view.read_text(encoding="utf-8"),
            privacy_page.read_text(encoding="utf-8"),
            route_weather_privacy_tests,
        )
    )
    if 'Set(["content-type", "content-language"])' not in response_cache:
        blockers.append("persistent HTTP cache must allowlist non-sensitive response headers")
    if "safePersistedURL" not in response_cache:
        blockers.append("persistent HTTP cache must strip sensitive URL components")
    if "completeUntilFirstUserAuthentication" not in database_provider:
        blockers.append("application database must use iOS file protection")
    if (
        "TeslaMateServerIdentity.key(for: url)" not in database_provider
        or '"matedrive-\\(namespace).sqlite"' not in database_provider
        or ".legacy-database-adopted" not in database_provider
        or "LiveAppDatabaseProvider(settingsStore: settingsStore)" not in app_environment
    ):
        blockers.append("application databases must be isolated by TeslaMate server with one-time legacy adoption")
    if (
        "serverConfigurationDidChange()" not in root_view
        or "resetForServerChange()" not in root_view
    ):
        blockers.append("server changes must reset visible vehicle state and restart synchronization")
    if (
        "completeFileProtectionUntilFirstUserAuthentication" not in activities_cache
        or "completeUntilFirstUserAuthentication" not in activities_cache
    ):
        blockers.append("activity state cache must use iOS file protection")
    if "50_000" in data_preloader or "50000" in data_preloader:
        blockers.append("background page preloading must not request oversized history lists")
    if "50_000" in history_sync or "50000" in history_sync:
        blockers.append("complete history sync must not request oversized history lists")
    blockers.extend(forced_crash_pattern_blockers(production_swift))
    blockers.extend(history_pagination_blockers(history_paginator, production_swift))
    blockers.extend(sync_cancellation_blockers(history_sync))
    blockers.extend(charge_pricing_safety_blockers(charge_pricing_rule))
    blockers.extend(
        automatic_charge_inference_blockers(
            charge_cost_resolver,
            charge_pricing_rule,
            dashboard_summary_provider,
            charges_view_model,
            charge_detail_view_model,
            smart_activity_indexer,
        )
    )
    blockers.extend(geofence_precedence_blockers(app_settings, settings_transaction_tests))
    blockers.extend(charge_cost_transparency_blockers(charges_view, ui_tests))
    blockers.extend(
        historical_tariff_transparency_blockers(
            regional_tariff_catalog,
            charge_pricing_rule,
            charge_cost_resolver,
            charge_detail_view_model,
            charges_view_model,
            charges_view,
            dashboard_summary_provider,
            dashboard_presentation,
            historical_tariff_tests,
        )
    )
    blockers.extend(
        cached_secondary_page_blockers(
            root_view,
            page_cache,
            recent_map_view_model,
            driving_records_view_model,
            drive_insights_view_model,
            drive_insights_view,
            energy_cycles_view_model,
            cached_page_tests,
        )
    )
    blockers.extend(
        cached_analytics_page_blockers(
            root_view,
            stats_view_model,
            stats_view,
            mileage_view_model,
            mileage_view,
            place_view_model,
            place_view,
            cached_analytics_tests,
        )
    )
    blockers.extend(
        cached_tertiary_page_blockers(
            root_view,
            commute_view_model,
            commute_view,
            environment_view_model,
            environment_view,
            cached_tertiary_tests,
        )
    )
    blockers.extend(
        cached_geography_page_blockers(
            root_view,
            page_cache,
            geography_enricher,
            countries_view,
            regions_view_model,
            regions_view,
            cached_geography_tests,
        )
    )
    blockers.extend(
        cached_where_was_i_blockers(
            root_view,
            where_was_i_view_model,
            where_was_i_view,
            cached_where_was_i_tests,
            ui_tests,
        )
    )
    blockers.extend(
        cached_battery_page_blockers(
            root_view,
            battery_view_model,
            battery_view,
            cached_battery_tests,
            ui_tests,
        )
    )
    blockers.extend(
        cached_software_updates_blockers(
            root_view,
            software_updates,
            Path("MateDriveApp/Features/Updates/SoftwareUpdatesView.swift").read_text(
                encoding="utf-8"
            ),
            cached_analytics_tests,
            ui_tests,
        )
    )
    blockers.extend(
        cached_system_safety_blockers(
            root_view,
            Path(
                "MateDriveApp/Features/Achievements/AchievementsViewModel.swift"
            ).read_text(encoding="utf-8"),
            Path("MateDriveApp/Features/Achievements/AchievementsView.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Features/Sentry/SentryHistoryViewModel.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Features/Sentry/SentryHistoryView.swift").read_text(
                encoding="utf-8"
            ),
            cached_system_safety_tests,
            ui_tests,
        )
    )
    blockers.extend(
        cached_cost_hotspot_trips_blockers(
            root_view,
            Path("MateDriveApp/Features/Costs/CostReviewViewModel.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Features/Costs/CostReviewView.swift").read_text(
                encoding="utf-8"
            ),
            Path(
                "MateDriveApp/Features/Activities/TopDrainLocationsViewModel.swift"
            ).read_text(encoding="utf-8"),
            Path(
                "MateDriveApp/Features/Activities/TopDrainLocationsView.swift"
            ).read_text(encoding="utf-8"),
            Path("MateDriveApp/Features/Trips/TripsViewModel.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Features/Trips/TripsView.swift").read_text(
                encoding="utf-8"
            ),
            cached_cost_hotspot_trips_tests,
            ui_tests,
        )
    )
    blockers.extend(
        cached_live_current_charge_blockers(
            root_view,
            Path(
                "MateDriveApp/Features/Charges/CurrentChargeViewModel.swift"
            ).read_text(encoding="utf-8"),
            Path("MateDriveApp/Features/Charges/CurrentChargeView.swift").read_text(
                encoding="utf-8"
            ),
            current_charge_tests,
            ui_tests,
        )
    )
    blockers.extend(
        cached_standby_create_trip_blockers(
            root_view,
            Path(
                "MateDriveApp/Features/Activities/StandbyDrainViewModel.swift"
            ).read_text(encoding="utf-8"),
            Path("MateDriveApp/Features/Activities/StandbyDrainView.swift").read_text(
                encoding="utf-8"
            ),
            Path(
                "MateDriveApp/Features/Activities/TopDrainLocationsView.swift"
            ).read_text(encoding="utf-8"),
            Path("MateDriveApp/Features/Trips/CreateTripViewModel.swift").read_text(
                encoding="utf-8"
            ),
            Path("MateDriveApp/Features/Trips/CreateTripView.swift").read_text(
                encoding="utf-8"
            ),
            standby_create_trip_tests,
            ui_tests,
        )
    )
    blockers.extend(
        launch_bootstrap_blockers(
            root_view,
            settings_view_model,
            debug_seeder,
            launch_bootstrap_tests,
            ui_tests,
        )
    )
    blockers.extend(
        connection_settings_transaction_blockers(
            settings_store,
            settings_view_model,
            root_view,
            settings_transaction_tests,
        )
    )
    blockers.extend(
        cloudkit_release_blockers(
            entitlements,
            cloudkit_schema,
            project,
            cloudkit_integration_tests,
        )
    )
    if (
        "summaryPageSize = 200" not in history_sync
        or "maximumSummaryPages" not in history_sync
        or "guard !newItems.isEmpty else" not in history_sync
        or "upsertDriveSummaries(newItems" not in history_sync
        or "upsertChargeSummaries(newItems" not in history_sync
    ):
        blockers.append("complete history sync must persist bounded pages with a no-progress guard")
    if (
        "ORDER BY start_date DESC, drive_id DESC" not in drive_summary_store
        or "ORDER BY start_date DESC, charge_id DESC" not in charge_summary_store
    ):
        blockers.append("background detail hydration must prioritize the newest drive and charge records")
    if "show: 200" not in software_updates:
        blockers.append("software update reads must match the bounded background cache key")
    if (
        "maximumEnergyEnrichmentCount: Int = 120" not in mileage_view_model
        or ".prefix(maximumEnergyEnrichmentCount)" not in mileage_view_model
        or "guard !Task.isCancelled else { return enriched }" not in mileage_view_model
    ):
        blockers.append("foreground mileage energy enrichment must remain bounded and cancellable")
    if (
        "maximumDetailRequests: Int = 24" not in geography_enricher
        or "detailRequests < maximumDetailRequests" not in geography_enricher
        or "guard !Task.isCancelled" not in geography_enricher
    ):
        blockers.append("historical geography enrichment must have a cancellable detail-request budget")
    if (
        "maximumConcurrentRouteRequests: Int = 8" not in trip_data_provider
        or "by: maximumConcurrentRouteRequests" not in trip_data_provider
        or "guard !Task.isCancelled else { break }" not in trip_data_provider
    ):
        blockers.append("trip route hydration must remain bounded and cancellable")
    if (
        "case recordingStartUnknown" not in battery_view_model
        or "let recordingStartIsKnown = batteryRecordingStartOdometerKm != nil" not in battery_view_model
        or "let historyBaselineIsUnverified = !recordingStartIsKnown || startsLate" not in battery_view_model
        or "healthSource != .recordedPeriod" not in battery_view_model
    ):
        blockers.append("unknown or late TeslaMate history must not be presented as lifetime battery health")
    blockers.extend(
        battery_ui_safety_blockers(
            debug_seeder,
            root_view,
            battery_view,
            metric_card,
            ui_tests,
        )
    )
    blockers.extend(accessibility_release_audit_blockers(ui_tests))
    blockers.extend(
        cached_detail_currency_blockers(
            currency_formatter,
            production_swift,
            charges_view_model,
            trip_detail_view_model,
            cached_detail_currency_tests,
        )
    )

    icon_root = Path("MateDriveApp/Resources/Assets.xcassets/AppIcon.appiconset")
    contents = json.loads((icon_root / "Contents.json").read_text(encoding="utf-8"))
    for image in contents.get("images", []):
        filename = image.get("filename")
        size = image.get("size")
        scale = image.get("scale")
        if not filename or not size or not scale:
            blockers.append(f"incomplete app icon slot: {image}")
            continue
        points = float(size.split("x")[0])
        multiplier = int(scale.removesuffix("x"))
        expected = int(round(points * multiplier))
        try:
            width, height, has_alpha = png_metadata(icon_root / filename)
        except (OSError, ValueError) as error:
            blockers.append(f"invalid app icon {filename}: {error}")
            continue
        if (width, height) != (expected, expected):
            blockers.append(f"app icon {filename} is {width}x{height}, expected {expected}x{expected}")
        if has_alpha:
            blockers.append(f"app icon {filename} contains an alpha channel")
    launch_root = Path("MateDriveApp/Resources/Assets.xcassets/LaunchWordmark.imageset")
    for filename, expected_width, expected_height in [
        ("LaunchMark.png", 220, 64),
        ("LaunchMark@2x.png", 440, 128),
        ("LaunchMark@3x.png", 660, 192),
    ]:
        try:
            width, height, _ = png_metadata(launch_root / filename)
        except (OSError, ValueError) as error:
            blockers.append(f"invalid launch image {filename}: {error}")
            continue
        if (width, height) != (expected_width, expected_height):
            blockers.append(
                f"launch image {filename} is {width}x{height}, expected {expected_width}x{expected_height}"
            )
    return blockers


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--technical-only", action="store_true")
    args = parser.parse_args()
    text = SUBMISSION_PATH.read_text(encoding="utf-8")
    technical = technical_blockers()
    print(f"app-store technical blockers: {len(technical)}")
    for blocker in technical:
        print(f"- {blocker}")
    if args.technical_only:
        return 1 if technical else 0

    support_html = Path("docs/support/index.html").read_text(encoding="utf-8")
    blockers = technical + submission_blockers(text, support_html)
    print(f"app-store submission blockers: {len(blockers)}")
    for blocker in blockers:
        print(f"- {blocker}")

    return 1 if blockers else 0


if __name__ == "__main__":
    sys.exit(main())
