# Manual Test Checklist

Run against an iOS Simulator before release:

```bash
make verify
make build
```

For a real local TeslaMate API smoke test:

```bash
MATEDRIVE_INTEGRATION_BASE_URL=http://127.0.0.1:3030 \
MATEDRIVE_INTEGRATION_API_TOKEN=... \
make integration-test
```

If the API uses Basic Auth instead of a bearer token:

```bash
MATEDRIVE_INTEGRATION_BASE_URL=http://127.0.0.1:3030 \
MATEDRIVE_INTEGRATION_BASIC_USERNAME=... \
MATEDRIVE_INTEGRATION_BASIC_PASSWORD=... \
make integration-test
```

For repeated local testing, put the same variables in `.matedrive-integration.env`.
This file is ignored by git and must not be committed:

```bash
MATEDRIVE_INTEGRATION_BASE_URL=http://127.0.0.1:3030
MATEDRIVE_INTEGRATION_API_TOKEN=...
# Or:
# MATEDRIVE_INTEGRATION_BASIC_USERNAME=...
# MATEDRIVE_INTEGRATION_BASIC_PASSWORD=...
```

The command-line probe validates that the vehicle list returns a usable vehicle id and enough metadata for the dashboard name/image path. Missing model, exterior color, or wheel type is reported before the XCTest integration target runs.

Manual simulator install:

```bash
make test
xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
open MateDroidIOS.xcodeproj
```

## First Launch And Settings

## TeslaMate Capability Profile

- [ ] Connection Test displays the detected TeslaMateApi version.
- [ ] A server with `api_version = unknown` and `mt_api_version = 2.4.1` displays version `2.4.1`.
- [ ] Server Statistics, Vehicle Cost Review, Unified Activities, Battery History, and Drive Insights show independent states.
- [ ] HTTP 404 displays Unavailable and does not break existing dashboard, drive, or charge pages.
- [ ] HTTP 401/403 displays authentication failure and does not label endpoints as unsupported.
- [ ] A temporary network failure retains the last successful profile with its checked time.
- [ ] Cloudflare Access secrets remain blank after reopening Settings and never appear in logs.
- [ ] Enter API Access Key and Secret Key for MyTesS API 2.5+, test the connection, relaunch, and confirm both fields remain blank while the saved Keychain credentials still work.
- [ ] With MyTesS API 2.6, confirm Vehicle Cost Review is Available; with an older API, confirm only this feature is Unavailable while existing Stats still works.

