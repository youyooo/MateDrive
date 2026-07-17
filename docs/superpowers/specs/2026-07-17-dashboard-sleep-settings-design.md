# MateDrive Dashboard, Sleep Duration, and Settings Design

Date: 2026-07-17
Status: Proposed for implementation

## 1. Goals

This iteration has four connected goals:

1. Add accurate sleep-duration data for the current sleep interval, since the last completed charge, today, this week, and this month.
2. Simplify the Features root screen by removing the prominent vehicle-model heading.
3. Restore the complete data configuration experience in Settings while keeping iCloud Backup as one settings destination rather than the entire settings experience.
4. Replace the compact dashboard overview strip with three cached-first, full-width summary cards in this order: latest drive, latest charge, total odometer.

The implementation must preserve the existing cached-first interaction model. Opening Home, Features, Settings, Activities, or a detail page must not wait for a new network request when local data already exists.

## 2. Dashboard Information Architecture

The Home screen keeps its current upper structure:

1. App navigation title and refresh action.
2. Vehicle name, software version, and current vehicle state.
3. Battery/range ring and tyre-pressure layout.
4. Vehicle location map.
5. Vehicle Overview.

Vehicle Overview becomes a vertical stack of three full-width cards:

1. Latest Drive
2. Latest Charge
3. Total Odometer

The previous three-column odometer, drive-count, and charge-count strip is removed. Drive and charge counts remain available in their feature pages and are not treated as the primary Home summary.

## 3. Vehicle Overview Card Design

All cards use the same visual grammar:

- Full-width layout with an 8-point continuous corner radius.
- System secondary background, with no decorative gradient and no nested cards.
- A small leading SF Symbol, a short label, an optional timestamp, and a trailing chevron when the card is actionable.
- One large primary value with monospaced digits where appropriate.
- One compact secondary row for supporting metrics.
- Stable minimum height and fixed internal spacing so missing values do not cause layout jumps.
- Dynamic Type, VoiceOver labels, high contrast, and dark mode are supported.
- Accent colors apply only to the icon, main value, and a thin leading indicator. Body text remains semantic primary or secondary text.

### 3.1 Latest Drive

Accent: system blue.

Primary value: distance, for example `26.5 km`.

Supporting data, when available:

- Start time or relative date.
- Duration.
- Net energy consumed or efficiency.
- Start and end place names in one compact route line.

The card opens the cached drive detail for the latest drive. If the detail record is not available yet, it opens the Drives list focused on the latest summary rather than showing a blocking loader.

### 3.2 Latest Charge

Accent: battery green.

Primary value: energy added, for example `32.4 kWh`. If energy is unavailable, the battery-level change becomes primary, for example `28% -> 80%`.

Supporting data, when available:

- Start or completion time.
- Battery-level change.
- Charge location.
- Cost in the configured currency.

The card opens the cached charge detail for the latest charge. An active charge may use the Current Charge destination, but the card never waits for a status refresh before becoming visible.

### 3.3 Total Odometer

Accent: system amber.

Primary value: the latest known total odometer in the configured distance unit.

Supporting data:

- Last cached update time.
- Optional distance since the last completed charge when that value can be derived from cached records without estimation.

The card opens the Mileage screen.

### 3.4 Empty and Partial States

Cards are always present after a vehicle is selected. Missing records show concise placeholders such as `No drive recorded` or `No charge recorded`; they do not show an indefinite progress indicator. A cache refresh updates the visible values in place.

## 4. Sleep Duration

### 4.1 Definitions

Sleep time only includes intervals explicitly reported as vehicle state `asleep`.

- `offline`, `unknown`, parked, disconnected, or missing telemetry must not be counted as sleep.
- The current sleep interval starts at `CarStatus.stateSince` only when `CarStatus.state == asleep`.
- Invalid or missing timestamps show `Sleeping` without inventing a duration.
- Historical intervals are clipped to the requested period boundary before summing.

### 4.2 User-Facing Data

The vehicle status line on Home shows the current continuous interval, for example `Sleeping · 3 h 20 min`.

Activities gains a Sleep Duration summary with these periods:

- Since Charge: from the end time of the latest completed charge through now.
- Today: local calendar day.
- Week: the user's local calendar week.
- Month: the user's local calendar month.

