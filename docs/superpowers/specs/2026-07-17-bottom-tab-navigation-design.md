# MateDrive Bottom Tab Navigation Design

**Date:** 2026-07-17  
**Status:** Approved visual direction; awaiting written-spec review  
**Product:** MateDrive iOS

## Purpose

Replace the dashboard's long mixed list of data and destinations with a native three-tab structure:

1. **Home / 首页** shows the current vehicle and the most frequently checked cached data.
2. **Features / 功能** contains the app's top-level feature cards.
3. **Settings / 设置** contains server configuration, synchronization controls, language, units, pricing, privacy, and app information.

The approved dashboard upper area remains visually intact. This change reorganizes navigation and presentation; it does not add foreground network requests or change the data contracts of existing feature pages.

## Root Navigation

Configured users enter a native SwiftUI `TabView` with Home selected. The tabs use `house.fill`, `square.grid.2x2.fill`, and `gearshape.fill`, with localized text labels. Settings is always the rightmost tab.

Each tab owns an independent `NavigationStack` and path:

- Home destinations return to the same Home stack.
- Feature-card destinations return to the same Features stack.
- Settings navigation remains in the Settings stack.
- Switching tabs preserves each tab's scroll and navigation state.

The tab bar uses native safe-area, VoiceOver, Dynamic Type, and appearance behavior. MateDrive's green is the selected accent; unselected items use the system secondary color. No custom floating tab-bar container is introduced.

When the app is not configured, it continues to show the existing Settings flow without Home or Features tabs. The tabs appear only after a valid server configuration has been saved. This prevents unusable tabs during first-run setup.

## Home Tab

Home keeps the approved content and ordering:

- MateDrive navigation title;
- refresh button on the top right;
- vehicle name and Performance underline treatment;
- software version and vehicle status;
- battery/range ring and charging animation;
- tyre pressures arranged around the ring;
- vehicle location map and address.

The existing top-left Settings button is removed because Settings is permanently available from the tab bar.

The current History and Odometer cards and the complete navigation-card grid are removed from Home. A compact three-column **Vehicle Overview / 车辆概览** strip follows the map:

- Odometer, opening Mileage;
- total drives, opening Activities;
- total charges, opening Charges.

The strip uses the values already present in `DashboardState`. Missing values remain visible as stable placeholders. It does not query daily aggregates or trigger a new API or database request. This keeps Home short and immediately usable from its existing cached snapshot.

## Features Tab

`FeatureHubView` is a static, scrollable catalog for the selected vehicle. It shows the selected vehicle name below the title and reuses the compact vehicle selector when more than one vehicle is available.

Feature cards are grouped in two columns with an 8-point corner radius, one SF Symbol, a localized title, a concise localized supporting line, and a stable minimum height. The full card is tappable. Cards do not show live values and perform no work until tapped.

### Common / 常用

- Current Charge
- Activities
- Drives
- Battery

### Charging And Driving / 充电与驾驶

- Charges
- Recent Driving Map
- Trips
- Energy Balance

### Data Insights / 数据洞察

- Stats
- Mileage
- Place Insights
- Drive Insights
- Environment History
- Standby Hotspots
- Commute Routes

### Vehicle Records / 车辆记录

- Achievements
- Updates
- Sentry

Detail-only destinations such as charge details, drive details, comparisons, and trip creation remain inside their parent features rather than appearing as top-level cards. Cost Review and Driving Records remain reachable from their existing parent analysis screens unless a later design explicitly promotes them.

When there is no selected vehicle, the Features tab shows a compact empty state with a button that switches to Settings. It does not attempt a server request to discover a vehicle.

## Settings Tab

The right tab reuses the existing complete `SettingsView` and shared `SettingsViewModel`. Existing server URLs, authentication modes, Cloudflare credentials, diagnostics, synchronization health, notifications, language, units, currency, battery calibration, charging-price rules, privacy controls, import/export, and save behavior remain unchanged.

This iteration does not split Settings into new subpages. The visual mockup's grouped settings rows describe the information hierarchy; the implementation retains the current grouped `Form` so server and authentication behavior are not destabilized during the navigation change.

