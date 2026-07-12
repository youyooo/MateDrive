# MyTesS Competitive Parity Roadmap

Source reviewed: `https://cn.mytess.net/zh` on 2026-07-12. This roadmap tracks observable product capabilities, not marketing wording or visual copying.

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
| Drive insights | Partial | Commute clusters, records and measured metrics exist. Missing a transparent, user-auditable driving score and actionable recommendations. |
| Multi-drive trips | Implemented | Automatic/manual grouping, weather, route, timeline, countries, charge stops and persistence. Photos and story-style share output remain missing. |
| Charging history and live charge | Implemented | SOC, power, energy, voltage, duration, cost, curves, comparisons and notifications. Live Activity and Dynamic Island remain missing. |
| Time/location charging prices | Implemented | Geofence/type/time/effective-date rules, synchronized charger identity, safe batch preview, selected-history API 2.6 writeback, per-record results, rollback evidence, vehicle-scoped persistent audit history and privacy-safe CSV export. Tariff-template sharing is the next quality bar. |
| Place insights | Implemented | Server smart places plus complete-history fallback, charging, parking, cost quality and standby drain. |
| Parking costs | Implemented | Free time, increments, fixed/hourly/monthly fees, caps, priorities and unmatched coverage. |
| Statistics and cost review | Implemented | Driving, energy, charging, parking, calendar heatmap, records and API 2.6 cost review. Add shareable recaps. |
| Activity history | Implemented | Complete paging, filters, map/list, summaries and parking detail. Adjacent-drive merge and recap sharing remain missing. |
| Notifications | Partial | Local charging, Sentry and tyre alerts exist. Remote APNs, navigation synchronization, parking status and richer multi-car naming remain missing. |
| Widgets | Implemented, single selected car | Read-only status widget with per-car data isolation. Add configurable multi-car widgets and App Shortcuts. |
| Drive classification and notes | Partial | Notes, purpose, passengers and export exist. Add commute/road-trip/custom classification workflows and bulk filtering. |
| Achievements | Implemented | Server achievements and linked drives. Mosaic exploration and personalized visual rewards remain missing. |
| Sharing | Major gap | CSV export exists. Native share cards for drives, battery, trips, achievements and period recaps are not implemented. |
| Offline context | Implemented | Vehicle-scoped recent dashboard snapshot and cached routes. Expand explicit cache age and purge controls. |
| Deployment and diagnostics | Partial | Connection diagnostics, API capability checks and privacy-safe in-app text export exist. Add optional backup/upgrade guidance without handling database credentials. |

## Priority Order

1. App Store and device readiness: signing, physical-device QA, support/privacy URLs, screenshots and review notes.
2. Cost accuracy: searchable regional currency, explicit units, batch charging-cost writeback and persisted/exportable audit history are implemented; next add reusable tariff templates and privacy-reviewed template sharing.
3. Native iOS experience: Live Activity, Dynamic Island, configurable widgets and App Shortcuts.
4. Explainable insights: documented score inputs, confidence, missing-sample handling and recommendations.
5. Sharing: privacy-reviewed native cards with selectable fields and map redaction.
6. Global reach: Traditional Chinese is implemented. German, Spanish, Italian and Catalan now pass both feature-specific coverage gates and a full-catalog English-equivalent allowlist; only approved brands, technical abbreviations, official Tesla color names and genuinely identical words may match English. Add Japanese, Korean and French only after each locale passes equivalent coverage.

Features are marked complete only after the feature matrix, manual checklist, automated tests and real API integration all agree.