- [ ] First launch without settings shows `SettingsView`.
- [ ] Enter primary TeslamateApi URL and save.
- [ ] Enter secondary URL, API token, Basic Auth username/password, invalid certificate toggle, and currency; relaunch and verify non-secret settings persist.
- [ ] On devices set to Mainland China, Hong Kong, Taiwan and United States regions, select Follow Device Region and confirm costs use CNY/¥, HKD/HK$, TWD/NT$ and USD/$ respectively; then select a manual ISO currency and confirm it remains selected after relaunch.
- [ ] On Hong Kong and Taiwan devices, select Traditional Chinese and confirm Settings, Dashboard and Widget use Traditional Chinese while Follow Device Region continues to use HKD/HK$ or TWD/NT$ independently.
- [ ] Switch Follow TeslaMate, Metric and Imperial units; confirm Dashboard, Widget, Drives, Drive Detail, Charges, Battery, Stats, Trips, Places and environment charts change together without changing the selected language.
- [ ] Confirm token and Basic Auth password are restored from Keychain behavior, not plain UserDefaults.
- [ ] Run Connection Test from Settings and confirm vehicles, status, settings, drive detail, charge detail, and battery health checks produce readable Chinese messages.
- [ ] After Connection Test, export the diagnostics text file and confirm it includes app/API versions, capability states, check statuses and messages; confirm it does not contain the configured server URL or IP, authentication values, vehicle identifiers, or coordinates.
- [ ] In History Data Quality, include an incomplete drive whose distance is absent; confirm the report labels the sum as known affected distance and shows distance coverage instead of treating the missing distance as zero. With all incomplete-drive distances present, confirm the concise affected-distance wording remains.
- [ ] For a vehicle whose TeslaMate history starts at high mileage, confirm Battery labels the API percentage or range ratio as recording-period retention, does not present the best-observed API capacity/range as a new-car baseline, preserves the earliest detected odometer as older data appears, and opens the per-vehicle calibration fields directly.
- [ ] Confirm Connection Test reports the last 30 days of environment data points, underlying sample count, temperature coverage, and tire-pressure coverage; missing samples or an unavailable endpoint must produce a warning rather than a pass.
- [ ] Open Activities, switch between list and map, filter each activity type, search a start or destination address, open drive/charge/parking markers, and load another page on the map.
- [ ] In Activities Period Summary, confirm partial drive distance, driving energy, or charged energy displays `≥` with localized record coverage; if every matching record lacks a metric, confirm it displays `--` instead of zero. Explicit API zero values must remain visible as zero.
- [ ] Tap Load Complete History and confirm the coverage label changes from partial to complete; verify the server's broken total-page metadata does not cause an endless load.
- [ ] Switch All Time, Last 7 Days, Last 30 Days, and This Year; combine with type and location filters and verify record counts, distance, charged energy, and driving energy update together.
- [ ] From a parking activity with valid coordinates, open Standby Drain and confirm the server period/radius, parking count, range loss, signed 24-hour battery change, rates, refresh, and unavailable state.
- [ ] Open Place Insights and confirm all server pages load, role/confidence labels and smart-place metrics match TeslaMateApi, missing charge costs are explicit, server mode does not invent parking cost, search/map work, and Standby Drain opens; verify activity-history fallback on an older server.
- [ ] During an active charge, leave Current Charge open for over 30 seconds; confirm the refresh timestamp advances, power and battery curves update, and touching a sample shows its power, SoC, voltage, and temperature without widening the page.
- [ ] On Dashboard, confirm all available tyre pressures match TeslaMate status, Chinese uses bar, English uses psi, missing sensors show `--`, and any soft warning is highlighted red.
- [ ] When status has coordinates but no geofence, confirm Dashboard resolves and caches a readable address, displays up to two lines without overlap, and falls back to coordinates when Apple geocoding is unavailable.
- [ ] Open Achievements from Dashboard and confirm unlocked/total counts match TeslaMate, tier progress is readable, unknown server IDs do not appear as raw codes, and unlocked tiers can open their related drive.
- [ ] Open Environment History from Dashboard, switch 7/30/90-day and one-year ranges, and confirm hourly/daily temperature, four-wheel pressure, pressure-change confidence, and temperature/consumption data match TeslaMateApi without invented zero samples.
- [ ] Open Standby Hotspots from Dashboard, switch list/map, confirm locations are ranked by server range loss, invalid coordinates are omitted, signed 24-hour battery change is not converted to an absolute value, and each hotspot opens its radius-based detail analysis.
- [ ] Open Commute Routes from Dashboard, verify summary totals and route ranking, then inspect the route map, duration range, regen/braking/elevation metrics, and speed distribution chart.
- [ ] Confirm achievement details display missing hours, visited places, distance/temperature/time units, and extreme-value drive links when the server provides them.
- [ ] Trigger connection/load failure and confirm the app surfaces a readable error.

## Sync And Dashboard

- [ ] Launch with a configured server and confirm the dashboard loads at least one car.
- [ ] Switch cars when multiple cars exist.
- [ ] Pull to refresh and use the toolbar refresh button.
- [ ] Confirm battery, charging, lock, Sentry, inside/outside temperatures, history, model, exterior color, wheel type, and car image match TeslaMate data.
- [ ] After a successful refresh, stop TeslaMateApi and relaunch; confirm the latest battery, range, location, odometer, software version, temperatures, lock, Sentry, and tyre pressures remain visible with an explicit offline timestamp and network error.
- [ ] Change to a different configured server or vehicle while offline and confirm no snapshot from the previous server/vehicle is displayed; snapshots older than 30 days must not load.
- [ ] Sync a drive whose distance or duration is absent, then inspect the local summary cache and confirm the fields remain NULL rather than zero. Upgrade a database at schema version 14 and confirm existing drive summaries survive migration to version 15 before the next sync.
- [ ] Open Palette and verify light/dark swatches for white, black, silver, blue, red, Quicksilver, Stealth Grey, Ultra Red, Midnight Cherry, and fallback colors.