The formatter uses localized hour and minute labels and does not depend on metric or imperial units.

### 4.3 Data Source and Accuracy

Current sleep duration uses the existing cached status payload containing `state` and `stateSince`.

Historical totals require explicit vehicle-state intervals from the TeslaMate-compatible server. The client should consume a dedicated state-history capability when available and cache normalized sleep intervals locally. It must not approximate historical sleep from parking records.

When the server lacks state history:

- Current sleep remains available from status.
- Historical period values show an unavailable-data state.
- The connection capability report identifies that sleep history is unavailable.

### 4.4 Local Persistence

Normalized sleep intervals are stored by car ID with start and end timestamps. Upserts are idempotent, overlapping intervals are merged for display calculations, and open intervals are only extended from trusted current status data.

Period summaries read the local database first. Background synchronization requests newer intervals and publishes a cache revision after saving them.

## 5. Features Screen

The large vehicle-model heading is removed from the Features root screen.

- A single configured vehicle shows feature sections immediately below the navigation title.
- Multiple vehicles retain a compact segmented vehicle picker without an additional model heading.
- Removing the heading does not alter the shared selected-vehicle state.

## 6. Settings Screen

Settings remains the complete configuration root, not an iCloud-only page. Its information order is:

1. Data Connection: primary and secondary server addresses.
2. Authentication: selected authentication method and its credentials.
3. Connection Test and detected server capabilities.
4. Local History Sync and data quality.
5. Preferences: language, units, and currency.
6. Battery Calibration.
7. Charge Pricing.
8. Notifications and Privacy.
9. iCloud Backup as a navigable row.

Opening iCloud Backup pushes a child page. Returning from that page always reveals the full Settings form. Selecting the Settings tab from another tab shows the Settings root rather than a retained backup-only destination.

Saved credentials remain in Keychain. Existing server, authentication, pricing, calibration, language, unit, and sync settings are preserved.

## 7. Cached-First Data Flow

Home must not create direct foreground network dependencies for the new cards or sleep summaries.

1. The dashboard reads its existing snapshot immediately.
2. Latest drive and charge summaries are read from the local SQLite stores.
3. Current state and current sleep start are read from the cached status snapshot.
4. Historical sleep totals are read from the local sleep-interval store.
5. The existing background synchronization lifecycle refreshes server data.
6. A cache revision updates visible data without replacing the page with a loading screen.

Manual refresh may request new data, but it keeps all currently visible cached data on screen while refreshing.

## 8. Compatibility and Migration

Dashboard snapshots gain optional fields for the current vehicle state, state start time, latest drive summary, and latest charge summary. Decoding older snapshots must continue to succeed.

The local database migration for sleep intervals is additive. Existing drive, charge, settings, and backup records remain unchanged.

iCloud backup includes the new sleep-interval table through the existing database backup mechanism.

## 9. Testing

Required automated coverage:

- Current sleep calculation for asleep, online, offline, missing, malformed, and future timestamps.
- Period clipping for since-charge, day, week, and month boundaries.
- Overlap merging and prevention of double counting.
- No parking or offline intervals counted as sleep.
- Backward-compatible dashboard snapshot decoding.
- Latest drive and latest charge selection from descending cached records.
- Card presentation with complete, partial, and empty data.
- Feature screen without a vehicle heading and with a multi-vehicle picker.
- Settings root retains all configuration sections and iCloud remains a child destination.
- Localization coverage for all new labels.

Manual verification on phone and simulator:

- Home renders cached cards without a loading overlay in airplane mode.
- Reopening the same drive or charge remains immediate.
- Background sync updates a visible card without navigation interruption.
- Card colors remain legible in light mode, dark mode, increased contrast, and large Dynamic Type.
- Settings never becomes trapped on the iCloud Backup page.

## 10. Acceptance Criteria

The work is complete when:

- Home displays the three cards in the required order with colored key metrics.
- Current sleep duration is accurate when the vehicle is asleep.
- Since-charge, today, week, and month sleep totals are accurate when server state history is available and explicitly unavailable otherwise.
- Features no longer emphasizes the vehicle model.
- Settings exposes the complete data configuration and backup experience.
- Existing cached data remains visible during every refresh.
- Focused tests, the complete test suite, localization audit, and release technical gate pass.
