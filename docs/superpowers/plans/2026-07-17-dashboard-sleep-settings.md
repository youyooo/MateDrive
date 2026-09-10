# Dashboard, Sleep Duration, and Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add accurate cached-first sleep duration, redesign Home vehicle-overview cards, remove the Features vehicle heading, and make Settings reliably return to the complete configuration root.

**Architecture:** Sleep calculation is a pure domain component backed by optional server state-history intervals and local SQLite persistence. Dashboard summaries are read from existing local drive/charge stores and injected into `DashboardViewModel`, while all UI renders cached values during refresh. Features and Settings navigation changes stay isolated to their existing presentation and root-navigation types.

**Tech Stack:** Swift 6, SwiftUI, Foundation, MapKit, SQLite, XCTest, XcodeGen, iOS 18+

## Global Constraints

- Only explicit `asleep` intervals count as sleep; `offline`, `unknown`, and parking intervals never count.
- Home, Activities, and detail destinations must display cached data without waiting for foreground network requests.
- Latest Drive, Latest Charge, and Total Odometer appear in that order.
- Card accents are system blue, battery green, and system amber; cards use an 8-point corner radius and no gradients.
- The standard TeslaMateAPI may not expose state history; historical sleep must show unavailable instead of an estimate when the optional endpoint is absent.
- Existing credentials stay in Keychain and all existing settings remain intact.
- Existing dashboard snapshots continue to decode after optional fields are added.

---

## File Map

**Create**

- `MateDriveApp/Core/Domain/SleepDuration.swift`: interval normalization, current-sleep calculation, period boundaries, and localized duration components.
- `MateDriveApp/Core/API/Models/VehicleStateHistoryModels.swift`: flexible decoding for the optional state-history response.
- `MateDriveApp/Core/Persistence/Records/SleepIntervalRecord.swift`: persistence record.
- `MateDriveApp/Core/Persistence/Stores/SleepIntervalStore.swift`: idempotent interval upsert and range query.
- `MateDriveApp/Features/Dashboard/DashboardSummaryProvider.swift`: local latest-drive/latest-charge provider.
- `MateDriveApp/Features/Dashboard/DashboardOverviewCards.swift`: the three full-width cards.
- `MateDriveTests/Domain/SleepDurationTests.swift`
- `MateDriveTests/API/VehicleStateHistoryModelsTests.swift`
- `MateDriveTests/Persistence/SleepIntervalStoreTests.swift`
- `MateDriveTests/Features/DashboardSummaryProviderTests.swift`

**Modify**

- `MateDriveApp/Core/API/TeslamateAPI.swift`: optional `vehicleStateHistory` request.
- `MateDriveApp/Core/API/TeslaMateCapability.swift`: add `stateHistory` capability.
- `MateDriveApp/Core/API/TeslaMateCapabilityService.swift`: probe and persist optional capability state.
- `MateDriveApp/Features/Settings/TeslaMateCapabilityPresentation.swift`: show sleep-history availability.
- `MateDriveApp/Core/Persistence/Migration.swift`: bump database version from 19 to 20.
- `MateDriveApp/Core/Persistence/Migrations.swift`: create `sleep_intervals` and indexes.
- `MateDriveApp/Core/Sync/AppDataPreloader.swift`: refresh and cache optional state history.
- `MateDriveApp/Features/Dashboard/DashboardViewModel.swift`: current state, current sleep, and cached summaries.
- `MateDriveApp/Features/Dashboard/DashboardSnapshotStore.swift`: optional backward-compatible fields.
- `MateDriveApp/Features/Dashboard/DashboardView.swift`: replace compact strip with card stack and show current sleep.
- `MateDriveApp/Features/Dashboard/DashboardOverviewPresentation.swift`: create latest-drive, latest-charge, and odometer presentations.
- `MateDriveApp/Features/Activities/ActivitiesViewModel.swift`: cached sleep-period summary state.
- `MateDriveApp/Features/Activities/ActivitiesView.swift`: period selector and sleep summary.
- `MateDriveApp/Features/FeatureHub/FeatureHubView.swift`: remove single-car model heading.
- `MateDriveApp/Features/FeatureHub/FeatureHubPresentation.swift`: remove unused vehicle name.
- `MateDriveApp/App/RootTabNavigation.swift`: reset Settings path when entering the tab.
- `MateDriveApp/App/RootView.swift`: inject local stores/providers and route tab selection through navigation state.
- `MateDriveApp/Resources/Localizable.xcstrings`: new labels and empty states.
- Existing focused tests under `MateDriveTests/Features` and `MateDriveTests/App`.

