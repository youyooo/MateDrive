# Vehicle Image Review

Review every new master at full resolution and in the dashboard frame before setting
its catalog `reviewStatus` to `reviewed`. The validator reads the `Reviewed Assets`
table below and requires a non-empty reviewer, ISO-8601 date, and source reference
for every reviewed asset. Every checklist cell must be exactly `Pass`, `Approved`,
or `Yes`, optionally followed by `: ` and a note.

## Checklist

- Generation: body is the intended model year and production generation.
- Trim: exterior specification is the intended trim group.
- Lamps/Fascia: headlamps, tail lamps, bumper, and fascia match the generation.
- Brightwork: exterior trim, handles, badges, and spoilers match the trim.
- Wheel: the wheel design and diameter match the catalog wheel ID.
- Caliper: caliper color and visible brake hardware match the selected trim.
- Paint: factory paint color and reflections are plausible and consistent.
- Perspective: vehicle faces right at the locked left-front three-quarter view.
- Scale: framing, horizontal center, and wheel baseline match the master template.
- Shadow: ground-contact shadow is soft, intentional, and inside the canvas.
- Edge: inspect transparency at 100% on both light and dark composites; require no
  visible white/dark matte or rim, scene, watermark, or text, and record both the
  opacity-weighted low-alpha and high-opacity boundary validation ratios.
- Source reference: list the official manual or reference URL and the feature checked;
  do not add source images or screenshots to the repository.

## Reviewed Assets

| Asset ID | Generation | Trim | Lamps/Fascia | Brightwork | Wheel | Caliper | Paint | Perspective | Scale | Shadow | Edge | Reviewer | Date | Source Reference |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| model-3-refresh-performance-midnight-silver-uberturbine-20 | Pass: 2021-2023 pre-Highland Model 3 body | Pass: Performance exterior with black trim and rear lip spoiler | Pass: pre-Highland headlamps and front fascia | Pass: black window trim and flush handles; no chrome or text artifact | Pass: dark factory 20-inch Uber Turbine multi-spoke design | Pass: red Performance calipers visible at both wheels | Pass: PMNG Midnight Silver Metallic with neutral studio reflections | Pass: right-facing fixed left-front 15-degree studio view | Pass: 1536x768; alpha bounds 0.1445, 0.2083, 0.8633, 0.7917; baseline 0.7917 | Pass: soft ground-contact shadow remains inside canvas | Pass: v5 inspected at 100% on light and dark composites with no visible matte/rim, scene, plate, watermark, or text; low-alpha 0.004929 < 0.02 and paired high-opacity 0.000417 < 0.01 | MateDrive visual review | 2026-07-13 | Tesla 2017-2023 Model 3 Owner's Manual exterior: https://www.tesla.com/ownersmanual/2017_2023_model3/en_us/GUID-6C6C3944-9674-4E81-A0E8-94D60B6D87B9.html; Tesla 2017-2023 Model 3 Service Manual paint/wheel codes: https://service.tesla.com/docs/Model3/ServiceManual/en-us/GUID-769C9625-76EE-467B-B756-C9032AC2B99A.html; used only to check body/lamp reference, PMNG paint, and 20-inch Uber Turbine wheel specification; no source imagery copied |
| model-3-early-base-pearl-white-aero-18 | Pass: 2017-2020 pre-refresh Model 3 body | Pass: base catalog group covering RWD, Long Range, and Performance aliases without Performance-specific exterior claims | Pass: early Model 3 headlamps, marker lamps, and front fascia | Pass: chrome window surround, flush bright handles, and early fender camera trim; no spoiler, plate, text, or watermark | Pass: pre-refresh factory 18-inch Aero wheel covers at both axles | Pass: neutral production brake hardware with no Performance caliper claim | Pass: PPSW Pearl White Multi-Coat with neutral studio reflections | Pass: right-facing fixed left-front 15-degree studio view | Pass: 1536x768; alpha bounds 0.1315, 0.1927, 0.8880, 0.7904; baseline 0.7904 | Pass: soft ground-contact shadow remains inside canvas | Pass: inspected at 100% on light and dark composites with no visible matte/rim, scene, plate, watermark, or text; low-alpha 0.011262 < 0.02 and paired high-opacity 0.005620 < 0.01 | MateDrive visual review | 2026-07-13 | Tesla 2017-2023 Model 3 Owner's Manual exterior: https://www.tesla.com/ownersmanual/2017_2023_model3/en_us/GUID-6C6C3944-9674-4E81-A0E8-94D60B6D87B9.html; Tesla Owner's Manual parts and accessories 18-inch Aero specification: https://www.tesla.com/ownersmanual/2017_2023_model3/en_us/GUID-ECA7C07B-7944-496B-8FC5-12762BF061F1.html; Tesla 2017-2023 Model 3 Service Manual paint/wheel codes: https://service.tesla.com/docs/Model3/ServiceManual/en-us/GUID-769C9625-76EE-467B-B756-C9032AC2B99A.html; Tesla 2017-2023 Aero Wheel Cover reference: https://shop.tesla.com/product/2017-2023-_-model-3-aero-wheel-cover; used only to check early body/brightwork, PPSW Pearl White, and pre-refresh 18-inch Aero cover specification; no source imagery copied |
