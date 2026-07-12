# MateDrive Vehicle Image Catalog Implementation Plan

> **Required sub-skill:** Execute this plan with `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`. Use `superpowers:test-driven-development` for every behavior change and `superpowers:verification-before-completion` before claiming completion.

**Goal:** Replace filename-based vehicle image guessing with a versioned, explainable catalog that correctly matches all first-phase production Tesla passenger vehicles, starting with the user's 2022 Model 3 Performance.

**Architecture:** A bundled JSON catalog is decoded and validated behind a provider protocol. A pure resolver consumes a privacy-safe descriptor and returns one `VehicleImageResolution`; the dashboard, offline snapshot, picker, and widget all use that result. Manual overrides are persisted in `AppSettings` by a SHA-256 server fingerprint plus TeslaMate car ID, while existing images remain deterministic fallbacks during phased asset replacement.

**Tech Stack:** Swift 6.3, SwiftUI, XCTest, XcodeGen, Foundation/CryptoKit, Python 3 + Pillow for read-only PNG validation, bundled JSON/PNG resources.

**Design source:** `docs/superpowers/specs/2026-07-13-vehicle-image-catalog-design.md`

## Completion Checklist

- [ ] A synthetic 2022 Model 3 Performance resolves to the 2021-2023 black-trim body and 20-inch Uberturbine asset by default.
- [ ] Every first-phase generation has boundary, trim, fallback, and unknown-data tests.
- [ ] Manual choices survive relaunch and are isolated by server fingerprint and car ID.
- [ ] Dashboard, cached dashboard, picker, and Widget render the same resolved asset.
- [ ] No VIN, server URL, coordinates, or PNG metadata leak into committed fixtures or diagnostics.
- [ ] Every reviewed asset passes automated framing/alpha/catalog checks and human review.
- [ ] Generic placeholder is used for unknown models or invalid catalogs; no blank hero image is possible.
- [ ] Generic simulator test build and runtime XCTest pass; physical-device smoke test is recorded.

## Task 1: Add Privacy Regression Gates

**Files:**
- Create: `scripts/audit_vehicle_fixture_privacy.py`
- Create: `scripts/test_audit_vehicle_fixture_privacy.py`
- Modify: `Makefile`

1. Write script tests using temporary files for a Tesla-shaped VIN (`5YJ...`), URL with credentials, GPS coordinates, and safe synthetic VIN `TSTMODEL3N0000000`. Assert unsafe fixtures fail with file/line only and synthetic data passes.
2. Run `python3 scripts/test_audit_vehicle_fixture_privacy.py`; expect failures because the audit script does not exist.
3. Implement a read-only repository scanner. Scan source, tests, JSON, Markdown, and PNG metadata; exclude `.git`, `.superpowers`, derived/build output, and private integration env files. Never print the matched secret.
4. Add `vehicle-privacy-audit` to `.PHONY`, `preflight`, and `verify`.
5. Run the script tests and `python3 scripts/audit_vehicle_fixture_privacy.py`; expect both exit 0.
6. Commit: `test: prevent vehicle fixture privacy leaks`.

## Task 2: Define And Load The Versioned Catalog

**Files:**
- Create: `MateDroidIOS/Core/Domain/VehicleImageCatalog.swift`
- Create: `MateDroidIOS/Resources/VehicleImageCatalog.json`
- Create: `MateDroidIOSTests/Domain/VehicleImageCatalogTests.swift`
- Modify: `project.yml`

1. Write decoding tests for schema version, unique generation/asset IDs, inclusive year ranges, valid default references, matcher priority ties, and referenced bundled paths. Add malformed in-memory fixtures for every rejection.
2. Define Codable/Sendable records: `VehicleImageCatalog`, `VehicleGenerationRecord`, `VehicleTrimRecord`, `VehicleWheelRecord`, `VehicleColorRecord`, `VehicleAssetRecord`, and `VehicleLegacyFallbackRecord`. Store localization keys, not display text.
3. Define `VehicleImageCatalogProviding` with `func catalog() throws -> VehicleImageCatalog`; implement `BundledVehicleImageCatalogProvider` with one actor-isolated cached decode.
4. Seed JSON with all 20 generation IDs from the design, aliases, year bounds, trim groups, defaults, legacy fallback paths, and `reviewStatus`. Only existing files may be marked `legacy`; no new file may be marked `reviewed` yet.
5. Explicitly list the JSON under application resources in `project.yml`, run `make generate`, and assert it appears in the built app bundle.
6. Run `xcodebuild -project MateDroidIOS.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS Simulator' -only-testing:MateDroidIOSTests/VehicleImageCatalogTests build-for-testing`; expect success.
7. Commit: `feat: add versioned vehicle image catalog`.

