# MateDrive Smart Activity Timeline And Tariffs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cached fourth-tab Activity timeline that reconstructs complete stays and replenishment trips, separates parking drain from charging gain, classifies place purpose, and estimates charge costs from user-confirmed station rules or verified regional tariffs.

**Architecture:** Immutable TeslaMate activities and sleep intervals feed pure reconstruction, parking-analysis, classification, and pricing components. A background indexer stores versioned derived sessions in SQLite, while user labels and pricing observations remain durable overrides. SwiftUI reads only the local session store, so tab switching and detail navigation never wait for network or classification work.

**Tech Stack:** Swift 6.3, SwiftUI, Foundation, MapKit, SQLite3 through the existing persistence layer, XcodeGen, XCTest, Python 3 audit scripts, iOS 18.0+

**Design Spec:** `docs/superpowers/specs/2026-07-18-smart-activity-timeline-and-tariffs-design.md`

## Global Constraints

- Preserve all existing uncommitted workspace changes; do not revert or replace unrelated edits.
- Keep `IPHONEOS_DEPLOYMENT_TARGET` at `18.0` and `SWIFT_VERSION` at `6.3`.
- Add no third-party runtime dependency.
- Never mutate or delete raw TeslaMate, TeslaMateApi, drive, charge, parking, or sleep records.
- Activity screens may read SQLite and local caches only; they must make zero foreground HTTP requests.
- Missing values remain unavailable or partial; never replace missing battery, range, energy, or price data with zero.
- User-confirmed labels, station rules, final costs, and explicit free sessions always outrank inferred values.
- Do not request phone location. Use only configured geofences and TeslaMate vehicle coordinates.
- Apply an official residential tariff only to AC charging in a confirmed Home geofence and only inside its effective date range.
- Every regional tariff with a numeric price must include an official source URL, document ID, verification date, currency, and effective dates.
- Ship a bundled tariff catalog only. Remote tariff updates are out of scope for this implementation.
- Keep English and Simplified Chinese visible strings complete in `Localizable.xcstrings`.
- Use native `TabView`, `NavigationStack`, safe areas, Dynamic Type, VoiceOver, and Reduce Motion behavior.
- Use semantic colors and card corner radii no greater than 8 points; do not nest cards.
- Run focused tests after every task and the full release gate before changing the build number or uploading TestFlight.

## File Map

### Domain And Reconstruction

- Create `MateDriveApp/Features/Activities/SmartActivityModels.swift`: shared immutable types, quality states, session payloads, purpose results, and stable IDs.
- Create `MateDriveApp/Features/Activities/ParkingIntervalAnalyzer.swift`: pure parking, charge-gain, standby-change, and sleep calculations.
- Create `MateDriveApp/Features/Activities/ActivitySessionReconstructor.swift`: event ordering, place matching, open-session updates, and replenishment grouping.
- Create `MateDriveApp/Features/Activities/ActivityPurposeClassifier.swift`: evidence precedence and confidence calculation.

### Persistence And Background Indexing

- Modify `MateDriveApp/Core/Persistence/Migrations.swift`: migration 23 for derived sessions, label overrides, and pricing observations.
- Modify `MateDriveApp/Core/Persistence/Migration.swift`: set `DatabaseSchemaVersion.current` to 23.
- Create `MateDriveApp/Core/Persistence/Records/SmartActivityRecords.swift`: database row models.
- Create `MateDriveApp/Core/Persistence/Stores/SmartActivityStore.swift`: session and label storage protocols and SQLite implementation.
- Create `MateDriveApp/Core/Persistence/Stores/ChargePricingObservationStore.swift`: confirmed pricing observation storage.
- Create `MateDriveApp/Core/Sync/SmartActivityIndexer.swift`: cached source loading and incremental rebuild service.
- Modify `MateDriveApp/Core/Sync/BackgroundRefreshWorkRunner.swift`: run indexing after source synchronization.
- Modify `MateDriveApp/App/MateDriveApp.swift`: construct and inject the live indexer.

### Tariffs And Cost Resolution

- Create `MateDriveApp/Features/Charges/RegionalChargingTariff.swift`: catalog types and active-entry lookup.
- Create `MateDriveApp/Resources/RegionalChargingTariffs.json`: reviewed records for all 31 mainland provincial-level region codes.
- Modify `MateDriveApp/Features/Charges/ChargePricingRule.swift`: rule provenance and extended fee constraints.
- Create `MateDriveApp/Features/Charges/ChargeCostResolver.swift`: explicit source precedence and regional Home fallback.
- Create `MateDriveApp/Features/Charges/ChargePricingObservationService.swift`: convert confirmed observations into future station rules.
- Create `scripts/audit_regional_tariffs.py`: catalog integrity and source audit.
- Create `scripts/test_audit_regional_tariffs.py`: deterministic audit tests.
- Modify `Makefile` and `project.yml`: include the catalog and audit in generation and preflight.

### Activity And Settings UI

- Create `MateDriveApp/Features/Activities/ActivityTimelineViewModel.swift`: store-only timeline state and filters.
- Create `MateDriveApp/Features/Activities/ActivityTimelineView.swift`: fourth-tab list and cached states.
- Create `MateDriveApp/Features/Activities/ActivitySessionCard.swift`: stable session summary presentation.
- Create `MateDriveApp/Features/Activities/ActivitySessionDetailView.swift`: event timeline, map, parking breakdown, source links, and edits.
- Create `MateDriveApp/Features/Activities/ParkingActivityDetailView.swift`: extracted reusable cached parking detail.
- Create `MateDriveApp/Features/Activities/ActivityLabelEditorView.swift`: session/place confirmation editor.
- Create `MateDriveApp/Features/Charges/ChargePriceConfirmationView.swift`: final amount and future station-rule editor.
- Create `MateDriveApp/Features/Settings/SmartActivitySettingsView.swift`: labels, tariff region, catalog status, and rebuild controls.
- Modify `MateDriveApp/App/RootTabNavigation.swift`, `MateDriveApp/App/RootView.swift`, and `MateDriveApp/App/AppRoute.swift`: four-tab paths and activity detail routing.
- Modify `MateDriveApp/Features/Settings/AppSettings.swift`, `SettingsViewModel.swift`, and `SettingsView.swift`: geofence kinds, home tariff region, and smart-activity settings.
- Modify `MateDriveApp/Features/Charges/ChargeDetailViewModel.swift` and `ChargeDetailView.swift`: shared cost resolution and confirmation entry point.
- Modify `MateDriveApp/Features/Settings/PrivacyDataView.swift`: derived-data and learned-suggestion clearing.
- Modify `MateDriveApp/Resources/Localizable.xcstrings`: all new English and Simplified Chinese copy.

---

### Task 1: Parking Interval Domain And Analyzer

**Files:**
- Create: `MateDriveApp/Features/Activities/SmartActivityModels.swift`
- Create: `MateDriveApp/Features/Activities/ParkingIntervalAnalyzer.swift`
- Test: `MateDriveTests/Features/ParkingIntervalAnalyzerTests.swift`

**Interfaces:**
- Consumes: `TeslaMateActivity`, `SleepInterval`, and `DomainDateParser.date(from:)`.
- Produces: `ActivityMetricQuality`, `ParkingIntervalInput`, `ParkingIntervalMetrics`, and `ParkingIntervalAnalyzer.analyze(_:)`.

- [ ] **Step 1: Write failing parking-component tests**

```swift
import XCTest
@testable import MateDriveApp

final class ParkingIntervalAnalyzerTests: XCTestCase {
    func testSeparatesChargeGainFromStandbyLoss() throws {
        let park = TeslaMateActivity(
            id: 10,
            type: "park",
            startDate: "2026-07-18T18:00:00+08:00",
            endDate: "2026-07-19T07:00:00+08:00",
            durationMin: 780,
            soc: 50,
            socDiff: 28,
            rangeDiffKm: 132,
            endRangeKm: 300
        )
        let charge = TeslaMateActivity(
            id: 11,
            type: "charge",
            startDate: "2026-07-18T23:00:00+08:00",
            endDate: "2026-07-19T01:00:00+08:00",
            kwh: 18,
            soc: 49,
            socDiff: 30
        )

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [charge], sleepIntervals: [])
        ))

        XCTAssertEqual(metrics.startBatteryPercent, 50)
        XCTAssertEqual(metrics.endBatteryPercent, 78)
        XCTAssertEqual(metrics.netBatteryChangePercent, 28)
        XCTAssertEqual(metrics.chargeGainPercent, 30)
        XCTAssertEqual(metrics.standbyBatteryChangePercent, -2)
        XCTAssertEqual(metrics.quality, .complete)
    }

    func testMissingBatteryBoundaryRemainsPartialInsteadOfZero() throws {
        let park = TeslaMateActivity(
            id: 12,
            type: "park",
            startDate: "2026-07-18T10:00:00+08:00",
            endDate: "2026-07-18T12:00:00+08:00"
        )

        let metrics = try XCTUnwrap(ParkingIntervalAnalyzer.analyze(
            ParkingIntervalInput(parking: park, charges: [], sleepIntervals: [])
        ))

        XCTAssertNil(metrics.startBatteryPercent)
        XCTAssertNil(metrics.netBatteryChangePercent)
        XCTAssertNil(metrics.standbyBatteryChangePercent)
        XCTAssertEqual(metrics.quality, .partial)
    }
}
```

- [ ] **Step 2: Generate the project and run the focused test to verify failure**

Run:

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/ParkingIntervalAnalyzerTests test
```

Expected: FAIL because `ParkingIntervalAnalyzer` and its input/result types do not exist.

- [ ] **Step 3: Implement the immutable metrics and pure analyzer**

Add these exact public interfaces and keep all calculations pure:

```swift
public enum ActivityMetricQuality: String, Codable, Equatable, Sendable {
    case complete, partial, estimated, unavailable
}

public struct ParkingIntervalInput: Equatable, Sendable {
    public let parking: TeslaMateActivity
    public let charges: [TeslaMateActivity]
    public let sleepIntervals: [SleepInterval]
    public let previousDrive: TeslaMateActivity?
    public let nextDrive: TeslaMateActivity?

