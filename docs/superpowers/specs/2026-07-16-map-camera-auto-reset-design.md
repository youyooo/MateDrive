# MateDrive Map Camera Auto-Reset Design

**Date:** 2026-07-16  
**Status:** Approved direction and scope; awaiting written-spec review  
**Product:** MateDrive iOS

## Purpose

Every interactive map in MateDrive should let the user pan or zoom temporarily, then return to the map's data-defined default view after three seconds without further interaction. The behavior must be consistent across the dashboard, activities, driving maps, drive and charge details, trips, places, insights, and historical location views. Route replay must keep playing while its camera resets.

## Behavior

- A user pan, pinch, rotation, or pitch gesture marks the camera as user-controlled.
- When that interaction ends, MateDrive starts a three-second reset delay.
- A new interaction cancels the pending reset and starts a fresh three-second delay after it ends.
- The reset returns to the latest data-defined target, not a stale camera captured when the page first appeared.
- Reset uses a short ease-in-out camera animation. When Reduce Motion is enabled, it resets without animation.
- Leaving the page cancels pending work.
- Programmatic camera changes, data refreshes, marker selection, route playback, and moving replay markers do not start the delay.
- Route replay continues from the same sample and does not restart, pause, or jump when the camera resets.

## Scope

The behavior applies to every user-interactive map surface, including:

- dashboard vehicle location;
- activity overview and activity location details;
- recent driving map;
- drive route replay;
- charge detail;
- trip detail;
- place insights and top standby-drain locations;
- commute route insight;
- historical `Where Was I` location.

Maps that contain one point reset to their original center and span. Multi-point maps reset to the current route or marker bounding region. Maps whose data changes while a delay is pending reset to the new data region.

## Architecture

### SwiftUI Maps

SwiftUI map surfaces use a shared camera auto-reset modifier backed by a small main-actor controller. Each map owns a bound `MapCameraPosition` and supplies a closure that returns its current default position.

The modifier listens at the end of a camera interaction and schedules one cancellable task. It only schedules when `MapCameraPosition.positionedByUser` is true, preventing programmatic updates from creating reset loops. On expiry it requests the latest default position and assigns it once with the appropriate animation.

Single-point maps that currently use only `initialPosition` move to a small reusable map wrapper so parent screens do not duplicate camera state and cancellation logic.

### Route Replay Map

The route replay map keeps its incremental `MKMapView` implementation. Its coordinator records the full-route region, distinguishes user gestures from programmatic region changes, and owns one cancellable reset task. The task calls `setRegion` after three idle seconds while a suppression flag prevents the animated reset from scheduling itself again.

Moving the current vehicle annotation and updating the traveled polyline remain independent from camera state. Camera reset therefore does not invalidate route samples, charts, playback progress, or the containing SwiftUI page.

## Performance Constraints

- No repeating `Timer`, display link, polling loop, or continuous camera callback is permitted for auto-reset.
- SwiftUI maps observe camera changes only at interaction end.
- Each visible map may own at most one pending sleep task; rescheduling cancels the previous task.
- Reset changes only camera state. It must not rebuild route samples, refetch data, or recompute chart series.
- Route bounds and static map geometry are computed when their source data changes, not during camera animation.
- The shared controller contains no network, persistence, or view-model dependency.

## Error And Lifecycle Handling

- Empty or invalid coordinates produce no reset target and schedule no work.
- If map data disappears before the delay expires, the pending task exits without changing the camera.
- A task cancelled by a new gesture or page disappearance performs no reset.
- Programmatic reset completion is ignored as a user interaction.
- Map selection remains intact across reset.

## Verification

Automated tests cover:

- the three-second delay policy;
- cancellation and replacement after repeated interactions;
- retrieving the newest reset target at execution time;
- cancellation on disappearance;
- prevention of programmatic reset loops;
- replay reset preserving the selected sample and playback state.

Simulator and phone checks cover every map surface. For each map, move or zoom it, interact again before three seconds, confirm the countdown restarts, then confirm it returns to the expected data region. During route playback, pan the map and verify playback remains responsive before, during, and after camera reset.

The full MateDrive test suite must pass, and the final signed build must be installed on the connected iPhone for manual validation.
