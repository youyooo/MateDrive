# Task 8 Report: 2022 Model 3 Performance Vehicle Art

## Status

Implemented the reviewed 2022 Model 3 Performance Midnight Silver reference as
`model-3-refresh-performance-midnight-silver-uberturbine-20`. The exact PMNG/
MidnightSilver match resolves to the new asset; the contradictory reported-wheel
case keeps its existing conflict and resolves with inferred confidence. The
pearl-white M3P configuration still uses the declared legacy fallback.

## Generation And Processing

- Built-in imagegen prompt: `2021-2023 Model 3 Performance body, black exterior
  trim, Midnight Silver Metallic, factory 20-inch Uberturbine wheels, red calipers,
  right-facing fixed left-front 15-degree studio view, transparent 1536x768 canvas,
  no text/plate/watermark.`
- Generated chroma-key source: `tmp/imagegen/model-3-refresh-performance-source.png`
  (1774x887 RGB). This remains untracked and is not bundled.
- The standard helper at
  `/Users/youyooo/.codex/skills/.system/imagegen/scripts/remove_chroma_key.py`
  produced `tmp/imagegen/model-3-refresh-performance-transparent.png` at 1774x887
  RGBA. The supplied reviewed final normalized the canvas to 1536x768, aligned the
  vehicle to the master bounds/baseline, and stripped ancillary metadata.
- The review remediation used built-in imagegen edits to remove the light silhouette
  rim and preserve dark glass: `model-3-refresh-performance-no-rim-source.png`, then
  `model-3-refresh-performance-dark-glass-source.png` (both 1774x887 RGB). The
  standard chroma helper produced their same-size `*-transparent.png` RGBA
  intermediates. The controller-supplied v5 normalized the corrected transparent
  edit to 1536x768, aligned it to the master frame, and stripped metadata.
- Corrected reviewed source:
  `tmp/imagegen/vehicle_model-3-refresh_performance_midnight-silver_uberturbine-20-v5.png`.
  It was independently inspected at original resolution and copied byte-for-byte to
  the catalog resource. Chroma/edit intermediates remain under untracked `tmp/`.
- Source and shipped SHA-256:
  `508334a6d2c65fff2109ebba58c5e41c3ff7d4023d361d48aaf8bf29b40a0586`.

## RED

The resolver and bundled-catalog tests were changed before the PNG or catalog.
Runtime XCTest could not start because installed CoreSimulator `1051.54.0` is older
than Xcode's required `1051.55.0`. A temporary Foundation harness then executed the
production decoder/resolver against the unchanged catalog and failed with exit 133:

```text
Precondition failed: expected reviewed Midnight Silver asset, got legacy-model-3-refresh-performance
```

### Review Remediation RED

The high-opacity fixture was added before the edge implementation. It places 100
isolated near-white boundary pixels at alpha 201, with two adjacent to substantially
darker inward opaque pixels. The current validator returned 0, so the required
failure test failed `0 != 1`. After adding the high-opacity rule, the live validator
rejected the original asset at `72/4349 = 0.016555`, above the new `0.01` limit.

A second RED control reproduced v5's sparse alpha-1 RGB residue: the count-only
low-alpha metric reported `0.03` instead of the required opacity-weighted
`3/(3 + 97*16) = 0.001929`. This justified weighting the existing low-alpha ratio by
opacity without changing its `0.02` threshold.

The final directional-pairing fixture added a bright silver boundary pixel with a
transparent outward neighbor, same-tone silver at the exact opposite inward pixel,
and unrelated dark glass orthogonal to that edge. The arbitrary-neighbor validator
reported `1.0` instead of the required `0`, confirming the false positive before the
pairing fix.

## GREEN

- Focused generic build-for-testing for `VehicleImageCatalogTests` and
  `VehicleImageResolverTests`: `** TEST BUILD SUCCEEDED **` for arm64 and x86_64.
- Foundation resolver harness: exact MidnightSilver/Uberturbine20 match is `exact`
  with no conflict; PMNG plus contradictory Pinwheel18CapKit is `inferred` with
  `reportedWheelContradictsFactoryTrim`; PPSW/W32D remains the pearl-white legacy
  fallback.
- The build log confirms the PNG is copied into both `MateDrive.app` and
  `MateDriveWidget.appex`.
