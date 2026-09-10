# MateDrive App Store Submission

This file is the local source of truth for App Store Connect copy and review notes. Keep it aligned with the shipped app name, privacy manifest, screenshots, and TeslaMate integration behavior before each release.

## App Name

MateDrive

## Submission Status

Build 19 is the current source and local distribution candidate as of August 10, 2026. The signed `1.0 (19)` archive at `/tmp/matedrive-build19-first-run-archive.n0nfPi/MateDrive.xcarchive` has matching App and Widget build numbers, matching binary/dSYM UUIDs, a valid nested signature, and zero release-archive blockers. The Apple Distribution-signed local IPA at `/tmp/matedrive-build19-first-run-local-export.vYc1ry/MateDrive.ipa` passes ZIP integrity and strict nested-signature verification, with debugging entitlements disabled for both the App and Widget. Its SHA-256 is `725268453e6fa90ed7d802543002f3d6840b0ee82e41ffa615449ce70bc71664`. Build 19 has not been uploaded or submitted from this verification run.

Build 18 remains the previously uploaded historical candidate. App Store Connect rejected an attempted reuse of build number 18 because that number had already been used, so the post-audit source was advanced to Build 19 instead of overwriting the existing delivery. Build 19 adds the final trip and charge history pagination correction, retry and empty-state refinements, explicit English and Traditional Chinese UI regression coverage, landscape and dark/high-contrast validation, Reduce Motion handling for nonessential app animations, and a focused first-run connection gate that validates TeslaMate before saving or entering the main app.

The final Build 19 source passed a fresh full run of 1,139 unit tests with 34 intentional external-environment skips and zero failures at `/tmp/matedrive-first-run-success-full-unit-20260810.xcresult`, plus all 35 UI tests with zero failures at `/tmp/matedrive-first-run-success-full-ui-20260810.xcresult`. The full UI run includes the focused fresh-install setup, failed-verification recovery, successful validation against a privacy-safe local TeslaMate HTTP fixture, stable dashboard content after connection, exact server-URL persistence after termination and relaunch, explicit English and Traditional Chinese release-language journeys, landscape navigation, accessibility-size layouts, system accessibility audits across all four root tabs, offline cached content, retry states, and repeated-tap navigation protection. A separate dark plus increased-contrast audit also passes across all four root tabs. English, Traditional Chinese, portrait, landscape, normal text, accessibility text, empty setup, failed network verification, and successful first-run landing states were visually reviewed using privacy-safe synthetic data. Technical, independent-release, vehicle-fixture privacy, localization, screenshot, submission, and archive gates pass.

The `MateDriveBackup` record type, its 15 fields, the `recordName` query index, and the `createdAt` sortable index are deployed in the Production environment of `iCloud.com.matedrive.ios`. The signed source passed the physical-device Production upload/list/download/delete and cleanup round trip at `/tmp/MateDrive-CloudKitProductionPhysical-20260728-11.xcresult`. Runtime listing uses CloudKit zone changes to enumerate private custom-zone backups without downloading backup assets. First-level Settings entries for Support & Feedback and the public Privacy Policy are included in Build 19. The public synthetic review API is generated daily and deployed by GitHub Actions; its deployed artifact passed the current native read-only endpoint integration test without exposing a VIN or credentials.

The final screenshot pipeline produced six exact `1242x2688` Simplified Chinese drafts in `build/app-store-screenshots/zh-Hans`, and the automated screenshot audit reports zero blockers. Its dedicated first-launch warm-up prevents splash or loading states from being captured. Dashboard, Activity, and Features use privacy-safe synthetic data and are the selected listing candidates; Charge Detail and Battery intentionally retain honest missing-data and calibration states and are excluded from the initial listing set. The current static App Store technical and submission audits report zero local blockers. App Store review submission still also requires uploading Build 19, installing that exact distribution build through TestFlight, completing the physical-device distribution smoke test, saving accurate review contact details, confirming third-party content rights, and completing the account-holder EU Digital Services Act declaration. No upload or review submission is authorized by this document alone.