    public init(
        parking: TeslaMateActivity,
        charges: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        previousDrive: TeslaMateActivity? = nil,
        nextDrive: TeslaMateActivity? = nil
    ) {
        self.parking = parking
        self.charges = charges
        self.sleepIntervals = sleepIntervals
        self.previousDrive = previousDrive
        self.nextDrive = nextDrive
    }
}

public struct ParkingIntervalMetrics: Codable, Equatable, Sendable {
    public let startDate: Date
    public let endDate: Date
    public let duration: TimeInterval
    public let startBatteryPercent: Int?
    public let endBatteryPercent: Int?
    public let netBatteryChangePercent: Int?
    public let chargeGainPercent: Int?
    public let standbyBatteryChangePercent: Int?
    public let startRatedRangeKm: Double?
    public let endRatedRangeKm: Double?
    public let ratedRangeChangeKm: Double?
    public let vehicleReportedChargeEnergyKWh: Double?
    public let sleepDuration: TimeInterval
    public let awakeDuration: TimeInterval
    public let wakeCount: Int
    public let quality: ActivityMetricQuality
    public let missingReasonCodes: [String]
}

public enum ParkingIntervalAnalyzer {
    public static func analyze(_ input: ParkingIntervalInput) -> ParkingIntervalMetrics? {
        guard input.parking.kind == .park,
              let start = input.parking.startDate.flatMap(DomainDateParser.date(from:)),
              let end = input.parking.endDate.flatMap(DomainDateParser.date(from:)),
              start < end else { return nil }

        let previousEndSOC = input.previousDrive?.soc.flatMap { startSOC in
            input.previousDrive?.socDiff.map { startSOC + $0 }
        }
        let startSOC = input.parking.soc ?? previousEndSOC
        let recordedEndSOC = input.parking.soc.flatMap { startSOC in
            input.parking.socDiff.map { startSOC + $0 }
        }
        let endSOC = recordedEndSOC ?? input.nextDrive?.soc
        let netSOC = input.parking.socDiff ?? startSOC.flatMap { start in endSOC.map { $0 - start } }
        let chargeDeltas = input.charges.compactMap(\.socDiff)
        let chargeGain: Int? = input.charges.isEmpty
            ? nil
            : (chargeDeltas.count == input.charges.count ? chargeDeltas.filter { $0 > 0 }.reduce(0, +) : nil)
        let standby = input.charges.isEmpty
            ? netSOC
            : netSOC.flatMap { net in chargeGain.map { net - $0 } }
        let sleep = SleepDurationCalculator.total(intervals: input.sleepIntervals, from: start, to: end)
        let wakeCount = input.sleepIntervals.filter { interval in
            interval.start < end && interval.end > start && interval.end < end
        }.count
        let nextDriveStartRange = input.nextDrive?.endRangeKm.flatMap { endRange in
            input.nextDrive?.rangeDiffKm.map { endRange - $0 }
        }
        let endRange = input.parking.endRangeKm ?? nextDriveStartRange
        let startRange = input.parking.endRangeKm.flatMap { endRange in
            input.parking.rangeDiffKm.map { endRange - $0 }
        } ?? input.previousDrive?.endRangeKm
        let rangeDelta = input.parking.rangeDiffKm ?? startRange.flatMap { start in endRange.map { $0 - start } }
        let missing = [
            startSOC == nil ? "missing_start_soc" : nil,
            netSOC == nil ? "missing_soc_change" : nil,
            (!input.charges.isEmpty && chargeGain == nil) ? "missing_charge_soc_change" : nil,
            endRange == nil ? "missing_end_range" : nil
        ].compactMap { $0 }

        return ParkingIntervalMetrics(
            startDate: start,
            endDate: end,
            duration: end.timeIntervalSince(start),
            startBatteryPercent: startSOC,
            endBatteryPercent: endSOC,
            netBatteryChangePercent: netSOC,
            chargeGainPercent: chargeGain,
            standbyBatteryChangePercent: standby,
            startRatedRangeKm: startRange,
            endRatedRangeKm: endRange,
            ratedRangeChangeKm: rangeDelta,
            vehicleReportedChargeEnergyKWh: input.charges.compactMap(\.kwh).nilIfEmpty?.reduce(0, +),
            sleepDuration: sleep,
            awakeDuration: max(0, end.timeIntervalSince(start) - sleep),
            wakeCount: wakeCount,
            quality: missing.isEmpty ? .complete : .partial,
            missingReasonCodes: missing
        )
    }
}
```

Use a private collection helper instead of exposing `nilIfEmpty` publicly.

- [ ] **Step 4: Add tests for sleep clipping, cross-midnight intervals, multiple charges, and invalid dates**

Add assertions that sleep intervals are clipped to parking boundaries, charge gains are summed, missing charge SOC keeps standby change unavailable, previous-drive end and next-drive start provide boundary fallbacks, awake duration never becomes negative, and malformed date ranges return `nil`.

- [ ] **Step 5: Run the focused test and verify pass**

Run the command from Step 2. Expected: all `ParkingIntervalAnalyzerTests` PASS.

- [ ] **Step 6: Commit the isolated domain change**

```bash
git add MateDriveApp/Features/Activities/SmartActivityModels.swift MateDriveApp/Features/Activities/ParkingIntervalAnalyzer.swift MateDriveTests/Features/ParkingIntervalAnalyzerTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: calculate parking energy changes"
```

### Task 2: Activity Session Reconstruction

**Files:**
- Modify: `MateDriveApp/Features/Activities/SmartActivityModels.swift`
- Create: `MateDriveApp/Features/Activities/ActivitySessionReconstructor.swift`
- Test: `MateDriveTests/Features/ActivitySessionReconstructorTests.swift`

**Interfaces:**
- Consumes: `ParkingIntervalAnalyzer.analyze(_:)`, `GeofenceRuleEngine.matchingRule`, sorted `TeslaMateActivity` values, and sleep intervals.
- Produces: `SmartActivitySession`, `SmartActivityEventReference`, `ActivitySessionReconstructionConfiguration`, and `ActivitySessionReconstructor.reconstruct(carId:events:sleepIntervals:geofences:configuration:)`.

- [ ] **Step 1: Write failing arrival-charge-departure and overnight Home tests**

```swift
func testGroupsArrivalChargeAndPromptDepartureAsOneSession() throws {
    let events = ActivityReconstructionFixtures.publicChargingStop()
    let sessions = ActivitySessionReconstructor.reconstruct(
        carId: 1,
        events: events,
        sleepIntervals: [],
        geofences: [ActivityReconstructionFixtures.chargingFence]
    )

    let session = try XCTUnwrap(sessions.first)
    XCTAssertEqual(session.eventReferences.map(\.kind), [.drive, .park, .charge, .drive])
    XCTAssertEqual(session.provisionalKind, .replenishment)
    XCTAssertFalse(session.isOpen)
}

func testHomeStayAllowsScheduledChargeAfterShortStopWindow() throws {
    let sessions = ActivitySessionReconstructor.reconstruct(
        carId: 1,
        events: ActivityReconstructionFixtures.homeOvernightCharge(arrivalHour: 18, chargeHour: 23),
        sleepIntervals: [],
        geofences: [ActivityReconstructionFixtures.homeFence]
    )

    XCTAssertEqual(sessions.first?.provisionalKind, .homeCharging)
}
```

- [ ] **Step 2: Run the focused test to verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/ActivitySessionReconstructorTests test
```

Expected: FAIL because reconstruction types do not exist.

- [ ] **Step 3: Implement stable session and event-reference types**

```swift
public enum SmartActivityPurpose: String, Codable, CaseIterable, Sendable {
    case replenishment, homeCharging, workCharging, commute, shopping
    case pickupDropoff, parking, custom, unclassified
}

public enum ActivityClassificationSource: String, Codable, Sendable {
    case userSession, userPlaceRule, geofence, learnedPattern, heuristic, none
}

public enum ActivityClassificationReason: String, Codable, Hashable, Sendable {
    case homeGeofence, workGeofence, chargingGeofence, shoppingGeofence
    case schoolGeofence, acCharging, dcCharging, promptDeparture
    case repeatedTimeWindow, repeatedRoute, confirmedOverride
}

public struct ActivityClassificationResult: Codable, Equatable, Sendable {
    public let purpose: SmartActivityPurpose
    public let confidence: Double
    public let source: ActivityClassificationSource
    public let reasons: [ActivityClassificationReason]
    public let classifierVersion: Int
}

public enum SmartActivityChargeCostSource: String, Codable, Equatable, Sendable {
    case manual, api, stationRule, homeRule, regionalTariff
}

public struct SmartActivityChargeCostComponent: Codable, Equatable, Sendable {
    public let kind: String
    public let amount: Double
    public let energyKWh: Double?
    public let pricePerKWh: Double?
}

public struct SmartActivityChargeCost: Codable, Equatable, Sendable {
    public let amount: Double
    public let currencyCode: String
    public let source: SmartActivityChargeCostSource
    public let ruleID: String?
    public let isEstimated: Bool
    public let isExplicitlyFree: Bool
    public let components: [SmartActivityChargeCostComponent]
}

public struct SmartActivityEventReference: Codable, Equatable, Sendable {
    public let kind: TeslaMateActivityKind
    public let sourceID: Int
    public let startDate: String?
    public let endDate: String?
    public let sourceActivity: TeslaMateActivity
}

public struct SmartActivitySession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let startDate: Date
    public let endDate: Date?
    public let placeKey: String
    public let latitude: Double?
    public let longitude: Double?
    public let geofenceID: String?
    public let provisionalKind: SmartActivityPurpose
    public let classification: ActivityClassificationResult?
    public let parkingMetrics: ParkingIntervalMetrics?
    public let chargeCost: SmartActivityChargeCost?
    public let eventReferences: [SmartActivityEventReference]
    public let isOpen: Bool
    public let quality: ActivityMetricQuality
    public let derivationVersion: Int
    public let sourceFingerprint: String
    public let derivationFingerprint: String
}
```