## Charges

- [ ] Open Current Charge while charging; verify AC/DC label, power, SoC, limit, elapsed time, and not-charging state.
- [ ] Open Charges and verify date, cost, and type filters.
- [ ] In Charges cost filters, confirm Has Cost includes every recorded price including explicit zero, Free includes only explicit zero-cost sessions, and Missing Cost includes only records whose price is absent. Verify all labels switch correctly in every bundled language.
- [ ] With missing charge energy, confirm Charges preserves the row, displays `--` on that record, shows `≥` for known energy totals with localized coverage, calculates Average from known-energy records only, and keeps unknown-energy rows when short records are hidden. Explicit zero energy must remain visible as zero.
- [ ] Confirm short charges are hidden when the setting is disabled.
- [ ] Open Charge Detail and inspect map marker, address fallback, power curve, peak power, average power, voltage, temperature, duration, efficiency, and cost.
- [ ] Open a charge with incomplete telemetry and confirm missing energy, power, voltage, temperature, duration, efficiency, and SOC display `--` rather than invented zero values; verify an explicitly recorded zero remains visible as zero.
- [ ] Open Compare Charges and verify comparable DC rows, sort modes, base marker, and empty state.
- [ ] Create two pricing rules for the same location with adjacent effective-date ranges and different prices; verify charging sessions on each side of the boundary use the correct historical price.
- [ ] From Charges, open Pricing Preview; confirm missing API costs are selected by default, existing API costs require explicit selection, manual local costs are excluded, and unmatched/already-correct counts are accurate.
- [ ] Write a mixed batch containing one missing cost and one explicit replacement; confirm every record shows its old/new cost and success or failure independently, then use Roll Back and verify successful writes restore their original API values, including an originally missing value.
- [ ] Relaunch after a pricing batch and verify its audit history still appears only for the same vehicle, including rule, old/new costs, write result, and rollback result.
- [ ] Change the current app currency after recording a pricing batch; verify historical audit rows still use the currency saved with that batch.
- [ ] Export the pricing audit CSV and verify it contains batch, charge, rule, cost, write, and rollback evidence without addresses, coordinates, server URLs, tokens, or credentials.
- [ ] Switch to German, Spanish, Italian, and Catalan in turn; open pricing rules and a charge detail, then verify rule editor fields, cost sources, charger types, empty states, and actions use the selected language rather than English placeholders.
- [ ] Edit only the current price rule and confirm charging sessions outside its effective-date range keep their previous calculated cost.

## Drives

- [ ] Open Drives and verify date/distance filters, totals, list rows, and short-drive filtering.
- [ ] With missing drive distance, duration, or efficiency, confirm Drives preserves the record, displays `--` on the affected row, shows `≥` known subtotals with localized coverage, and excludes unknown distance from distance-category filters. Explicit zero values must remain distinguishable from missing values.
- [ ] Open Drive Detail and inspect route map, start/end markers, speed, power, elevation, outside temperature, efficiency, and duration.
- [ ] Open a drive with incomplete summary and position telemetry; distance, speed, power, elevation, SOC and duration must display `--` instead of invented zero values across Drive Detail, metric drill-down, comparison and CSV, while explicit zero values remain visible and exportable.
- [ ] Open Recent Driving Map from Dashboard, switch map/list, confirm the API point coverage text, separate route colors, map framing and Drive Detail links; verify the page states that the API window is not complete history.
- [ ] Confirm drive charts use clock-time axes rather than equal-width bars: speed is a blue line, power uses an orange line with green regeneration points, elevation is an area chart, battery heating is marked, and inside/outside temperatures use separate lines.
- [ ] Switch between Chinese/metric and English/imperial; verify chart values convert consistently and undated samples are omitted instead of being plotted at invented times.
- [ ] In Drive Detail, classify a drive as commute/personal/business/road trip/custom, add a custom label and multiline note, relaunch, and confirm the annotation persists only for that vehicle and drive.
- [ ] Export a Drive Detail CSV and verify drive ID, timestamps, addresses, distance, speed, energy, efficiency, classification, label, note, and preferred distance unit; confirm commas, quotes, and multiline notes open correctly in a spreadsheet.
- [ ] Confirm Open-Meteo weather along the route appears when coordinates are available.
- [ ] Open Compare Drives and verify same-route comparisons and empty state.

