# MateDrive Smart Activity Timeline And Tariff Design

**Date:** 2026-07-18  
**Status:** Approved product direction; awaiting written-spec review  
**Product:** MateDrive iOS

## Purpose

Add a fourth root tab named **Activity / 动态** and turn the existing independent drive, parking, sleep, and charging records into a cached chronological vehicle story. The new experience must answer four questions without making the user wait for a foreground request:

1. What did the vehicle do?
2. Why was it probably at that place?
3. What changed while it was parked?
4. What did a charging session probably cost, and why?

The feature must preserve source accuracy. Raw TeslaMate and TeslaMateApi records remain immutable. Derived activity groups may be rebuilt when the classifier improves. User-confirmed labels, prices, and costs are stored separately and always override inferred values.

## Scope And Delivery Boundaries

This design is one product experience implemented through four bounded subsystems:

1. cached activity-session reconstruction;
2. parking and sleep change calculation;
3. place and purpose classification;
4. tariff selection and charge-cost estimation.

The root Activity tab consumes the outputs of those subsystems. Each subsystem must remain independently testable and versioned. Implementation may be delivered incrementally, but the Activity tab is not considered complete until all four outputs can coexist in one timeline.

This iteration does not obtain the phone's location, control the vehicle, scrape charging-operator applications, or claim that vehicle-reported charge energy equals a utility meter reading. Public charging prices that cannot be verified remain estimates or require user confirmation.

## Root Navigation

Configured users see four native tabs in this order:

1. **Home / 首页** using `house.fill`;
2. **Activity / 动态** using `clock.arrow.circlepath`;
3. **Features / 功能** using `square.grid.2x2.fill`;
4. **Settings / 设置** using `gearshape.fill`.

Activity owns an independent `NavigationStack` and path, matching the existing Home, Features, and Settings architecture. Switching tabs preserves scroll position and navigation state. Opening Activity, returning to an already-open activity detail, or switching tabs performs no foreground API request.

The existing Activities feature remains available during migration. Once the new timeline has feature parity, its list and map modes become Activity-tab views rather than a duplicate top-level feature card.

## Canonical Event Inputs

The reconstruction engine reads only locally cached inputs:

- drive summaries and cached drive details;
- charge summaries and cached charge details;
- unified activity records, including parking records;
- vehicle state history and sleep intervals;
- configured geofences;
- user activity-label decisions;
- charge cost overrides and pricing rules.

An input records its source identifier, source timestamp, and completeness. Missing data is not replaced with zero. Every derived metric carries a quality state:

- **complete**: both boundaries and required samples are present;
- **partial**: the value can be calculated but one or more internal spans are missing;
- **estimated**: the value uses an explicit fallback or pricing assumption;
- **unavailable**: there is not enough evidence to display a value.

## Activity Session Reconstruction

An activity session is centered on a stay at one place and may contain:

`arrival drive -> parking -> sleep or wake periods -> charging -> departure drive`

The session has a stable identifier anchored to the car ID and the first available source event at the stay. An open session can be updated when a later charge or departure drive arrives without creating a duplicate card.

Events belong to the same session when all applicable checks pass:

- the arrival endpoint, parking point, charge point, and departure start are in the same geofence or location cluster;
- timestamps are ordered and do not overlap incorrectly;
- the charge begins no more than 60 minutes after arrival for a short-stop charging session;
- departure begins no more than 90 minutes after charge completion for a completed replenishment trip;
- a home or work stay may remain one session overnight even when those short-stop limits are exceeded;
- an unexplained data gap prevents a high-confidence grouping but does not discard the raw events.

The 60- and 90-minute defaults are classifier constants, not user-facing settings in the first release. They are covered by tests and can be adjusted in a later classifier version.

### Session Kinds

- **replenishment trip**: arrival, charging, and prompt departure at a charging place;
- **home charging stay**: charging in a confirmed Home geofence, normally AC, regardless of overnight duration;
- **work charging stay**: charging in a confirmed Work geofence;
- **commute stay**: a confirmed or confidently suggested Home-to-Work or Work-to-Home pattern;
- **shopping stay**: a shopping place or user-confirmed shopping pattern;
- **pickup or drop-off**: a user-confirmed school or pickup place with a recurring time window and short dwell;
- **parking stay**: a stay without enough evidence for a more specific purpose;
- **unclassified**: the source events are valid but purpose evidence is insufficient.