## Shared Vehicle Context

Home and Features use one shared `DashboardViewModel` instance owned by `RootView`. This gives both tabs the same selected car, exterior color, cached state, and vehicle-selector updates without constructing a second dashboard API or loading the car list twice.

Changing the vehicle from Home or Features updates the shared model and existing persisted selection. Both tabs redraw from that state. Feature routes are built from the latest selected car ID and exterior color at tap time.

The background synchronization revision continues to refresh the shared dashboard state from the cache. The redesign must not create a second foreground refresh path.

## Route Handling

Root navigation distinguishes tab changes from pushed destinations:

- `.dashboard` selects Home and returns Home to its root.
- `.settings` selects Settings and returns Settings to its root.
- A route tapped on Home is appended to the Home path.
- A route tapped in Features is appended to the Features path.
- App shortcuts for vehicle features select Features and push the requested route.
- Existing shortcuts for Dashboard and Settings select the corresponding tab.

The existing destination factory remains shared by the Home and Features stacks. No feature view is instantiated inside a card.

## Performance And Cache Behavior

- `FeatureHubView` has no `.task`, `onAppear` request, timer, polling, or preloading loop.
- Home retains its current cached-first `DashboardViewModel` behavior.
- Tab switching performs no API request and no cache invalidation.
- Destination pages retain their existing cache-only providers and background-refresh lifecycle.
- Each tab preserves its navigation path so returning to a tab does not reconstruct its last visible detail page.
- Feature-card identity and ordering are stable across dashboard state updates.
- No custom tab-bar animation, matched geometry effect, or continuous visual effect is added.

## Visual And Interaction Rules

- Home keeps the current neutral surface, green battery treatment, red Performance underline, and map presentation.
- Feature cards use neutral secondary surfaces. Green is reserved for the selected tab and meaningful active state, not every decorative element.
- Cards are not nested inside other cards, and no page section is styled as a floating card.
- Text may wrap to two lines where needed and must remain readable in English and Simplified Chinese.
- All cards and tab items expose at least a 44-point touch target.
- VoiceOver order follows the visual order within each tab.
- Reduce Motion requires no special replacement because the new navigation uses native transitions and standard button feedback.

## Localization

The string catalog gains localized labels for:

- Home, Features, Settings;
- Vehicle Overview;
- the four feature-group headings;
- feature-card supporting lines;
- the no-vehicle Features empty state.

Existing route titles and unit formatters remain the source of truth for feature names and values. Simplified Chinese and English must have complete coverage.

## Error And Empty States

- During initial configuration, only Settings is shown.
- If cached dashboard data is unavailable after configuration, Home keeps the existing loading and error presentation.
- Vehicle Overview placeholders do not collapse the layout.
- Features remains static and responsive even while Home is loading.
- If the selected car becomes unavailable, vehicle-specific cards are disabled and the user is directed to Settings rather than starting a foreground discovery request.
- Existing Settings validation and connection-test errors remain unchanged.

## Verification

Automated tests cover:

- default tab selection for configured and unconfigured states;
- Dashboard and Settings tab routing;
- shortcut routing into the correct tab and stack;
- independent Home and Features navigation paths;
- shared selected-vehicle state across Home and Features;
- feature groups, item order, and top-level route coverage;
- Home Vehicle Overview formatting and destinations;
- no-vehicle Features behavior;
- English and Simplified Chinese localization coverage.

Manual simulator checks cover:

- switching repeatedly among all three tabs without loading pauses;
- navigating several levels deep in Home and Features, switching tabs, and returning to the preserved page;
- changing the selected vehicle and confirming both tabs update;
- light and dark mode;
- metric and imperial units;
- English and Simplified Chinese;
- large Dynamic Type and smaller iPhone layouts;
- cached/offline launch and background synchronization updates;
- first-run configuration before the tab bar appears.

The full MateDrive test suite must pass. If the connected iPhone remains available, the signed build is installed for final tab switching, touch-target, scroll, cache, and navigation-state verification.