Stable IDs use `carId` plus the center parking source ID. If no parking source exists, use the arrival drive ID. The source fingerprint hashes sorted `kind-sourceID-startDate-endDate` strings with SHA-256. Reconstruction initializes `derivationFingerprint` to the source fingerprint; the background indexer replaces it with the complete classifier/pricing fingerprint in Task 7.

Define the private `ActivityReconstructionFixtures` helper at the bottom of the test file. It returns concrete `TeslaMateActivity` arrays and valid `GeofenceRule` values for the two scenarios above; it is test support, not production API.

- [ ] **Step 4: Implement reconstruction using one stay-centered pass**

```swift
public struct ActivitySessionReconstructionConfiguration: Equatable, Sendable {
    public let chargeStartGrace: TimeInterval
    public let departureGrace: TimeInterval
    public let clusterRadiusMeters: Double

    public init(
        chargeStartGrace: TimeInterval = 60 * 60,
        departureGrace: TimeInterval = 90 * 60,
        clusterRadiusMeters: Double = 250
    ) {
        self.chargeStartGrace = chargeStartGrace
        self.departureGrace = departureGrace
        self.clusterRadiusMeters = clusterRadiusMeters
    }
}

public enum ActivitySessionReconstructor {
    public static func reconstruct(
        carId: Int,
        events: [TeslaMateActivity],
        sleepIntervals: [SleepInterval],
        geofences: [GeofenceRule],
        configuration: ActivitySessionReconstructionConfiguration = .init()
    ) -> [SmartActivitySession] {
        let ordered = events.sorted { eventStart($0) < eventStart($1) }
        return ordered.filter { $0.kind == .park }.compactMap { parking in
            buildSession(
                carId: carId,
                parking: parking,
                events: ordered,
                sleepIntervals: sleepIntervals,
                geofences: geofences,
                configuration: configuration
            )
        }.sorted { $0.startDate > $1.startDate }
    }
}
```

`buildSession` must attach only temporally ordered events at the same smallest matching geofence or within 250 meters. Home and Work geofences waive the 60-minute charge-start limit; all other locations use both configured limits.

- [ ] **Step 5: Add open-session, duplicate-event, location-mismatch, and source-gap tests**

Assert an unfinished parking record remains one `isOpen` session, a later departure updates its fingerprint without changing its stable ID, and events at different coordinates never merge.

- [ ] **Step 6: Run focused tests and commit**

Run the Step 2 command. Expected: PASS.

```bash
git add MateDriveApp/Features/Activities/SmartActivityModels.swift MateDriveApp/Features/Activities/ActivitySessionReconstructor.swift MateDriveTests/Features/ActivitySessionReconstructorTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: reconstruct smart activity sessions"
```

### Task 3: Derived Session And Override Persistence

**Files:**
- Modify: `MateDriveApp/Core/Persistence/Migrations.swift`
- Modify: `MateDriveApp/Core/Persistence/Migration.swift`
- Create: `MateDriveApp/Core/Persistence/Records/SmartActivityRecords.swift`
- Create: `MateDriveApp/Core/Persistence/Stores/SmartActivityStore.swift`
- Create: `MateDriveApp/Core/Persistence/Stores/ChargePricingObservationStore.swift`
- Test: `MateDriveTests/Persistence/SmartActivityStoreTests.swift`
- Modify test: `MateDriveTests/Persistence/PersistenceMigrationTests.swift`

**Interfaces:**
- Consumes: Codable `SmartActivitySession` values.
- Produces: `SmartActivitySessionStoring`, `ActivityLabelOverrideStoring`, `ChargePricingObservationStoring`, and database-backed implementations.

- [ ] **Step 1: Write failing migration and round-trip tests**

```swift
func testMigration23CreatesSmartActivityTables() async throws {
    let database = try await TestDatabaseFactory.migratedDatabase()
    XCTAssertEqual(try await database.userVersion(), 23)
    for table in ["vehicle_activity_sessions", "activity_label_overrides", "charge_pricing_observations"] {
        let rows = try await database.rows(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
            bindings: [.text(table)]
        )
        XCTAssertEqual(rows.count, 1)
    }
}

func testReplacingDerivedSessionsDoesNotDeleteUserOverrides() async throws {
    let stores = try await SmartActivityTestStores.make()
    try await stores.labels.save(ActivityLabelOverride.fixture)
    try await stores.sessions.replace(carId: 1, sessions: [.fixture])
    try await stores.sessions.replace(carId: 1, sessions: [])

    XCTAssertTrue(try await stores.sessions.sessions(carId: 1).isEmpty)
    XCTAssertEqual(try await stores.labels.override(id: ActivityLabelOverride.fixture.id), .fixture)
}
```

- [ ] **Step 2: Run focused persistence tests to verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/SmartActivityStoreTests -only-testing:MateDriveTests/PersistenceMigrationTests test
```

Expected: FAIL at schema version 22 and missing store types.

- [ ] **Step 3: Add migration 23 and update the schema constant**

```swift
Migration(
    version: 23,
    statements: [
        """
        CREATE TABLE IF NOT EXISTS vehicle_activity_sessions (
          session_id TEXT PRIMARY KEY NOT NULL,
          car_id INTEGER NOT NULL,
          start_date TEXT NOT NULL,
          end_date TEXT,
          place_key TEXT NOT NULL,
          purpose TEXT NOT NULL,
          confidence REAL,
          quality TEXT NOT NULL,
          derivation_version INTEGER NOT NULL,
          source_fingerprint TEXT NOT NULL,
          derivation_fingerprint TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS vehicle_activity_sessions_car_date ON vehicle_activity_sessions(car_id, start_date DESC);",
        """
        CREATE TABLE IF NOT EXISTS activity_label_overrides (
          override_id TEXT PRIMARY KEY NOT NULL,
          car_id INTEGER NOT NULL,
          session_id TEXT,
          place_key TEXT,
          scope TEXT NOT NULL,
          purpose TEXT NOT NULL,
          custom_name TEXT,
          icon TEXT NOT NULL,
          color_hex TEXT NOT NULL,
          start_minute INTEGER,
          end_minute INTEGER,
          updated_at TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS charge_pricing_observations (
          observation_id TEXT PRIMARY KEY NOT NULL,
          car_id INTEGER NOT NULL,
          charge_id INTEGER NOT NULL,
          station_key TEXT NOT NULL,
          scope TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          confirmed_at TEXT NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS charge_pricing_observations_station ON charge_pricing_observations(car_id, station_key, confirmed_at DESC);"
    ]
)
```

Set `DatabaseSchemaVersion.current = 23`.

- [ ] **Step 4: Implement typed store protocols and atomic session replacement**

```swift
public enum ActivityLabelScope: String, Codable, Sendable {
    case sessionOnly, futureAtPlace
}

public struct ActivityLabelOverride: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let sessionId: String?
    public let placeKey: String?
    public let scope: ActivityLabelScope
    public let purpose: SmartActivityPurpose
    public let customName: String?
    public let icon: String
    public let colorHex: String
    public let startMinute: Int?
    public let endMinute: Int?
    public let updatedAt: Date
}

public enum ChargePricingObservationScope: String, Codable, Sendable {
    case sessionOnly, futureAtStation
}

public struct ChargePricingObservation: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let carId: Int
    public let chargeId: Int
    public let stationKey: String
    public let scope: ChargePricingObservationScope
    public let finalAmount: Double
    public let billedEnergyKWh: Double?
    public let pricePerKWh: Double?
    public let serviceFeePerKWh: Double?
    public let fixedFee: Double?
    public let currencyCode: String
    public let confirmedAt: Date
}

public protocol SmartActivitySessionStoring: Sendable {
    func sessions(carId: Int) async throws -> [SmartActivitySession]
    func session(carId: Int, sessionId: String) async throws -> SmartActivitySession?
    func replace(carId: Int, sessions: [SmartActivitySession]) async throws
    func removeDerivedSessions() async throws
}

public protocol ActivityLabelOverrideStoring: Sendable {
    func overrides(carId: Int) async throws -> [ActivityLabelOverride]
    func override(id: String) async throws -> ActivityLabelOverride?
    func save(_ value: ActivityLabelOverride) async throws
    func delete(id: String) async throws
    func removeAll() async throws
}

public protocol ChargePricingObservationStoring: Sendable {
    func observations(carId: Int, stationKey: String) async throws -> [ChargePricingObservation]
    func save(_ value: ChargePricingObservation) async throws
    func removeAll() async throws
}
```

Encode payloads with `JSONEncoder` configured for ISO-8601 dates. Replace derived sessions in one `BEGIN IMMEDIATE` transaction. Never touch override or observation tables from `replace`.

Define private `.fixture` values for sessions, label overrides, observations, and the `SmartActivityTestStores` container inside `SmartActivityStoreTests.swift`; production code must not expose test factories.

- [ ] **Step 5: Add malformed-payload, empty-replacement, ordering, and database-restore tests**

Malformed rows are skipped instead of crashing the timeline. Sessions return newest first. Empty replacement removes only sessions for the requested car.

- [ ] **Step 6: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/Core/Persistence/Migrations.swift MateDriveApp/Core/Persistence/Migration.swift MateDriveApp/Core/Persistence/Records/SmartActivityRecords.swift MateDriveApp/Core/Persistence/Stores/SmartActivityStore.swift MateDriveApp/Core/Persistence/Stores/ChargePricingObservationStore.swift MateDriveTests/Persistence/SmartActivityStoreTests.swift MateDriveTests/Persistence/PersistenceMigrationTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: persist smart activity sessions"
```

### Task 4: Purpose Classification And Geofence Expansion