- A built-bundle probe exposed that Xcode flattens PNG resources while the catalog
  provider checked only the logical `CarImages` subdirectory. The existing bundled
  provider test covered the intended behavior; the minimal root-resource fallback
  now matches `CarImageView`. A Foundation harness against the actual built app
  loaded all 21 assets and resolved PMNG with exact confidence.
- Review-remediation fixtures pass at 2% high-opacity rejection, the inclusive 1%
  high-opacity boundary, similar-tone silver inward color, and sparse near-transparent
  RGB residue. The corrected v5 asset passes the live validator.

## Image Validation

- PNG: 1536x768 RGBA, alpha extrema 0...255, no embedded image metadata.
- Allowed chunks only: `IHDR`, `IDAT`, `IEND`.
- Alpha bounds: `(222, 160, 1326, 608)`, normalized to
  `(0.1445, 0.2083, 0.8633, 0.7917)`; baseline `0.7917`.
- Low-alpha edge metric is opacity-weighted and remains limited to `>0.02`; v5 is
  `95/19275 = 0.004929`. High-opacity candidates use alpha `128...254`, an outward
  alpha drop of at least 32, and an inward neighbor at alpha at least 200 and at least
  16 more opaque (capped at 255). A near-white pixel (brightness at least 220) is
  tested per outward direction only against the exact opposite inward pixel; unrelated
  orthogonal/diagonal opaque colors are never compared. Each boundary pixel enters
  the denominator once and is contaminated when any valid directional pair is at
  least 48 darker. This avoids both cross-feature false positives and denominator
  dilution. The high-opacity ratio rejects `>0.01`; the old fringe remains rejected
  at `72/4349 = 0.016555`, while v5 passes at `1/2399 = 0.000417`.
- Full-resolution visual review passed pre-Highland lamps/fascia, black exterior
  trim, dark 20-inch Uber Turbine wheel design, red calipers, Midnight Silver paint,
  right-facing perspective, unclipped shadow, and no plate/text/watermark artifact.
- Only official Tesla owner/service manual links were recorded as visual notes; no
  official or competitor imagery was copied into the repository.
- `tmp/imagegen/model-3-v5-light-dark-review.jpg` was inspected at 100%: the top
  light composite and bottom dark composite show a clean silhouette without the
  continuous roof, glass/hood, bumper, rear-quarter, or lower-body light matte from
  the reviewed v1 asset. This evidence remains untracked.

## Display Checks

**Actual simulator screenshot matrix: DEFERRED until CoreSimulator is updated.**
CoreSimulator/Xcode mismatch prevents launching the iPhone SE, iPhone 17, and iPhone
17 Pro Max simulators. A static pixel matrix passed using the installed device
profiles and reproduced the shipped `CarImageView` geometry (`2.2` stable aspect
ratio, `scaledToFit`, dashboard display scale `1.18`, clipped frame):

| Device | Screen profile | Rendered alpha bounds | Result |
| --- | --- | --- | --- |
| iPhone SE (3rd generation) | 375x667 pt at 2x | `(87, 51, 668, 289)` in 750x341 px | Nonblank; no title/metric overlap |
| iPhone 17 | 402x874 pt at 3x | `(142, 84, 1073, 464)` in 1206x548 px | Nonblank; no title/metric overlap |
| iPhone 17 Pro Max | 440x956 pt at 3x | `(156, 93, 1175, 508)` in 1320x600 px | Nonblank; no title/metric overlap |

The source alpha remains contained on every frame and fills 78-79% of frame width.
The static pixel matrix passed, but it is not a substitute for the deferred actual
simulator screenshot matrix.

## Gates

```text
python3 scripts/test_validate_vehicle_images.py                 PASS (49 tests)
python3 scripts/validate_vehicle_images.py                      PASS
make vehicle-privacy-audit                                     PASS
make localization-audit                                        PASS (429 keys, 0 findings)
integration probe and archive/privacy script fixtures          PASS
make app-store-technical-audit                                 PASS (0 blockers)
Foundation resolver harness                                    PASS
built MateDrive.app catalog/resolver harness                    PASS (21 assets)
focused generic build-for-testing                              PASS
```

## Concerns

- Runtime XCTest and actual iPhone SE/iPhone 17/iPhone 17 Pro Max simulator
  screenshots remain unavailable until CoreSimulator is updated from `1051.54.0`
  to the `1051.55.0` version required by Xcode.
- The source was AI-generated and approved by `MateDrive visual review`; automated
  validation cannot independently prove factory geometry beyond the documented
  human review and official-reference comparison.
