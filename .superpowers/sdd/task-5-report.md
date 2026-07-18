# Task 5 Report: Versioned Regional Residential Tariff Catalog

## Catalog coverage

- 31 mainland ISO 3166-2 region records, exactly matching the task list, with no duplicates.
- 1 verified record: CN-43 Hunan, containing the mandatory historical residential EV tariff dated 2024-07-01 through 2025-06-30.
- 30 records marked `noVerifiedDedicatedTariff`, each with an empty `tariffs` array. No numeric values were inferred for these regions.
- The catalog is a bundled JSON resource only. The implementation performs no network access or runtime update behavior.

## Files

- `MateDroidIOS/Features/Charges/RegionalChargingTariff.swift`
- `MateDroidIOS/Resources/RegionalChargingTariffs.json`
- `MateDroidIOSTests/Features/RegionalChargingTariffTests.swift`
- `scripts/audit_regional_tariffs.py`
- `scripts/test_audit_regional_tariffs.py`
- `Makefile`
- `project.yml`
- `MateDroidIOS.xcodeproj/project.pbxproj`

## Verification

| Command | Result |
| --- | --- |
| `make generate` | Initially failed because `/opt/homebrew/bin` was absent from `PATH`; no project code failure. |
| `PATH=/opt/homebrew/bin:$PATH make generate` | Passed. |
| `python3 scripts/test_audit_regional_tariffs.py` | Passed: 6 tests. |
| `python3 scripts/audit_regional_tariffs.py --today 2026-07-18` | Passed: 31 records, 1 verified, 30 no verified dedicated tariff. |
| `make regional-tariff-audit` | Passed with the same 31-record result. |
| `xcrun swiftc -parse MateDroidIOS/Features/Charges/RegionalChargingTariff.swift MateDroidIOSTests/Features/RegionalChargingTariffTests.swift` | Passed. |
| `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | Passed. The app compiled, linked, and included `RegionalChargingTariffs.json`. |
| Focused `RegionalChargingTariffTests` simulator test | Attempted before and after implementation. Blocked before test execution by the local `AssetCatalogSimulatorAgent` / CoreSimulator code-signature failure while compiling `Assets.xcassets`. |
| `PATH=/opt/homebrew/bin:$PATH make test-build` | Attempted; blocked by the same simulator asset-catalog environment failure. |

## Concerns

- Simulator test execution remains unavailable on this machine because the iOS 26.5 CoreSimulator asset-catalog agent cannot load CoreGraphics due to a code-signature policy failure. This is independent of the catalog code; a generic iOS app build succeeded.
- The catalog intentionally has no current numeric tariffs. Hunan's required pilot is historical and resolves only within its inclusive effective range. Numeric entries for other regions should be added only with an official HTTPS source, document identifier, verification date, CNY currency, and exact effective dates.