**Files:**
- Modify: `MateDriveApp/Features/Settings/AppSettings.swift`
- Modify: `MateDriveApp/Features/Activities/SmartActivityModels.swift`
- Create: `MateDriveApp/Features/Activities/ActivityPurposeClassifier.swift`
- Modify: `MateDriveApp/Features/Activities/ActivitySessionReconstructor.swift`
- Test: `MateDriveTests/Features/ActivityPurposeClassifierTests.swift`
- Modify test: `MateDriveTests/Features/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: a reconstructed session, matching `GeofenceRule`, stored label overrides, recurrence count, charging identity, and commute evidence.
- Produces: `ActivityClassificationInput`, `ActivityClassificationResult`, `ActivityClassificationReason`, and `ActivityPurposeClassifier.classify(_:)`.

- [ ] **Step 1: Write failing precedence and confidence tests**

```swift
func testSessionOverrideWinsOverGeofenceAndHeuristics() {
    let result = ActivityPurposeClassifier.classify(.fixture(
        sessionOverride: .fixture(purpose: .pickupDropoff),
        geofenceKind: .work,
        recurrenceCount: 20,
        hasCharge: true
    ))
    XCTAssertEqual(result.purpose, .pickupDropoff)
    XCTAssertEqual(result.source, .userSession)
    XCTAssertEqual(result.confidence, 1)
}

func testHomeACLateChargeExplainsHomeCharging() {
    let result = ActivityPurposeClassifier.classify(.fixture(
        geofenceKind: .home,
        chargeIdentity: .ac,
        chargeStartMinute: 23 * 60
    ))
    XCTAssertEqual(result.purpose, .homeCharging)
    XCTAssertGreaterThanOrEqual(result.confidence, 0.8)
    XCTAssertTrue(result.reasons.contains(.homeGeofence))
    XCTAssertTrue(result.reasons.contains(.acCharging))
}

func testLowEvidenceRemainsUnclassified() {
    XCTAssertEqual(ActivityPurposeClassifier.classify(.fixture()).purpose, .unclassified)
}
```

- [ ] **Step 2: Run focused tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/ActivityPurposeClassifierTests -only-testing:MateDriveTests/SettingsViewModelTests test
```

Expected: FAIL because new geofence kinds and classifier types are missing.

- [ ] **Step 3: Extend geofences without breaking old settings**

Add `.shopping` and `.schoolPickup` to `GeofenceKind`, with titles `Shopping / 商场`, `School or Pickup / 学校或接送`, and SF Symbols `cart.fill` and `figure.2.and.child.holdinghands`. Existing Codable values remain unchanged.

- [ ] **Step 4: Implement explicit evidence scoring**

```swift
public struct ActivityClassificationInput: Sendable {
    public let session: SmartActivitySession
    public let sessionOverride: ActivityLabelOverride?
    public let placeOverride: ActivityLabelOverride?
    public let geofenceKind: GeofenceKind?
    public let recurrenceCount: Int
    public let chargeIdentity: ChargePricingChargerIdentity?
    public let chargeStartMinute: Int?
    public let hasCharge: Bool
    public let hasPromptDeparture: Bool
    public let isConfirmedCommute: Bool
}

public enum ActivityPurposeClassifier {
    public static let classifierVersion = 1
    public static let suggestionThreshold = 0.80

    public static func classify(_ input: ActivityClassificationInput) -> ActivityClassificationResult {
        if let override = input.sessionOverride { return override.result(source: .userSession) }
        if let override = input.placeOverride { return override.result(source: .userPlaceRule) }
        let scored = scoreGeofenceAndPatternEvidence(input)
        guard scored.confidence >= suggestionThreshold else {
            return .init(purpose: .unclassified, confidence: scored.confidence, source: .none, reasons: scored.reasons, classifierVersion: classifierVersion)
        }
        return scored
    }
}
```

Add a private `ActivityLabelOverride.result(source:)` mapper that returns the stored purpose at confidence 1.0 with reason `.confirmedOverride`. Use deterministic scores: confirmed overrides 1.0; explicit Home/Work/Shopping/School geofence 0.85; Charging geofence plus a charge 0.90; repeated same place/time at least four times adds 0.10 up to 0.95; prompt post-charge departure adds 0.05. Cap all scores at 1.0.

Add `SmartActivityPurpose.title(language:)` and `systemImage` mappings in `SmartActivityModels.swift`. Use localized titles for every fixed purpose and let a stored custom label name replace `.custom` in presentation; never use an enum raw value as visible copy.

- [ ] **Step 5: Apply classification after reconstruction and test all supported purposes**

Cover replenishment, Home charging, Work charging, commute, shopping, pickup/drop-off, parking, custom, and unclassified. Ensure existing commute evidence outranks an unconfirmed generic Work heuristic but not a user override.

- [ ] **Step 6: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/Features/Settings/AppSettings.swift MateDriveApp/Features/Activities/SmartActivityModels.swift MateDriveApp/Features/Activities/ActivityPurposeClassifier.swift MateDriveApp/Features/Activities/ActivitySessionReconstructor.swift MateDriveTests/Features/ActivityPurposeClassifierTests.swift MateDriveTests/Features/SettingsViewModelTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: classify smart activity purposes"
```

### Task 5: Versioned Regional Residential Tariff Catalog

**Files:**
- Create: `MateDriveApp/Features/Charges/RegionalChargingTariff.swift`
- Create: `MateDriveApp/Resources/RegionalChargingTariffs.json`
- Create: `scripts/audit_regional_tariffs.py`
- Create: `scripts/test_audit_regional_tariffs.py`
- Modify: `project.yml`
- Modify: `Makefile`
- Test: `MateDriveTests/Features/RegionalChargingTariffTests.swift`

**Interfaces:**
- Consumes: a bundled JSON resource and a requested ISO 3166-2 region code/date.
- Produces: `RegionalChargingTariffCatalog.load()`, `entry(regionCode:date:)`, and `makePricingRule(from:)`.

- [ ] **Step 1: Write failing catalog coverage and Hunan historical tests**

```swift
func testCatalogContainsEveryMainlandProvincialRegionCode() throws {
    let catalog = try RegionalChargingTariffCatalog.load()
    XCTAssertEqual(Set(catalog.regions.map(\.regionCode)), Set([
        "CN-11", "CN-12", "CN-13", "CN-14", "CN-15",
        "CN-21", "CN-22", "CN-23", "CN-31", "CN-32", "CN-33", "CN-34", "CN-35", "CN-36", "CN-37",
        "CN-41", "CN-42", "CN-43", "CN-44", "CN-45", "CN-46",
        "CN-50", "CN-51", "CN-52", "CN-53", "CN-54",
        "CN-61", "CN-62", "CN-63", "CN-64", "CN-65"
    ]))
}

func testExpiredHunanPilotIsHistoricalForNewCharges() throws {
    let catalog = try RegionalChargingTariffCatalog.load()
    let historicalDate = try XCTUnwrap(DomainDateParser.date(from: "2025-06-30T12:00:00+08:00"))
    let currentDate = try XCTUnwrap(DomainDateParser.date(from: "2026-07-18T12:00:00+08:00"))
    XCTAssertNotNil(catalog.entry(regionCode: "CN-43", date: historicalDate))
    XCTAssertNil(catalog.entry(regionCode: "CN-43", date: currentDate))
}
```

- [ ] **Step 2: Run focused tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/RegionalChargingTariffTests test
```

Expected: FAIL because the catalog types and resource do not exist.

- [ ] **Step 3: Implement catalog models with strict active-date lookup**

```swift
public enum RegionalTariffStatus: String, Codable, Sendable {
    case active, historical, superseded
}

public enum RegionalTariffAvailability: String, Codable, Sendable {
    case verified, noVerifiedDedicatedTariff
}

public struct RegionalChargingTariffRegion: Codable, Equatable, Sendable {
    public let regionCode: String
    public let names: [String: String]
    public let availability: RegionalTariffAvailability
    public let verifiedAt: String
    public let tariffs: [RegionalChargingTariff]
}

public struct RegionalChargingTariff: Codable, Equatable, Sendable {
    public let id: String
    public let status: RegionalTariffStatus
    public let customerClass: String
    public let chargeType: ChargePricingChargeType
    public let currencyCode: String
    public let effectiveFromDate: String
    public let effectiveToDate: String?
    public let documentID: String
    public let sourceURL: URL
    public let basePricePerKWh: Double
    public let timeSegments: [ChargePricingTimeSegment]
    public let serviceFeePerKWh: Double
    public let sessionFee: Double
    public let applicableWeekdays: [Int]?
    public let applicableMonths: [Int]?
}

public struct RegionalChargingTariffCatalog: Codable, Equatable, Sendable {
    public let version: Int
    public let generatedAt: String
    public let regions: [RegionalChargingTariffRegion]

    public static func load(bundle: Bundle = .main) throws -> Self
    public func entry(regionCode: String, date: Date) -> RegionalChargingTariff?
    public func makePricingRule(regionCode: String, from entry: RegionalChargingTariff) -> ChargePricingRule
}
```

`entry` searches all tariffs inside one unique region and returns the newest source-backed tariff whose effective range contains the requested local date. `historical` entries remain usable for historical sessions inside their dates. A region with availability `noVerifiedDedicatedTariff` has an empty `tariffs` array and never produces a pricing rule. This nested model permits a historical and a current policy to coexist for the same region code.

- [ ] **Step 4: Add all 31 reviewed region records**

The JSON must contain exactly the region codes in Step 1. For each region, add either:

- `availability: verified` with one or more source-backed active or historical tariffs and exact official effective dates; or
- `availability: noVerifiedDedicatedTariff` with a verification date and an empty tariff array.

Include this Hunan historical record exactly:

