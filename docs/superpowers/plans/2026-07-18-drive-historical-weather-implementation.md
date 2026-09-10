# Drive Historical Weather Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace route-wide weather sampling with one cached historical-weather snapshot that conditionally powers the drive-detail “Driving Environment” card.

**Architecture:** `WeatherSelection` selects one valid route sample nearest the trip’s temporal midpoint. `WeatherService` checks a persistent `WeatherCache`, coalesces duplicate work, and calls `OpenMeteoAPI` only on a miss; `DriveDetailViewModel` exposes one optional snapshot and `DriveDetailView` inserts the card only when that snapshot exists.

**Tech Stack:** Swift 6.3, Swift Concurrency actors, SwiftUI, XCTest, Open-Meteo Historical Forecast API, JSON file persistence, XcodeGen, xcodebuild.

## Global Constraints

- iOS deployment target remains 18.0.
- Query exactly one historical weather sample per drive load; do not build an along-route list or curve.
- Hide the whole Driving Environment module when no weather result exists.
- Persist only successful historical weather results and reuse them without a repeat network request.
- Preserve smart commute analysis, personal calibration, dashboard vehicle overview, minimum-energy presentation, and all unrelated in-progress workspace changes.

---

### Task 1: Representative Historical Sample

**Files:**
- Modify: `MateDriveApp/Core/Domain/WeatherSelection.swift`
- Test: `MateDriveTests/Domain/WeatherSelectionTests.swift`

**Interfaces:**
- Consumes: `[WeatherRoutePosition]` containing optional coordinate and ISO-8601 time strings.
- Produces: `WeatherSelection.driveEnvironmentPosition(positions:) -> WeatherRoutePosition?`.

- [ ] **Step 1: Write the failing tests** for midpoint-time selection, invalid coordinate rejection, and missing/unparseable timestamp rejection.
- [ ] **Step 2: Run** `xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/WeatherSelectionTests test` and confirm the new API is missing.
- [ ] **Step 3: Implement the selector** by validating with `GeoCoordinateValidator`, parsing with `DomainDateParser`, and minimizing absolute distance from the first/last timestamp midpoint.
- [ ] **Step 4: Re-run the same test command** and require zero failures.

### Task 2: Persistent Success Cache and Single Weather Request

**Files:**
- Modify: `MateDriveApp/Core/Sync/WeatherService.swift`
- Modify: `MateDriveApp/Features/Drives/DriveAPIProvider.swift`
- Test: `MateDriveTests/Sync/WeatherServiceTests.swift`

**Interfaces:**
- Consumes: one representative `WeatherRoutePosition` selected in Task 1.
- Produces: `DriveWeatherServicing.drivingEnvironment(positions:) async -> WeatherPoint?`.
- Produces: `WeatherCaching.load(key:)`, `save(_:key:)`, and persistent `WeatherCache` actor behavior.

- [ ] **Step 1: Write failing tests** proving a drive triggers one API call, a second service instance reads the persisted result without calling the API, concurrent identical requests are coalesced, and failed responses are not cached.
- [ ] **Step 2: Run** `xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/WeatherServiceTests test` and confirm failures are caused by missing cache/single-snapshot behavior.
- [ ] **Step 3: Implement** a bounded JSON-backed actor cache in Application Support, keying four-decimal coordinates plus UTC epoch hour, storing only successful `WeatherPoint` values, and coalescing in-flight requests inside `WeatherService`.
- [ ] **Step 4: Re-run the same test command** and require zero failures.

### Task 3: Open-Meteo Environment Fields

**Files:**
- Modify: `MateDriveApp/Core/API/OpenMeteoAPI.swift`
- Modify: `MateDriveApp/Core/Sync/WeatherService.swift`
- Test: `MateDriveTests/API/OpenMeteoAPITests.swift`

**Interfaces:**
- Extends `WeatherPoint` with optional `windSpeedKph`, `windDirectionDegrees`, `precipitationMillimeters`, and `visibilityMeters`.
- Extends `OpenMeteoHourly` with matching optional arrays while keeping temperature and weather code required for a successful point.