## Task 3: Build The Privacy-Safe Resolver Contract

**Files:**
- Create: `MateDroidIOS/Core/Domain/VehicleImageResolver.swift`
- Create: `MateDroidIOSTests/Domain/VehicleImageResolverTests.swift`
- Modify: `MateDroidIOS/Core/Domain/CarImageResolver.swift`

1. Add failing tests for exact, inferred, fallback, manual, conflicting, missing-year, unknown-model, and invalid-override outcomes. The key regression descriptor is model `3`, model year `2022`, trim `P74D`, color `MidnightSilver`, wheel `Pinwheel18CapKit`; assert generation `model-3-refresh-performance`, trim `performance`, wheel `uberturbine-20`, conflict `reportedWheelContradictsFactoryTrim`, and no raw input in evidence text.
2. Introduce:

```swift
public struct VehicleImageDescriptor: Equatable, Sendable {
    let model: String?
    let modelYear: Int?
    let trimBadging: String?
    let wheelType: String?
    let exteriorColor: String?
    let spoilerType: String?
}

public struct VehicleImageResolution: Equatable, Sendable {
    let generationID: String?
    let trimID: String?
    let colorID: String?
    let wheelID: String?
    let assetPath: String
    let presentationScale: Double
    let confidence: VehicleImageConfidence
    let evidence: [VehicleImageEvidence]
    let conflicts: [VehicleImageConflict]
    let usesLegacyAsset: Bool
}
```

3. Implement normalization and the exact evidence order: override, model, year, explicit trim, generation-specific wheel, color, default. Never construct a path from raw input; select an asset record.
4. Derive model year in memory through a separate `VINModelYearDecoder`; return only `Int?`, never include VIN in descriptor/result/logging. Test synthetic year characters including `N = 2022` and invalid/repeating cycles.
5. Make `CarImageResolver` a compatibility facade backed by the new resolver so existing callers/tests remain green during migration.
6. Run the new tests plus `CarImageResolverTests`; expect success.
7. Commit: `feat: resolve vehicle generation with explainable evidence`.

## Task 4: Persist Per-Car Manual Overrides Safely

**Files:**
- Modify: `MateDroidIOS/Features/Settings/AppSettings.swift`
- Modify: `MateDroidIOS/Features/Settings/SettingsStore.swift`
- Modify: `MateDroidIOSTests/Features/SettingsViewModelTests.swift`
- Create: `MateDroidIOSTests/Domain/VehicleImageOverrideTests.swift`

1. Add Codable migration tests proving old settings decode unchanged, valid overrides round-trip, two servers with the same car ID do not collide, and deleted catalog IDs are ignored without deleting the record.
2. Add `VehicleImageOverride` containing catalog generation/trim/color/wheel IDs and optional asset ID, never a VIN or server URL.
3. Add `[String: VehicleImageOverride] vehicleImageOverrides` to `AppSettings`. Build keys as `SHA256(canonicalServerURL) + ":" + carID`; expose methods to read, set, and clear without exposing the digest in UI.
4. Add deterministic migration from current legacy variant/wheel values only when both map unambiguously; otherwise remain automatic.
5. Run settings and override tests; expect success.
6. Commit: `feat: persist vehicle image overrides per car`.

## Task 5: Use One Resolution Across Dashboard, Cache, And Widget

**Files:**
- Modify: `MateDroidIOS/Features/Dashboard/DashboardViewModel.swift`
- Modify: `MateDroidIOS/Features/Dashboard/DashboardSnapshotStore.swift`
- Modify: `MateDroidIOS/Features/Dashboard/DashboardView.swift`
- Modify: `MateDroidIOS/SharedUI/CarImageView.swift`
- Modify: `MateDroidWidget/WidgetDisplayData.swift`
- Modify: `MateDroidWidget/CarStatusWidget.swift`
- Modify: `MateDroidIOSTests/Features/DashboardViewModelTests.swift`
- Modify: `MateDroidIOSTests/Features/WidgetDisplayDataTests.swift`