---

### Task 1: Pure Sleep-Duration Domain

**Files:**
- Create: `MateDriveApp/Core/Domain/SleepDuration.swift`
- Create: `MateDriveTests/Domain/SleepDurationTests.swift`

**Interfaces:**
- Produces: `SleepInterval`, `SleepDurationPeriod`, `SleepDurationSummary`, and `SleepDurationCalculator`.
- Consumes: `Date`, `Calendar`, and `CarStatus.state/stateSince` values supplied by later tasks.

- [ ] **Step 1: Write failing tests for current sleep**

```swift
func testCurrentSleepRequiresAsleepState() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertEqual(
        SleepDurationCalculator.currentDuration(
            state: "asleep",
            stateSince: Date(timeIntervalSince1970: 6_400),
            now: now
        ),
        3_600
    )
    XCTAssertNil(SleepDurationCalculator.currentDuration(state: "offline", stateSince: now.addingTimeInterval(-600), now: now))
}

func testFutureSleepStartIsRejected() {
    let now = Date(timeIntervalSince1970: 10_000)
    XCTAssertNil(SleepDurationCalculator.currentDuration(state: "asleep", stateSince: now.addingTimeInterval(1), now: now))
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/SleepDurationTests test
```

Expected: compile failure because `SleepDurationCalculator` is not defined.

- [ ] **Step 3: Implement the core types**

```swift
public struct SleepInterval: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
}

public enum SleepDurationPeriod: String, CaseIterable, Identifiable, Sendable {
    case sinceCharge, today, week, month
    public var id: String { rawValue }
}

public struct SleepDurationSummary: Equatable, Sendable {
    public let period: SleepDurationPeriod
    public let duration: TimeInterval?
    public let isAvailable: Bool
}

public enum SleepDurationCalculator {
    public static func currentDuration(state: String?, stateSince: Date?, now: Date) -> TimeInterval? {
        guard state?.lowercased() == "asleep", let stateSince, stateSince <= now else { return nil }
        return now.timeIntervalSince(stateSince)
    }

    public static func total(intervals: [SleepInterval], from start: Date, to end: Date) -> TimeInterval {
        guard start < end else { return 0 }
        let clipped = intervals.compactMap { interval -> SleepInterval? in
            let lower = max(interval.start, start)
            let upper = min(interval.end, end)
            return lower < upper ? SleepInterval(start: lower, end: upper) : nil
        }.sorted { $0.start < $1.start }
        var merged: [SleepInterval] = []
        for interval in clipped {
            guard let last = merged.last, interval.start <= last.end else {
                merged.append(interval)
                continue
            }
            merged[merged.count - 1] = SleepInterval(start: last.start, end: max(last.end, interval.end))
        }
        return merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }
}
```

- [ ] **Step 4: Add overlap, clipping, and calendar-boundary tests**

Test day, ISO week, month, and since-charge boundaries, including intervals crossing midnight and overlapping intervals that must not double count.

- [ ] **Step 5: Run focused tests**

Expected: all `SleepDurationTests` pass.

- [ ] **Step 6: Commit**

```bash
git add MateDriveApp/Core/Domain/SleepDuration.swift MateDriveTests/Domain/SleepDurationTests.swift
git commit -m "feat: add accurate sleep duration calculations"
```

---

### Task 2: Optional State-History API and Capability

**Files:**
- Create: `MateDriveApp/Core/API/Models/VehicleStateHistoryModels.swift`
- Create: `MateDriveTests/API/VehicleStateHistoryModelsTests.swift`
- Modify: `MateDriveApp/Core/API/TeslamateAPI.swift`
- Modify: `MateDriveApp/Core/API/TeslaMateCapability.swift`
- Modify: `MateDriveApp/Core/API/TeslaMateCapabilityService.swift`
- Modify: `MateDriveApp/Features/Settings/TeslaMateCapabilityPresentation.swift`
- Test: `MateDriveTests/API/APIClientTests.swift`

