# MateDrive Vehicle Image Catalog Design

**Date:** 2026-07-13  
**Status:** Approved direction and scope; awaiting written-spec review  
**Product:** MateDrive iOS

## Purpose

MateDrive must show a vehicle image that matches the recorded car's model, model year, generation, trim, exterior color, and wheels. The current resolver uses a small set of model variants and often treats all pre-Highland Model 3 vehicles as one body generation. That makes a 2022 Model 3 Performance reuse an early chrome-trim body and, when TeslaMate reports `Pinwheel18CapKit`, select an 18-inch Aero image instead of the expected factory Performance configuration.

This design replaces ad hoc dictionaries with a versioned vehicle-image catalog, makes automatic decisions explainable, preserves per-car manual overrides, and introduces a controlled process for replacing the existing 97 images with a visually consistent image library.

## Goals

- Cover every first-phase mass-produced Tesla passenger vehicle and its visually meaningful body generations.
- Distinguish model generation from trim, wheel, and color instead of encoding every concern in one short filename prefix.
- Use VIN model year, model, trim, wheel, color, and other available TeslaMate fields without exposing the VIN in UI, diagnostics, logs, exports, tests, or screenshots.
- Correctly identify a 2022 Model 3 Performance as the 2021-2023 refresh body with black exterior trim and a factory 20-inch Überturbine default.
- Allow users with changed wheels or unusual regional configurations to override the automatic result for one server and one car.
- Keep the dashboard usable while images are replaced incrementally by retaining a deterministic legacy fallback.
- Enforce a single visual standard and automated asset validation before images can ship.

## Non-Goals

- Semi is not included in the first phase because it is a commercial vehicle rather than a passenger vehicle.
- The unreleased second-generation Roadster is not included until a production specification exists.
- MateDrive will not infer a vehicle from a photo.
- MateDrive will not download arbitrary vehicle images at runtime.
- The catalog will not claim certainty when TeslaMate fields are missing or contradictory.

## First-Phase Vehicle Generations

The catalog uses stable generation identifiers that do not depend on marketing names changing by region.

| Catalog ID | Vehicle | Model years | Trim groups | Required visual distinction |
| --- | --- | --- | --- | --- |
| `roadster-1` | Roadster | 2008-2012 | Base, Sport | First-generation roadster body |
| `model-s-nosecone` | Model S | 2012-2015 | 60/70/85/P variants | Nose-cone front fascia |
| `model-s-facelift` | Model S | 2016-2020 | Standard/Long Range/Performance | Facelift front fascia and legacy interior-era exterior |
| `model-s-refresh` | Model S | 2021+ | Dual Motor | Palladium/refresh body details and current wheels |
| `model-s-plaid` | Model S | 2021+ | Plaid | Plaid trim and wheel defaults |
| `model-x-legacy` | Model X | 2015-2020 | Standard/Long Range/Performance | Legacy fascia and wheel family |
| `model-x-refresh` | Model X | 2021+ | Dual Motor | Refresh trim and current wheels |
| `model-x-plaid` | Model X | 2021+ | Plaid | Plaid trim and wheel defaults |
| `model-3-early` | Model 3 | 2017-2020 | RWD/Long Range/Performance | Chrome window trim and early console-era exterior |
| `model-3-refresh` | Model 3 | 2021-2023 | RWD/Long Range | Black window trim and refreshed wheels |
| `model-3-refresh-performance` | Model 3 | 2021-2023 | Performance | Black trim, 20-inch Überturbine and red calipers by default |
| `model-3-highland` | Model 3 | 2024+ | RWD/Long Range | Highland lamps, fascia and wheel family |
| `model-3-highland-performance` | Model 3 | 2024+ | Performance | Highland Performance fascia, wheels and trim details |
| `model-y-legacy` | Model Y | 2020-2024 | RWD/Long Range | Legacy body and non-Performance wheel families |
| `model-y-legacy-performance` | Model Y | 2020-2024 | Performance | Überturbine wheel and Performance details |
| `model-y-juniper-standard` | Model Y | 2025+ | Standard | Juniper body and Standard wheel family |
| `model-y-juniper-premium` | Model Y | 2025+ | Premium | Juniper body and Premium wheel family |
| `model-y-juniper-performance` | Model Y | 2025+ | Performance | Juniper Performance body and wheel details |
| `cybertruck-awd` | Cybertruck | 2023+ | AWD/Long Range | Stainless body with the matching production wheel cover |
| `cybertruck-cyberbeast` | Cybertruck | 2023+ | Cyberbeast | Cyberbeast trim and wheel defaults |

Year boundaries are catalog evidence, not the only evidence. Regional rollout differences are handled through trim and wheel evidence plus manual override rather than creating region-specific body IDs without a visible body difference.

## Source Data

The resolver receives a `VehicleImageDescriptor` containing only the fields needed for image selection:

