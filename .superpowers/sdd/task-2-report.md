# Task 2: Activity Session Reconstruction

## Status

Implemented and committed as `04aeefa feat: reconstruct smart activity sessions`.

## Implementation

- Added stable session-domain models for purpose, classification, charge cost, event references, and sessions.
- Added `ActivitySessionReconstructor` and its configurable 60-minute charge-start, 90-minute departure, and 250-meter clustering thresholds.
- Reconstructs each session from a parking-center record, then conditionally attaches a prior arrival drive, in-stay charges, and a prompt departure drive.
- Requires a shared smallest matching geofence or spatial clustering for every attached event. Home and Work waive only the charge-start grace; departure grace still applies.
- Uses `carId-parkingSourceID` as the stable ID and SHA-256 over sorted `kind-sourceID-startDate-endDate` sources for both initial fingerprints.
- Reuses `ParkingIntervalAnalyzer`, `GeofenceRuleEngine`, `TeslaMateActivity`, `SleepInterval`, and `DomainDateParser`; performs no HTTP work and adds no dependency.
- Missing session metrics and charge costs remain nil. Open parking records remain sessions with `isOpen == true`.

## Tests

`ActivitySessionReconstructorTests` was written before production implementation. It covers arrival-charge-departure grouping, delayed Home charging, open parking, fingerprint stability, duplicate sources, coordinate mismatch, and a non-Home charge source gap.

### RED evidence

1. `make generate`
   - Failed before generation because `xcodegen` is not installed: `xcodegen is required. Install with: brew install xcodegen`.
2. `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDroidIOSTests/ActivitySessionReconstructorTests test`
   - Attempted as required.
   - Blocked before test compilation by the known simulator defect: `AssetCatalogSimulatorAgent` cannot load `CoreGraphics.framework`, then `Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn`.

### GREEN evidence

1. `xcrun swiftc -parse MateDroidIOS/Features/Activities/SmartActivityModels.swift MateDroidIOS/Features/Activities/ActivitySessionReconstructor.swift MateDroidIOSTests/Features/ActivitySessionReconstructorTests.swift`
   - Passed.
2. `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
   - Passed: `** BUILD SUCCEEDED **`.
   - This compiles and links the production reconstructor in the iOS application target.
3. `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS Simulator' ASSETCATALOG_COMPILER_APPICON_NAME= build-for-testing`
   - Attempted as the fallback required by the task.
   - Blocked by the same AssetCatalogSimulatorAgent/CoreGraphics failure before tests could compile or run.
4. `git diff --check` for all four Task 2 files and `xcodebuild -project MateDroidIOS.xcodeproj -list`
   - Passed. The generated Swift file lists include both new production and test sources.

## Files

- `MateDroidIOS/Features/Activities/SmartActivityModels.swift`
- `MateDroidIOS/Features/Activities/ActivitySessionReconstructor.swift`
- `MateDroidIOSTests/Features/ActivitySessionReconstructorTests.swift`
- `MateDroidIOS.xcodeproj/project.pbxproj` (Task 2 registrations only in the staged commit)

## Self-review

- Stable ID intentionally excludes mutable event timings and later departure records.
- Source fingerprints are order-independent and include every attached source event.
- Location matching never treats missing coordinates as a match; a common valid smallest geofence is the only non-distance path.
- The reconstructor uses no network APIs and leaves future classifier and pricing fields unset rather than inventing values.
- The project file staging was limited to eight Task 2 registration lines; unrelated pre-existing project changes remain unstaged.

## Concerns

- Focused XCTest execution is still unverified because the installed iOS 26.5 simulator asset catalog agent fails at launch. The production target compiles successfully, but the tests must be run once that simulator/runtime issue is repaired.
- `make generate` remains unavailable until `xcodegen` is installed. The project source globs will include these files on the next successful generation.

## Post-review Fix

- Added deterministic source ownership while reconstructing parking sessions. Attached drives and charges are claimed once, and each valid unclaimed drive becomes a partial fallback session with stable ID `carId-arrivalDriveID`.
- Fallback sessions retain only the drive reference. Parking metrics and charge cost remain nil, and their quality is partial.
- Departure selection now continues past spatially mismatched candidates until the configured departure grace expires.
- Charges now require parsed start and end timestamps, a closed parking interval, and full containment within that interval.
- Replaced the stable-ID regression with an initially open parking record followed by an updated closed parking record and departure. Added fallback, exclusive-drive ownership, mismatched-departure, and charge-boundary coverage.

## Post-review Verification

1. `xcrun swiftc -parse MateDroidIOS/Features/Activities/SmartActivityModels.swift MateDroidIOS/Features/Activities/ActivitySessionReconstructor.swift MateDroidIOSTests/Features/ActivitySessionReconstructorTests.swift`
   - Passed.
2. `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDroidIOSTests/ActivitySessionReconstructorTests test`
   - Blocked before test compilation by the simulator environment: `Failed to launch AssetCatalogSimulatorAgent via CoreSimulator spawn` and `Testing cancelled because the build failed.`
3. `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
   - Passed: `** BUILD SUCCEEDED **`.
4. `git diff --check` for the updated Task 2 source and test files
   - Passed.
