# Task 9 Report: Remaining Model 3 Generations

## Status

Completed reviewed art for the remaining Model 3 generations. The corrected v2
refresh base and Highland base candidates are approved alongside the existing
reviewed early, refresh Performance, and Highland Performance assets. Every
reviewed record has precedence over its same-configuration legacy record, while
all declared legacy fallbacks remain present for unavailable combinations.

## Candidate Decisions

| Candidate | Decision | Current low-alpha ratio | Current paired high-opacity ratio | Reason |
| --- | --- | ---: | ---: | --- |
| Original refresh base | Rejected | `0.020871` | `0.015914` | Both current limits fail (`0.02`, `0.01`); a bright edge is visible against the dark composite. |
| Corrected refresh base v2 | Approved | `0.0053945` | `0.0090423` | Both limits pass; original-resolution and fresh light/dark review passed. |
| Original Highland base | Rejected | `0.004354` | `0.019883` | Paired high-opacity limit fails. |
| Corrected Highland base v2 | Approved | `0.0010490` | `0.0008496` | Both limits pass; original-resolution and fresh light/dark review passed. |
| `vehicle_model-3-highland-performance_performance_stealth-grey_performance-20.png` | Approved | `0.015629` | `0.001418` | Both current limits pass; original-resolution and light/dark review also passed. |

The decisions use current `scripts/validate_vehicle_images.py` metrics computed
directly from the controller-inspected 1536x768 candidates. The failed originals
were never copied or cataloged; only independently reviewed v2 outputs were
copied to the final non-v2 resource names.

## Generation Briefs

The controller generation briefs were:

- Refresh base: `2021-2023 refreshed Model 3 base body, black window trim and
  flush handles, Pearl White Multi-Coat, factory refreshed 18-inch Aero wheel
  covers, neutral production brakes, right-facing fixed left-front 15-degree
  studio view, chroma-key background for transparent 1536x768 delivery, no
  spoiler, plate, text, or watermark.`
- Highland base: `2024+ Highland Model 3 base body, slim Highland lamps and
  revised fascia, Pearl White Multi-Coat, factory 18-inch Photon wheel covers,
  neutral production brakes, right-facing fixed left-front 15-degree studio
  view, chroma-key background for transparent 1536x768 delivery, no spoiler,
  plate, text, or watermark.`
- Highland Performance: `2024+ Highland Model 3 Performance body, slim
  Highland lamps, Performance front fascia and rear lip spoiler, PN01 Stealth
  Grey metallic, factory staggered 20-inch dark Warp/Performance wheels, red
  Performance calipers, right-facing fixed left-front 15-degree studio view,
  chroma-key background for transparent 1536x768 delivery, no plate, text, or
  watermark.`

The corrected imagegen edit briefs were:

- Refresh base v2: `Edit the supplied refresh-base chroma source only to remove
  the visible bright/white transparency fringe. Preserve the exact 2021-2023
  body geometry, black brightwork, Pearl White paint, 18-inch Aero wheels,
  camera, framing, baseline, and contained shadow. Return the same vehicle on a
  uniform bright-green chroma background; do not add text, plate, watermark,
  scenery, or regenerate vehicle details.`
- Highland base v2: `Edit the supplied Highland-base chroma source only to
  remove the high-opacity white edge fringe. Preserve the exact 2024+ Highland
  lamps and fascia, Pearl White paint, 18-inch Photon wheels, camera, framing,
  baseline, and contained shadow. Return the same vehicle on a uniform
  bright-green chroma background; do not add text, plate, watermark, scenery,
  or regenerate vehicle details.`

## Chroma And Hashes

Each controller source used a bright green chroma field. Original corner
samples were approximately RGB `(26...41, 227...241, 25...37)`; corrected v2
source corners were RGB `(40...44, 213...225, 37...51)`. The standard chroma
helper produced a 1774x887 RGBA intermediate, followed by controller framing
into a metadata-free 1536x768 RGBA candidate. Intermediates remain under
`tmp/imagegen` and are not bundled.