1. Add failing tests that live state, saved/restored snapshot, and widget payload contain the same asset ID/path and presentation scale for the synthetic 2022 M3P. Add unknown-model and missing-file tests that require the generic placeholder.
2. Add `vehicleImageResolution` to `DashboardState` while keeping computed `carImagePath`/scale compatibility accessors during migration. Pass model year derived from the API car record into the resolver.
3. Persist only non-sensitive resolution output in `DashboardSnapshot`; decode old snapshots with defaults.
4. Extend `WidgetDisplayData` with image path and scale using backward-compatible decoding. Do no catalog resolution inside the extension.
5. Make `CarImageView` verify bundle decode and render `car.fill` in the same stable frame on failure. Keep the dashboard edge-to-edge presentation.
6. Run dashboard, snapshot, and widget tests; expect success.
7. Commit: `feat: share resolved vehicle image across surfaces`.

## Task 6: Connect And Localize The Configuration Picker

**Files:**
- Modify: `MateDroidIOS/Features/Dashboard/DashboardView.swift`
- Rewrite: `MateDroidIOS/Features/Dashboard/CarImagePickerView.swift`
- Modify: `MateDroidIOS/Features/Dashboard/DashboardViewModel.swift`
- Modify: `MateDroidIOS/Resources/Localizable.xcstrings`
- Create: `MateDroidIOSTests/Features/CarImagePickerViewModelTests.swift`

1. Extract a testable `CarImagePickerViewModel`. Test localized generation/trim/wheel names, valid option filtering, confidence explanation, conflict copy, save, reset-to-automatic, and invalid override recovery in English, Simplified Chinese, and Traditional Chinese.
2. Add a dashboard context menu action using an image icon and localized accessibility label to present the picker. Do not rely on undiscoverable long-press alone.
3. Show detected generation/confidence, trim selector, color swatches, wheel thumbnails, conflict note, `Use this configuration`, and `Use automatic match`. The final action calls async `DashboardViewModel.setVehicleImageOverride(...)`, persists settings, re-resolves, updates snapshot/widget, and dismisses.
4. Replace all hard-coded picker English strings such as `Model Y Legacy` and wheel names with catalog localization keys in every supported app language; audit fallback behavior.
5. Run picker tests and `make localization-audit`; expect success.
6. Commit: `feat: add localized vehicle image configuration`.

## Task 7: Add Automated Asset And Catalog Validation

**Files:**
- Create: `scripts/validate_vehicle_images.py`
- Create: `scripts/test_validate_vehicle_images.py`
- Create: `docs/vehicle-image-review.md`
- Modify: `Makefile`

1. Add fixture-based tests for wrong dimensions, missing alpha, excessive transparent-edge contamination, bounding-box drift, baseline drift, duplicate asset keys, missing files, unreferenced files, PNG metadata, and reviewed assets lacking a review record.
2. Implement validation using Pillow. Enforce 1536x768 masters for new assets, catalog-declared optimized legacy dimensions, normalized non-transparent bounds, baseline tolerance, alpha edges, stripped metadata, and exact catalog references.
3. Document a human checklist with generation, lamps/fascia, brightwork, wheel, caliper, paint, angle, scale, shadow, edge, reviewer, date, and source-reference notes.
4. Add `vehicle-image-audit` to `preflight`, `verify`, and `app-store-technical-audit`.
5. Run validator tests and validator against the repository; expect exit 0.
6. Commit: `test: validate vehicle image catalog assets`.

## Task 8: Produce And Ship The 2022 Model 3 Performance Reference

**Files:**
- Create: `MateDroidIOS/Resources/CarImages/vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20.png`
- Modify: `MateDroidIOS/Resources/VehicleImageCatalog.json`
- Modify: `docs/vehicle-image-review.md`
- Modify: `MateDroidIOSTests/Domain/VehicleImageResolverTests.swift`

1. Use the image-generation tool with the locked prompt: 2021-2023 Model 3 Performance body, black exterior trim, Midnight Silver Metallic, factory 20-inch Uberturbine wheels, red calipers, right-facing fixed left-front 15-degree studio view, transparent 1536x768 canvas, no text/plate/watermark. Do not download competitor or Tesla website art into the bundle.
2. Inspect the generated source at original resolution. Reject wrong chrome trim, Highland lamps, wheel shape, calipers, perspective, clipping, or badge/text artifacts.
3. Remove chroma-key background only with the approved helper, strip metadata, and run `python3 scripts/validate_vehicle_images.py`.
4. Display the asset in the dashboard at iPhone SE, iPhone 17, and iPhone 17 Pro Max simulator sizes; compare canvas pixels to ensure it is nonblank, edge-to-edge, and does not overlap the vehicle title or metrics.
5. Record human approval, set catalog review status to `reviewed`, and rerun the regression test. Expected exact asset path is the new PNG.
6. Commit: `feat: add 2022 Model 3 Performance vehicle art`.