```json
{
  "regionCode": "CN-43",
  "names": { "en": "Hunan", "zh-Hans": "湖南" },
  "availability": "verified",
  "verifiedAt": "2026-07-18",
  "tariffs": [
    {
      "id": "cn43-2024-residential-ev",
      "status": "historical",
      "customerClass": "residential-ev",
      "chargeType": "ac",
      "currencyCode": "CNY",
      "effectiveFromDate": "2024-07-01",
      "effectiveToDate": "2025-06-30",
      "documentID": "湘发改价调规〔2024〕405号",
      "sourceURL": "https://fgw.hunan.gov.cn/fgw/xxgk_70899/zcfg/dfxfg/202407/t20240708_33349442.html",
      "basePricePerKWh": 0.604,
      "serviceFeePerKWh": 0,
      "sessionFee": 0,
      "applicableWeekdays": null,
      "applicableMonths": null,
      "timeSegments": [
        { "id": "cn43-low", "startMinuteOfDay": 1380, "endMinuteOfDay": 419, "pricePerKWh": 0.504 },
        { "id": "cn43-flat-am", "startMinuteOfDay": 420, "endMinuteOfDay": 659, "pricePerKWh": 0.604 },
        { "id": "cn43-high-midday", "startMinuteOfDay": 660, "endMinuteOfDay": 839, "pricePerKWh": 0.704 },
        { "id": "cn43-flat-pm", "startMinuteOfDay": 840, "endMinuteOfDay": 1079, "pricePerKWh": 0.604 },
        { "id": "cn43-high-evening", "startMinuteOfDay": 1080, "endMinuteOfDay": 1379, "pricePerKWh": 0.704 }
      ]
    }
  ]
}
```

- [ ] **Step 5: Add the deterministic catalog audit and preflight target**

The Python audit exits nonzero for a missing region, duplicate code, numeric value without an official `https` source, invalid customer class or charge type, invalid currency, missing effective-from date, malformed effective-to date, invalid weekday outside 1 through 7, invalid month outside 1 through 12, negative fee, overlap, uncovered minutes for an active tariff, or an expired entry marked active.

```make
regional-tariff-audit:
	python3 scripts/audit_regional_tariffs.py

preflight: regional-tariff-audit
```

Add `RegionalChargingTariffs.json` as an application resource in `project.yml`.

- [ ] **Step 6: Run Swift and script tests and commit**

```bash
python3 scripts/test_audit_regional_tariffs.py
python3 scripts/audit_regional_tariffs.py
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/RegionalChargingTariffTests test
```

Expected: all commands PASS and the audit reports 31 region records.

```bash
git add MateDriveApp/Features/Charges/RegionalChargingTariff.swift MateDriveApp/Resources/RegionalChargingTariffs.json scripts/audit_regional_tariffs.py scripts/test_audit_regional_tariffs.py MateDriveTests/Features/RegionalChargingTariffTests.swift Makefile project.yml MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: add verified regional tariff catalog"
```

### Task 6: Cost Source Resolution And Station Learning

**Files:**
- Modify: `MateDriveApp/Features/Charges/ChargePricingRule.swift`
- Create: `MateDriveApp/Features/Charges/ChargeCostResolver.swift`
- Create: `MateDriveApp/Features/Charges/ChargePricingObservationService.swift`
- Modify: `MateDriveApp/Features/Charges/ChargeDetailViewModel.swift`
- Test: `MateDriveTests/Features/ChargeCostResolverTests.swift`
- Modify test: `MateDriveTests/Features/ChargeDetailViewModelTests.swift`
- Modify test: `MateDriveTests/Features/ChargePricingRuleTests.swift`

**Interfaces:**
- Consumes: manual override presence, API cost, charge input, rule provenance, Home geofence match, regional catalog, and persisted observations.
- Produces: `ChargeCostResolution`, `ChargeCostResolver.resolve(_:)`, and `ChargePricingObservationService.confirm(_:)`.

- [ ] **Step 1: Write failing source-priority and Home-safety tests**

```swift
func testManualZeroMeansExplicitFreeAndWinsEverySource() {
    let result = ChargeCostResolver.resolve(.fixture(
        manualCost: 0,
        apiCost: 25,
        rules: [.station(price: 1)],
        regionalRule: .home(price: 0.5)
    ))
    XCTAssertEqual(result?.amount, 0)
    XCTAssertEqual(result?.source, .manual)
    XCTAssertTrue(result?.isExplicitlyFree == true)
}

func testRegionalTariffNeverAppliesOutsideConfirmedHomeAC() {
    XCTAssertNil(ChargeCostResolver.resolve(.fixture(
        manualCost: nil,
        apiCost: nil,
        isAC: false,
        geofenceKind: .charging,
        regionalRule: .home(price: 0.5)
    )))
}

func testConfirmedStationRuleWinsRegionalHomeFallback() {
    let result = ChargeCostResolver.resolve(.fixture(
        rules: [.station(price: 0.66)],
        geofenceKind: .home,
        regionalRule: .home(price: 0.5)
    ))
    XCTAssertEqual(result?.source, .stationRule)
    XCTAssertEqual(result?.unitPricePerKWh, 0.66)
}
```

- [ ] **Step 2: Run focused tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/ChargeCostResolverTests -only-testing:MateDriveTests/ChargeDetailViewModelTests -only-testing:MateDriveTests/ChargePricingRuleTests test
```

Expected: FAIL because provenance and resolver types do not exist.

- [ ] **Step 3: Add backward-compatible rule provenance**

```swift
public enum ChargePricingRuleOrigin: String, Codable, Equatable, Sendable {
    case user, stationLearned, regionalOfficial
}

// Add to ChargePricingRule with decoder default .user:
public var origin: ChargePricingRuleOrigin
public var regionCode: String?
public var sourceURL: String?
public var verifiedAt: String?
public var serviceFeePerKWh: Double
public var parkingFeeRuleID: String?
public var applicableWeekdays: [Int]?
public var applicableMonths: [Int]?
```

Preserve all existing initializers with defaults so old settings and tests continue compiling. Extend validation to reject negative service fees, weekdays outside 1 through 7, and months outside 1 through 12. Extend `ChargePricingRuleEngine.matches` to apply the charge timestamp's local weekday and month. Extend each estimate so `cost = segmented energy charge + energy * serviceFeePerKWh + sessionFee`; parking remains a separate `ParkingFeeRuleEngine` result referenced by `parkingFeeRuleID`.

- [ ] **Step 4: Implement one explicit resolver**

```swift
public struct ChargeCostResolution: Equatable, Sendable {
    public let amount: Double
    public let source: SmartActivityChargeCostSource
    public let currencyCode: String
    public let ruleID: String?
    public let unitPricePerKWh: Double?
    public let serviceFee: Double
    public let sessionFee: Double
    public let parkingFeeRuleID: String?
    public let components: [ChargePricingCostComponent]
    public let isEstimated: Bool
    public let isExplicitlyFree: Bool
}

public struct ChargeCostResolutionInput: Sendable {
    public let manualCost: Double?
    public let apiCost: Double?
    public let currencyCode: String
    public let isAC: Bool
    public let geofenceKind: GeofenceKind?
    public let pricingInput: ChargePricingInput
    public let rules: [ChargePricingRule]
    public let regionalRule: ChargePricingRule?
}

public enum ChargeCostResolver {
    public static func resolve(_ input: ChargeCostResolutionInput) -> ChargeCostResolution? {
        if let manual = input.manualCost { return .manual(manual, currency: input.currencyCode) }
        if let api = input.apiCost, api > 0 { return .api(api, currency: input.currencyCode) }
        if let estimate = bestUserOrStationEstimate(input) { return estimate }
        guard input.isAC, input.geofenceKind == .home else { return nil }
        return regionalEstimate(input)
    }
}
```

The resolver must sort matching user rules by existing priority, then provenance. It must reject mismatched currencies and expired official rules.

Add tests for weekday-only, seasonal-month, service-fee, fixed-fee, and cross-midnight segmented sessions. A 10 kWh session at CNY 0.50/kWh with CNY 0.20/kWh service fee and CNY 1 fixed fee must resolve to CNY 8.00 before any separate parking fee.

- [ ] **Step 5: Implement confirmed observation persistence and future-rule creation**

```swift
public struct ChargePricingConfirmation: Equatable, Sendable {
    public let carId: Int
    public let chargeId: Int
    public let stationKey: String
    public let scope: ChargePricingObservationScope
    public let finalAmount: Double
    public let billedEnergyKWh: Double?
    public let pricePerKWh: Double?
    public let serviceFeePerKWh: Double?
    public let fixedFee: Double?
    public let currencyCode: String
    public let coordinates: GeocodeLocation?
    public let chargerIdentity: ChargePricingChargerIdentity
    public let startMinute: Int?
    public let endMinute: Int?
}

public protocol ChargePricingObservationServicing: Sendable {
    func confirm(_ value: ChargePricingConfirmation) async throws
}
```

`ChargePricingObservationService` is initialized with `ChargePricingObservationStoring`, `ChargeCostOverriding`, and `SettingsStoring`. For `sessionOnly`, save only the manual cost and observation. For `futureAtStation`, also create a normal enabled `ChargePricingRule` with origin `.stationLearned`, 150-meter radius, applicable charger identity and time window, and priority 100. If `pricePerKWh` is absent, derive it only when billed energy is positive; never derive it from missing or zero energy. Build `stationKey` from a matched geofence ID when available, otherwise from latitude and longitude rounded to four decimal places plus charger identity.

- [ ] **Step 6: Route Charge detail through the resolver and test legacy behavior**

Replace ad hoc `manual -> API -> rule` selection inside `ChargeDetailViewModel.applyCosts` with `ChargeCostResolver`. Existing visible values and manual save behavior must remain unchanged when no new provenance exists.

- [ ] **Step 7: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/Features/Charges/ChargePricingRule.swift MateDriveApp/Features/Charges/ChargeCostResolver.swift MateDriveApp/Features/Charges/ChargePricingObservationService.swift MateDriveApp/Features/Charges/ChargeDetailViewModel.swift MateDriveTests/Features/ChargeCostResolverTests.swift MateDriveTests/Features/ChargeDetailViewModelTests.swift MateDriveTests/Features/ChargePricingRuleTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: resolve and learn charging prices"
```

### Task 7: Cached Source Repository And Background Indexer

**Files:**
- Create: `MateDriveApp/Core/Sync/SmartActivityIndexer.swift`
- Modify: `MateDriveApp/Core/Sync/BackgroundRefreshWorkRunner.swift`
- Modify: `MateDriveApp/App/MateDriveApp.swift`
- Test: `MateDriveTests/Sync/SmartActivityIndexerTests.swift`
- Modify test: `MateDriveTests/Sync/BackgroundRefreshWorkRunnerTests.swift`