Arrival and departure drives remain individually accessible from the session detail. Grouping changes presentation and analysis only; it never merges or deletes source records.

## Place And Purpose Classification

Classification combines vehicle coordinates, configured geofences, charging state, time of day, day of week, dwell duration, route recurrence, and prior user decisions. Evidence priority is:

1. user-confirmed label for this session;
2. user-confirmed rule for the same place and matching time window;
3. explicit Home, Work, Charging, or Parking geofence;
4. repeated place and schedule pattern;
5. one-time heuristic suggestion.

The engine produces a proposed kind, confidence score, reason codes, and classifier version. It does not silently promote a one-time heuristic to a permanent fact.

- confidence of 0.80 or greater may show a suggested label;
- lower confidence stays unclassified;
- a confirmed place-and-time rule may classify future matching sessions automatically;
- the UI always exposes the evidence, such as `Home geofence + AC + 23:00 start`;
- users can rename a label, choose an icon and color, limit it to a time window, or remove the learned rule.

Existing commute classification remains the source of truth for route similarity. This feature adds place-purpose context rather than implementing a second competing commute algorithm.

The existing geofence kinds are extended with **Shopping / 商场** and **School or Pickup / 学校或接送**. Existing saved geofences continue decoding unchanged. A custom activity label may still be attached to any geofence kind, so the enum does not need to grow for every user-specific destination.

## Parking Interval Metrics

A parking interval starts at the previous drive's end or the parking record start, whichever is best supported. It ends at the next drive's start or the parking record end. The calculation records:

- start and end time;
- total parked duration;
- start and departure battery percentage;
- battery percentage change;
- start and departure rated or displayed range;
- rated-range change;
- estimated energy change when supported;
- total sleep duration;
- total awake duration;
- wake count;
- matched geofence and place;
- data-quality state and missing-evidence reason codes.

Charging inside the interval is split from standby change:

1. standby before charging;
2. charge gain;
3. standby after charging.

The displayed net change is accompanied by those components. For example, a stay that loses 1% before charging, gains 30%, and loses 1% after charging shows `net +28%`, `charged +30%`, and `standby -2%`. It must never present the net gain as negative standby drain.

When only boundary percentages exist, energy in kWh remains unavailable unless a documented battery-capacity estimate is enabled. A derived kWh value is always labeled estimated and is not used as a battery-health measurement.

## Charge Energy Semantics

MateDrive distinguishes three values when the source supports them:

- **vehicle-reported energy added**;
- **battery percentage gained**;
- **charger or utility-meter energy**.

TeslaMateApi fields are labeled according to their documented source. A value is not called charger-meter energy merely because it is used for charge-cost estimation. If only vehicle-reported energy is available, the cost card states that the amount is estimated from vehicle data. A user may enter the billed energy or final amount from a receipt, which becomes the authoritative value for that session.

## Tariff Architecture

Tariff resolution extends the existing `ChargePricingRule`, `ChargePricingTimeSegment`, rule validity dates, charger identity, station coordinates, session fee, and manual charge-cost override. It does not create a parallel price engine.

The winning cost source is selected in this order:

1. manual final cost for the individual charge;
2. confirmed non-placeholder cost returned by TeslaMateApi;
3. user-confirmed station rule;
4. user-confirmed Home or Work rule;
5. learned station suggestion that the user accepted;
6. active official regional residential-charging template;
7. no cost.

Zero is treated as unknown unless the source explicitly marks the session as free. The UI displays the winning source and never replaces a higher-priority value in the background.

### Cost Components

A tariff may contain:

- one or more time-of-use energy-price segments;
- a charging service fee per kWh;
- a fixed session fee;
- a parking fee reference;
- currency;
- charger type;
- effective date range;
- weekday, weekend, season, or month constraints.