The optional App Accessibility nutrition label remains unpublished. Existing evidence now covers system accessibility audits on the four root tabs, dark plus increased-contrast presentation, Reduce Motion handling, release-language navigation, landscape navigation, and focused accessibility-size layout paths. The final large-text pass fixed the Battery metric-card icon/title collision and the Activity session-time clipping, and removed their broad app-owned clipping exceptions. The iOS 26.5 simulator's non-actionable Dynamic Type audit category and documented system or viewport-edge findings remain filtered, so do not claim complete Larger Text support until the remaining whole-app paths are independently retested without those platform-level filters.

## Subtitle

TeslaMate dashboard for iPhone

## Promotional Text

Track your TeslaMate vehicle data, charging, drives, trips, battery health, widgets, App Shortcuts, and read-only notifications from a native iOS app.

## Description

MateDrive is a native iOS companion for TeslaMate. Connect it to your own TeslaMate API server to view vehicle status, charging sessions, drives, mileage, trips, software updates, battery health, location history, widgets, App Shortcuts, and read-only notifications.

MateDrive is designed for owners who already run TeslaMate and want a focused mobile dashboard. The app reads your TeslaMate data, stores your server settings locally, keeps authentication secrets in Keychain, and does not send your vehicle data to a MateDrive-operated service.

Key features:

- Cache-first dashboard with a circular battery or rated-range gauge, current vehicle state, tyre pressures, map, latest drive, latest charge cost, and odometer overview.
- Charging history with manual cost overrides, regional and time-segment pricing rules, reusable location-free tariff templates, protected batch API writeback and rollback, persistent vehicle-scoped audit history, privacy-safe CSV audit export, AC/DC comparisons, power curves, and cost summaries.
- Drive details with route maps, speed, power, elevation, efficiency, optional route-weather samples when available, and comparison tools.
- Privacy-conscious native drive, activity-period recap, battery, achievement and multi-drive trip report cards. Drive cards hide addresses, time, classification and route shape by default; period recaps hide exact dates and costs; battery reports hide exact recording dates and start odometer; achievement cards hide unlock dates, place names and progress details and never include raw coordinates or related drive IDs. Reports preserve missing values and disclose calibration limits.
- Mileage, statistics, countries and regions visited, software updates, and battery health analysis.
- On-device activity classification, geofence-assisted place recognition, commute suggestions, trip detection, custom labels, sleep summaries, and manually saved trips.
- Configurable per-vehicle Home Screen widgets and local notifications for read-only status updates.
- Siri, Spotlight, and Shortcuts actions for opening Dashboard, Current Charge, Charges, Drives, and Activities.
- Regional cost formatting with automatic device currency, manual ISO currency selection, and independent TeslaMate/metric/imperial units.
- In-app language selection for Simplified Chinese, Traditional Chinese, and English.
- Optional private iCloud backup with explicit consent, newest-three retention, integrity verification, and automatic rollback during restore. Keychain credentials are excluded.

MateDrive does not control your vehicle. It does not unlock, start, move, charge, honk, flash lights, or send commands to your Tesla account or vehicle.

MateDrive is an independently developed, unofficial iOS app. It is not affiliated with, sponsored by, or endorsed by Tesla, Inc., TeslaMate, or any other service provider. Product and service names are used only to describe compatibility; all related trademarks belong to their respective owners.

## Keywords

TeslaMate,Tesla,EV,charging,drives,mileage,battery,widget,vehicle,dashboard

## Support URL

https://youyooo.github.io/MateDrive/

## Marketing URL

Omit this optional field in App Store Connect unless a public MateDrive product page is published.

## Privacy Policy URL

https://youyooo.github.io/MateDrive/privacy.html

## Review Notes

MateDrive requires the reviewer to configure a reachable TeslaMate API server in Settings before data appears. For review, use the public MateDrive synthetic TeslaMate API below. The app is read-only: it reads data from the configured API and never sends vehicle-control commands. The review dataset contains no real user or vehicle data and requires no Tesla account or API credentials.

Recommended review flow:

1. Open Settings.
2. Enter `https://youyooo.github.io/MateDrive/review-demo` as the TeslaMate API base URL.
3. Choose no authentication and leave all credential fields empty.
4. Tap Test Connection and confirm the diagnostic report passes.
5. Leave MateDrive in the background until history sync completes, then return to the dashboard and open Activities, Charges, Drives, Battery, Mileage, Stats, Vehicle Cost Review, Trips, Sentry, and Widget-related views. These views should show cached data immediately while network refresh continues silently.