**Interfaces:**
- Produces: `VehicleStateHistoryResponse`, `VehicleStateInterval`, and `TeslamateAPI.vehicleStateHistory(carId:startDate:endDate:)`.
- Consumes: `SleepInterval` from Task 1.

- [ ] **Step 1: Write flexible decoding tests**

```swift
func testDecodesStateHistoryEnvelope() throws {
    let json = #"{"data":{"states":[{"state":"asleep","start_date":"2026-07-17T00:00:00Z","end_date":"2026-07-17T02:00:00Z"}]}}"#
    let result = try JSONDecoder.teslamate.decode(VehicleStateHistoryResponse.self, from: Data(json.utf8))
    XCTAssertEqual(result.intervals.count, 1)
    XCTAssertEqual(result.intervals[0].state, "asleep")
}
```

Also test a top-level array/envelope variant, null end times, malformed dates, and non-asleep states.

- [ ] **Step 2: Run tests and verify failure**

Expected: compile failure for undefined response types.

- [ ] **Step 3: Implement response models and conversion**

```swift
public struct VehicleStateInterval: Decodable, Equatable, Sendable {
    public let state: String
    public let startDate: String
    public let endDate: String?

    public func sleepInterval(now: Date) -> SleepInterval? {
        guard state.lowercased() == "asleep",
              let start = DomainDateParser.date(from: startDate)
        else { return nil }
        let end = endDate.flatMap(DomainDateParser.date(from:)) ?? now
        return start < end ? SleepInterval(start: start, end: end) : nil
    }
}
```

- [ ] **Step 4: Add API method using the optional endpoint**

```swift
public func vehicleStateHistory(carId: Int, startDate: String, endDate: String) async -> APIResult<[VehicleStateInterval]> {
    let query = [
        URLQueryItem(name: "startDate", value: startDate),
        URLQueryItem(name: "endDate", value: endDate)
    ]
    return await decode(
        VehicleStateHistoryResponse.self,
        endpoint: endpoint("api/v1/cars/\(carId)/states", queryItems: query)
    ) { $0.intervals }
}
```

HTTP 404/405 remains an ordinary capability-unavailable result. Do not fall back to parking data.

- [ ] **Step 5: Add `TeslaMateCapability.stateHistory` and a visible Settings row**

Probe `api/v1/cars/{id}/states` with a one-day bounded query. Mark 404/405 as unsupported, 2xx as supported, and network/auth failures as unknown/unavailable rather than unsupported.

- [ ] **Step 6: Run API, capability, diagnostic, and localization tests**

Expected: focused suites pass and standard status behavior is unchanged.

- [ ] **Step 7: Commit**

```bash
git add MateDriveApp/Core/API MateDriveApp/Features/Settings/TeslaMateCapabilityPresentation.swift MateDriveTests/API
git commit -m "feat: detect optional vehicle state history"
```

---

### Task 3: Persist and Preload Sleep Intervals

**Files:**
- Create: `MateDriveApp/Core/Persistence/Records/SleepIntervalRecord.swift`
- Create: `MateDriveApp/Core/Persistence/Stores/SleepIntervalStore.swift`
- Create: `MateDriveTests/Persistence/SleepIntervalStoreTests.swift`
- Modify: `MateDriveApp/Core/Persistence/Migration.swift`
- Modify: `MateDriveApp/Core/Persistence/Migrations.swift`
- Modify: `MateDriveApp/Core/Sync/AppDataPreloader.swift`
- Test: `MateDriveTests/Persistence/PersistenceMigrationTests.swift`

**Interfaces:**
- Produces: `SleepIntervalStoring.records(carId:start:end:)` and `upsertAll(_:)`.
- Consumes: state-history models from Task 2.

- [ ] **Step 1: Add migration tests for version 20**

Assert `sleep_intervals` has `car_id`, `start_date`, `end_date`, and a unique `(car_id,start_date,end_date)` key plus a range-query index.

- [ ] **Step 2: Run migration tests and verify failure**

Expected: table is missing and database version remains 19.

- [ ] **Step 3: Add migration 20**