Energy samples are allocated across time segments using the existing segmented-energy calculation. If sample-level energy is unavailable, the allocation is proportional to elapsed time and is labeled estimated. Parking fees continue to use the separate parking-fee rule engine and are shown as a separate component rather than folded silently into electricity cost.

## Station Learning

After a charge with no authoritative price, Activity shows an estimated-cost card and a single **Confirm price / 确认价格** action. The editor accepts:

- final paid amount;
- billed energy;
- price per kWh;
- service fee;
- fixed or parking fee;
- applicable time window;
- whether the rule should apply to this session only or future sessions at the place.

When the user applies the value to future sessions, MateDrive stores a station rule bound to the location cluster or geofence, charger identity, time window, currency, and effective start date. The next matching session is estimated immediately after background synchronization.

One unconfirmed session never creates a permanent tariff. Multiple conflicting observations lower confidence and prompt review. Changing a learned rule recalculates estimates but does not overwrite manually confirmed historical totals.

## Regional Residential Tariff Catalog

The catalog supports all 31 mainland provincial-level regions and is structured so Hong Kong, Macao, Taiwan, and other countries can be added without changing the engine. An entry contains:

- stable region and grid identifier;
- customer and charging class;
- currency;
- seasonal and day-type applicability;
- time segments and price components;
- effective-from and effective-to dates;
- official source URL and document identifier;
- last verification date;
- status: active, historical, superseded, or no verified dedicated tariff.

The initial catalog must not invent a value for a region without a verified official source. Such a region remains selectable but says that no current dedicated template has been verified and directs the user to create a custom rule.

Catalog data ships as human-reviewable JSON in the repository. A build audit rejects entries with prices but no source, no effective date, overlapping time segments, invalid currency, or an expired entry marked active. A bundled catalog is always available offline. The initial implementation updates this catalog through reviewed App releases; remote catalog updates are explicitly out of scope. A future remote design must require signed HTTPS data, prohibit executable content, and preserve all user rules.

The Home tariff region is selected explicitly in Settings. Vehicle-coordinate reverse geocoding may suggest a region but does not silently change it. This avoids applying a travel destination's residential rate to the user's home charger.

The official national policy delegates detailed time-of-use mechanisms to regional authorities, so catalog entries require individual source verification. The historical Hunan entry from `2024-07-01` uses high periods `11:00-14:00` and `18:00-23:00` at CNY 0.704/kWh, flat periods `07:00-11:00` and `14:00-18:00` at CNY 0.604/kWh, and low period `23:00-07:00` at CNY 0.504/kWh. Because the notice states a temporary one-year term, that entry is historical after `2025-06-30` unless a later official document confirms continuation.

Official references:

- National Development and Reform Commission, time-of-use electricity mechanism: <https://www.ndrc.gov.cn/xxgk/jd/jd/202108/t20210802_1292769_ext.html>
- Hunan residential EV charging pilot tariff: <https://fgw.hunan.gov.cn/fgw/xxgk_70899/zcfg/dfxfg/202407/t20240708_33349442.html>

## Persistence And Rebuildability

New derived data uses local SQLite storage:

- `vehicle_activity_sessions`: stable session ID, car ID, start/end, place key, kind, confidence, quality, derivation version, source fingerprint, and JSON payload;
- `activity_label_overrides`: session or place rule, localized user name, icon, color, time window, and update time;
- `charge_pricing_observations`: charge ID, station key, entered values, currency, scope, and confirmation time.

Pricing rules remain in the existing settings model. Confirmed observations may create or update a normal pricing rule through one service boundary. Charge-cost overrides remain in the existing override store.

Derived sessions are disposable and can be rebuilt from cached source records. Label overrides, pricing observations, and manual costs are durable user data and are included in existing export, deletion, and iCloud backup flows. Database migrations are additive and preserve older settings through default decoding.

## Background Data Flow

1. Existing synchronization stores raw summaries, details, activities, and vehicle states.
2. An incremental activity indexer receives the changed source IDs.
3. It reconstructs only affected open or neighboring sessions.
4. Parking metrics, purpose evidence, and tariff estimates are computed off the main actor.
5. One transaction updates the derived session cache.
6. Activity view models observe the local cache and publish the new snapshot.