**Interfaces:**
- Consumes: `ActivitiesStateCache`, `SleepIntervalStoring`, `SettingsStoring`, session/label stores, classifier, resolver, and car IDs from `HistorySyncReport`.
- Produces: `SmartActivityIndexing.rebuild(carIds:)`, a published change notification, and `BackgroundRefreshReport.smartActivitiesIndexed`.

- [ ] **Step 1: Write failing cached-only and post-sync ordering tests**

```swift
func testIndexerBuildsFromCacheWithoutCallingHTTP() async throws {
    let source = SpySmartActivitySourceLoader(snapshot: .fixture)
    let store = InMemorySmartActivitySessionStore()
    let indexer = SmartActivityIndexer(
        source: source,
        sessionStore: store,
        labelStore: InMemoryActivityLabelOverrideStore()
    )

    let report = await indexer.rebuild(carIds: [1])

    XCTAssertEqual(report.completedCarIds, [1])
    XCTAssertEqual(await source.networkRequestCount, 0)
    XCTAssertFalse(try await store.sessions(carId: 1).isEmpty)
}

func testBackgroundRunnerIndexesOnlyAfterHistoryAndStatusFinish() async {
    let order = CallOrderRecorder()
    let runner = BackgroundRefreshWorkRunner(
        historySyncRunner: OrderedHistoryRunner(order: order),
        refreshVehicleStatus: { await order.append("status"); return true },
        rebuildSmartActivities: { ids in await order.append("index-\(ids)"); return true }
    )
    _ = await runner.run()
    XCTAssertEqual(await order.last, "index-[1]")
}
```

- [ ] **Step 2: Run focused sync tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/SmartActivityIndexerTests -only-testing:MateDriveTests/BackgroundRefreshWorkRunnerTests test
```

Expected: FAIL because the indexer and runner closure do not exist.

- [ ] **Step 3: Implement the cached source boundary**

```swift
public struct SmartActivitySourceSnapshot: Sendable {
    public let carId: Int
    public let activities: [TeslaMateActivity]
    public let historyFullyLoaded: Bool
    public let sleepIntervals: [SleepInterval]
    public let geofences: [GeofenceRule]
    public let settings: AppSettings
    public let chargeCostOverrides: [Int: Double]
    public let tariffCatalog: RegionalChargingTariffCatalog
}

public protocol SmartActivitySourceLoading: Sendable {
    func snapshot(carId: Int) async throws -> SmartActivitySourceSnapshot?
}

public struct SmartActivityIndexReport: Equatable, Sendable {
    public let attemptedCarIds: [Int]
    public let completedCarIds: [Int]
    public let failedCarIds: [Int]
    public let unchangedCarIds: [Int]
}

public protocol SmartActivityIndexing: Sendable {
    func rebuild(carIds: [Int]) async -> SmartActivityIndexReport
    func removeDerivedData() async throws
}
```

`CachedSmartActivitySourceLoader` loads `AppSettings.serverURL`, reads `ActivitiesStateCache` including `historyFullyLoaded`, queries the persisted sleep range and charge-cost overrides, loads the bundled tariff catalog, and returns no snapshot when no activity cache exists. It has no HTTP client or API factory dependency. Sessions at a truncated history boundary are marked partial rather than complete.

- [ ] **Step 4: Implement idempotent indexing off the main actor**

For each car, reconstruct, apply label overrides and purpose classification, resolve charge costs, map each `ChargeCostResolution` into Codable `SmartActivityChargeCost`, and calculate a derivation fingerprint from the raw source fingerprint, matching override timestamps, pricing-rule digest, tariff-catalog version, and classifier version. Replace the derived car snapshot in one store transaction only when that derivation fingerprint changes. Post `.smartActivityIndexDidChange` only after a successful commit.

- [ ] **Step 5: Extend background reports and wire the live indexer**

```swift
public struct BackgroundRefreshReport: Equatable, Sendable {
    public let historySyncReport: HistorySyncReport
    public let vehicleStatusRefreshed: Bool
    public let smartActivitiesIndexed: Bool
    public let wasCancelled: Bool
}
```

Give `BackgroundRefreshReport.init` a `smartActivitiesIndexed: Bool = true` default for existing callers and require it in `isSuccessful`. Extend `BackgroundRefreshWorkRunner.init` with `rebuildSmartActivities: @escaping @Sendable ([Int]) async -> Bool = { _ in true }` so existing focused callers remain source-compatible. Run the index closure after awaiting both existing tasks. Construct the live indexer in `MateDriveApp.init` from `environment.databaseProvider`, `environment.settingsStore`, `ActivitiesStateCache.shared`, `DatabaseBackedChargeCostOverrideStore`, and `DatabaseBackedSleepIntervalStore`.

- [ ] **Step 6: Add cancellation, missing-cache, partial-car-failure, and unchanged-fingerprint tests**

Cancellation must not replace the prior snapshot. One failed car must not remove another car's sessions. An unchanged derivation fingerprint must not post a change notification, while a changed user label or pricing rule must rebuild even when raw source events are unchanged.

- [ ] **Step 7: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/Core/Sync/SmartActivityIndexer.swift MateDriveApp/Core/Sync/BackgroundRefreshWorkRunner.swift MateDriveApp/App/MateDriveApp.swift MateDriveTests/Sync/SmartActivityIndexerTests.swift MateDriveTests/Sync/BackgroundRefreshWorkRunnerTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: index activities after background sync"
```

### Task 8: Store-Only Timeline And Detail View Models

**Files:**
- Create: `MateDriveApp/Features/Activities/ActivityTimelineViewModel.swift`
- Test: `MateDriveTests/Features/ActivityTimelineViewModelTests.swift`

**Interfaces:**
- Consumes: `SmartActivitySessionStoring`, `ActivityLabelOverrideStoring`, and `.smartActivityIndexDidChange`.
- Produces: `ActivityTimelineState`, `ActivityTimelineFilter`, `ActivityTimelineViewModel`, and `ActivitySessionDetailViewModel`.

- [ ] **Step 1: Write failing no-network state tests**

```swift
@MainActor
func testLoadPublishesCachedSessionsWithoutLoadingSpinner() async {
    let store = SpySmartActivitySessionStore(sessions: [.fixture])
    let viewModel = ActivityTimelineViewModel(sessionStore: store)

    await viewModel.load(carId: 1)

    XCTAssertEqual(viewModel.state.sessions, [.fixture])
    XCTAssertFalse(viewModel.state.isLoading)
    XCTAssertEqual(store.loadCount, 1)
}

@MainActor
func testFiltersDoNotReadStoreAgain() async {
    let store = SpySmartActivitySessionStore(sessions: [.driveFixture, .chargeFixture])
    let viewModel = ActivityTimelineViewModel(sessionStore: store)
    await viewModel.load(carId: 1)
    viewModel.setFilter(.charge)
    XCTAssertEqual(viewModel.filteredSessions, [.chargeFixture])
    XCTAssertEqual(store.loadCount, 1)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/ActivityTimelineViewModelTests test
```

Expected: FAIL because timeline view-model types do not exist.

- [ ] **Step 3: Implement a store-only observable view model**

```swift
public enum ActivityTimelineFilter: String, CaseIterable, Sendable {
    case all, drive, charge, park
}

public struct ActivityTimelineState: Equatable, Sendable {
    public var sessions: [SmartActivitySession] = []
    public var filter: ActivityTimelineFilter = .all
    public var errorMessage: String?
    public var isLoading = false
}

@MainActor
public final class ActivityTimelineViewModel: ObservableObject {
    @Published public private(set) var state = ActivityTimelineState()
    private let sessionStore: any SmartActivitySessionStoring

    public init(sessionStore: any SmartActivitySessionStoring) {
        self.sessionStore = sessionStore
    }

    public func load(carId: Int) async {
        do {
            state.sessions = try await sessionStore.sessions(carId: carId)
            state.errorMessage = nil
        } catch {
            state.errorMessage = error.localizedDescription
        }
        state.isLoading = false
    }
}

@MainActor
public final class ActivitySessionDetailViewModel: ObservableObject {
    @Published public private(set) var session: SmartActivitySession?
    @Published public private(set) var errorMessage: String?
    private let sessionStore: any SmartActivitySessionStoring

    public init(sessionStore: any SmartActivitySessionStoring) {
        self.sessionStore = sessionStore
    }

    public func load(carId: Int, sessionId: String) async {
        do {
            session = try await sessionStore.session(carId: carId, sessionId: sessionId)
            errorMessage = session == nil ? "activity_session_missing" : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

Do not inject `TeslamateAPI`, `HTTPClient`, an API factory, or a foreground refresh closure.

- [ ] **Step 4: Add day sections, filters, index notifications, and cached detail loading**

`daySections` groups using the app locale/calendar. A change notification reloads the current car once with request coalescing. `ActivitySessionDetailViewModel.load` reads one session ID from the same store and never reconstructs it.

- [ ] **Step 5: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/Features/Activities/ActivityTimelineViewModel.swift MateDriveTests/Features/ActivityTimelineViewModelTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: expose cached activity timeline state"
```

### Task 9: Fourth Tab, Timeline Cards, And Session Detail

**Files:**
- Modify: `MateDriveApp/App/RootTabNavigation.swift`
- Modify: `MateDriveApp/App/RootView.swift`
- Modify: `MateDriveApp/App/AppRoute.swift`
- Modify: `MateDriveApp/App/RouteCoverage.swift`
- Create: `MateDriveApp/Features/Activities/ActivityTimelineView.swift`
- Create: `MateDriveApp/Features/Activities/ActivitySessionCard.swift`
- Create: `MateDriveApp/Features/Activities/ActivitySessionDetailView.swift`
- Create: `MateDriveApp/Features/Activities/ParkingActivityDetailView.swift`
- Modify: `MateDriveApp/Features/Activities/ActivitiesView.swift`
- Modify: `MateDriveApp/Features/FeatureHub/FeatureHubPresentation.swift`
- Modify test: `MateDriveTests/App/RootTabNavigationTests.swift`
- Modify test: `MateDriveTests/App/AppShortcutTests.swift`
- Create test: `MateDriveTests/Features/ActivitySessionCardTests.swift`