- server identity hash and TeslaMate car ID for override scoping;
- normalized base model;
- model year derived in memory from VIN;
- trim badging;
- wheel type;
- exterior color;
- spoiler type when available;
- legacy manually selected variant and wheel, for migration.

The raw VIN is never stored in the catalog result, override record, widget snapshot, diagnostic export, analytics, or log message. Unit tests use explicitly synthetic 17-character values with a model-year character, never production VINs.

## Catalog Model

`VehicleImageCatalog.json` is the checked-in source of truth. It contains:

- catalog schema version;
- generation entries with model and inclusive year bounds;
- trim matching patterns and priority;
- supported colors and aliases;
- wheel entries, Tesla configuration aliases, and factory-default flags;
- asset records with generation, trim group, color, wheel, filename, and visual-review status;
- fallback generation and fallback asset identifiers;
- human-readable localization keys rather than embedded display strings.

The app decodes the catalog once. Catalog loading is isolated behind `VehicleImageCatalogProviding` so tests can use small fixtures and the production app can reject an invalid catalog without crashing.

## Resolution Result

The resolver returns a `VehicleImageResolution`, not only a path:

- selected generation ID;
- selected trim group;
- selected color and wheel IDs;
- asset path;
- confidence: `exact`, `inferred`, `fallback`, or `manual`;
- ordered evidence used;
- non-sensitive conflict reasons;
- whether an existing legacy asset was used.

This result lets Settings explain why a picture was selected without exposing VIN or server details.

## Resolution Algorithm

1. Load a valid manual override scoped by server identity hash and car ID. A valid override always wins.
2. Normalize the base model and reject catalog generations for other models.
3. Use VIN-derived model year to narrow the generation candidates.
4. Apply trim evidence to choose Performance, Plaid, Standard, Premium, or base groups.
5. Apply generation-specific wheel evidence when it does not contradict stronger year and trim evidence.
6. Resolve exterior color through catalog aliases and generation availability.
7. Select an exact reviewed asset when available.
8. If no exact asset exists, keep generation and trim fixed while falling back to that generation's default wheel, then default color.
9. If the generation has no reviewed image, map to the declared legacy fallback and mark the result as `fallback`.
10. If the model itself is unknown, use the neutral generic vehicle placeholder rather than showing a Model 3 as if it were certain.

### Conflicting Evidence

Evidence priority is:

1. manual override;
2. base model;
3. VIN-derived model year;
4. explicit Performance/Plaid/Standard/Premium trim;
5. generation-specific wheel;
6. generation-specific color;
7. catalog default.

For a 2022 Model 3 with `P74D` and `Pinwheel18CapKit`, model year and Performance trim select `model-3-refresh-performance`. The factory default is 20-inch Überturbine with red calipers. The conflicting 18-inch value is recorded as a non-sensitive selection warning and offered as a manual wheel alternative; it does not silently turn the vehicle into an early or non-Performance image.

## Manual Override

Long-pressing the dashboard car continues to open the image picker. The redesigned picker presents:

- detected generation and confidence;
- trim group;
- body color swatches;
- wheel thumbnails valid for that generation;
- a concise explanation when source fields conflict;
- `Use automatic match` to delete the override;
- `Use this configuration` to persist it for only the current server and car.

Overrides are migrated from the current variant/wheel format where a deterministic mapping exists. Invalid or removed asset IDs are ignored safely and surfaced as a fallback, not as a broken image.

## Image Production Standard

Every new image follows one locked rendering template:

- transparent PNG master at 1536x768;
- vehicle facing right at a fixed left-front three-quarter angle of approximately 15 degrees;
- fixed camera height, focal length, wheel baseline, vehicle bounding box, and horizontal center;
- neutral studio lighting and physically plausible paint reflections;
- soft ground contact shadow inside the transparent canvas;
- no scene, road, building, text, plate number, watermark, or decorative gradient;
- no readable manufacturer badge is required for recognition;
- trim-accurate lamps, fascia, exterior brightwork, door handles, spoiler, wheels, and brake calipers;
- transparent edges without white or dark halos;
- consistent visual scale across sedans, SUVs, Roadster, and Cybertruck while preserving real proportions.

### Generation Workflow

1. Produce one neutral-gray reference master for a generation and trim group.
2. Compare it against official manuals and multiple reference views for visible generation details; reference images are not copied into the repository.
3. Review the master in the visual companion at dashboard size and full resolution.
4. Lock the accepted master as the reference for wheel and color variants.
5. Generate distinct wheel variants with all body geometry, camera, lighting, and framing unchanged.
6. Generate factory color variants from the accepted wheel masters with geometry unchanged.
7. Remove the chroma-key background using the standard image-generation helper when transparent output is required.
8. Run automated asset validation and a human visual checklist.
9. Mark the asset `reviewed` in the catalog only after both checks pass.