```sql
CREATE TABLE IF NOT EXISTS sleep_intervals (
  car_id INTEGER NOT NULL,
  start_date TEXT NOT NULL,
  end_date TEXT NOT NULL,
  PRIMARY KEY(car_id, start_date, end_date)
);
CREATE INDEX IF NOT EXISTS sleep_intervals_car_range
ON sleep_intervals(car_id, start_date, end_date);
```

Set `DatabaseSchemaVersion.current = 20`.

- [ ] **Step 4: Implement idempotent upsert and overlap range query**

The query predicate is `start_date < requestedEnd AND end_date > requestedStart`, ordered by `start_date ASC`.

- [ ] **Step 5: Add store tests**

Verify duplicate upserts remain one row, different cars stay isolated, and intervals crossing query boundaries are returned.

- [ ] **Step 6: Connect background preload**

Request the current month through now only when `.stateHistory` is supported, normalize explicit asleep intervals, save them, and publish the existing cache revision. A failed optional request must not fail the rest of the preload report.

- [ ] **Step 7: Run persistence and preloader tests**

Expected: focused tests pass, unsupported state history produces zero saved intervals without a sync failure.

- [ ] **Step 8: Commit**

```bash
git add MateDriveApp/Core/Persistence MateDriveApp/Core/Sync/AppDataPreloader.swift MateDriveTests/Persistence MateDriveTests/Sync
git commit -m "feat: cache vehicle sleep intervals"
```

---

### Task 4: Cached Dashboard Summary Provider

**Files:**
- Create: `MateDriveApp/Features/Dashboard/DashboardSummaryProvider.swift`
- Create: `MateDriveTests/Features/DashboardSummaryProviderTests.swift`
- Modify: `MateDriveApp/Features/Dashboard/DashboardViewModel.swift`
- Modify: `MateDriveApp/Features/Dashboard/DashboardSnapshotStore.swift`
- Modify: `MateDriveApp/App/RootView.swift`
- Test: `MateDriveTests/Features/DashboardViewModelTests.swift`

**Interfaces:**
- Produces: `DashboardLatestDrive`, `DashboardLatestCharge`, `DashboardCachedSummary`, and `DashboardSummaryProviding.summary(carId:)`.
- Consumes: `DriveSummaryStore`, `ChargeSummaryStore`, and `SleepIntervalStore`.

- [ ] **Step 1: Write provider tests**

```swift
func testProviderSelectsNewestDriveAndCharge() async throws {
    let summary = await provider.summary(carId: 1)
    XCTAssertEqual(summary.latestDrive?.driveId, 20)
    XCTAssertEqual(summary.latestCharge?.chargeId, 30)
}
```

Add tests for empty stores, vehicle isolation, missing optional values, and sleep summaries since latest completed charge/day/week/month.

- [ ] **Step 2: Run and verify failure**

Expected: compile failure for undefined provider types.

- [ ] **Step 3: Implement provider**

Read both local stores concurrently, select records already sorted descending, derive the latest completed charge cutoff, query sleep intervals for the month boundary through now, and calculate four summaries with Task 1.

- [ ] **Step 4: Extend `DashboardState`**

```swift
public var vehicleState: String?
public var vehicleStateSince: Date?
public var currentSleepDuration: TimeInterval?
public var latestDrive: DashboardLatestDrive?
public var latestCharge: DashboardLatestCharge?
public var sleepSummaries: [SleepDurationPeriod: SleepDurationSummary]
```

Load summaries from SQLite before any API refresh. Recompute current sleep from cached `stateSince` using the injected clock.

- [ ] **Step 5: Extend snapshots with optional fields**

Decode all new fields with `decodeIfPresent`; add a test that an existing version-19 snapshot still decodes and renders.

- [ ] **Step 6: Inject the database-backed provider in `RootView`**

Use `environment.databaseProvider` and do not create a network dependency.

- [ ] **Step 7: Run dashboard tests**

Expected: cached summary is visible before refresh completes; failed API refresh retains summary and current sleep state.

- [ ] **Step 8: Commit**

```bash
git add MateDriveApp/Features/Dashboard MateDriveApp/App/RootView.swift MateDriveTests/Features/DashboardSummaryProviderTests.swift MateDriveTests/Features/DashboardViewModelTests.swift
git commit -m "feat: load dashboard summaries from local cache"
```