## Analytics

- [ ] Open Battery and verify current/new capacity, loss, range, loading, and unavailable states.
- [ ] With battery health, capacity, range, SOC and efficiency fields absent, confirm Battery shows calibration required and `--`/Unavailable rather than a fallback `100%`, `0 kWh`, `0 km` or default efficiency. Restore real API fields and confirm their explicit zero/nonzero values remain distinguishable.
- [ ] Confirm Battery Data Quality shows a 0-100 score, level, capacity/range sample counts, history span, qualifying charges, and explicitly says it measures estimate stability rather than physical cell health.
- [ ] For a vehicle whose TeslaMate recording began at high mileage, confirm the page does not present recording-period retention as lifetime health and requests a verified new-car capacity or range reference when needed.
- [ ] Enter a verified new-car usable capacity for one vehicle, confirm Battery shows Manual Capacity as the source and calculates current capacity divided by that baseline; switch vehicles and confirm the calibration does not carry over.
- [ ] Clear the usable-capacity baseline and confirm the app falls back to a verified rated-range baseline only when present, otherwise it labels late-start TeslaMate percentages as recording-period retention.
- [ ] Open Mileage and drill down year -> month -> day -> drive.
- [ ] With one drive distance absent, confirm Mileage shows the known subtotal with `≥` and localized distance coverage, calculates Average from known-distance drives only, and shows `--` for the missing individual drive. Complete periods must not show the incomplete marker.
- [ ] Open Updates, switch range, and verify monthly counts, newest/oldest, longest gap, and current version.
- [ ] Open Stats, switch year, and verify totals, records, AC/DC split, and country navigation.
- [ ] In a period with missing drive distance/duration or charging energy, confirm Stats displays the known subtotal with `≥` and localized data coverage rather than treating missing records as zero; Longest Drive must ignore records without distance. A complete period and an authoritative server all-time distance must not show the incomplete marker.
- [ ] In Stats, confirm Vehicle Cost equals charge plus parking cost only when parking history is complete and every parking record matches a rule; otherwise it must display Incomplete with an explanatory unmatched/partial message.
- [ ] From Stats, open Vehicle Cost Review and switch 7/30/90-day and one-year ranges; confirm the server returns the selected RFC3339 range and an equal-length previous period.
- [ ] Confirm Recorded Spend and Estimated Use Cost remain separate, missing charge/parking prices display as incomplete rather than zero, explicit free records count as recorded zero, and comparison percentages appear only when the API marks them eligible.
- [ ] Open a top or missing charging-cost record from Vehicle Cost Review and confirm it opens the matching Charge Detail; verify location rankings and cost coverage match the API 2.6 response.
- [ ] On MyTesS API 2.6, edit one Charge Detail cost and confirm the screen reports that it synced to the TeslaMate API cost ledger; refresh Vehicle Cost Review and confirm its total and missing-cost coverage reflect the edit.
- [ ] With an older API or the server temporarily offline, edit one Charge Detail cost and confirm it is marked as saved on this device only and remains available in local charge summaries.
- [ ] From Stats, open Driving Records and confirm all server extremes, dates, units and icons; drive-linked records open Drive Detail while daily aggregate records do not show a disclosure indicator.
- [ ] Open Countries Visited, sort by every mode, and open Regions Visited.
- [ ] For a country/region containing records with missing distance or charging energy, confirm rows show `≥` known subtotals plus localized distance/energy coverage; complete rows must not show the marker.
- [ ] Open Where Was I for driving, charging, and parked timestamps; verify map, state, metrics, and related links.

## Vehicle Costs

- [ ] In Settings, add and edit parking rules using address or coordinate radius; verify free minutes, billing increment, hourly rate, fixed fee, session cap, monthly fee, priority, enable/disable, and deletion.
- [ ] Confirm a monthly parking rule is counted once per rule and calendar month, while hourly rules round billable time up by the configured increment after free time.
- [ ] Open Activities and Place Insights; verify parking cost uses the selected currency code and unmatched parking records are reported rather than silently treated as free.