The review dataset is regenerated daily with recent synthetic dates and is hosted as static content, so write operations are unavailable. Production App Store builds do not embed this URL, local TeslaMate defaults, or reviewer credentials; ordinary users connect only to the TeslaMate server they configure.

## Pre-Submission Verification

Run these checks before uploading a build or screenshots to App Store Connect:

```bash
make preflight
make verify
make release-technical-gate
make app-store-audit
make app-store-screenshots
make app-store-screenshot-audit
```

`make preflight` is the stable local gate for script probes, Simplified and Traditional Chinese localization coverage, simulator-generic app compilation, and XCTest bundle compilation. `make verify` must also pass on a healthy simulator before submission because it exercises real test installation and execution.
`make release-technical-gate` runs the metadata and icon audit, creates an unsigned compile-validation archive at `build/MateDrive.xcarchive`, and verifies the built app and widget identifiers, versions, executables, privacy manifests, and Chinese resources. The signed archive is stored at `build/MateDrive-AppStore.xcarchive`; run `python3 scripts/audit_release_archive.py build/MateDrive-AppStore.xcarchive` after every signed rebuild. Use `docs/release/AppStoreLocalExportOptions.plist` for a local Apple Distribution IPA without upload. `docs/release/AppStoreExportOptions.plist` has an upload destination and must only be used after explicit owner authorization. Exporting or uploading from the command line may require one-time local Keychain authorization for the Apple Distribution private key.
`make app-store-audit` must pass only after this document contains a real support URL, no placeholder submission values, and no local/private server details.
`make app-store-screenshots` creates a dedicated 6.5-inch simulator, launches six deterministic privacy-safe synthetic routes, writes exact `1242x2688` PNG files to `build/app-store-screenshots/zh-Hans`, and runs the screenshot validator. Regenerate them from the final release-candidate source and visually inspect every image before upload; the generated images are drafts, not proof that the corresponding App Store build contains the same source.

Then run a live TeslaMate API smoke test against the exact public review endpoint that will be entered in App Store Connect:

```bash
MATEDRIVE_INTEGRATION_BASE_URL=https://youyooo.github.io/MateDrive/review-demo \
make review-integration-test
```

Use `.matedrive-integration.env.example` as the local template for private development servers; keep the populated `.matedrive-integration.env` file untracked. `make integration-test` remains available for LAN development. Do not submit until `make review-integration-test` confirms public HTTPS/DNS and can read vehicles, status, charge and drive lists/details, battery health, software updates, current charge, and global settings from the exact public review endpoint.

Authenticated integration environments may use `MATEDRIVE_INTEGRATION_API_TOKEN`, `MATEDRIVE_INTEGRATION_BASIC_USERNAME`, and `MATEDRIVE_INTEGRATION_BASIC_PASSWORD` with `MATEDRIVE_INTEGRATION_BASE_URL`. These values are for local verification only. Never commit reviewer server URLs or credentials.

## Demo Account And Server

Provide these values in App Store Connect:

- TeslaMate API base URL: `https://youyooo.github.io/MateDrive/review-demo`
- Authentication: None
- Account credentials: Not required
- Test vehicle data notes: daily-refreshed synthetic Model 3 Performance data covering status, trips, charges, battery health, costs, activities, statistics, places, and software updates.

The endpoint is static and read-only. It contains no VIN, account identity, credentials, private server URL, or real route history. Do not commit real server URLs, tokens, usernames, or passwords to this repository.

The public synthetic endpoint needs no account. If an authenticated review server is ever required, its URL and credentials must be provided privately in App Store Connect review notes and must not be added to this document or the repository.

## Privacy Summary

MateDrive reads data from the TeslaMate server configured by the user. The app stores non-secret settings with UserDefaults and stores API tokens and Basic Auth secrets in Keychain.

MateDrive does not use third-party tracking, does not collect analytics for the developer, and does not transmit vehicle data to a MateDrive-operated backend. When the user explicitly enables iCloud backup, the local database and non-secret settings are stored only in that user's private CloudKit database; Keychain credentials are excluded.

The in-app Settings > Privacy & Local Data page explains these data flows, including Apple map/geocoding and Open-Meteo route-weather coordinate processing. Route weather is off by default and requires one-time explicit consent before one representative precise route coordinate and the drive time are transmitted. The user can revoke future access and independently clear saved route weather, API responses, offline dashboard data, and per-vehicle widget snapshots without deleting server configuration or Keychain credentials.