- [ ] **Step 1: Add failing HTTP decoding tests** that inspect the historical endpoint query and verify nearest-hour field mapping.
- [ ] **Step 2: Run** `xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/OpenMeteoAPITests test` and confirm expected failures.
- [ ] **Step 3: Request** `temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation,visibility`, decode optional arrays safely, and attach the nearest-hour values to `WeatherPoint`.
- [ ] **Step 4: Re-run the same test command** and require zero failures.

### Task 4: Conditional Driving Environment UI

**Files:**
- Modify: `MateDriveApp/Features/Drives/DriveDetailViewModel.swift`
- Modify: `MateDriveApp/Features/Drives/DriveDetailView.swift`
- Delete: `MateDriveApp/Features/Drives/WeatherAlongTheWayView.swift`
- Create: `MateDriveApp/Features/Drives/DrivingEnvironmentView.swift`
- Test: `MateDriveTests/Features/DriveDetailViewModelTests.swift`
- Test: `MateDriveTests/Features/DrivingEnvironmentViewTests.swift`

**Interfaces:**
- Replaces `[DriveWeatherPoint]` with `DriveDetailState.drivingEnvironment: DriveWeatherPoint?`.
- Produces `DrivingEnvironmentPresentation` helpers for condition, wind, precipitation, and visibility copy.

- [ ] **Step 1: Write failing tests** that require successful weather to populate one snapshot, failed or unavailable weather to leave it nil, and presentation helpers to omit unavailable optional rows.
- [ ] **Step 2: Run the two focused test classes** and confirm failures reflect the old array/always-visible implementation.
- [ ] **Step 3: Update the view model** to request one snapshot and clear it on a new uncached detail.
- [ ] **Step 4: Replace the old view** with `DrivingEnvironmentView` and guard its insertion with `if let environment = viewModel.state.drivingEnvironment`.
- [ ] **Step 5: Re-run focused tests** and require zero failures.

### Task 5: Regression and Simulator Verification

**Files:**
- Regenerate: `MateDrive.xcodeproj/project.pbxproj`
- Modify only if required by audits: `MateDriveApp/Resources/Localizable.xcstrings`, privacy/release documentation.

**Interfaces:**
- Consumes the complete feature from Tasks 1-4.
- Produces verified simulator and test evidence without changing unrelated behavior.

- [ ] **Step 1: Run** `xcodegen generate` and inspect `git diff --check` plus weather-related diffs.
- [ ] **Step 2: Run focused weather/drive-detail tests**, followed by `make verify` and `make preflight`; require exit code 0 and zero XCTest failures.
- [ ] **Step 3: Build, install, and launch** the app on an available iPhone simulator with `xcrun simctl`; verify the process launches and capture a screenshot/log evidence.
- [ ] **Step 4: Inspect regressions** in smart commute, calibration, dashboard overview, and low-energy presentation tests and require them all to remain green.

### Task 6: Build Number, Signed Archive, and TestFlight

**Files:**
- Modify: `project.yml`
- Regenerate: `MateDriveApp/Info.plist`
- Regenerate: `MateDriveWidget/Info.plist`
- Regenerate: `MateDrive.xcodeproj/project.pbxproj`
- Create: `build/MateDrive-AppStore.xcarchive`

**Interfaces:**
- Consumes a fully verified Release source tree and installed signing credentials.
- Produces the next unique App Store build and Apple upload result.

- [ ] **Step 1: Read the current build number** from `project.yml`, increment it by one consistently for app and widget, then run `xcodegen generate`.
- [ ] **Step 2: Create a signed archive** with `xcodebuild archive -project MateDrive.xcodeproj -scheme MateDrive -configuration Release -destination 'generic/platform=iOS' -archivePath build/MateDrive-AppStore.xcarchive -allowProvisioningUpdates`.
- [ ] **Step 3: Audit the archive** with `python3 scripts/audit_release_archive.py build/MateDrive-AppStore.xcarchive` and verify signing, identifiers, marketing version, build number, privacy manifests, and embedded widget.
- [ ] **Step 4: Export and upload** using the locally configured App Store Connect credentials, preserving Apple’s exact upload request identifier and success/failure message.
- [ ] **Step 5: Re-read project metadata and App Store Connect/upload output** before reporting the final build number and TestFlight processing state.