The first reference master is the user's 2022 Model 3 Performance configuration: Midnight Silver Metallic, black exterior trim, 20-inch Überturbine wheels, red brake calipers, and the 2021-2023 body.

## Asset Naming

New assets use readable, stable identifiers:

```text
vehicle_<generation>_<trim>_<color>_<wheel>.png
```

Example:

```text
vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20.png
```

Legacy short filenames remain supported only through catalog fallback entries. New code does not construct filenames by string concatenation.

## Asset Validation

The repository gains a read-only validator that fails when:

- a catalog asset is missing;
- an asset is not PNG or has no alpha channel;
- dimensions do not match the catalog standard or approved optimized size;
- the non-transparent bounding box violates framing tolerances;
- wheels sit outside the baseline tolerance;
- transparent edge contamination exceeds the threshold;
- duplicate catalog keys or ambiguous matcher priorities exist;
- an asset is marked reviewed without a human-review record;
- an unreferenced new vehicle asset is committed accidentally.

Visual review checks body generation, trim, lamps, brightwork, wheel design, caliper color, paint color, perspective, scale, shadow, and edge quality.

## Dashboard Integration

The dashboard continues to use a stable frame so changing assets cannot resize surrounding content. `CarImageView` uses the catalog's per-generation presentation scale only for real proportion correction; arbitrary per-image scale factors are rejected by validation.

The widget uses the same resolution result and reviewed optimized assets. It never performs network image loading and never stores VIN-derived input.

## Error Handling And Fallbacks

- Invalid catalog: record a non-sensitive diagnostic warning and use the bundled generic placeholder.
- Missing exact image: preserve generation/trim, use its reviewed default wheel/color, and report `inferred`.
- Missing generation image: use its declared legacy fallback and report `fallback`.
- Unknown model: use the generic placeholder instead of silently using Model 3.
- Invalid manual override: ignore it, retain the record for migration diagnostics, and resolve automatically.
- Image decode failure: show the generic placeholder without changing dashboard layout.

No missing image path produces an empty first screen.

## Privacy And Distribution

- Production VINs, vehicle IDs, server URLs, coordinates, and user screenshots are prohibited from test fixtures and image metadata.
- Generated PNG metadata is stripped before commit.
- New imagery is generated for MateDrive; online and official images are visual references only and are not downloaded into the shipping bundle without an explicit redistributable license.
- Existing GPL-covered assets remain documented in legal notices while they are bundled as fallbacks.
- App Store screenshots use synthetic or deliberately redacted vehicle data.

## Testing

### Resolver Unit Tests

- each catalog generation's lower and upper year bounds;
- trim aliases for Performance, Plaid, Standard, Premium, and regional codes;
- exact and aliased wheel/color matching;
- contradictory evidence ordering;
- unknown model and missing-year behavior;
- manual override scope and reset;
- legacy override migration;
- catalog validation failures.

The regression fixture for the reported issue uses a synthetic 2022-model-year VIN, Model 3, `P74D`, Midnight Silver, and `Pinwheel18CapKit`. It must resolve to `model-3-refresh-performance`, Überturbine 20, with an inferred/conflict explanation and no raw VIN in the result.

### Integration Tests

- dashboard and widget choose the same asset;
- offline snapshot retains the resolved asset ID but not VIN;
- switching server or car never leaks an override across identities;
- picker selection persists and automatic reset restores catalog resolution;
- localization covers generation, trim, wheel, confidence, and conflict text.

### Visual Tests

- render every reviewed master in dashboard and widget frames;
- verify no clipping or layout shift at supported iPhone sizes;
- compare bounding boxes and baselines across the complete catalog;
- inspect light and dark palettes for adequate vehicle contrast.

## Rollout

1. Add catalog schema, validator, resolution result, and regression tests while retaining all current images as legacy fallbacks.
2. Migrate dashboard, widget, picker, snapshot, and overrides to catalog IDs.
3. Generate and approve the 2021-2023 Model 3 Performance master, then its required color and wheel variants.
4. Complete Model 3 generations, then Model Y, Model S/X, Cybertruck, and first-generation Roadster.
5. Remove a legacy fallback only when every catalog entry that references it has a reviewed replacement.
6. Run full unit, integration, localization, visual, privacy, and App Store release gates before shipping.

## Acceptance Criteria

- The reported 2022 Model 3 Performance resolves to the correct refreshed black-trim body and factory Performance wheel by default.
- Every first-phase generation has at least one reviewed image and an explicit fallback.
- Every automatic result includes confidence and evidence without raw VIN.
- Manual override works per server and car and can return to automatic mode.
- All reviewed assets pass automated and human visual checks.
- Dashboard and widget never show a blank vehicle image.
- No production VIN or private TeslaMate value exists in source, Git history, diagnostics, image metadata, or screenshots.
- Full relevant tests and release gates pass on a compatible simulator and physical iPhone before App Store submission.