Data visible in the app may include vehicle status, charging sessions, drive routes, geofence/location-derived labels, software updates, battery health estimates, pricing rules, manually entered charge costs, and widget snapshots. Adjacent-drive grouping is a local presentation feature and does not modify, merge, or delete TeslaMate records. Drive, activity-period recap, battery, achievement and multi-drive trip report images are rendered locally and are sent outside the app only when the user invokes the iOS share sheet. Trip reports omit custom trip names and default-hide exact dates, start/destination, route shape and costs. Battery reports default-hide exact recording dates and the recording-start odometer. Achievement cards default-hide unlock dates, place names and progress details; raw coordinates and related drive IDs are never copied into them. This data stays on the device and the user-configured TeslaMate server unless the user shares it outside the app or explicitly enables private iCloud backup.

## App Privacy Questionnaire Draft

- Data collection by MateDrive developer: No developer-operated backend or analytics collection. Optional backups are stored in the user's private CloudKit database and are not accessible through a MateDrive-operated service. After one-time explicit consent, Open-Meteo receives one representative precise route coordinate and the drive time for weather functionality and may retain request logs for up to 90 days.
- Third-party tracking: No.
- User account creation: No.
- Precise location: Yes, collected by third-party Open-Meteo for app functionality only after the user enables route weather; not linked to the user's identity; not used for tracking.
- Vehicle location displayed from user-configured TeslaMate data: Yes, locally in app views.
- Authentication secrets stored locally: Yes, Keychain.
- Diagnostics sent to developer: No.
- External network communication: User-configured TeslaMate API and weather/map tile services used by the app features.

## Export Compliance

The app declares `ITSAppUsesNonExemptEncryption` as false. It uses standard Apple platform networking and Keychain storage, and does not include custom non-exempt encryption.

## Screenshot Checklist

Generate the fixed six-image first-release draft with `make app-store-screenshots`. The current sequence is Dashboard, Activity, Features, Drive Detail, Charge Detail, and Battery. It uses synthetic data and must not depend on a private TeslaMate server. Then consider these additional manual captures only when they improve the final listing:

- Dashboard with a circular battery gauge and vehicle status.
- Settings with language selector and connection test.
- Charge detail with cost section and chart.
- Drive detail with route and metric cards.
- Drive share-card preview with the default privacy-safe options.
- Activity period-recap preview with exact dates and costs hidden.
- Battery report preview with exact recording dates and recording-start odometer hidden.
- Achievement card preview with unlock dates, place names and progress details hidden.
- Trip report preview with custom name, exact dates, locations, route shape and costs hidden.
- Battery health screen.
- Mileage drilldown.
- Stats screen.
- Vehicle Cost Review screen with recorded-versus-estimated cost and data-quality coverage.
- Trips screen.
- Widget preview.
- Privacy & Local Data showing data flow and local snapshot controls.
- iCloud Backup showing consent, automatic-backup status, cached backup rows, and restore/delete controls.

## CloudKit Release Checklist

- Confirm `iCloud.com.matedrive.ios` is assigned to the App Store app identifier and its provisioning profiles.
- Confirm the deployed Production schema still contains the `MateDriveBackup` record type, all 15 fields, the `recordName` query index, and the `createdAt` sortable index before each release.
- Verify upload, list, restore, delete-one, and delete-all on a signed physical-device build using a non-production test vehicle account.
- Confirm a restore does not include Keychain credentials and that the app asks the reviewer to recheck server authentication afterward.

Before upload, verify screenshots show MateDrive branding, no local/private server URLs, no real secrets, no unrelated simulator debug overlays, and no stale legacy branding.

## Physical Device Install

Prerequisites:

- The iPhone has Developer Mode enabled and trusts this Mac.
- The selected Xcode release supports the iOS version installed on the phone.
- Xcode Settings > Accounts contains an Apple ID with an Apple Development certificate and a development team.

Then install and launch a Debug build with:

```bash
MATEDRIVE_DEVELOPMENT_TEAM=YOUR_TEAM_ID make install-device
```

Set `MATEDRIVE_DEVICE_ID` as well when more than one available iPhone is connected. The script builds both the app and widget with automatic provisioning, installs the resulting app, and launches `com.matedrive.ios`.
