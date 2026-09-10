# MyTesS Competitive Parity Roadmap

Source reviewed: `https://cn.mytess.net/zh/docs/guide` on 2026-07-16. This roadmap tracks observable product capabilities, not marketing wording or visual copying.

MateDrive product position:

- Free to use and intended for community sharing.
- Direct connection to the user's self-hosted TeslaMate API.
- No developer collection of vehicle history or credentials.
- Accurate missing-data semantics: unknown values are not converted to zero.
- Every parity claim requires automated tests plus real TeslaMate integration evidence.

## Current Coverage

| Capability | MateDrive status | Evidence / next quality bar |
| --- | --- | --- |
| Live vehicle dashboard | Implemented | Vehicle identity, battery, range, locks, climate, Sentry, location, TPMS, offline snapshot and widget. Continue multi-car isolation testing. |
| Battery health and history | Implemented with calibration | Capacity/range trends, confidence and late-recording baseline. Late-history best-observed capacity/range is never treated as a new-car baseline. Add model-specific verified reference library only when source evidence is available. |
| Drive maps and telemetry | Implemented | Route, replay, speed, traction/regen power, battery/heating, elevation, temperature and four-wheel pressure. Add richer behavior explanations. |
| Drive insights | Implemented | Commute clusters, records, measured metrics, transparent safety/regen score components, confidence, missing-sample exclusion and actionable recommendations. Expand only with server-validated inputs. |
| Multi-drive trips | Implemented | Automatic/manual grouping, weather, route, timeline, countries, charge stops, persistence and local 1080 x 1350 trip reports. Reports preserve missing-energy coverage and hide dates, locations, route shape, costs and custom trip names by default. Photos and richer story layouts remain missing. |
| Charging history and live charge | Implemented | SOC, power, energy, voltage, duration, cost, curves, comparisons, notifications and a read-only local Live Activity/Dynamic Island view. Remote push updates remain out of scope until a privacy-preserving design exists. |
| Time/location charging prices | Implemented | Geofence/type/time/effective-date rules, synchronized charger identity, safe batch preview, selected-history API 2.6 writeback, per-record results, rollback evidence, vehicle-scoped persistent audit history, privacy-safe CSV export and reusable local tariff templates that exclude locations and effective dates. Privacy-reviewed template file sharing is the next quality bar. |
| Place insights | Implemented | Server smart places plus complete-history fallback, charging, parking, cost quality and standby drain. |
| Parking costs | Implemented | Free time, increments, fixed/hourly/monthly fees, caps, priorities and unmatched coverage. |
| Statistics and cost review | Implemented | Driving, energy, charging, parking, calendar heatmap, records and API 2.6 cost review. Activity-period recap sharing is implemented; dedicated cost-review and heatmap cards remain missing. |
| Activity history | Implemented | Complete paging, filters, map/list, summaries, parking detail, configurable adjacent-drive display grouping and local period-recap posters. Recaps preserve missing-data coverage, mark partial history and hide exact dates and costs by default. |
| Notifications | Partial | Local charging, Sentry and tyre alerts exist. Remote APNs, navigation synchronization, parking status and richer multi-car naming remain missing. |
| Widgets and App Shortcuts | Implemented | Read-only status, battery trend and 30-day charging trend widgets can be configured per vehicle using opaque server-scoped identities; localized shortcuts open Dashboard, Current Charge, Charges, Drives and Activities with safe vehicle fallback. Trend snapshots exclude locations and exact event times. |
| Drive classification and notes | Implemented | Commute, personal, business, road-trip and custom classifications, notes, passengers and export exist. Add activity-list classification filters and bulk editing only after real-device workflow validation. |
| Achievements | Implemented | Server achievements, linked drives and local 1080 x 1350 achievement cards. Cards default-hide unlock dates, place names and progress details, and never include raw coordinates or related drive IDs. Mosaic exploration and personalized visual rewards remain missing. |
| Sharing | Partial | Native drive, activity-period, battery, achievement and multi-drive trip report cards render locally. Trip reports omit custom names and default-hide exact dates, locations, route shape and costs; battery reports never present late-recording retention as lifetime health; achievement cards default-hide unlock dates, place names and progress details. All cards preserve missing-value coverage and warn before sensitive fields are enabled. CSV export remains available. Dedicated cost-review/heatmap cards and richer layouts remain missing. |
| Offline context | Implemented | Vehicle-scoped dashboard snapshots, cached routes and summaries, 30-day protected API-response cache, coalesced foreground/background full sync, per-page activity checkpoints, bounded detail loading, cache-age display and explicit purge controls. Page caches warm before expensive history details, while iOS background refresh and processing tasks resume incomplete work when the system grants execution time. Continue multi-car and long-offline device QA. |
| Deployment and diagnostics | Partial | Connection diagnostics, API capability checks and privacy-safe in-app text export exist. Add optional backup/upgrade guidance without handling database credentials. |

## Priority Order

1. App Store and device readiness: signing, physical-device QA, support/privacy URLs, screenshots and review notes.
2. Cost accuracy: searchable regional currency, explicit units, batch charging-cost writeback, persisted/exportable audit history and reusable privacy-scoped tariff templates are implemented; next add privacy-reviewed template file sharing.
3. Native iOS experience: Live Activity, Dynamic Island, localized App Shortcuts, configurable multi-car widgets, battery trends and 30-day charging trends are implemented; next validate Lock Screen/accessory widget variants only after privacy and real-device QA.
4. Explainable insights: score inputs, confidence, missing-sample handling and recommendations are implemented; next validate richer inputs against real server evidence.
5. Sharing: privacy-safe drive, activity-period recap, battery, achievement and multi-drive trip report cards are implemented with selectable sensitive fields, explicit missing-data coverage and calibration disclosure; next add dedicated cost-review/heatmap cards and richer privacy-reviewed layouts.
6. Global reach: Simplified Chinese, Traditional Chinese, and English are implemented. Add Japanese, Korean, French, and other locales only after each locale passes equivalent feature and full-catalog coverage gates.

Features are marked complete only after the feature matrix, manual checklist, automated tests and real API integration all agree.