---

### Task 5: Vehicle Overview Card UI and Current Sleep Status

**Files:**
- Create: `MateDriveApp/Features/Dashboard/DashboardOverviewCards.swift`
- Modify: `MateDriveApp/Features/Dashboard/DashboardOverviewPresentation.swift`
- Modify: `MateDriveApp/Features/Dashboard/DashboardView.swift`
- Modify: `MateDriveTests/Features/DashboardOverviewPresentationTests.swift`
- Modify: `MateDriveApp/Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `DashboardOverviewCards` and three presentation rows in required order.
- Consumes: `DashboardState` additions from Task 4.

- [ ] **Step 1: Replace presentation tests**

Assert IDs are exactly `["latest-drive", "latest-charge", "odometer"]`; verify drive distance, charge energy/SOC fallback, localized empty states, and destination routes.

- [ ] **Step 2: Run and verify existing tests fail**

Expected: old IDs `["odometer", "drives", "charges"]` do not match.

- [ ] **Step 3: Implement three presentations**

Drive accent is `.blue`, charge accent is `Color(red: 0.10, green: 0.68, blue: 0.32)`, odometer accent is `.orange`. Route latest records directly to `.driveDetail` and `.chargeDetail`; otherwise route to the corresponding list when a car is selected.

- [ ] **Step 4: Implement reusable card layout**

```swift
VStack(alignment: .leading, spacing: 10) {
    HStack {
        Label(item.title, systemImage: item.systemImage)
        Spacer()
        if item.route != nil { Image(systemName: "chevron.right") }
    }
    Text(item.primaryValue)
        .font(.title2.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(item.accent)
    if let subtitle = item.subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
}
.padding(16)
.frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
.overlay(alignment: .leading) { Rectangle().fill(item.accent).frame(width: 3).clipShape(.capsule) }
```

- [ ] **Step 5: Show current sleep in the vehicle status line**

When asleep and a valid start exists, format `Sleeping · 3 h 20 min`; when asleep without a valid start, show `Sleeping`; otherwise retain current status formatting.

- [ ] **Step 6: Run presentation, localization, and build checks**

Run focused tests, `make localization-audit`, and `make build-code`.

- [ ] **Step 7: Commit**

```bash
git add MateDriveApp/Features/Dashboard MateDriveApp/Resources/Localizable.xcstrings MateDriveTests/Features/DashboardOverviewPresentationTests.swift
git commit -m "feat: redesign cached vehicle overview cards"
```

---

### Task 6: Activities Sleep Summary

**Files:**
- Modify: `MateDriveApp/Features/Activities/ActivitiesViewModel.swift`
- Modify: `MateDriveApp/Features/Activities/ActivitiesView.swift`
- Modify: `MateDriveTests/Features/ActivitiesViewModelTests.swift`
- Modify: `MateDriveApp/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: local `SleepIntervalStore` and `SleepDurationSummary`.
- Produces: cached period values for Since Charge, Today, Week, and Month.

- [ ] **Step 1: Add failing view-model tests**

Verify all four periods are exposed, unavailable history remains unavailable, cached values survive a failed activity refresh, and switching periods performs no API request.

- [ ] **Step 2: Run and verify failure**

Expected: missing sleep-summary state.

- [ ] **Step 3: Add cached sleep summary state and provider injection**

Read local summaries during initial cached load. Do not include sleep in existing drive/charge/parking record counts.

- [ ] **Step 4: Add a segmented period control and value row**

Use a segmented picker with four options. Display a localized duration, `No sleep recorded`, or `Server does not provide sleep history`; never display a progress spinner after cached content is visible.

- [ ] **Step 5: Run focused tests and localization audit**

Expected: all tests pass with zero missing localization keys.

- [ ] **Step 6: Commit**

```bash
git add MateDriveApp/Features/Activities MateDriveApp/Resources/Localizable.xcstrings MateDriveTests/Features/ActivitiesViewModelTests.swift
git commit -m "feat: show cached sleep period summaries"
```

---

### Task 7: Simplify Features and Restore Settings Root Behavior

**Files:**
- Modify: `MateDriveApp/Features/FeatureHub/FeatureHubView.swift`
- Modify: `MateDriveApp/Features/FeatureHub/FeatureHubPresentation.swift`
- Modify: `MateDriveTests/Features/FeatureHubPresentationTests.swift`
- Modify: `MateDriveApp/App/RootTabNavigation.swift`
- Modify: `MateDriveApp/App/RootView.swift`
- Modify: `MateDriveTests/App/RootTabNavigationTests.swift`

**Interfaces:**
- Produces: a feature root without a single-car model heading and a Settings-tab entry action that clears retained child paths.

- [ ] **Step 1: Add failing presentation/navigation tests**

Assert a single vehicle does not produce a header, multiple vehicles still produce a picker, and entering Settings from another tab clears a retained `[.palettePreview]` path while preserving the full `SettingsView` root.

- [ ] **Step 2: Run and verify failure**

Expected: existing feature presentation still exposes `vehicleName`; Settings path remains retained.

- [ ] **Step 3: Remove single-car heading**

Delete `vehicleName` from `FeatureHubPresentation`. Render only the segmented picker when `showsVehiclePicker` is true.

- [ ] **Step 4: Add explicit tab-selection handling**

Add `RootNavigationState.selectTab(_:)`; when the selected tab changes to `.settings`, clear `settingsPath`. Bind `TabView` through a `Binding` that calls this method.

- [ ] **Step 5: Verify Settings content remains complete**

Keep all current `SettingsView` sections and the existing iCloud `NavigationLink`; do not move server/authentication fields into the backup child page.

- [ ] **Step 6: Run focused tests and build**

Expected: feature and root-navigation tests pass and Settings opens at the full Form.

- [ ] **Step 7: Commit**

```bash
git add MateDriveApp/Features/FeatureHub MateDriveApp/App/RootTabNavigation.swift MateDriveApp/App/RootView.swift MateDriveTests/Features/FeatureHubPresentationTests.swift MateDriveTests/App/RootTabNavigationTests.swift
git commit -m "fix: simplify features and restore settings root"
```

---

### Task 8: Integration, Simulator QA, and Release Gates

**Files:**
- Modify: `docs/parity/manual-test-checklist.md`
- Modify only as required by failures found in Tasks 1-7.

**Interfaces:**
- Consumes all previous tasks.
- Produces a verified simulator build and release-ready technical result.

- [ ] **Step 1: Regenerate the Xcode project**

Run `make generate` and verify new source/test files are included.

- [ ] **Step 2: Run focused suites together**

Run all sleep, dashboard, activity, feature, navigation, persistence, API, and localization tests. Expected: zero failures.

- [ ] **Step 3: Run the complete suite**

Run `make test`. Expected: zero failures; pre-existing intentionally skipped integration tests remain skipped.

- [ ] **Step 4: Run technical checks**

Run:

```bash
make preflight
make release-technical-gate
```

Expected: localization, privacy, vehicle-image, build-for-testing, archive, and release archive audit all pass.

- [ ] **Step 5: Perform simulator QA**

Launch iPhone 17 / iOS 26.5 and verify:

- Home opens with cached cards and no full-page spinner.
- Card order, colors, empty states, routes, Dynamic Type, light mode, and dark mode.
- Current asleep state updates duration without a network request.
- Activities period switching is immediate.
- Features has no single-car model heading.
- Switching away from and back to Settings returns to the complete configuration root.

- [ ] **Step 6: Update the manual checklist**

Add the verified behaviors and note that historical sleep depends on the optional server state-history capability.

- [ ] **Step 7: Commit verification documentation**

```bash
git add docs/parity/manual-test-checklist.md
git commit -m "docs: add sleep and dashboard verification checks"
```

---

## Self-Review

- Spec coverage: Tasks 1-3 cover accurate sleep data and optional server capability; Tasks 4-5 cover cached Home summaries and visual design; Task 6 covers since-charge/day/week/month display; Task 7 covers Features and Settings; Task 8 covers full verification.
- No parking/offline approximation exists in any task.
- All new persistence and snapshot fields are optional or additive.
- Interface names are consistent across API, persistence, dashboard, and activity tasks.
- The plan contains no deferred implementation gaps.