**Interfaces:**
- Consumes: `ActivityTimelineViewModel`, selected car ID from the shared dashboard view model, and store-only session detail view models.
- Produces: `RootTab.activity`, `activityPath`, `.activitySession(carId:sessionId:)`, timeline cards, detail navigation, and source-route links.

- [ ] **Step 1: Write failing four-tab path tests**

```swift
func testActivityOwnsIndependentPath() {
    var state = RootNavigationState(
        homePath: [.dashboard],
        featuresPath: [.charges(carId: 1, exteriorColor: nil)]
    )
    state.open(.activitySession(carId: 1, sessionId: "park-10"), source: .activity)
    XCTAssertEqual(state.selectedTab, .activity)
    XCTAssertEqual(state.activityPath, [.activitySession(carId: 1, sessionId: "park-10")])
    XCTAssertEqual(state.featuresPath, [.charges(carId: 1, exteriorColor: nil)])
}

func testSelectingActivityPreservesItsDetailPath() {
    var state = RootNavigationState(activityPath: [.activitySession(carId: 1, sessionId: "park-10")])
    state.selectTab(.activity)
    XCTAssertEqual(state.activityPath.count, 1)
}
```

- [ ] **Step 2: Run focused UI-model tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/RootTabNavigationTests -only-testing:MateDriveTests/AppShortcutTests -only-testing:MateDriveTests/ActivitySessionCardTests test
```

Expected: FAIL because the Activity tab, path, route, and presentation are missing.

- [ ] **Step 3: Add the Activity root path and route handling**

```swift
public enum RootTab: Hashable, Sendable {
    case home, activity, features, settings
}

public struct RootNavigationState: Equatable, Sendable {
    public var selectedTab: RootTab
    public var homePath: [AppRoute]
    public var activityPath: [AppRoute]
    public var featuresPath: [AppRoute]
    public var settingsPath: [AppRoute]
}
```

Keep the existing initializer source-compatible by adding `activityPath: [AppRoute] = []`. Add `AppRoute.activitySession(carId: Int, sessionId: String)` and localized route title `Activity Detail / 活动详情`. Update route coverage and exhaustive destination switches. Existing feature shortcuts still open Features; Dashboard and Settings behavior remains unchanged, and no new App Shortcut destination is introduced.

- [ ] **Step 4: Insert the native fourth tab between Home and Features**

Construct one `ActivityTimelineViewModel` in `RootView` using `DatabaseBackedSmartActivitySessionStore`. Pass the shared selected car ID to `ActivityTimelineView`. Use:

```swift
.tabItem {
    Label(t("Activity", "动态"), systemImage: "clock.arrow.circlepath")
}
.tag(RootTab.activity)
```

Reload the timeline from SQLite when `syncLifecycleController.cacheRevision` changes or the selected car changes. Do not call the network.

- [ ] **Step 5: Build stable session cards and cached detail**

The card shows purpose, place, time, parking duration, net battery change, charge gain, standby loss, rated-range change, and cost source. Omit unavailable rows rather than displaying zero. Orange denotes estimated or review-needed values; green denotes confirmed charge gain or verified savings; blue denotes drives; indigo denotes sleep.

`ActivityTimelineView` includes the existing list/map mode control. Map mode reads the same cached sessions and places one marker per valid session coordinate; selecting a marker opens the cached session detail. It performs no geocoding or API request.

The detail view uses a vertical event timeline and a non-interactive-by-default map consistent with existing map interaction rules. Source events navigate to existing drive, charge, and parking details. Extract the current private `ParkingActivityDetailView` from `ActivitiesView.swift` into its own internal file without changing its behavior, then reuse it for parking event references. The energy section explicitly labels vehicle-reported energy, billed energy, and battery percentage gain as separate values; it never relabels vehicle energy as charger-meter energy.

- [ ] **Step 6: Remove the duplicate Activities feature card only after parity**

Keep all existing Activities routes and views for source detail and map access. Remove only its duplicate top-level `FeatureHubPresentation` card after the Activity tab exposes list, filters, map access, and parking detail.

- [ ] **Step 7: Add Dynamic Type, missing-data, and presentation tests**

Test that unavailable cost and range rows are absent, `-2%` standby and `+30%` charge remain distinct, estimated cost uses an orange source label, and the card accessibility value reads metrics in visual order.

- [ ] **Step 8: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/App/RootTabNavigation.swift MateDriveApp/App/RootView.swift MateDriveApp/App/AppRoute.swift MateDriveApp/App/RouteCoverage.swift MateDriveApp/Features/Activities/ActivityTimelineView.swift MateDriveApp/Features/Activities/ActivitySessionCard.swift MateDriveApp/Features/Activities/ActivitySessionDetailView.swift MateDriveApp/Features/Activities/ParkingActivityDetailView.swift MateDriveApp/Features/Activities/ActivitiesView.swift MateDriveApp/Features/FeatureHub/FeatureHubPresentation.swift MateDriveTests/App/RootTabNavigationTests.swift MateDriveTests/App/AppShortcutTests.swift MateDriveTests/Features/ActivitySessionCardTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: add smart activity tab"
```

### Task 10: User Label, Price Confirmation, And Smart Activity Settings

**Files:**
- Create: `MateDriveApp/Features/Activities/ActivityLabelEditorView.swift`
- Create: `MateDriveApp/Features/Charges/ChargePriceConfirmationView.swift`
- Create: `MateDriveApp/Features/Settings/SmartActivitySettingsView.swift`
- Modify: `MateDriveApp/Features/Activities/ActivitySessionDetailView.swift`
- Modify: `MateDriveApp/Features/Charges/ChargeDetailView.swift`
- Modify: `MateDriveApp/Features/Settings/AppSettings.swift`
- Modify: `MateDriveApp/Features/Settings/SettingsViewModel.swift`
- Modify: `MateDriveApp/Features/Settings/SettingsView.swift`
- Test: `MateDriveTests/Features/SmartActivitySettingsTests.swift`
- Test: `MateDriveTests/Features/ChargePriceConfirmationTests.swift`

**Interfaces:**
- Consumes: label and observation stores, pricing observation service, tariff catalog, settings store, and indexer maintenance interface.
- Produces: confirmed session/place labels, final charge costs, future station rules, `homeTariffRegionCode`, catalog status, and rebuild/clear controls.

- [ ] **Step 1: Write failing settings round-trip and confirmation validation tests**

```swift
func testHomeTariffRegionRoundTripsWithoutChangingCurrency() throws {
    var settings = AppSettings(currencyCode: "HKD")
    settings.homeTariffRegionCode = "CN-43"
    let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.homeTariffRegionCode, "CN-43")
    XCTAssertEqual(decoded.currencyCode, "HKD")
}

func testFutureStationRuleRequiresPositiveEnergyOrExplicitUnitPrice() {
    let result = ChargePricingConfirmationValidator.validate(.fixture(
        scope: .futureAtStation,
        finalAmount: 12,
        billedEnergyKWh: nil,
        pricePerKWh: nil
    ))
    XCTAssertEqual(result, [.missingFutureUnitPrice])
}
```

- [ ] **Step 2: Run focused tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/SmartActivitySettingsTests -only-testing:MateDriveTests/ChargePriceConfirmationTests -only-testing:MateDriveTests/SettingsViewModelTests test
```

Expected: FAIL because settings and editor validation types are missing.

- [ ] **Step 3: Add backward-compatible settings fields and save methods**

```swift
public var homeTariffRegionCode: String?

@MainActor
public func saveHomeTariffRegionCode(_ regionCode: String?) async {
    var updated = settings
    updated.homeTariffRegionCode = regionCode
    await settingsStore.save(updated)
    settings = updated
}
```

Decode the field with `decodeIfPresent`, defaulting to `nil`. Never derive or change `currencyCode` from the tariff region.

Add the editor validator in `ChargePriceConfirmationView.swift`:

```swift
public enum ChargePricingConfirmationValidationIssue: Equatable, Sendable {
    case invalidFinalAmount, invalidBilledEnergy, invalidUnitPrice
    case invalidServiceFee, invalidFixedFee, missingFutureUnitPrice
}