## Trips

- [ ] Open Trips and verify automatically detected trips require at least two real drives, at least one DC charge, and at least 300 km total distance.
- [ ] Confirm micro-drives under 1 km are ignored in trip detection.
- [ ] Create a manual trip, add legs, save, relaunch, and confirm the saved trip persists.
- [ ] Open Trip Detail and inspect summary, legs, charge stops, timeline, route, country stats, and saved-trip edits.

## Sentry, Widgets, Notifications

- [ ] Open Sentry History and verify current session, alert count, last six days, past alerts, location fallback, and empty state.
- [ ] Request notification authorization and deliver charging, Sentry, and tyre-pressure test content from the debug/test harness.
- [ ] Trigger `com.matedrive.ios.sync` from Xcode's Background Tasks debugger and confirm history sync completes, the selected vehicle/widget snapshot refreshes, eligible notifications are evaluated once, and an expired task reports failure without duplicate completion.
- [ ] Add the MateDrive Widget and confirm it displays read-only car name, battery, range, status, lock, temperatures, location, and car image fallback.
- [ ] Confirm no widget or notification path exposes Tesla command actions.

## Localization And Accessibility

- [ ] Run the app once with English, Italian, Spanish, Catalan, German, Simplified Chinese, and Traditional Chinese simulator languages.
- [ ] Select English, Italian, Spanish, Catalan, German, Simplified Chinese, and Traditional Chinese from the in-app language menu and confirm Settings plus primary dashboard/detail labels update immediately.
- [ ] In German, Spanish, Italian and Catalan, open Battery and Connection Test; confirm capacity/range labels, calibration guidance, server capabilities and availability states do not fall back to English.
- [ ] In German, Spanish, Italian and Catalan, verify Dashboard live status, Trips loading/empty/actions, and the Widget description do not fall back to English.
- [ ] In German, Spanish, Italian and Catalan, open Current Charge, Compare Charges, Compare Drives and Updates; confirm loading, empty, sorting and summary labels do not fall back to English.
- [ ] In German, Spanish, Italian and Catalan, change Charges date/cost/type filters and Drives date/distance filters; confirm every menu option updates in the selected language without changing the underlying filter result.
- [ ] In German, Spanish, Italian and Catalan, verify Countries/Regions sort menus, Software Updates install-age text, and Trip Detail timeline labels use the selected language, including labels containing dynamic numbers.
- [ ] In German, Spanish, Italian and Catalan, trigger charging, Sentry and low-tyre-pressure local notifications; confirm battery/limit, alert location, wheel position and threshold text use the selected language while vehicle names and measurements remain unchanged.
- [ ] In German, Spanish, Italian and Catalan, open Drive Detail and edit its classification; confirm classification choices, direct/reconstructed/unavailable energy-source explanations and metric-card accessibility hints use the selected language.
- [ ] Confirm Settings, Dashboard, Charges, Drives, Battery, Mileage, Updates, Stats, Vehicle Cost Review, Countries, Regions, Where Was I, Trips, Sentry, Widget, notifications, loading, and error labels are localized.
- [ ] Confirm drive/trip terminology remains distinct: English `drive/trip`, Italian `tragitto/viaggio`, Spanish `trayecto/viaje`, Catalan `trajecte/viatge`, German `Fahrt/Trip`, Simplified Chinese `行程/路程`, Traditional Chinese `行程/路程`.
- [ ] Use VoiceOver on Dashboard, Palette, Charges, Drive Detail, Trips, Sentry, and Widget; confirm image, refresh, settings, compare, route, and status controls have useful labels.

## Privacy And Local Data

- [ ] Open Privacy & Local Data and verify the Chinese explanation accurately describes direct TeslaMate access, Keychain storage, no developer collection, offline snapshots, and explicit sharing.
- [ ] Clear offline dashboard snapshots and confirm their count reaches zero while server settings, Keychain credentials, pricing rules, trips, and unrelated UserDefaults remain intact.