## Task 9: Complete Model 3 And Model Y Generations

**Files:**
- Create/Modify: `MateDroidIOS/Resources/CarImages/vehicle_model-3-*.png`
- Create/Modify: `MateDroidIOS/Resources/CarImages/vehicle_model-y-*.png`
- Modify: `MateDroidIOS/Resources/VehicleImageCatalog.json`
- Modify: `docs/vehicle-image-review.md`
- Modify: `MateDroidIOSTests/Domain/VehicleImageResolverTests.swift`

1. Add failing table-driven tests for every year boundary, trim group, wheel alias, supported color, and contradictory evidence case for Model 3 and Model Y.
2. Generate and approve one gray geometry master per generation/trim, then locked wheel variants, then locked factory colors. Never regenerate body geometry while recoloring.
3. Mark only approved variants reviewed; retain declared legacy fallback for missing color/wheel combinations.
4. Run resolver, image validator, privacy audit, and dashboard screenshot matrix after each generation, committing one generation at a time with `feat: add <generation> vehicle art`.

## Task 10: Complete Model S, Model X, Roadster, And Cybertruck

**Files:**
- Create/Modify: `MateDroidIOS/Resources/CarImages/vehicle_model-s-*.png`
- Create/Modify: `MateDroidIOS/Resources/CarImages/vehicle_model-x-*.png`
- Create/Modify: `MateDroidIOS/Resources/CarImages/vehicle_roadster-1_*.png`
- Create/Modify: `MateDroidIOS/Resources/CarImages/vehicle_cybertruck-*.png`
- Modify: `MateDroidIOS/Resources/VehicleImageCatalog.json`
- Modify: `docs/vehicle-image-review.md`
- Modify: `MateDroidIOSTests/Domain/VehicleImageResolverTests.swift`

1. Repeat Task 9's red-green generation workflow for nosecone/facelift/refresh/Plaid Model S, legacy/refresh/Plaid Model X, first-generation Roadster, and AWD/Cyberbeast Cybertruck.
2. Use official manuals only to verify visible generation details; do not copy source imagery. Record source URL and observed feature, not screenshots, in review notes.
3. Assert an unknown model never falls through to any Tesla generation image.
4. Finish with zero unreferenced vehicle PNGs and no `reviewed` catalog entry lacking approval.
5. Commit per generation, then `feat: complete passenger vehicle image catalog` for catalog defaults and fallback cleanup.

## Task 11: End-To-End Verification And Release Evidence

**Files:**
- Modify: `README.md`
- Modify: `docs/app-store-release-checklist.md`
- Create: `docs/qa/vehicle-image-catalog-2026-07.md`

1. Run `make generate`, `make test-scripts`, `make localization-audit`, `make vehicle-privacy-audit`, `make vehicle-image-audit`, and `make test-build`; record exact commands and results.
2. After the user completes `sudo xcodebuild -runFirstLaunch`, run `make test`; runtime XCTest must pass on an installed simulator. Do not substitute compile-only success.
3. Run `make integration-test` against the user's TeslaMate. Record only field availability and resolution outcomes; redact server, VIN, coordinates, names, and credentials.
4. Install on the user's iPhone with `make install-device`. Verify first load, multi-car isolation, relaunch persistence, automatic reset, airplane-mode snapshot, Widget, light/dark mode, all languages, Dynamic Type, and unknown/missing data.
5. Add README coverage table and explain automatic matching, manual correction, privacy, offline behavior, and how contributors add an image without using copyrighted source art.
6. Run `make preflight` and `make app-store-technical-audit`; expect all gates green. Commit: `docs: publish vehicle image coverage and QA evidence`.

## Execution Notes

- Keep `.superpowers/`, integration env files, DerivedData, generated comparison screenshots, and user photos out of commits.
- Never commit a real VIN, even redacted fragments that remain unique. Use `TSTMODEL3N0000000` for 2022 fixtures.
- The image catalog must degrade incrementally: catalog/resolver/persistence may ship before all images, but an unreviewed exact asset may never outrank a reviewed fallback.
- Stop and fix any resolver ambiguity, privacy finding, asset validation failure, or visual mismatch before continuing to the next generation.