| Slice | File | SHA-256 |
| --- | --- | --- |
| Refresh base | `model-3-refresh-pearl-white-source.png` | `062841a076339035fbb258f6e533735a0a63ca7bb59a45cb779c0e425867cae2` |
| Refresh base | `model-3-refresh-pearl-white-transparent.png` | `0729dcf7ced28d5be689079da14eeacb097526230aa27574fae0de069d54d7b1` |
| Refresh base original rejected candidate | `vehicle_model-3-refresh_base_pearl-white_aero-18.png` under `tmp/imagegen` | `509a5f88a1fc27580e54d11e2b51bb666ba0585612dbfb756f0b44dbc35acbd5` |
| Refresh base corrected source | `model-3-refresh-pearl-white-v2-source.png` | `dc5a9248e3840fa5dd3f07249bb4ede9d4cd595bf75ed4b3f0dbada84d1ec2ce` |
| Refresh base corrected transparent | `model-3-refresh-pearl-white-v2-transparent.png` | `bef3056349fd727e3b77660b18d8f5b9a71895ec49b426666dca8e48f23425da` |
| Refresh base corrected v2 and shipped final | `vehicle_model-3-refresh_base_pearl-white_aero-18-v2.png` copied to non-v2 resource | `4eaf33ad0545c422f5a752ac8c8ddaeb1c3340958dcba9352fdcb28e30d912ce` |
| Highland base | `model-3-highland-pearl-white-source.png` | `151468ec1abe4ff724aa0828f35511ea98f0814bb61ce1767cbc8a581ff773ed` |
| Highland base | `model-3-highland-pearl-white-transparent.png` | `5f75ca759a3bda123e9080a1740965f6dcad8ac0a3d2b9052f8ad716d8c68ff7` |
| Highland base original rejected candidate | `vehicle_model-3-highland_base_pearl-white_photon-18.png` under `tmp/imagegen` | `5de135a574d55d1421be72cd2503b871f08425e8a0b40aed7a2d7dab4cd1bbe2` |
| Highland base corrected source | `model-3-highland-pearl-white-v2-source.png` | `855a8fd6b587ce426e3062080c661974c956991bf58170d636476181e076f59f` |
| Highland base corrected transparent | `model-3-highland-pearl-white-v2-transparent.png` | `60b151caea8f9cbdef95ac83115ee0d2bf2e2e99a1f07cb0ba3102cc7811f663` |
| Highland base corrected v2 and shipped final | `vehicle_model-3-highland_base_pearl-white_photon-18-v2.png` copied to non-v2 resource | `8e167afa3679ad2b0d363781f712f1b70b36a6034f8c4db1c5990d1b52d2dc01` |
| Highland Performance | `model-3-highland-performance-stealth-grey-source.png` | `388ed4b6b8f3198315685eebf2b0e3f7d79ecb71ad81d0de0f03b88f0dbf55c4` |
| Highland Performance | `model-3-highland-performance-stealth-grey-transparent.png` | `089f887b4d5b885a1c492ecb2131e26a87f246e2aa0072eacf4656d0265b373a` |
| Highland Performance reviewed final and shipped resource | `vehicle_model-3-highland-performance_performance_stealth-grey_performance-20.png` | `0de4b75946fae80d44bcbbbca2d3bf658bf9335e33c9f2cc2bf7f4a183649f10` |

Each approved controller final and its shipped resource were verified
byte-identical before Xcode bundle processing.

## Framing And Alpha

All approved final candidates are 1536x768 RGBA, have alpha extrema `0...255`,
contain only `IHDR`, `IDAT`, and `IEND`, and have no Pillow-visible metadata.

| Candidate | Alpha bounds | Normalized bounds | Baseline |
| --- | --- | --- | ---: |
| Refresh base corrected v2 | `(210, 133, 1338, 584)` | `(0.1367, 0.1732, 0.8711, 0.7604)` | `0.7604` |
| Highland base corrected v2 | `(188, 147, 1339, 614)` | `(0.1224, 0.1914, 0.8717, 0.7995)` | `0.7995` |
| Highland Performance | `(179, 135, 1344, 591)` | `(0.1165, 0.1758, 0.8750, 0.7695)` | `0.7695` |

Framing, baseline, metadata, and edge metrics are inside current validator
ranges for all three reviewed remaining-generation assets.

## Original And Light/Dark Review

The corrected candidates were independently opened at original resolution. A
fresh four-panel light/dark composite was inspected at original resolution from
`tmp/imagegen/model-3-refresh-highland-v2-light-dark-review.jpg` (SHA-256
`2fe3c12842226b701a0cc987ae9674614276fd6b8e8cf64d1eda736154e8226e`).

- Refresh base v2 passed the 2021-2023 black brightwork, pre-Highland lamps and
  fascia, refreshed Aero covers, neutral brakes, Pearl White paint, shadow,
  scale, and locked perspective checks. No continuous matte/rim remains.
- Highland base v2 passed the slim Highland lamps, clean base fascia, Photon
  covers, neutral brakes, Pearl White paint, shadow, scale, and locked
  perspective checks. No continuous matte/rim remains.
- Highland Performance passed the Highland lamp and Performance fascia shape,
  black brightwork, restrained rear lip, PN01 Stealth Grey finish, current
  dark 20-inch Warp/Performance wheel treatment, red calipers, shadow,
  perspective and scale checks. No visible scene, plate, text, watermark, or
  continuous matte/rim remains on light or dark.

Official Tesla references were used for comparison only; no reference imagery
was copied into the repository:

- 2017-2023 owner exterior:
  `https://www.tesla.com/ownersmanual/2017_2023_model3/en_us/GUID-6C6C3944-9674-4E81-A0E8-94D60B6D87B9.html`
