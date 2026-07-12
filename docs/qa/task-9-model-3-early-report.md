# Task 9 Report: Early Model 3 Vehicle Art

## Status

Implemented only the `model-3-early` generation slice as the reviewed
`model-3-early-base-pearl-white-aero-18` asset. Model years 2017 through 2020,
the early trim aliases, 18-inch Aero aliases, and Pearl White aliases resolve to
the exact reviewed asset. Model year 2021 remains on the declared
`model-3-refresh` legacy fallback.

## Generation And Processing

- Built-in imagegen prompt: `2017-2020 pre-refresh Model 3 body, chrome window
  trim and bright flush handles, Pearl White Multi-Coat, factory pre-refresh
  18-inch Aero wheel covers, neutral production brakes, right-facing fixed
  left-front 15-degree studio view, chroma-key background for transparent
  1536x768 delivery, no spoiler, plate, text, or watermark.`
- Generated chroma-key source:
  `tmp/imagegen/model-3-early-pearl-white-source.png` (1774x887 RGB), SHA-256
  `e582de51aee034d0e6eaa7a0175942e588d5d12de5ab4e256defdced15032927`.
- The standard image-generation chroma helper produced
  `tmp/imagegen/model-3-early-pearl-white-transparent.png` (1774x887 RGBA),
  SHA-256
  `7c23f98c424bc5810d0dfa28bdb7e4a93ad1f02ba321c53e26cf4f7be6434883`.
  Both intermediates remain untracked and are not bundled.
- Controller-inspected final:
  `tmp/imagegen/vehicle_model-3-early_base_pearl-white_aero-18.png`. It was
  independently inspected at original resolution and copied byte-for-byte to
  the catalog resource without changing pixels.
- Source-final and shipped SHA-256:
  `faeb4a511d0b3838ad0fcba8cc4071710a6cc4ab95e9e4c7383eb2d5e8c8464f`.

## RED And GREEN

The bundled catalog and resolver tables were added before the PNG or catalog
record. They cover the inclusive 2017/2020 bounds, `rwd`, `long range`, and
`performance` trim aliases, `W38B`, `aero18`, and `pinwheel18` Aero aliases,
`PPSW` and `pearlwhite`, and the 2020/2021 generation boundary.

Runtime XCTest could not start because installed CoreSimulator `1051.54.0` is
older than Xcode's required `1051.55.0`. A temporary Foundation harness executed
the production decoder/resolver against the unchanged catalog and failed with
exit 133:

```text
Precondition failed: expected reviewed early Model 3 asset, got legacy-model-3-early
```

After adding the reviewed record and exact PNG, the same harness passed. The
2020 case resolves reviewed/exact while 2021 still resolves
`legacy-model-3-refresh` with fallback confidence.

## Image Review

- PNG: 1536x768 RGBA, alpha extrema 0...255, no embedded image metadata.
- Allowed chunks only: `IHDR`, `IDAT`, `IEND`.
- Alpha bounds: `(202, 148, 1364, 607)`, normalized to
  `(0.1315, 0.1927, 0.8880, 0.7904)`; baseline `0.7904`.
- Current validator edge ratios: opacity-weighted low-alpha `0.011262 < 0.02`;
  paired high-opacity `0.005620 < 0.01`.
- `tmp/imagegen/model-3-early-light-dark-review.jpg` was inspected at 100%.
  Both composites have a clean silhouette without a continuous matte or rim;
  the shadow is contained and there is no scene, plate, text, or watermark.
- Full-resolution review passed the early headlamps/fascia, chrome window and
  handle brightwork, pre-refresh five-sector 18-inch Aero covers, neutral brake
  hardware, PPSW Pearl White finish, and locked right-facing perspective.
- Official Tesla 2017-2023 owner/service references were used only to check the
  exterior, PPSW paint, and pre-refresh Aero wheel specification. No reference
  imagery was copied into the repository.

## Display Checks

**Actual simulator screenshot matrix: DEFERRED until CoreSimulator is updated.**
A static pixel matrix reproduced the shipped `CarImageView` geometry (`2.2`
stable aspect ratio, `scaledToFit`, dashboard display scale `1.18`, clipped
frame):