The view never waits for reconstruction. It displays the last complete snapshot, then updates rows in place after the transaction commits. Repeatedly opening a session detail reads the same cached payload and does not trigger a network request or re-run the classifier.

## Activity Tab Experience

The root screen uses a native list with day sections. A compact segmented control switches between **All / 全部**, **Drive / 行程**, **Charge / 充电**, and **Park / 停车** without fetching data.

Each session card shows only high-value information:

- purpose label and confidence state;
- place and time range;
- arrival or departure route summary;
- parked duration;
- battery and rated-range change;
- charging gain and standby loss as separate values;
- estimated or confirmed cost with source badge.

A replenishment-session detail shows a vertical event timeline, map, arrival drive, parking spans, charge, departure drive, energy comparison, and cost calculation. Source records remain tappable. User edits use a sheet and do not block navigation.

Color is semantic and restrained:

- green for confirmed savings, charging gain, or verified completion;
- orange for estimated values or values needing review;
- blue for drive events;
- indigo for sleep;
- neutral gray for unclassified or incomplete data.

Cards use an 8-point maximum corner radius, stable dimensions, Dynamic Type, and 44-point touch targets. No nested cards or custom floating tab bar are introduced.

## Settings Changes

Settings gains one **Smart Activity / 智能活动** group containing:

- Geofences;
- Activity labels and learned place rules;
- Charging price rules;
- Residential tariff region;
- Tariff catalog version and source status;
- Rebuild derived activity data;
- Clear learned suggestions without deleting source history.

Existing currency, unit, server, authentication, privacy, backup, and manual pricing controls remain the source of truth. Selecting a regional tariff never changes the user's display currency automatically.

## Error And Safety Behavior

- Incomplete source data produces a partial card with the missing reason, not a spinner.
- A data gap prevents high-confidence purpose classification.
- An expired regional tariff is never applied to a new charge.
- A mismatched currency prevents automatic cost combination.
- Conflicting geofences use the smallest valid matching radius, following the existing engine.
- An invalid or overlapping tariff is disabled by validation.
- Failed reconstruction leaves the previous snapshot intact and retries during the next background cycle.
- Manual labels, costs, and accepted station rules survive classifier rebuilds.
- No tariff estimate is described as an invoice or exact utility-meter amount.

## Privacy

All classification runs on device from TeslaMate vehicle data already configured by the user. MateDrive does not request phone location for this feature. Place labels, learned schedules, price observations, and derived sessions remain in the local database and the user's configured iCloud backup. Regional tariff downloads, if later enabled, send no vehicle coordinates or activity history.

## Verification

Automated tests cover:

- root navigation with four independent tab paths and shortcut routing;
- stable open-session updates when a charge or departure drive arrives;
- location clustering and geofence precedence;
- replenishment, home charging, work, commute, shopping, pickup, parking, and unclassified outcomes;
- confidence thresholds and user-override precedence;
- parking intervals with no charge, one charge, multiple charge spans, missing boundaries, and source gaps;
- separate standby loss, charge gain, and net change;
- sleep duration and wake counts;
- cost-source priority, explicit free charging, currency mismatch, and expired tariffs;
- cross-midnight and multi-segment pricing allocation;
- station-rule learning and non-destructive historical recalculation;
- catalog schema, official-source, effective-date, overlap, and expiry audits;
- persistence migration, export, deletion, and iCloud backup coverage;
- cached Activity and detail opening with zero foreground requests;
- English and Simplified Chinese localization coverage.

Manual tests cover:

- a public DC charge reached at midday and left shortly after charging;
- a Home AC session scheduled after 23:00;
- a charge that crosses two tariff periods;
- the first user-confirmed station price and the next automatic estimate;
- parking with battery and rated-range loss but no charging;
- parking with both charging gain and standby loss;
- offline launch, stale catalog, and incomplete TeslaMate history;
- repeated Activity-detail opening and tab switching on a physical iPhone;
- light and dark mode, large Dynamic Type, and smaller iPhone layouts.

The full MateDrive test suite, localization audit, privacy audit, and release archive audit must pass before a TestFlight build is uploaded.