- 2017-2023 service paint and wheel codes:
  `https://service.tesla.com/docs/Model3/ServiceManual/en-us/GUID-769C9625-76EE-467B-B756-C9032AC2B99A.html`
- Current owner exterior:
  `https://www.tesla.com/ownersmanual/model3/en_us/GUID-6C6C3944-9674-4E81-A0E8-94D60B6D87B9.html`
- Current owner wheel specifications:
  `https://www.tesla.com/ownersmanual/model3/en_us/GUID-FDDB10EF-FFA9-46EB-B8CC-03614AE92B6B.html`
- Current service paint and wheel codes:
  `https://service.tesla.com/docs/Model3/ServiceManual/2024/en-us/GUID-769C9625-76EE-467B-B756-C9032AC2B99A.html`
- Current service wheel dimensions:
  `https://service.tesla.com/docs/Model3/ServiceManual/2024/en-us/GUID-B6813E31-8CD2-494E-80F5-497AEEAE1DE0.html`

## Catalog Behavior

The catalog now has exact reviewed Pearl White records for `model-3-refresh`
base / `aero-18` and `model-3-highland` base / `photon-18`, in addition to the
reviewed Highland Performance record. All three same-configuration legacy
records and generation-level fallback declarations remain unchanged.
Reviewed-first catalog precedence is unchanged.

Table-driven XCTest coverage includes each remaining generation's lower and
upper/open boundary, trim aliases, wheel aliases, supported colors,
contradictory other-generation wheels, precise reviewed selection,
and the 2020-to-2021 and 2023-to-2024 transitions.

The production Foundation resolver harness observed RED before the catalog and
asset change:

```text
resolver: refresh lower: asset legacy-model-3-refresh
picker: year 2021 preview selected CarImages/m3_PPSW_W38B.png
```

Both source harnesses passed after the minimal catalog/resource change.

## Review Gap Remediation

The follow-up review found two committed XCTest gaps hidden by the unavailable
runtime simulator. The stale 2020/2021 boundary test still expected the 2021
refresh legacy record even though the bundled catalog now selects the reviewed
refresh asset. It now asserts exact reviewed selection and no legacy use at both
boundaries. A separate 2024 Highland Performance Pearl White (`P74D`, `W30P`,
`PPSW`) test proves a genuinely unavailable reviewed color still returns
`legacy-model-3-highland-performance` with fallback confidence.

The bundled picker precedence table now covers all three remaining reviewed
records. Its per-case color input includes Highland Performance `W30P` / `PN01`
and asserts the Stealth Grey reviewed path for preview and wheel thumbnail plus
the reviewed asset ID on save.

Static checks were RED before the edit because the reviewed-boundary test name
and PN01/W30P picker row were absent. The updated checks pass, and the source and
built-bundle harnesses continue to exercise the same production behavior.

## Verification

```text
python3 scripts/test_validate_vehicle_images.py                 PASS (50 tests)
python3 scripts/validate_vehicle_images.py                      PASS
make test-scripts                                               PASS
make vehicle-privacy-audit                                      PASS
make localization-audit                                         PASS (430 keys, 0 findings)
make app-store-technical-audit                                  PASS (0 blockers)
plutil -lint MateDroidIOS.xcodeproj/project.pbxproj             PASS
Foundation source resolver harness                              PASS (10 generation cases, 4 transitions)
Foundation/SwiftUI source picker harness                        PASS
focused generic build-for-testing                               PASS (arm64 and x86_64)
built MateDrive.app resolver harness                            PASS (10 generation cases, 4 transitions)
built MateDrive.app picker harness                              PASS
```

The rebuilt `MateDrive.app` and embedded `MateDriveWidget.appex` both contain
all three remaining-generation reviewed PNGs. Xcode's `copypng` processing
produced identical app/widget copies for each asset:

| Built asset | App/widget SHA-256 |
| --- | --- |
| Refresh base | `5d28834bceb040537330ca6b0fd2986e4aa13b1f1c2d0c421362ed86bf8483a9` |
| Highland base | `a3909c8b645cbbe2f2c7f0b70438c26ae35c356325865bdbeb53660140439734` |
| Highland Performance | `26c50a8b15ec8378606ca69419f614985320874e30e8516979ee5616fe7aea67` |

The reviewed source resources remain byte-identical to their inspected
controller finals at the separately recorded pre-build hashes.

## Concerns

- Runtime XCTest and actual simulator dashboard screenshots depend on the local
  CoreSimulator/Xcode compatibility noted in the early Model 3 report. Generic
  test compilation and static/bundle harnesses remain the available checks if
  that mismatch persists.
- The accepted source is AI-generated. Automated validation cannot prove
  factory geometry beyond documented full-resolution human review against
  official references.
