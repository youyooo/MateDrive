# Task 6 Report: Cost Source Resolution And Station Learning

## Status

Implemented and committed as `f7ade21b95153e42f303fe6a82d1d110c00f693a`
(`feat: resolve charging cost sources and learn station pricing`).

The commit parent is the requested base `0980a2507f30f7a0fbfead1f9cf991a258cc8f2d`.
Only the eight scoped Task 6 project/source/test files were committed. Existing
unrelated working-tree changes were left untouched.

## Implementation

- Added `ChargeCostResolver` with strict source order: explicit manual cost,
  positive API cost, best user/station rule, then eligible regional official rule.
- Limited regional official pricing to AC sessions in a confirmed Home geofence,
  CNY currency, and an active charger/date match.
- Added service-fee arithmetic. Estimated cost is segmented energy cost plus
  `energy * serviceFeePerKWh` plus session fee. Parking remains a separately
  referenced rule/component and is not added to charging cost.
- Added backward-compatible `parkingFeeRuleID` coding to `ChargePricingRule` and
  `serviceFee` to `ChargePricingEstimate`.
- Added `ChargePricingObservationService`. Session-only confirmation saves the
  manual final cost and observation without creating a rule. Future-at-station
  confirmation also creates an enabled, priority-100, 150-meter station-learned
  rule scoped to charger and time.
- Station keys prefer a matched geofence ID and otherwise use coordinates rounded
  to four decimals plus charger identity.
- Unit price is never derived for missing or zero billed energy. Derivation for
  positive energy subtracts service and fixed fees first.
- Integrated resolution into `ChargeDetailViewModel` while retaining legacy
  visible pricing metadata when no new provenance applies. Explicit user changes
  remain authoritative over background-derived values.

## TDD And Verification

- RED: the first focused type-check failed because `ChargeCostResolver` and
  `ChargeCostResolutionInput` did not yet exist.
- Focused Swift parse passed for all seven changed Swift source/test files.
- Focused generic iOS Simulator `build-for-testing` passed for
  `ChargeCostResolverTests`, `ChargeDetailViewModelTests`, and
  `ChargePricingRuleTests`. The command excluded the pre-existing broken
  `ActivitySessionReconstructorTests.swift` and asset catalog processing.
- Generic iOS device build passed with code signing disabled.
- `python3 scripts/test_audit_regional_tariffs.py`: 17 tests passed.
- `python3 scripts/audit_regional_tariffs.py --today 2026-07-18`: passed for all
  31 regional entries (1 verified tariff, 30 entries without a tariff).
- Scoped staged diff check passed.
- `/opt/homebrew/bin/xcodegen generate` completed. The committed project-file
  delta was narrowed to the 12 registrations for the two new production files
  and one new test file.

## Runtime And Environment Limits

- Runtime XCTest did not complete. One simulator could not boot `launchd_sim`;
  an already-booted simulator attempt then hung before an XCTest process began.
- The first unexcluded test build was blocked by existing argument-order compile
  errors in `ActivitySessionReconstructorTests.swift`.
- A separate clean exported-tree generic build was blocked by the local asset
  compiler's system-policy signature denial. Its focused build also exposed
  clean-HEAD references to `HTTPResponseCache` and `ActivitiesStateCache`, whose
  implementations currently exist only in unrelated dirty workspace changes.
- Regional official currency matching is intentionally CNY because the existing
  regional tariff catalog is CNY and `ChargePricingRule` has no currency field.

## Committed Files

- `MateDroidIOS.xcodeproj/project.pbxproj`
- `MateDroidIOS/Features/Charges/ChargeCostResolver.swift`
- `MateDroidIOS/Features/Charges/ChargeDetailViewModel.swift`
- `MateDroidIOS/Features/Charges/ChargePricingObservationService.swift`
- `MateDroidIOS/Features/Charges/ChargePricingRule.swift`
- `MateDroidIOSTests/Features/ChargeCostResolverTests.swift`
- `MateDroidIOSTests/Features/ChargeDetailViewModelTests.swift`
- `MateDroidIOSTests/Features/ChargePricingRuleTests.swift`

## Review Repair: 2026-07-18

### Status

All Important review findings were repaired and committed as `bd0b547`
(`fix: repair charging tariff resolution`). The repair was staged with index-only
versions for files that also contained unrelated work; those unrelated working-tree
changes remain unstaged.

### Repairs

- Added backward-compatible residential tariff region, currency, and station-key
  metadata. Charge detail now obtains regional authority only from the bundled
  catalog for the configured region and charge start instant; forged official
  settings rules remain excluded.
- Enforced explicit currency matching and complete regional provenance while
  retaining legacy nil-currency user-rule behavior and the Home plus AC fallback
  gate.
- Serialized confirmations in an actor, replaced prior learned station rules by
  station/charger/currency, preserved user rules, and added compensating restoration
  for covered observation, override, and settings persistence failures.
- Tightened minute, currency, energy, and sample validation. Zero billed energy can
  still produce a fixed session fee; accepted sampled energy cannot exceed billed
  energy, and service fees use the same billed total.
- Applied Shanghai calendar semantics only to official regional tariffs. User and
  learned rules use the timestamp offset, including UTC `Z`, for date and time
  applicability.
- Preserved editor provenance, parking, currency, and station metadata, and kept a
  manual save visible when it occurs before charge context is loaded.

### Verification Evidence

- Focused Swift parse passed for the changed production and test files.
- Focused generic iOS Simulator `build-for-testing` passed for the four tariff and
  charge-detail suites with the pre-existing broken
  `ActivitySessionReconstructorTests.swift` excluded.
- `python3 scripts/test_audit_regional_tariffs.py`: 17 tests passed.
- `python3 scripts/audit_regional_tariffs.py --today 2026-07-18`: passed for all 31
  catalog records.
- Scoped diff whitespace checks passed before commit.

### Remaining Environment Limit

Runtime XCTest on the booted simulator hung during test-session finalization before
producing XCTest results and was terminated. No further validation was started after
the stop request. Compensation is deliberately best effort across separate stores;
the injected one-step failure paths restore all known state, without claiming
distributed atomicity if a rollback write itself also fails.
