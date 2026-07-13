# MateDrive App Store Submission

This file is the local source of truth for App Store Connect copy and review notes. Keep it aligned with the shipped app name, privacy manifest, screenshots, and TeslaMate integration behavior before each release.

## App Name

MateDrive

## Submission Status

Technical archive ready. GitHub Pages deployment, the temporary reviewer TeslaMate server, signing, TestFlight validation, and App Store distribution permission must be completed before submission. The support and privacy pages in `docs/support/index.html` and `docs/support/privacy.html` must be published before submission.

## Subtitle

TeslaMate dashboard for iPhone

## Promotional Text

Track your TeslaMate vehicle data, charging history, drives, trips, battery health, widgets, and read-only notifications from a native iOS app.

## Description

MateDrive is a native iOS companion for TeslaMate. Connect it to your own TeslaMate API server to view vehicle status, charging sessions, drives, mileage, trips, software updates, battery health, location history, widgets, and read-only notifications.

MateDrive is designed for owners who already run TeslaMate and want a focused mobile dashboard. The app reads your TeslaMate data, stores your server settings locally, keeps authentication secrets in Keychain, and does not send your vehicle data to a MateDrive-operated service.

Key features:

- Read-only dashboard with battery, charging, lock, Sentry, temperature, range, and vehicle image status.
- Charging history with manual cost overrides, regional and time-segment pricing rules, protected batch API writeback and rollback, persistent vehicle-scoped audit history, privacy-safe CSV audit export, AC/DC comparisons, power curves, and cost summaries.
- Drive details with route maps, speed, power, elevation, efficiency, weather samples, and comparison tools.
- Mileage, statistics, countries and regions visited, software updates, and battery health analysis.
- Trip detection and manually saved trips.
- Home screen widget and local notifications for read-only status updates.
- Regional cost formatting with automatic device currency, manual ISO currency selection, and independent TeslaMate/metric/imperial units.
- In-app language selection for Simplified Chinese, Traditional Chinese, English, German, Spanish, Italian, and Catalan.

MateDrive does not control your vehicle. It does not unlock, start, move, charge, honk, flash lights, or send commands to your Tesla account or vehicle.

## Keywords

TeslaMate,Tesla,EV,charging,drives,mileage,battery,widget,vehicle,dashboard

## Support URL

https://youyooo.github.io/MateDrive/

## Marketing URL

Omit this optional field in App Store Connect unless a public MateDrive product page is published.

## Privacy Policy URL

https://youyooo.github.io/MateDrive/privacy.html

## Review Notes

MateDrive requires the reviewer to configure a reachable TeslaMate API server in Settings before live data appears. The app is read-only and does not require Tesla account credentials.

Recommended review flow:

1. Open Settings.
2. Enter the provided TeslaMate API base URL.
3. Enter the provided API token or Basic Auth credentials if required.
4. Tap Test Connection and confirm the diagnostic report passes.
5. Return to the dashboard and open Charges, Drives, Battery, Mileage, Stats, Vehicle Cost Review, Trips, Sentry, and Widget-related views.

If no live TeslaMate server is provided for review, use the debug simulator build only for internal verification. Production App Store builds must not embed local TeslaMate defaults or reviewer credentials.

## Pre-Submission Verification

Run these checks before uploading a build or screenshots to App Store Connect:

```bash
make preflight
make verify
make release-technical-gate
make app-store-audit
```

`make preflight` is the stable local gate for script probes, Simplified and Traditional Chinese localization coverage, simulator-generic app compilation, and XCTest bundle compilation. `make verify` must also pass on a healthy simulator before submission because it exercises real test installation and execution.
`make release-technical-gate` runs the metadata and icon audit, creates an unsigned compile-validation archive at `build/MateDrive.xcarchive`, and verifies the built app and widget identifiers, versions, executables, privacy manifests, and Chinese resources. Create the final signed archive with the App Store distribution team in Xcode before upload, then run `make archive-audit` against that artifact as well.
`make app-store-audit` must pass only after this document contains a real support URL, no placeholder submission values, and no local/private server details.

Then run a live TeslaMate API smoke test against the exact temporary review server that will be entered in App Store Connect:

```bash
MATEDRIVE_INTEGRATION_BASE_URL=https://review-server.example \
MATEDRIVE_INTEGRATION_API_TOKEN=... \
make integration-test
```

If the review server uses HTTP Basic Auth instead of a bearer token:

```bash
MATEDRIVE_INTEGRATION_BASE_URL=https://review-server.example \
MATEDRIVE_INTEGRATION_BASIC_USERNAME=... \
MATEDRIVE_INTEGRATION_BASIC_PASSWORD=... \
make integration-test
```

Do not submit until `make integration-test` can read vehicles, status, charge and drive lists/details, battery health, software updates, current charge, and global settings from that review server.

## Demo Account And Server

Provide these values in App Store Connect only when a temporary review server is available:

- TeslaMate API base URL: provided privately in App Store Connect review notes.
- Authentication: provide either a temporary API token or temporary Basic Auth credentials privately in App Store Connect.
- Test vehicle data notes: describe the populated review vehicle and expected dashboard state in App Store Connect.

Do not commit real server URLs, tokens, usernames, or passwords to this repository.

Never commit reviewer server URLs or credentials. Revoke temporary access after review.

## Privacy Summary

MateDrive reads data from the TeslaMate server configured by the user. The app stores non-secret settings with UserDefaults and stores API tokens and Basic Auth secrets in Keychain.

MateDrive does not use third-party tracking, does not collect analytics for the developer, and does not transmit vehicle data to a MateDrive-operated backend.

The in-app Settings > Privacy & Local Data page explains these data flows, including Apple map/geocoding and Open-Meteo route-weather coordinate processing, and lets the user clear all offline dashboard snapshots without deleting server configuration or Keychain credentials.

Data visible in the app may include vehicle status, charging sessions, drive routes, geofence/location-derived labels, software updates, battery health estimates, pricing rules, manually entered charge costs, and widget snapshots. This data stays on the device and the user-configured TeslaMate server unless the user shares it outside the app.

## App Privacy Questionnaire Draft

- Data collection by MateDrive developer: No.
- Third-party tracking: No.
- User account creation: No.
- Precise location collected by developer: No.
- Vehicle location displayed from user-configured TeslaMate data: Yes, locally in app views.
- Authentication secrets stored locally: Yes, Keychain.
- Diagnostics sent to developer: No.
- External network communication: User-configured TeslaMate API and weather/map tile services used by the app features.

## Export Compliance

The app declares `ITSAppUsesNonExemptEncryption` as false. It uses standard Apple platform networking and Keychain storage, and does not include custom non-exempt encryption.

## Screenshot Checklist

Capture screenshots after connecting to a populated TeslaMate server:

- Dashboard with vehicle image and status.
- Settings with language selector and connection test.
- Charge detail with cost section and chart.
- Drive detail with route and metric cards.
- Battery health screen.
- Mileage drilldown.
- Stats screen.
- Vehicle Cost Review screen with recorded-versus-estimated cost and data-quality coverage.
- Trips screen.
- Widget preview.
- Privacy & Local Data showing data flow and local snapshot controls.

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