| Device | Screen profile | Rendered alpha bounds | Result |
| --- | --- | --- | --- |
| iPhone SE (3rd generation) | 375x667 pt at 2x | `(78, 47, 687, 287)` in 750x341 px | Nonblank and contained; 81.2% frame width |
| iPhone 17 | 402x874 pt at 3x | `(126, 75, 1105, 462)` in 1206x548 px | Nonblank and contained; 81.1% frame width |
| iPhone 17 Pro Max | 440x956 pt at 3x | `(138, 82, 1209, 506)` in 1320x600 px | Nonblank and contained; 81.2% frame width |

The static matrix does not replace the deferred actual simulator screenshots.

## Remaining Task 9 Scope

This commit intentionally does not add or approve `model-3-refresh`,
`model-3-refresh-performance` variants beyond the existing Task 8 asset,
`model-3-highland`, `model-3-highland-performance`, or any Model Y generation.
Their geometry masters, wheel variants, colors, tests, review rows, and screenshot
matrices remain independent future Task 9 generation commits. Legacy fallbacks
remain declared for every unreviewed combination.

## Gates

```text
python3 scripts/test_validate_vehicle_images.py                 PASS (50 tests)
python3 scripts/validate_vehicle_images.py                      PASS
make test-scripts                                               PASS
make vehicle-privacy-audit                                      PASS
make localization-audit                                         PASS (429 keys, 0 findings)
make app-store-technical-audit                                  PASS (0 blockers)
Foundation resolver harness                                     PASS
built MateDrive.app catalog/resolver harness                    PASS (22 assets)
focused generic build-for-testing                               PASS (arm64 and x86_64)
```

The build copied the reviewed PNG into both `MateDrive.app` and
`MateDriveWidget.appex`; the two processed bundle copies have the same SHA-256.

## Concerns

- Runtime XCTest and the actual dashboard simulator screenshot matrix remain
  unavailable until CoreSimulator is updated from `1051.54.0` to `1051.55.0`.
- The source is AI-generated. Automated validation cannot independently prove
  factory geometry beyond the documented human review and official-reference
  comparison.

## Review Remediation

The follow-up review found that manual catalog consumers still used raw asset
order. Because the declared early legacy fallback precedes the reviewed asset,
the picker preview and wheel thumbnail showed `m3_PPSW_W38B.png`, `save()`
persisted `legacy-model-3-early`, and an older override without `assetID` could
not be restored.

Tests were added before production changes for the bundled picker preview,
wheel thumbnail, saved asset ID, nil-`assetID` restoration in forward and
reversed catalog order, and contradictory early wheel evidence. A macOS
Foundation/SwiftUI harness compiled the production picker view-model source and
observed the expected RED with exit 133:

```text
Precondition failed: preview selected CarImages/m3_PPSW_W38B.png
```

`VehicleImageCatalog` now owns asset precedence. For one configuration key it
selects a reviewed asset first and otherwise returns only the generation's
declared legacy fallback. A requested missing asset ID remains invalid, while a
requested same-key legacy ID upgrades to its reviewed replacement. The picker,
override restoration and migration, and resolver exact/manual selection all use
the catalog policy instead of relying on JSON order.

The early resolver table now also covers model year 2020, early `performance`
trim evidence, and refresh-only wheel `W32D`. It retains `model-3-early` and the
reviewed Aero asset, reports inferred confidence with evidence
`model, year, explicitTrim, color, default`, emits
`reportedWheelContradictsFactoryTrim`, and does not expose the raw wheel value.

Review-remediation verification:

```text
focused picker/override/resolver generic build-for-testing    PASS
production picker/override/resolver harness                   PASS
python3 scripts/test_validate_vehicle_images.py                PASS (50 tests)
python3 scripts/validate_vehicle_images.py                     PASS
make test-scripts                                              PASS
make vehicle-privacy-audit                                     PASS
make localization-audit                                        PASS (429 keys, 0 findings)
make app-store-technical-audit                                 PASS (0 blockers)
plutil -lint MateDroidIOS.xcodeproj/project.pbxproj            PASS
```

Runtime XCTest and actual simulator screenshots remain blocked by the existing
CoreSimulator `1051.54.0` versus Xcode-required `1051.55.0` mismatch.