public enum ChargePricingConfirmationValidator {
    public static func validate(_ value: ChargePricingConfirmation) -> [ChargePricingConfirmationValidationIssue] {
        var issues: [ChargePricingConfirmationValidationIssue] = []
        if !value.finalAmount.isFinite || value.finalAmount < 0 { issues.append(.invalidFinalAmount) }
        if let energy = value.billedEnergyKWh, !energy.isFinite || energy <= 0 { issues.append(.invalidBilledEnergy) }
        if let price = value.pricePerKWh, !price.isFinite || price < 0 { issues.append(.invalidUnitPrice) }
        if let fee = value.serviceFeePerKWh, !fee.isFinite || fee < 0 { issues.append(.invalidServiceFee) }
        if let fee = value.fixedFee, !fee.isFinite || fee < 0 { issues.append(.invalidFixedFee) }
        if value.scope == .futureAtStation,
           value.pricePerKWh == nil,
           value.billedEnergyKWh == nil {
            issues.append(.missingFutureUnitPrice)
        }
        return issues
    }
}
```

- [ ] **Step 4: Implement the Activity label editor**

The editor supports session-only or future matching-place scope, purpose, custom name, SF Symbol, semantic color, and optional start/end minutes. Validate that custom labels have a nonempty name and that time windows have both boundaries.

- [ ] **Step 5: Implement one shared price confirmation editor**

Use decimal pads and localized currency symbols for final amount, billed energy, unit price, service fee, and fixed fee. Offer `This charge only / 仅本次` and `Future charges here / 此地点以后充电`. Show the exact station, charger type, time window, and resulting estimated rule before save.

Both Activity session detail and Charge detail present the same `ChargePriceConfirmationView` and call the same service.

- [ ] **Step 6: Implement Smart Activity settings**

Add one Settings group containing links to existing Geofences and Charge Pricing, plus Activity labels, Residential Tariff Region, catalog version/source status, Rebuild Derived Activity Data, and Clear Learned Suggestions. Rebuild deletes and regenerates only `vehicle_activity_sessions`; clear learned suggestions removes label-place rules and pricing observations only after confirmation.

- [ ] **Step 7: Run focused tests and commit**

Run Step 2. Expected: PASS.

```bash
git add MateDriveApp/Features/Activities/ActivityLabelEditorView.swift MateDriveApp/Features/Charges/ChargePriceConfirmationView.swift MateDriveApp/Features/Settings/SmartActivitySettingsView.swift MateDriveApp/Features/Activities/ActivitySessionDetailView.swift MateDriveApp/Features/Charges/ChargeDetailView.swift MateDriveApp/Features/Settings/AppSettings.swift MateDriveApp/Features/Settings/SettingsViewModel.swift MateDriveApp/Features/Settings/SettingsView.swift MateDriveTests/Features/SmartActivitySettingsTests.swift MateDriveTests/Features/ChargePriceConfirmationTests.swift MateDriveTests/Features/SettingsViewModelTests.swift MateDrive.xcodeproj/project.pbxproj
git commit -m "feat: confirm activity labels and charging prices"
```

### Task 11: Backup, Privacy, Localization, And Cache Clearing

**Files:**
- Modify: `MateDriveApp/Features/Settings/PrivacyDataView.swift`
- Modify: `MateDriveApp/Resources/Localizable.xcstrings`
- Modify test: `MateDriveTests/Backup/DatabaseBackupProviderTests.swift`
- Modify test: `MateDriveTests/Backup/CloudBackupRestoreTests.swift`
- Modify test: `MateDriveTests/Localization/LocalizationCoverageTests.swift`
- Test: `MateDriveTests/Features/SmartActivityPrivacyTests.swift`

**Interfaces:**
- Consumes: existing whole-database backup artifacts, AppSettings backup, smart-activity stores, and Privacy data actions.
- Produces: restored durable overrides, removable derived caches, clear privacy copy, and complete localization.

- [ ] **Step 1: Write failing backup and clearing tests**

```swift
func testBackupRestorePreservesLabelsAndPricingObservations() async throws {
    let fixture = try await SmartActivityBackupFixture.make()
    try await fixture.labels.save(.fixture)
    try await fixture.observations.save(.fixture)
    let artifact = try await fixture.provider.createArtifact(appVersion: "1.0")
    try await fixture.restore(artifact)
    XCTAssertEqual(try await fixture.labels.override(id: ActivityLabelOverride.fixture.id), .fixture)
    XCTAssertEqual(try await fixture.observations.observations(carId: 1, stationKey: "station"), [.fixture])
}

func testClearDerivedDataPreservesLearnedAndManualValues() async throws {
    let stores = try await SmartActivityTestStores.make()
    try await stores.sessions.replace(carId: 1, sessions: [.fixture])
    try await stores.labels.save(.fixture)
    try await stores.sessions.removeDerivedSessions()
    XCTAssertTrue(try await stores.sessions.sessions(carId: 1).isEmpty)
    XCTAssertNotNil(try await stores.labels.override(id: ActivityLabelOverride.fixture.id))
}
```

- [ ] **Step 2: Run focused tests and verify failure**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/DatabaseBackupProviderTests -only-testing:MateDriveTests/CloudBackupRestoreTests -only-testing:MateDriveTests/SmartActivityPrivacyTests -only-testing:MateDriveTests/LocalizationCoverageTests test
```

Expected: new smart-activity assertions FAIL until stores and copy are integrated.

- [ ] **Step 3: Include derived-cache clearing without deleting durable decisions**

Extend `PrivacyDataView.clearSnapshots()` to call `SmartActivitySessionStoring.removeDerivedSessions()`. Add a separate destructive confirmation for learned labels and pricing observations. Do not include Keychain credentials in either action.

- [ ] **Step 4: Verify whole-database backup and schema 23 restore**

The existing backup already copies the complete SQLite database and encoded AppSettings. Add assertions for the three new tables and `homeTariffRegionCode`. The expected implementation leaves `DatabaseBackupProvider` unchanged because its whole-database snapshot already includes additive tables.

- [ ] **Step 5: Add visible privacy and localization copy**

State that classification runs on device from TeslaMate vehicle coordinates, no phone location is requested, estimates are not invoices, and learned labels/prices are included in iCloud backup. Add English and Simplified Chinese translations for every new tab, filter, purpose, quality, reason, editor, tariff, cost-source, and destructive confirmation string.

- [ ] **Step 6: Run focused tests and audits, then commit**

```bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/DatabaseBackupProviderTests -only-testing:MateDriveTests/CloudBackupRestoreTests -only-testing:MateDriveTests/SmartActivityPrivacyTests -only-testing:MateDriveTests/LocalizationCoverageTests test
python3 scripts/audit_localization.py
```

Expected: tests PASS and localization audit exits 0.

```bash
git add MateDriveApp/Features/Settings/PrivacyDataView.swift MateDriveApp/Resources/Localizable.xcstrings MateDriveTests/Backup/DatabaseBackupProviderTests.swift MateDriveTests/Backup/CloudBackupRestoreTests.swift MateDriveTests/Localization/LocalizationCoverageTests.swift MateDriveTests/Features/SmartActivityPrivacyTests.swift
git commit -m "feat: back up smart activity decisions"
```

### Task 12: Performance Gate, Physical Device, And TestFlight Build

**Files:**
- Create: `MateDriveTests/Performance/ActivityTimelinePerformanceTests.swift`
- Modify: `project.yml`
- Modify: `MateDriveApp/Info.plist`
- Modify: `MateDriveWidget/Info.plist`
- Create: `build/ExportOptions-TestFlight.plist` during release execution; do not commit generated build artifacts.

**Interfaces:**
- Consumes: complete feature, release audits, connected iPhone, and existing App Store signing.
- Produces: measured cached navigation, build number 4, installed device build, and uploaded TestFlight archive.

- [ ] **Step 1: Add a cached-load performance regression test**

```swift
@MainActor
func testLoadingFiveHundredCachedSessionsStaysWithinBudget() async throws {
    let store = InMemorySmartActivitySessionStore(sessions: SmartActivitySession.fixtures(count: 500))
    let viewModel = ActivityTimelineViewModel(sessionStore: store)
    let clock = ContinuousClock()
    let duration = await clock.measure { await viewModel.load(carId: 1) }
    XCTAssertLessThan(duration, .milliseconds(100))
    XCTAssertEqual(store.networkRequestCount, 0)
}
```

- [ ] **Step 2: Run focused performance and repeated-detail tests**

```bash
make generate
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/ActivityTimelinePerformanceTests -only-testing:MateDriveTests/ActivityTimelineViewModelTests test
```

Expected: PASS, cached load under 100 ms in the test fixture, and zero network requests.

- [ ] **Step 3: Run the complete technical gate before version changes**

```bash
make preflight
make test
python3 scripts/audit_regional_tariffs.py
python3 scripts/audit_app_store_submission.py --technical-only
```

Expected: all tests and audits PASS with zero failures.

- [ ] **Step 4: Manually verify simulator interaction**

Launch iPhone 17 and verify all four tabs, repeated Activity and detail opening, source links, filters, Home overnight charging, public DC replenishment, price confirmation, dark mode, large Dynamic Type, Chinese, English, offline launch, and map scrolling. Confirm no spinner replaces already cached data and no overlapping toolbar buttons appear.

- [ ] **Step 5: Increment build number only after the gate passes**

Change `CURRENT_PROJECT_VERSION` and all `CFBundleVersion` values from `3` to `4`, regenerate the project, and verify the app and widget both report build 4.

- [ ] **Step 6: Build and install on the connected iPhone**

```bash
make generate
./scripts/install_on_iphone.sh
```

Expected: MateDrive 1.0 (4) installs and launches on the connected device without a crash.

- [ ] **Step 7: Archive and upload TestFlight**

Create `build/ExportOptions-TestFlight.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>destination</key><string>upload</string>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>JYN528573D</string>
<key>uploadSymbols</key><true/>
</dict></plist>
```

Then run:

```bash
rm -rf build/MateDrive-1.0-4.xcarchive
xcodebuild archive -project MateDrive.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS' -archivePath build/MateDrive-1.0-4.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/MateDrive-1.0-4.xcarchive -exportOptionsPlist build/ExportOptions-TestFlight.plist -allowProvisioningUpdates
```

Expected: `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, and App Store Connect reports upload success.

- [ ] **Step 8: Commit release metadata after successful upload**

```bash
git add project.yml MateDrive.xcodeproj/project.pbxproj MateDriveApp/Info.plist MateDriveWidget/Info.plist MateDriveTests/Performance/ActivityTimelinePerformanceTests.swift
git commit -m "release: prepare MateDrive build 4"
```

Do not commit `build/`, archives, export options containing transient release settings, or exported packages.

## Plan Completion Criteria

- Four independent root tabs work with Activity between Home and Features.
- A public charging stop groups arrival, parking, charge, and departure into one complete replenishment session.
- A Home AC charge may start hours after arrival and still groups correctly.
- Parking cards separate net battery change, charge gain, standby loss, rated-range change, sleep, and awake time.
- Purpose suggestions explain their evidence and never outrank user decisions.
- The tariff catalog contains all 31 mainland region codes and never guesses an unverified price.
- Manual cost, API cost, station rules, Home rules, and regional tariffs resolve in the documented order.
- A first confirmed station price estimates the next matching charge without overwriting history.
- Activity and detail pages read cached SQLite data only and repeatedly open without visible loading stalls.
- Derived data can be rebuilt; labels, observations, and manual costs survive rebuilds and iCloud backup.
- Full tests, localization, privacy, tariff, App Store, archive, device, and TestFlight checks pass.
