# MateDrive iPhone Widgets and Live Activity Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a privacy-safe current-charge Home Screen widget, trustworthy stale/offline states, secure per-vehicle navigation, and a centralized local-only Live Activity lifecycle.

**Architecture:** Extend the existing App Group snapshot with an optional current-charge value, derive it through a pure builder, and keep all TeslaMate access inside the app. A small coordinator separates foreground start-or-update behavior from background update-existing behavior, while an allow-listed URL router carries only the existing opaque vehicle identity into the app.

**Tech Stack:** Swift 6.3, SwiftUI, WidgetKit, ActivityKit, AppIntents, Foundation, XCTest, XCUITest, XcodeGen; iOS 18.0 minimum.

## Global Constraints

- Preserve the existing read-only product boundary; do not add vehicle-control actions.
- Do not add APNs, push-to-start tokens, a Singapore-server worker, or any other server component.
- The Widget extension must not create a TeslaMate API client, access Keychain, or issue network requests.
- Support only systemSmall and systemMedium for the new Current Charge widget.
- Support English, Simplified Chinese, and Traditional Chinese.
- Widget data is current for 30 minutes; after that, show an explicit stale state.
- Live Activity content uses a two-minute staleDate and must visibly indicate stale content.
- A failed request is indeterminate and must never be treated as authoritative “not charging.”
- URLs and shared snapshots must not contain server URLs, tokens, authentication headers, VINs, raw vehicle IDs, precise locations, or addresses.
- Do not claim full-app accessibility compliance; validate only the native-entry paths in this plan.
- Do not upload, submit, or install on a physical iPhone without explicit user authorization.
- Preserve the existing Build 19 archive. Increment the source to Build 20 only after focused and full regression gates pass.
- The current migrated worktree contains user-owned uncommitted changes. Do not stage or commit. Each task ends with an uncommitted verification checkpoint. If the user later authorizes an isolated clean worktree, those checkpoints may be converted into commits.
- Preserve unrelated dirty-worktree changes and use apply_patch for edits.

---

## File Map

### New files

- MateDriveApp/Features/Charges/WidgetCurrentChargeSnapshotBuilder.swift — pure conversion from TeslaMate status/current-charge results into widget-safe state.
- MateDriveApp/Features/Charges/ChargeLiveActivityCoordinator.swift — policy engine for start/update/end/no-op decisions.
- MateDriveApp/Core/Sync/WidgetTimelineReloader.swift — injectable WidgetCenter boundary.
- MateDriveApp/App/WidgetNavigationRouter.swift — app-only route resolution and app-private vehicle registry.
- MateDriveWidget/WidgetCurrentChargePresentation.swift — pure localized presentation model shared with app tests.
- MateDriveWidget/CurrentChargeWidget.swift — WidgetKit configuration, timeline provider, and small/medium views.
- MateDriveWidget/WidgetNavigation.swift — shared allow-listed URL request and URL builder/parser.
- MateDriveWidget/ChargeLiveActivityPresentation.swift — pure localized Live Activity text model.
- MateDriveTests/Features/WidgetCurrentChargeSnapshotBuilderTests.swift
- MateDriveTests/Features/WidgetCurrentChargePresentationTests.swift
- MateDriveTests/Features/ChargeLiveActivityCoordinatorTests.swift
- MateDriveTests/Features/ChargeLiveActivityPresentationTests.swift
- MateDriveTests/App/WidgetNavigationRouterTests.swift
- MateDriveTests/Support/WidgetNativeEntryFixtures.swift — shared deterministic fixtures used by the new test classes.
- scripts/audit_native_entry_boundaries.py — independently executable native-entry security and localization boundary audit.
- scripts/test_audit_native_entry_boundaries.py — controlled-fixture behavior tests for the audit.

### Existing files to modify

- MateDriveWidget/WidgetDisplayData.swift — new current-charge model, kind, snapshot field, and merge-safe store update.
- MateDriveWidget/MateDriveWidgetBundle.swift — register CurrentChargeWidget.
- MateDriveWidget/CarStatusWidget.swift — preserve the configured opaque vehicle ID and attach Dashboard navigation.
- MateDriveWidget/TrendWidgets.swift — attach Battery and Charges navigation.
- MateDriveWidget/ChargeLiveActivityAttributes.swift — anonymous vehicle ID, language, quality, and updated time.
- MateDriveWidget/ChargeLiveActivityWidget.swift — localized/stale UI and Current Charge navigation.
- MateDriveApp/Core/Sync/AppDataPreloader.swift — conditional current-charge read, merge-on-failure, per-kind reload, existing-only activity reconciliation.
- MateDriveApp/Features/Dashboard/DashboardViewModel.swift — foreground partial charge snapshot and allow-start reconciliation.
- MateDriveApp/Features/Charges/CurrentChargeViewModel.swift — publish complete charge snapshot and use the coordinator.
- MateDriveApp/Features/Charges/ChargeLiveActivityManager.swift — split start-or-update from update-existing.
- MateDriveApp/App/RootView.swift — inject the foreground coordinator and handle widget URLs.
- MateDriveApp/App/MateDriveApp.swift — inject existing-only coordination into background preload.
- MateDriveApp/Resources/Localizable.xcstrings — three-language copy.
- MateDriveApp/Resources/CompiledLocalizations/**/Localizable.strings — regenerated resources.
- project.yml — shared source membership, custom URL scheme, and final Build 20 increment.
- MateDrive.xcodeproj/project.pbxproj — regenerate from project.yml.
- MateDriveTests/Features/WidgetDisplayDataTests.swift
- MateDriveTests/Features/CurrentChargeViewModelTests.swift
- MateDriveTests/Features/DashboardViewModelTests.swift
- MateDriveTests/Sync/BackgroundRefreshWorkRunnerTests.swift
- Makefile
- docs/parity/manual-test-checklist.md
- docs/release/app-store-submission.md
- docs/release/app-store-publishing-zh.md
- docs/release/continuous-product-readiness.md

---

### Task 1: Add the backward-compatible current-charge snapshot domain

**Files:**
- Modify: MateDriveWidget/WidgetDisplayData.swift
- Test: MateDriveTests/Features/WidgetDisplayDataTests.swift
- Create: MateDriveTests/Support/WidgetNativeEntryFixtures.swift
- Regenerate: MateDrive.xcodeproj/project.pbxproj (from the existing project.yml test-source directory)

**Interfaces:**
- Produces: WidgetChargePhase, WidgetChargeDataQuality, WidgetCurrentChargeData.
- Produces: WidgetConstants.currentChargeKind.
- Produces: WidgetVehicleSnapshot.currentCharge.
- Produces: WidgetSnapshotStore.updateCurrentCharge(_:vehicleIdentifier:) -> Bool.
- Produces: internal test-only fixture factories shared by the native-entry test classes.
- Consumes: Existing WidgetDisplayLanguage, WidgetDisplayUnitSystem, WidgetVehicleSnapshot, and WidgetSnapshotStore.

- [ ] **Step 1: Write failing model and persistence tests**

Add these test cases to WidgetDisplayDataTests:

~~~swift
func testLegacyVehicleSnapshotDecodesWithoutCurrentCharge() throws {
    let json = """
    {
      "id":"opaque",
      "data":{"carName":"Model 3","isCharging":false,"sentryModeActive":false,"isReadOnly":true,"displayLanguage":"english"},
      "updatedAt":0
    }
    """

    let snapshot = try JSONDecoder().decode(
        WidgetVehicleSnapshot.self,
        from: Data(json.utf8)
    )

    XCTAssertNil(snapshot.currentCharge)
}

func testCurrentChargeNormalizesUnsafeNumericValues() {
    let value = WidgetCurrentChargeData(
        phase: .charging,
        quality: .complete,
        batteryLevel: 140,
        chargeLimitSoc: -3,
        chargerPowerKW: -20,
        energyAddedKWh: -.infinity,
        timeToFullMinutes: -4,
        isDC: true,
        updatedAt: Date(timeIntervalSince1970: 100)
    )

    XCTAssertEqual(value.batteryLevel, 100)
    XCTAssertEqual(value.chargeLimitSoc, 0)
    XCTAssertNil(value.chargerPowerKW)
    XCTAssertNil(value.energyAddedKWh)
    XCTAssertEqual(value.timeToFullMinutes, 0)
}

func testSavingDashboardDataPreservesCurrentCharge() throws {
    let suiteName = "WidgetCurrentChargePreservation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WidgetSnapshotStore(defaults: defaults)
    let charge = WidgetCurrentChargeData.fixture(phase: .charging)

    store.replaceVehicleSnapshots([
        WidgetVehicleSnapshot(
            id: "opaque",
            data: .fixture(carName: "Model 3"),
            currentCharge: charge
        )
    ], preferredIdentifier: "opaque")
    store.save(.fixture(carName: "Model 3", batteryLevel: 72), vehicleIdentifier: "opaque")

    XCTAssertEqual(store.vehicleSnapshot(vehicleIdentifier: "opaque")?.currentCharge, charge)
}

func testUpdateCurrentChargeChangesOnlyTheSelectedVehicle() throws {
    let suiteName = "WidgetCurrentChargeIsolation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WidgetSnapshotStore(defaults: defaults)
    store.replaceVehicleSnapshots([
        WidgetVehicleSnapshot(id: "one", data: .fixture(carName: "One")),
        WidgetVehicleSnapshot(id: "two", data: .fixture(carName: "Two"))
    ], preferredIdentifier: "one")

    let changed = store.updateCurrentCharge(
        .fixture(phase: .charging, batteryLevel: 64),
        vehicleIdentifier: "two"
    )

    XCTAssertTrue(changed)
    XCTAssertNil(store.vehicleSnapshot(vehicleIdentifier: "one")?.currentCharge)
    XCTAssertEqual(
        store.vehicleSnapshot(vehicleIdentifier: "two")?.currentCharge?.batteryLevel,
        64
    )
}

func testCurrentChargeSnapshotCodableRoundTripPreservesEveryField() throws {
    let original = WidgetVehicleSnapshot.fixture(
        id: "opaque",
        currentCharge: .fixture(
            phase: .charging,
            quality: .partial,
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: true,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
    )

    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(WidgetVehicleSnapshot.self, from: encoded)

    XCTAssertEqual(decoded, original)
}

func testRemovingWidgetStoreClearsCurrentChargeSnapshot() throws {
    let suiteName = "WidgetCurrentChargeRemoval.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WidgetSnapshotStore(defaults: defaults)
    store.replaceVehicleSnapshots([
        .fixture(id: "opaque", currentCharge: .fixture(phase: .charging))
    ], preferredIdentifier: "opaque")

    store.remove()

    XCTAssertTrue(store.vehicleSnapshots().isEmpty)
    XCTAssertNil(store.vehicleSnapshot(vehicleIdentifier: "opaque"))
}

func testEncodedCurrentChargeContainsOnlyAllowListedFields() throws {
    let snapshot = WidgetVehicleSnapshot.fixture(
        id: "opaque",
        batteryTrend: WidgetBatteryTrendData(metric: .capacity, samples: [75, 72]),
        chargingTrend: WidgetChargingTrendData(
            sessionCount: 1,
            energyKWh: 18.4,
            energyKnownCount: 1,
            currencyCode: "CNY",
            energyBuckets: [0, 0, 0, 0, 0, 18.4]
        ),
        currentCharge: .fixture(
            phase: .charging,
            quality: .complete,
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: true
        )
    )
    let object = try XCTUnwrap(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))
            as? [String: Any]
    )
    let currentCharge = try XCTUnwrap(object["currentCharge"] as? [String: Any])

    XCTAssertEqual(
        Set(object.keys),
        ["id", "data", "batteryTrend", "chargingTrend", "currentCharge", "updatedAt"]
    )
    XCTAssertEqual(
        Set(currentCharge.keys),
        [
            "phase", "quality", "batteryLevel", "chargeLimitSoc", "chargerPowerKW",
            "energyAddedKWh", "timeToFullMinutes", "isDC", "updatedAt"
        ]
    )
    let forbidden = [
        "token", "password", "serverurl", "basicauth", "authorization", "vin",
        "latitude", "longitude", "address", "location"
    ]
    XCTAssertTrue(Set(currentCharge.keys.map { $0.lowercased() }).isDisjoint(with: forbidden))
}
~~~

- [ ] **Step 2: Regenerate test source membership, then run the focused test and verify RED**

Run xcodegen generate after adding the new test-support file. Do not hand-edit project.pbxproj and do not modify project.yml in this task.

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/WidgetDisplayDataTests test
~~~

Expected: compilation fails because WidgetCurrentChargeData, currentCharge, and updateCurrentCharge do not exist.

- [ ] **Step 3: Implement the model and merge-safe store API**

Add this domain shape beside the existing trend models:

~~~swift
public enum WidgetChargePhase: String, Codable, Equatable, Sendable {
    case charging
    case starting
    case idle
}

public enum WidgetChargeDataQuality: String, Codable, Equatable, Sendable {
    case complete
    case partial
    case offline
}

public struct WidgetCurrentChargeData: Codable, Equatable, Sendable {
    public let phase: WidgetChargePhase
    public let quality: WidgetChargeDataQuality
    public let batteryLevel: Int?
    public let chargeLimitSoc: Int?
    public let chargerPowerKW: Int?
    public let energyAddedKWh: Double?
    public let timeToFullMinutes: Int?
    public let isDC: Bool?
    public let updatedAt: Date

    public init(
        phase: WidgetChargePhase,
        quality: WidgetChargeDataQuality,
        batteryLevel: Int? = nil,
        chargeLimitSoc: Int? = nil,
        chargerPowerKW: Int? = nil,
        energyAddedKWh: Double? = nil,
        timeToFullMinutes: Int? = nil,
        isDC: Bool? = nil,
        updatedAt: Date
    ) {
        self.phase = phase
        self.quality = quality
        self.batteryLevel = batteryLevel.map { min(max($0, 0), 100) }
        self.chargeLimitSoc = chargeLimitSoc.map { min(max($0, 0), 100) }
        self.chargerPowerKW = chargerPowerKW.flatMap { $0 >= 0 ? $0 : nil }
        self.energyAddedKWh = energyAddedKWh.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.timeToFullMinutes = timeToFullMinutes.map { max($0, 0) }
        self.isDC = isDC
        self.updatedAt = updatedAt
    }

    public func markingOffline() -> Self {
        Self(
            phase: phase,
            quality: .offline,
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            updatedAt: updatedAt
        )
    }

    public func isStale(at now: Date, threshold: TimeInterval = 30 * 60) -> Bool {
        now.timeIntervalSince(updatedAt) > threshold
    }
}
~~~

Also:

- add currentChargeKind = "CurrentChargeWidget";
- add currentCharge: WidgetCurrentChargeData? with a defaulted initializer parameter to WidgetVehicleSnapshot;
- preserve existing.currentCharge inside WidgetSnapshotStore.save(_:vehicleIdentifier:makeLatest:updatedAt:);
- implement updateCurrentCharge under the existing store lock; return false when the vehicle is missing or its currentCharge is equal, otherwise replace only currentCharge, preserve the parent snapshot updatedAt, persist once, and return true;
- add the following internal test-only factories in WidgetNativeEntryFixtures.swift rather than shipping test defaults in production code:

~~~swift
import Foundation
@testable import MateDriveApp

extension WidgetCurrentChargeData {
    static func fixture(
        phase: WidgetChargePhase = .charging,
        quality: WidgetChargeDataQuality = .complete,
        batteryLevel: Int? = nil,
        chargeLimitSoc: Int? = nil,
        chargerPowerKW: Int? = nil,
        energyAddedKWh: Double? = nil,
        timeToFullMinutes: Int? = nil,
        isDC: Bool? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> Self {
        Self(
            phase: phase,
            quality: quality,
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            updatedAt: updatedAt
        )
    }
}

extension WidgetVehicleSnapshot {
    static func fixture(
        id: String = String(repeating: "a", count: 64),
        data: WidgetDisplayData = .fixture(
            carName: "Model 3",
            displayLanguage: .english
        ),
        batteryTrend: WidgetBatteryTrendData? = nil,
        chargingTrend: WidgetChargingTrendData? = nil,
        currentCharge: WidgetCurrentChargeData? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> Self {
        Self(
            id: id,
            data: data,
            batteryTrend: batteryTrend,
            chargingTrend: chargingTrend,
            currentCharge: currentCharge,
            updatedAt: updatedAt
        )
    }
}

extension ChargeLiveActivitySnapshot {
    static func fixture(
        carName: String = "Model 3",
        batteryLevel: Int? = 64,
        chargeLimitSoc: Int? = 80,
        chargerPowerKW: Int? = 72,
        energyAddedKWh: Double? = 18.4,
        timeToFullMinutes: Int? = 65,
        isDC: Bool = false,
        isCharging: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_786_320_000)
    ) -> Self {
        Self(
            carName: carName,
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            isCharging: isCharging,
            updatedAt: updatedAt
        )
    }
}
~~~

The store update must rebuild one WidgetVehicleSnapshot while preserving data, batteryTrend, chargingTrend, and the opaque id.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run the same xcodebuild command. Expected: WidgetDisplayDataTests passes with zero failures.

- [ ] **Step 5: Record the uncommitted checkpoint**

Run:

~~~bash
git diff --check
git status --short -- MateDriveWidget/WidgetDisplayData.swift MateDriveTests/Features/WidgetDisplayDataTests.swift
~~~

Expected: no whitespace errors; only the intended files are reported.

---

### Task 2: Build current-charge state through one pure converter

**Files:**
- Create: MateDriveApp/Features/Charges/WidgetCurrentChargeSnapshotBuilder.swift
- Create: MateDriveTests/Features/WidgetCurrentChargeSnapshotBuilderTests.swift
- Regenerate: MateDrive.xcodeproj/project.pbxproj (from existing project.yml source directories)

**Interfaces:**
- Consumes: APIResult<CarStatusPayload>, APIResult<CurrentChargeOutcome>?, WidgetCurrentChargeData?, and Date.
- Produces: WidgetCurrentChargeSnapshotBuilder.build(statusResult:currentChargeResult:previous:now:) -> WidgetCurrentChargeData?.

- [ ] **Step 1: Write failing state-matrix tests**

Cover all authoritative and indeterminate outcomes:

~~~swift
@MainActor
final class WidgetCurrentChargeSnapshotBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_320_000)

    func testActiveChargeBuildsCompleteSnapshot() throws {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.chargingFixture),
            currentChargeResult: .success(.active(.activeFixture)),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.phase, .charging)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertEqual(result?.batteryLevel, 70)
        XCTAssertEqual(result?.chargeLimitSoc, 80)
        XCTAssertEqual(result?.chargerPowerKW, 80)
        XCTAssertEqual(result?.energyAddedKWh, 28)
        XCTAssertEqual(result?.timeToFullMinutes, 90)
        XCTAssertEqual(result?.updatedAt, now)
    }

    func testChargingStatusWithoutActiveRecordBuildsStartingSnapshot() {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.chargingFixture),
            currentChargeResult: .success(.noActiveCharge),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.phase, .starting)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertNil(result?.energyAddedKWh)
    }

    func testDetailFailureBuildsPartialSnapshotFromAuthoritativeStatus() {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.chargingFixture),
            currentChargeResult: .failure(.network("offline")),
            previous: nil,
            now: now
        )

        XCTAssertEqual(result?.phase, .charging)
        XCTAssertEqual(result?.quality, .partial)
        XCTAssertEqual(result?.batteryLevel, 70)
        XCTAssertEqual(result?.energyAddedKWh, 27)
    }

    func testAuthoritativeIdleClearsEveryChargeMetric() {
        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .success(.idleFixture),
            currentChargeResult: nil,
            previous: .fixture(phase: .charging, batteryLevel: 70),
            now: now
        )

        XCTAssertEqual(result?.phase, .idle)
        XCTAssertEqual(result?.quality, .complete)
        XCTAssertEqual(result?.batteryLevel, 55)
        XCTAssertEqual(result?.chargeLimitSoc, 80)
        XCTAssertNil(result?.chargerPowerKW)
        XCTAssertNil(result?.energyAddedKWh)
        XCTAssertNil(result?.timeToFullMinutes)
    }

    func testStatusFailurePreservesPreviousTimestampAndMarksOffline() {
        let previous = WidgetCurrentChargeData.fixture(
            phase: .charging,
            batteryLevel: 65,
            updatedAt: now.addingTimeInterval(-600)
        )

        let result = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .failure(.network("offline")),
            currentChargeResult: nil,
            previous: previous,
            now: now
        )

        XCTAssertEqual(result?.quality, .offline)
        XCTAssertEqual(result?.batteryLevel, 65)
        XCTAssertEqual(result?.updatedAt, previous.updatedAt)
    }

    func testStatusFailureWithoutPreviousSnapshotReturnsNil() {
        XCTAssertNil(WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: .failure(.network("offline")),
            currentChargeResult: nil,
            previous: nil,
            now: now
        ))
    }
}
~~~

Define these private fixtures inside this new test file so it does not depend on CurrentChargeViewModelTests:

~~~swift
private extension CarStatusPayload {
    static let chargingFixture = CarStatusPayload(status: CarStatus(
        displayName: "Model 3",
        batteryDetails: BatteryDetails(batteryLevel: 70),
        chargingDetails: ChargingDetails(
            pluggedIn: true,
            chargingState: "Charging",
            chargeEnergyAdded: 27,
            chargeLimitSoc: 80,
            chargerPhases: 0,
            chargerPower: 80,
            timeToFullCharge: 1.5
        )
    ))

    static let idleFixture = CarStatusPayload(status: CarStatus(
        displayName: "Model 3",
        batteryDetails: BatteryDetails(batteryLevel: 55),
        chargingDetails: ChargingDetails(
            pluggedIn: false,
            chargingState: "Disconnected",
            chargeLimitSoc: 80
        )
    ))
}

private extension ChargeDetail {
    static let activeFixture = ChargeDetail(
        chargeId: 9007,
        chargeEnergyAdded: 28,
        batteryDetails: ChargeBatteryDetails(
            startBatteryLevel: 40,
            currentBatteryLevel: 69
        ),
        chargePoints: [],
        isCharging: true
    )
}
~~~

- [ ] **Step 2: Regenerate source membership, then run the new test and verify RED**

Run xcodegen generate after adding the new files. Do not hand-edit project.pbxproj or modify project.yml in this task.

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/WidgetCurrentChargeSnapshotBuilderTests test
~~~

Expected: compilation fails because WidgetCurrentChargeSnapshotBuilder is undefined.

- [ ] **Step 3: Implement the pure builder**

Use this public boundary:

~~~swift
public enum WidgetCurrentChargeSnapshotBuilder {
    public static func build(
        statusResult: APIResult<CarStatusPayload>,
        currentChargeResult: APIResult<CurrentChargeOutcome>?,
        previous: WidgetCurrentChargeData?,
        now: Date
    ) -> WidgetCurrentChargeData? {
        guard case let .success(payload) = statusResult,
              let status = payload.status
        else {
            return previous?.markingOffline()
        }

        guard status.isCharging else {
            return WidgetCurrentChargeData(
                phase: .idle,
                quality: .complete,
                batteryLevel: status.batteryLevel,
                chargeLimitSoc: status.chargeLimitSoc,
                updatedAt: now
            )
        }

        switch currentChargeResult {
        case let .success(.active(detail)):
            return makeCharging(
                status: status,
                detail: detail,
                quality: .complete,
                now: now
            )
        case .success(.noActiveCharge):
            return makeStarting(status: status, now: now)
        case .failure, .none:
            return makeCharging(
                status: status,
                detail: nil,
                quality: .partial,
                now: now
            )
        }
    }
}
~~~

The private makeCharging helper must use status battery/limit/power/time first, fall back to the active detail's battery and latest charge point only when a status value is absent, prefer detail.chargeEnergyAdded over status.chargingDetails?.chargeEnergyAdded, convert hours to rounded minutes, and never manufacture zero values. When detail fails, authoritative status energy remains available as partial data; do not reuse an older session's metrics merely because they were cached.

- [ ] **Step 4: Run the state-matrix test and verify GREEN**

Expected: all new builder tests pass.

- [ ] **Step 5: Re-run the current-charge view-model tests**

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/CurrentChargeViewModelTests test
~~~

Expected: existing current-charge behavior remains green.

- [ ] **Step 6: Record the uncommitted checkpoint**

Run git diff --check and inspect only the new builder and test files.

---

### Task 3: Integrate conditional background snapshots without erasing good data

**Files:**
- Create: MateDriveApp/Core/Sync/WidgetTimelineReloader.swift
- Modify: MateDriveApp/Core/Sync/AppDataPreloader.swift
- Modify: MateDriveTests/Sync/BackgroundRefreshWorkRunnerTests.swift
- Regenerate: MateDrive.xcodeproj/project.pbxproj (from existing project.yml source directories)

**Interfaces:**
- Consumes: WidgetCurrentChargeSnapshotBuilder from Task 2.
- Produces: WidgetTimelineReloading.reloadTimelines(ofKind:) async.
- Produces: AppDataPreloader widget result counts that include conditional current-charge requests.

- [ ] **Step 1: Write failing preloader tests**

Add tests proving request bounds, preservation, and targeted reloads:

~~~swift
func testWidgetPreloadRequestsCurrentChargeOnlyForChargingVehicles() async throws {
    let client = PreloadRecordingHTTPClient(
        carIDs: [7, 8],
        chargingCarIDs: [7]
    )
    let suiteName = "PreloadCurrentCharge.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WidgetSnapshotStore(defaults: defaults)
    let reloader = RecordingWidgetTimelineReloader()
    let preloader = AppDataPreloader(
        settingsStore: PreloadSettingsStore(settings: AppSettings(
            serverURL: "https://teslamate.example",
            lastSelectedCarId: 7
        )),
        secretStore: PreloadSecretStore(),
        clientOverride: client,
        widgetSnapshotStore: store,
        widgetTimelineReloader: reloader
    )

    let report = await preloader.preload(force: true)
    let paths = await client.requestedPaths

    XCTAssertTrue(paths.contains("/api/v1/cars/7/charges/current"))
    XCTAssertFalse(paths.contains("/api/v1/cars/8/charges/current"))
    let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
        serverURL: "https://teslamate.example",
        carID: 7
    ))
    XCTAssertEqual(
        store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge?.phase,
        .charging
    )
    XCTAssertEqual(report.requestedEndpointCount, 55)
}

func testFailedStatusPreservesLastCurrentChargeAndMarksItOffline() async throws {
    let suiteName = "PreloadCurrentChargeOffline.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WidgetSnapshotStore(defaults: defaults)
    let reloader = RecordingWidgetTimelineReloader()
    let settings = AppSettings(
        serverURL: "https://teslamate.example",
        lastSelectedCarId: 7
    )
    let successful = AppDataPreloader(
        settingsStore: PreloadSettingsStore(settings: settings),
        secretStore: PreloadSecretStore(),
        clientOverride: PreloadRecordingHTTPClient(
            carIDs: [7],
            chargingCarIDs: [7],
            chargingPowerKWByCarID: [7: 72]
        ),
        widgetSnapshotStore: store,
        widgetTimelineReloader: reloader
    )
    _ = await successful.preload(force: true)
    let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
        serverURL: settings.serverURL,
        carID: 7
    ))
    let before = try XCTUnwrap(
        store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge
    )
    await reloader.reset()

    let failing = AppDataPreloader(
        settingsStore: PreloadSettingsStore(settings: settings),
        secretStore: PreloadSecretStore(),
        clientOverride: PreloadRecordingHTTPClient(
            carIDs: [7],
            chargingCarIDs: [7],
            failedStatusCarIDs: [7],
            chargingPowerKWByCarID: [7: 72]
        ),
        widgetSnapshotStore: store,
        widgetTimelineReloader: reloader
    )
    _ = await failing.preload(force: true)

    let after = try XCTUnwrap(
        store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge
    )
    XCTAssertEqual(after.quality, .offline)
    XCTAssertEqual(after.batteryLevel, before.batteryLevel)
    XCTAssertEqual(after.energyAddedKWh, before.energyAddedKWh)
    XCTAssertEqual(after.updatedAt, before.updatedAt)
    let reloadedKinds = await reloader.kinds
    XCTAssertEqual(reloadedKinds, [WidgetConstants.currentChargeKind])
}

func testWidgetPreloadReloadsOnlyChangedKinds() async throws {
    let suiteName = "PreloadTargetedReload.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = WidgetSnapshotStore(defaults: defaults)
    let reloader = RecordingWidgetTimelineReloader()
    let settings = AppSettings(
        serverURL: "https://teslamate.example",
        lastSelectedCarId: 7
    )
    let first = AppDataPreloader(
        settingsStore: PreloadSettingsStore(settings: settings),
        secretStore: PreloadSecretStore(),
        clientOverride: PreloadRecordingHTTPClient(
            carIDs: [7],
            chargingCarIDs: [7],
            chargingPowerKWByCarID: [7: 72]
        ),
        widgetSnapshotStore: store,
        widgetTimelineReloader: reloader
    )
    _ = await first.preload(force: true)
    await reloader.reset()

    let second = AppDataPreloader(
        settingsStore: PreloadSettingsStore(settings: settings),
        secretStore: PreloadSecretStore(),
        clientOverride: PreloadRecordingHTTPClient(
            carIDs: [7],
            chargingCarIDs: [7],
            chargingPowerKWByCarID: [7: 80]
        ),
        widgetSnapshotStore: store,
        widgetTimelineReloader: reloader
    )
    _ = await second.preload(force: true)

    let vehicleIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
        serverURL: settings.serverURL,
        carID: 7
    ))
    XCTAssertEqual(
        store.vehicleSnapshot(vehicleIdentifier: vehicleIdentifier)?.currentCharge?.chargerPowerKW,
        80
    )
    let reloadedKinds = await reloader.kinds
    XCTAssertEqual(reloadedKinds, [WidgetConstants.currentChargeKind])
}
~~~

- [ ] **Step 2: Regenerate source membership, then run the focused preloader tests and verify RED**

Run xcodegen generate after adding WidgetTimelineReloader.swift. Do not hand-edit project.pbxproj or modify project.yml in this task.

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/BackgroundRefreshWorkRunnerTests test
~~~

Expected: compilation fails for chargingCarIDs and WidgetTimelineReloading.

- [ ] **Step 3: Add an injectable WidgetCenter boundary**

Create:

~~~swift
import WidgetKit

public protocol WidgetTimelineReloading: Sendable {
    func reloadTimelines(ofKind kind: String) async
}

public struct SystemWidgetTimelineReloader: WidgetTimelineReloading {
    public init() {}

    public func reloadTimelines(ofKind kind: String) async {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
~~~

Use this actor recorder so kind order and duplicates can be asserted safely:

~~~swift
private actor RecordingWidgetTimelineReloader: WidgetTimelineReloading {
    private(set) var kinds: [String] = []

    func reloadTimelines(ofKind kind: String) async {
        kinds.append(kind)
    }

    func reset() {
        kinds.removeAll()
    }
}
~~~

- [ ] **Step 4: Make AppDataPreloader perform one conditional detail request**

Replace the fixed cars.count * 4 accounting with a private result:

~~~swift
private struct WidgetLoadResult: Sendable {
    let requestedRequestCount: Int
    let successfulRequestCount: Int
    let snapshots: [WidgetVehicleSnapshot]
}
~~~

Inside each vehicle task:

1. remove the existing unconditional /charges/current warmup from Self.requests so the endpoint has exactly one owner, then start status, battery health, battery history, and 200-charge history concurrently;
2. await status;
3. call refreshCurrentCharge only when status.value?.status?.isCharging == true;
4. build currentCharge through WidgetCurrentChargeSnapshotBuilder;
5. preserve previous data when status fails;
6. preserve previous batteryTrend or chargingTrend when its refresh fails;
7. count four base requests plus the optional current-charge request.

Capture the previous snapshots before entering the task group:

~~~swift
let previousByID = Dictionary(
    uniqueKeysWithValues: widgetSnapshotStore.vehicleSnapshots().map { ($0.id, $0) }
)
~~~

After building the new snapshots, compare data, batteryTrend, chargingTrend, and currentCharge independently and reload only their affected kinds.

- [ ] **Step 5: Extend the HTTP fixture with exact charging responses**

Add the following stored properties and initializer arguments to PreloadRecordingHTTPClient:

~~~swift
private let chargingCarIDs: Set<Int>
private let failedStatusCarIDs: Set<Int>
private let chargingPowerKWByCarID: [Int: Int]

init(
    carIDs: [Int] = [7],
    includesHistory: Bool = false,
    placePageCount: Int = 1,
    chargingCarIDs: Set<Int> = [],
    failedStatusCarIDs: Set<Int> = [],
    chargingPowerKWByCarID: [Int: Int] = [:]
) {
    self.carIDs = carIDs
    self.includesHistory = includesHistory
    self.placePageCount = placePageCount
    self.chargingCarIDs = chargingCarIDs
    self.failedStatusCarIDs = failedStatusCarIDs
    self.chargingPowerKWByCarID = chargingPowerKWByCarID
}
~~~

Return HTTP 503 with an empty object when failedStatusCarIDs contains the status car. Its status response for a charging car must include:

~~~json
{
  "charging_state": "Charging",
  "charge_limit_soc": 80,
  "charger_power": 80,
  "charge_energy_added": 12.5,
  "time_to_full_charge": 1.5
}
~~~

Return this active body at /charges/current and put the branch before the general /charges branch:

~~~json
{
  "data": {
    "car": {"car_id": 7, "car_name": "Test car 7"},
    "charge": {
      "charge_id": 9007,
      "charge_energy_added": 18.4,
      "battery_details": {
        "start_battery_level": 40,
        "current_battery_level": 67
      },
      "charge_points": [],
      "is_charging": true
    }
  }
}
~~~

Interpolate carID in car_id and charge_id. Interpolate chargingPowerKWByCarID[carID] ?? 72 in the status charger_power value. The inactive status branch remains exactly the existing Disconnected response.

- [ ] **Step 6: Run focused tests and verify GREEN**

Expected: request count is unchanged for idle cars, increases by one per charging car, failed status preserves the prior content, and reload kinds match exact changes.

- [ ] **Step 7: Record the uncommitted checkpoint**

Run git diff --check and inspect the preloader diff for accidental changes to unrelated history preloading.

---

### Task 4: Add the small and medium Current Charge widget

**Files:**
- Create: MateDriveWidget/WidgetCurrentChargePresentation.swift
- Create: MateDriveWidget/CurrentChargeWidget.swift
- Modify: MateDriveWidget/MateDriveWidgetBundle.swift
- Modify: project.yml
- Modify: MateDrive.xcodeproj/project.pbxproj
- Create: MateDriveTests/Features/WidgetCurrentChargePresentationTests.swift

**Interfaces:**
- Consumes: WidgetVehicleSnapshot.currentCharge and CarStatusConfigurationIntent.
- Produces: WidgetChargeVisualState and WidgetCurrentChargePresentation.make(snapshot:configuredVehicleName:now:).
- Produces: CurrentChargeWidget with systemSmall/systemMedium families.

- [ ] **Step 1: Write failing presentation tests**

~~~swift
final class WidgetCurrentChargePresentationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_786_320_000)

    func testChargingPresentationUsesRealMetrics() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                batteryLevel: 64,
                chargeLimitSoc: 80,
                chargerPowerKW: 72,
                energyAddedKWh: 18.4,
                timeToFullMinutes: 65,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .charging)
        XCTAssertEqual(value.batteryText, "64%")
        XCTAssertEqual(value.limitText, "Limit 80%")
        XCTAssertEqual(value.powerText, "72 kW")
        XCTAssertEqual(value.energyText, "18.4 kWh")
        XCTAssertEqual(value.remainingText, "1h 05m remaining")
    }

    func testOfflineBeatsFreshnessAndPreservesLastValues() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                quality: .offline,
                batteryLevel: 64,
                chargerPowerKW: 72,
                updatedAt: now.addingTimeInterval(-5 * 60)
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .offline)
        XCTAssertEqual(value.statusText, "Offline")
        XCTAssertEqual(value.batteryText, "64%")
        XCTAssertEqual(value.powerText, "72 kW")
        XCTAssertEqual(value.updatedText, "Updated 5m")
    }

    func testThirtyMinuteBoundaryBecomesStaleOnlyAfterThreshold() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                quality: .complete,
                batteryLevel: 64,
                updatedAt: now
            )
        )

        let atBoundary = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now.addingTimeInterval(1_800)
        )
        let afterBoundary = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now.addingTimeInterval(1_801)
        )

        XCTAssertEqual(atBoundary.state, .charging)
        XCTAssertEqual(afterBoundary.state, .stale)
        XCTAssertEqual(afterBoundary.statusText, "Data may be out of date")
    }

    func testSnapshotWithoutCurrentChargeShowsEnglishRecovery() {
        let snapshot = WidgetVehicleSnapshot.fixture(currentCharge: nil)
        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: "Model Y",
            now: now
        )

        XCTAssertEqual(value.state, .unavailable)
        XCTAssertEqual(value.carName, "Model 3")
        XCTAssertEqual(value.batteryText, "--")
        XCTAssertEqual(value.statusText, "Open MateDrive to sync")
        XCTAssertNil(value.powerText)
    }

    func testCompletelyMissingSnapshotIsUnavailable() {
        let value = WidgetCurrentChargePresentation.make(
            snapshot: nil,
            configuredVehicleName: "Model Y",
            now: now
        )

        XCTAssertEqual(value.state, .unavailable)
        XCTAssertEqual(value.carName, "Model Y")
        XCTAssertEqual(value.batteryText, "--")
    }

    func testIdlePresentationContainsNoPreviousChargeMetrics() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .idle,
                quality: .complete,
                batteryLevel: 55,
                chargeLimitSoc: 80,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .idle)
        XCTAssertEqual(value.statusText, "Not charging")
        XCTAssertEqual(value.batteryText, "55%")
        XCTAssertNil(value.limitText)
        XCTAssertNil(value.powerText)
        XCTAssertNil(value.energyText)
        XCTAssertNil(value.remainingText)
    }

    func testPartialChargeHasAnExplicitTrustLabel() {
        let snapshot = WidgetVehicleSnapshot.fixture(
            currentCharge: .fixture(
                phase: .charging,
                quality: .partial,
                batteryLevel: 64,
                updatedAt: now
            )
        )

        let value = WidgetCurrentChargePresentation.make(
            snapshot: snapshot,
            configuredVehicleName: nil,
            now: now
        )

        XCTAssertEqual(value.state, .charging)
        XCTAssertEqual(value.statusText, "Charging")
        XCTAssertEqual(value.trustText, "Partial data")
    }

    func testChargingStatusAndDurationFollowTheAppLanguage() {
        let cases: [(WidgetDisplayLanguage, String, String)] = [
            (.english, "Charging", "1h 05m remaining"),
            (.chinese, "正在充电", "剩余 1小时05分钟"),
            (.traditionalChinese, "正在充電", "剩餘 1小時05分鐘")
        ]

        for (language, status, remaining) in cases {
            let snapshot = WidgetVehicleSnapshot.fixture(
                data: .fixture(carName: "Model 3", displayLanguage: language),
                currentCharge: .fixture(
                    phase: .charging,
                    timeToFullMinutes: 65,
                    updatedAt: now
                )
            )
            let value = WidgetCurrentChargePresentation.make(
                snapshot: snapshot,
                configuredVehicleName: nil,
                now: now
            )

            XCTAssertEqual(value.statusText, status)
            XCTAssertEqual(value.remainingText, remaining)
        }
    }
}
~~~

- [ ] **Step 2: Run the presentation tests and verify RED**

Expected: compilation fails because WidgetCurrentChargePresentation is missing.

- [ ] **Step 3: Implement the shared presentation model**

Create a Foundation-only file so it can compile in both targets:

~~~swift
public enum WidgetChargeVisualState: Equatable, Sendable {
    case charging
    case starting
    case idle
    case offline
    case stale
    case unavailable
}

public struct WidgetCurrentChargePresentation: Equatable, Sendable {
    public let state: WidgetChargeVisualState
    public let carName: String
    public let statusText: String
    public let batteryText: String
    public let limitText: String?
    public let powerText: String?
    public let energyText: String?
    public let remainingText: String?
    public let updatedText: String?
    public let trustText: String?
    public let accessibilityText: String

    public static func make(
        snapshot: WidgetVehicleSnapshot?,
        configuredVehicleName: String?,
        now: Date
    ) -> Self {
        let language = snapshot?.data.displayLanguage ?? .system
        let carName = snapshot?.data.carName
            ?? configuredVehicleName?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "MateDrive"
        guard let charge = snapshot?.currentCharge else {
            let recovery = language.value(
                english: "Open MateDrive to sync",
                chinese: "打开 MateDrive 同步",
                traditionalChinese: "開啟 MateDrive 同步"
            )
            return Self(
                state: .unavailable,
                carName: carName,
                statusText: recovery,
                batteryText: "--",
                limitText: nil,
                powerText: nil,
                energyText: nil,
                remainingText: nil,
                updatedText: nil,
                trustText: nil,
                accessibilityText: "\(carName), \(recovery)"
            )
        }

        let state: WidgetChargeVisualState
        if charge.quality == .offline {
            state = .offline
        } else if charge.isStale(at: now) {
            state = .stale
        } else {
            state = switch charge.phase {
            case .charging: .charging
            case .starting: .starting
            case .idle: .idle
            }
        }

        let status = localizedStatus(state, language: language)
        let battery = charge.batteryLevel.map { "\($0)%" } ?? "--"
        let limit = charge.chargeLimitSoc.map {
            language.value(
                english: "Limit \($0)%",
                chinese: "目标 \($0)%",
                traditionalChinese: "目標 \($0)%"
            )
        }
        let power = charge.chargerPowerKW.map { "\($0) kW" }
        let energy = charge.energyAddedKWh.map { String(format: "%.1f kWh", $0) }
        let remaining = charge.timeToFullMinutes.map {
            let duration = localizedDuration($0, language: language)
            return language.value(
                english: "\(duration) remaining",
                chinese: "剩余 \(duration)",
                traditionalChinese: "剩餘 \(duration)"
            )
        }
        let age = max(0, Int(now.timeIntervalSince(charge.updatedAt).rounded(.down)))
        let updated = language.value(
            english: "Updated \(localizedDuration(age / 60, language: language))",
            chinese: "更新于 \(localizedDuration(age / 60, language: language))",
            traditionalChinese: "更新於 \(localizedDuration(age / 60, language: language))"
        )
        let trust = charge.quality == .partial
            ? language.value(
                english: "Partial data",
                chinese: "部分数据待更新",
                traditionalChinese: "部分資料待更新"
            )
            : nil
        let accessibility = [carName, status, trust, battery, limit, power, energy, remaining, updated]
            .compactMap { $0 }
            .joined(separator: ", ")

        return Self(
            state: state,
            carName: carName,
            statusText: status,
            batteryText: battery,
            limitText: state == .idle ? nil : limit,
            powerText: state == .idle ? nil : power,
            energyText: state == .idle ? nil : energy,
            remainingText: state == .idle ? nil : remaining,
            updatedText: updated,
            trustText: trust,
            accessibilityText: accessibility
        )
    }
}
~~~

Implement localizedStatus(_:language:) as an exhaustive switch over all six states, and localizedDuration(_:language:) with these exact outputs: 65 minutes -> 1h 05m / 1小时05分钟 / 1小時05分鐘; 5 minutes -> 5m / 5分钟 / 5分鐘; 0 minutes -> 0m / 0分钟 / 0分鐘. The helper must use the supplied WidgetDisplayLanguage, not Locale, so the App-selected language remains authoritative.

- [ ] **Step 4: Implement the WidgetKit provider and views**

CurrentChargeWidget must use:

~~~swift
struct CurrentChargeWidget: Widget {
    let kind = WidgetConstants.currentChargeKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CarStatusConfigurationIntent.self,
            provider: CurrentChargeTimelineProvider()
        ) { entry in
            CurrentChargeWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("Current Charge"))
        .description(LocalizedStringResource("Shows current read-only charging status."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
~~~

The entry stores date, snapshot, and configured vehicle name. The provider reads only WidgetSnapshotStore. The view uses Environment widgetFamily:

- small: car name, status, large battery, then power or remaining time;
- medium: leading battery/progress, trailing power, energy, remaining time, and update state;
- idle: neutral plug icon and no historical power/energy;
- offline/stale: clock or wifi-slash status without hiding cached values;
- unavailable: recovery text.

Use only SF Symbols and the existing green/blue system palette. Add one combined accessibility element with presentation.accessibilityText.

- [ ] **Step 5: Register and share the presentation file**

Add CurrentChargeWidget() to MateDriveWidgetBundle. Add MateDriveWidget/WidgetCurrentChargePresentation.swift to the MateDriveApp source list in project.yml so MateDriveTests can import it, then run:

~~~bash
xcodegen generate
~~~

- [ ] **Step 6: Run tests and compile the extension**

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/WidgetCurrentChargePresentationTests test
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS Simulator' ASSETCATALOG_COMPILER_APPICON_NAME= build
~~~

Expected: presentation tests pass and both app and widget extension compile.

- [ ] **Step 7: Record the uncommitted checkpoint**

Run git diff --check and verify project generation changed only source membership required by project.yml.

---

### Task 5: Add allow-listed anonymous widget navigation

**Files:**
- Create: MateDriveWidget/WidgetNavigation.swift
- Create: MateDriveApp/App/WidgetNavigationRouter.swift
- Modify: MateDriveWidget/CurrentChargeWidget.swift
- Modify: MateDriveWidget/CarStatusWidget.swift
- Modify: MateDriveWidget/TrendWidgets.swift
- Modify: MateDriveApp/Core/Sync/AppDataPreloader.swift
- Modify: MateDriveApp/App/RootView.swift
- Modify: project.yml
- Modify: MateDrive.xcodeproj/project.pbxproj
- Create: MateDriveTests/App/WidgetNavigationRouterTests.swift
- Modify: MateDriveTests/Sync/BackgroundRefreshWorkRunnerTests.swift

**Interfaces:**
- Produces: MateDriveWidgetDestination, MateDriveWidgetRequest, MateDriveWidgetNavigation.url and parse.
- Produces: WidgetNavigationVehicleRegistry.replace and resolve.
- Produces: WidgetNavigationRouter.route(request:settings:resolvedCarID:fallbackCarID:) -> AppRoute.

- [ ] **Step 1: Write failing URL, registry, and route tests**

Cover exact allow-list and privacy behavior:

~~~swift
func testWidgetURLRoundTripContainsOnlyOpaqueVehicleIdentity() throws {
    let id = String(repeating: "a", count: 64)
    let url = try XCTUnwrap(MateDriveWidgetNavigation.url(
        destination: .currentCharge,
        vehicleIdentifier: id
    ))

    XCTAssertEqual(
        url.absoluteString,
        "matedrive://widget/current-charge?vehicle=\(id)"
    )
    XCTAssertEqual(
        MateDriveWidgetNavigation.parse(url),
        MateDriveWidgetRequest(destination: .currentCharge, vehicleIdentifier: id)
    )
}

func testParserRejectsUnknownRouteRawVehicleIDAndExtraQuery() {
    XCTAssertNil(MateDriveWidgetNavigation.parse(
        URL(string: "matedrive://widget/delete?vehicle=1")!
    ))
    XCTAssertNil(MateDriveWidgetNavigation.parse(
        URL(string: "matedrive://widget/current-charge?vehicle=7")!
    ))
    XCTAssertNil(MateDriveWidgetNavigation.parse(
        URL(string: "matedrive://widget/current-charge?vehicle=\(String(repeating: "a", count: 64))&token=secret")!
    ))
}

func testRegistryResolvesOpaqueVehicleWithoutPersistingServerURL() throws {
    let suiteName = "WidgetNavigationRegistry.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = WidgetNavigationVehicleRegistry(defaults: defaults)
    registry.replace(serverURL: "https://teslamate.example", carIDs: [7, 8])
    let id = try XCTUnwrap(WidgetVehicleIdentity.identifier(
        serverURL: "https://teslamate.example",
        carID: 8
    ))

    XCTAssertEqual(
        registry.resolve(serverURL: "https://teslamate.example", vehicleIdentifier: id),
        8
    )
    XCTAssertFalse(defaults.dictionaryRepresentation().description.contains("teslamate.example"))
}

func testBatteryWidgetRouteUsesResolvedVehicle() {
    let request = MateDriveWidgetRequest(
        destination: .battery,
        vehicleIdentifier: String(repeating: "b", count: 64)
    )

    XCTAssertEqual(
        WidgetNavigationRouter.route(
            request: request,
            settings: AppSettings(serverURL: "https://teslamate.example"),
            resolvedCarID: 8,
            fallbackCarID: 7
        ),
        .battery(carId: 8, efficiency: nil, exteriorColor: nil)
    )
}

func testWidgetRouteFallbackOrderAndUnconfiguredRecovery() {
    let request = MateDriveWidgetRequest(
        destination: .currentCharge,
        vehicleIdentifier: String(repeating: "c", count: 64)
    )

    XCTAssertEqual(
        WidgetNavigationRouter.route(
            request: request,
            settings: AppSettings(),
            resolvedCarID: 8,
            fallbackCarID: 7
        ),
        .settings
    )
    XCTAssertEqual(
        WidgetNavigationRouter.route(
            request: request,
            settings: AppSettings(
                serverURL: "https://teslamate.example",
                lastSelectedCarId: 6
            ),
            resolvedCarID: nil,
            fallbackCarID: 7
        ),
        .currentCharge(carId: 6, exteriorColor: nil)
    )
    XCTAssertEqual(
        WidgetNavigationRouter.route(
            request: request,
            settings: AppSettings(serverURL: "https://teslamate.example"),
            resolvedCarID: nil,
            fallbackCarID: 7
        ),
        .currentCharge(carId: 7, exteriorColor: nil)
    )
    XCTAssertEqual(
        WidgetNavigationRouter.route(
            request: request,
            settings: AppSettings(serverURL: "https://teslamate.example"),
            resolvedCarID: nil,
            fallbackCarID: nil
        ),
        .dashboard
    )
}

func testRegistryDoesNotResolveAnIdentifierForAnotherServer() throws {
    let suiteName = "WidgetNavigationServerIsolation.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registry = WidgetNavigationVehicleRegistry(defaults: defaults)
    registry.replace(serverURL: "https://first.example", carIDs: [7])
    let firstID = try XCTUnwrap(WidgetVehicleIdentity.identifier(
        serverURL: "https://first.example",
        carID: 7
    ))

    XCTAssertNil(registry.resolve(
        serverURL: "https://second.example",
        vehicleIdentifier: firstID
    ))
}
~~~

- [ ] **Step 2: Run the router tests and verify RED**

Expected: the navigation types are undefined.

- [ ] **Step 3: Implement the shared URL contract**

In WidgetNavigation.swift define:

~~~swift
public enum MateDriveWidgetDestination: String, Codable, Equatable, Sendable {
    case dashboard
    case currentCharge = "current-charge"
    case battery
    case charges
}

public struct MateDriveWidgetRequest: Codable, Equatable, Sendable {
    public let destination: MateDriveWidgetDestination
    public let vehicleIdentifier: String?
}

public enum MateDriveWidgetNavigation {
    public static func url(
        destination: MateDriveWidgetDestination,
        vehicleIdentifier: String?
    ) -> URL?

    public static func parse(_ url: URL) -> MateDriveWidgetRequest?
}
~~~

The parser accepts only scheme matedrive, host widget, one allow-listed path, zero or one query named vehicle, and a 64-character lowercase hexadecimal identifier. Reject fragments, user information, ports, duplicate query names, and every additional parameter.

- [ ] **Step 4: Implement the app-private registry and route resolver**

WidgetNavigationVehicleRegistry stores only a server identity hash and integer car IDs in UserDefaults.standard. It never stores the server URL in a new key. It recomputes WidgetVehicleIdentity for resolution.

WidgetNavigationRouter maps:

- dashboard -> .dashboard;
- currentCharge -> .currentCharge(carId: selectedCarID, exteriorColor: nil);
- battery -> .battery(carId: selectedCarID, efficiency: nil, exteriorColor: nil);
- charges -> .charges(carId: selectedCarID, exteriorColor: nil);
- unconfigured settings -> .settings.

Use resolvedCarID, then settings.lastSelectedCarId, then fallbackCarID. If none exists, return .dashboard.

- [ ] **Step 5: Persist known car IDs and wire RootView**

After AppDataPreloader successfully loads cars, call:

~~~swift
widgetNavigationVehicleRegistry.replace(
    serverURL: settings.serverURL,
    carIDs: orderedCars.map(\.carId)
)
~~~

Add an injected registry with a shared default and tests proving multi-server isolation.

In RootView add onOpenURL and:

~~~swift
private func openWidgetURL(_ url: URL) async {
    guard let request = MateDriveWidgetNavigation.parse(url) else { return }
    let settings = await environment.settingsStore.load()
    let resolved = request.vehicleIdentifier.flatMap {
        widgetNavigationVehicleRegistry.resolve(
            serverURL: settings.serverURL,
            vehicleIdentifier: $0
        )
    }
    let route = WidgetNavigationRouter.route(
        request: request,
        settings: settings,
        resolvedCarID: resolved,
        fallbackCarID: dashboardViewModel.state.selectedCarId
    )
    navigation.openShortcut(route)
}
~~~

- [ ] **Step 6: Add URLs to all four widgets**

- CarStatusEntry gains vehicleIdentifier and links to dashboard.
- BatteryTrendWidget links to battery.
- ChargingTrendWidget links to charges.
- CurrentChargeWidget links to currentCharge.

When no valid opaque ID exists, omit widgetURL rather than constructing an unsafe fallback URL.

- [ ] **Step 7: Declare the URL scheme and regenerate**

Add CFBundleURLTypes under the app Info properties in project.yml:

~~~yaml
CFBundleURLTypes:
  - CFBundleURLName: com.matedrive.ios
    CFBundleURLSchemes:
      - matedrive
~~~

Add MateDriveWidget/WidgetNavigation.swift to the app target source list and run xcodegen generate.

- [ ] **Step 8: Run focused tests and a simulator route smoke test**

Run router and preloader tests, build, install on the audit simulator, then:

~~~bash
xcrun simctl openurl F4218592-FDB8-4E44-A23B-A910868B59D1 'matedrive://widget/current-charge?vehicle=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
~~~

Expected: the app opens safely; an unmatched identity uses the documented fallback without exposing an error or changing server configuration.

- [ ] **Step 9: Record the uncommitted checkpoint**

Run git diff --check and inspect generated project changes.

---

### Task 6: Centralize and localize Live Activity behavior

**Files:**
- Modify: MateDriveApp/Features/Charges/ChargeLiveActivityManager.swift
- Create: MateDriveApp/Features/Charges/ChargeLiveActivityCoordinator.swift
- Modify: MateDriveWidget/ChargeLiveActivityAttributes.swift
- Create: MateDriveWidget/ChargeLiveActivityPresentation.swift
- Modify: MateDriveWidget/ChargeLiveActivityWidget.swift
- Modify: project.yml
- Modify: MateDrive.xcodeproj/project.pbxproj
- Create: MateDriveTests/Features/ChargeLiveActivityCoordinatorTests.swift
- Create: MateDriveTests/Features/ChargeLiveActivityPresentationTests.swift
- Modify: MateDriveTests/Features/CurrentChargeViewModelTests.swift

**Interfaces:**
- Extends: ChargeLiveActivityManaging with updateExisting(carId:snapshot:) async.
- Produces: ChargeLiveActivityActivationPolicy and ChargeLiveActivityEvent.
- Produces: ChargeLiveActivityCoordinator.reconcile(carId:event:policy:) async.
- Produces: ChargeLiveActivityPresentation.make(attributes:state:isStale:).
- Produces: ChargeLiveActivitySnapshot.staleDate fixed at updatedAt + 120 seconds.

- [ ] **Step 1: Write failing lifecycle tests**

~~~swift
func testAllowStartUsesStartOrUpdate() async {
    let manager = RecordingLiveActivityManager()
    let coordinator = ChargeLiveActivityCoordinator(manager: manager)

    await coordinator.reconcile(
        carId: 7,
        event: .charging(.fixture()),
        policy: .allowStart
    )

    let calls = await manager.recordedCalls()
    XCTAssertEqual(calls, [.startOrUpdate(carId: 7)])
}

func testExistingOnlyNeverStartsANewActivity() async {
    let manager = RecordingLiveActivityManager()
    let coordinator = ChargeLiveActivityCoordinator(manager: manager)

    await coordinator.reconcile(
        carId: 7,
        event: .charging(.fixture()),
        policy: .existingOnly
    )

    let calls = await manager.recordedCalls()
    XCTAssertEqual(calls, [.updateExisting(carId: 7)])
}

func testIdleEndsForBothPolicies() async {
    let manager = RecordingLiveActivityManager()
    let coordinator = ChargeLiveActivityCoordinator(manager: manager)

    await coordinator.reconcile(carId: 7, event: .idle, policy: .allowStart)
    await coordinator.reconcile(carId: 7, event: .idle, policy: .existingOnly)

    let calls = await manager.recordedCalls()
    XCTAssertEqual(calls, [.end(carId: 7), .end(carId: 7)])
}

func testIndeterminateDoesNothing() async {
    let manager = RecordingLiveActivityManager()
    let coordinator = ChargeLiveActivityCoordinator(manager: manager)

    await coordinator.reconcile(
        carId: 7,
        event: .indeterminate,
        policy: .allowStart
    )
    await coordinator.reconcile(
        carId: 7,
        event: .indeterminate,
        policy: .existingOnly
    )

    let calls = await manager.recordedCalls()
    XCTAssertEqual(calls, [])
}
~~~

Use this exact actor recorder:

~~~swift
private actor RecordingLiveActivityManager: ChargeLiveActivityManaging {
    enum Call: Equatable, Sendable {
        case startOrUpdate(carId: Int)
        case updateExisting(carId: Int)
        case end(carId: Int)
    }

    private var calls: [Call] = []

    func update(carId: Int, snapshot _: ChargeLiveActivitySnapshot) async {
        calls.append(.startOrUpdate(carId: carId))
    }

    func updateExisting(carId: Int, snapshot _: ChargeLiveActivitySnapshot) async {
        calls.append(.updateExisting(carId: carId))
    }

    func end(carId: Int) async {
        calls.append(.end(carId: carId))
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
~~~

- [ ] **Step 2: Write failing localized presentation and compatibility tests**

~~~swift
func testChargeLabelsMetricsAndDurationInAllLanguages() {
    let cases: [(
        WidgetDisplayLanguage,
        ac: String,
        dc: String,
        battery: String,
        limit: String,
        remaining: String
    )] = [
        (.english, "AC charging", "DC charging", "Battery", "Limit 80%", "1h 05m remaining"),
        (.chinese, "交流充电", "直流充电", "电量", "目标 80%", "剩余 1小时05分钟"),
        (.traditionalChinese, "交流充電", "直流充電", "電量", "目標 80%", "剩餘 1小時05分鐘")
    ]

    for item in cases {
        let ac = makePresentation(language: item.0, isDC: false)
        let dc = makePresentation(language: item.0, isDC: true)
        XCTAssertEqual(ac.statusText, item.ac)
        XCTAssertEqual(dc.statusText, item.dc)
        XCTAssertEqual(ac.batteryLabelText, item.battery)
        XCTAssertEqual(ac.limitText, item.limit)
        XCTAssertEqual(ac.remainingText, item.remaining)
    }
}

func testTrustPrecedenceIsOfflineThenStaleThenPartialThenChargeType() {
    XCTAssertEqual(
        makePresentation(quality: .offline, isStale: true).statusText,
        "Offline"
    )
    XCTAssertEqual(
        makePresentation(quality: .complete, isStale: true).statusText,
        "Update pending"
    )
    XCTAssertEqual(
        makePresentation(quality: .partial, isStale: false).statusText,
        "Partial data"
    )
    XCTAssertEqual(
        makePresentation(quality: .complete, isStale: false).statusText,
        "AC charging"
    )
}

func testAccessibilityContainsEveryVisibleMetricAndTrustState() {
    let value = makePresentation(quality: .partial)

    for expected in [
        "Model 3", "Partial data", "Battery", "64%", "Limit 80%",
        "72 kW", "18.4 kWh", "1h 05m remaining"
    ] {
        XCTAssertTrue(value.accessibilityText.contains(expected), "Missing \(expected)")
    }
}

func testLegacyActivityPayloadDecodesWithSafeDefaults() throws {
    let attributes = try JSONDecoder().decode(
        ChargeLiveActivityAttributes.self,
        from: Data(#"{"carID":7,"carName":"Model 3"}"#.utf8)
    )
    let state = try JSONDecoder().decode(
        ChargeLiveActivityAttributes.ContentState.self,
        from: Data(#"{"isDC":false,"isCharging":true,"updatedAt":0}"#.utf8)
    )

    XCTAssertNil(attributes.vehicleIdentifier)
    XCTAssertEqual(state.displayLanguage, .system)
    XCTAssertEqual(state.quality, .complete)
}

func testNewActivityPayloadRoundTripsVehicleLanguageAndQuality() throws {
    let identifier = String(repeating: "a", count: 64)
    let attributes = ChargeLiveActivityAttributes(
        carID: 7,
        carName: "Model 3",
        vehicleIdentifier: identifier
    )
    let state = ChargeLiveActivityAttributes.ContentState(
        isDC: true,
        isCharging: true,
        displayLanguage: .traditionalChinese,
        quality: .partial,
        updatedAt: Date(timeIntervalSince1970: 1_786_320_000)
    )

    XCTAssertEqual(
        try JSONDecoder().decode(
            ChargeLiveActivityAttributes.self,
            from: JSONEncoder().encode(attributes)
        ).vehicleIdentifier,
        identifier
    )
    let decodedState = try JSONDecoder().decode(
        ChargeLiveActivityAttributes.ContentState.self,
        from: JSONEncoder().encode(state)
    )
    XCTAssertEqual(decodedState.displayLanguage, .traditionalChinese)
    XCTAssertEqual(decodedState.quality, .partial)
}

func testLiveActivityStaleDateIsExactlyTwoMinutesAfterUpdate() {
    let updatedAt = Date(timeIntervalSince1970: 1_786_320_000)
    XCTAssertEqual(
        ChargeLiveActivitySnapshot.fixture(updatedAt: updatedAt).staleDate,
        updatedAt.addingTimeInterval(120)
    )
}

private func makePresentation(
    language: WidgetDisplayLanguage = .english,
    isDC: Bool = false,
    quality: WidgetChargeDataQuality = .complete,
    isStale: Bool = false
) -> ChargeLiveActivityPresentation {
    ChargeLiveActivityPresentation.make(
        attributes: ChargeLiveActivityAttributes(
            carID: 7,
            carName: "Model 3",
            vehicleIdentifier: String(repeating: "a", count: 64)
        ),
        state: ChargeLiveActivityAttributes.ContentState(
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: isDC,
            isCharging: true,
            displayLanguage: language,
            quality: quality,
            updatedAt: Date(timeIntervalSince1970: 1_786_320_000)
        ),
        isStale: isStale
    )
}
~~~

The presentation value has these concrete fields: carName, statusText, batteryLabelText, batteryText, limitText, powerText, energyText, remainingText, updatedText, isStale, and accessibilityText. Missing metrics are nil except batteryText, which is "--".

- [ ] **Step 3: Run both test classes and verify RED**

Expected: coordinator, updateExisting, and presentation types are undefined.

- [ ] **Step 4: Split manager behavior without breaking the existing update call**

Keep update(carId:snapshot:) as start-or-update for compatibility and add:

~~~swift
public protocol ChargeLiveActivityManaging: Sendable {
    func update(carId: Int, snapshot: ChargeLiveActivitySnapshot) async
    func updateExisting(carId: Int, snapshot: ChargeLiveActivitySnapshot) async
    func end(carId: Int) async
}
~~~

SystemChargeLiveActivityManager.updateExisting must return without requesting an Activity when no matching car activity exists. DisabledChargeLiveActivityManager implements all methods as no-ops.

Extend ChargeLiveActivitySnapshot with vehicleIdentifier: String? = nil, displayLanguage: WidgetDisplayLanguage = .system, and quality: WidgetChargeDataQuality = .complete. Add staleDate returning updatedAt.addingTimeInterval(120), and use that value when constructing ActivityContent. These defaults keep existing call sites compiling until Task 7.

- [ ] **Step 5: Implement the coordinator**

~~~swift
public enum ChargeLiveActivityActivationPolicy: Equatable, Sendable {
    case allowStart
    case existingOnly
}

public enum ChargeLiveActivityEvent: Equatable, Sendable {
    case charging(ChargeLiveActivitySnapshot)
    case idle
    case indeterminate
}

public struct ChargeLiveActivityCoordinator: Sendable {
    private let manager: any ChargeLiveActivityManaging

    public static let disabled = ChargeLiveActivityCoordinator(
        manager: DisabledChargeLiveActivityManager()
    )

    public init(manager: any ChargeLiveActivityManaging) {
        self.manager = manager
    }

    public func reconcile(
        carId: Int,
        event: ChargeLiveActivityEvent,
        policy: ChargeLiveActivityActivationPolicy
    ) async {
        switch (event, policy) {
        case let (.charging(snapshot), .allowStart):
            await manager.update(carId: carId, snapshot: snapshot)
        case let (.charging(snapshot), .existingOnly):
            await manager.updateExisting(carId: carId, snapshot: snapshot)
        case (.idle, _):
            await manager.end(carId: carId)
        case (.indeterminate, _):
            return
        }
    }
}
~~~

- [ ] **Step 6: Extend attributes and localize every visible string**

ChargeLiveActivityAttributes gains vehicleIdentifier: String? and keeps the initializer order init(carID:carName:vehicleIdentifier:). ContentState gains displayLanguage and quality. Implement explicit init(from:) methods using decodeIfPresent so a legacy attributes payload defaults vehicleIdentifier to nil and a legacy content-state payload defaults displayLanguage to .system and quality to .complete. Preserve explicit encode(to:) coverage through a round-trip assertion; declaration-site defaults alone are not sufficient for synthesized Decodable compatibility.

ChargeLiveActivityPresentation must produce all visible strings. ChargeLiveActivityWidget must not contain hardcoded AC Charging, DC Charging, Battery, Limit, h, or m. Pass context.isStale to the presentation, dim stale metrics, and set the same allow-listed Current Charge widget URL on Lock Screen and Dynamic Island.

- [ ] **Step 7: Share the presentation file and regenerate**

Add MateDriveWidget/ChargeLiveActivityPresentation.swift to the app target sources in project.yml and run xcodegen generate.

- [ ] **Step 8: Run focused tests and compile**

Run coordinator, presentation, and existing CurrentChargeViewModel tests, then build both targets. Expected: zero failures and no protocol-conformance break.

- [ ] **Step 9: Record the uncommitted checkpoint**

Run git diff --check and search the Live Activity sources for the removed hardcoded English labels.

---

### Task 7: Wire foreground start, background update-existing, and snapshot publishing

**Files:**
- Modify: MateDriveApp/Features/Dashboard/DashboardViewModel.swift
- Modify: MateDriveApp/Features/Charges/CurrentChargeViewModel.swift
- Modify: MateDriveApp/Core/Sync/AppDataPreloader.swift
- Modify: MateDriveApp/App/RootView.swift
- Modify: MateDriveApp/App/MateDriveApp.swift
- Modify: MateDriveTests/Features/DashboardViewModelTests.swift
- Modify: MateDriveTests/Features/CurrentChargeViewModelTests.swift
- Modify: MateDriveTests/Sync/BackgroundRefreshWorkRunnerTests.swift

**Interfaces:**
- Consumes: WidgetCurrentChargeSnapshotBuilder, WidgetSnapshotStore.updateCurrentCharge, ChargeLiveActivityCoordinator.
- Produces: one consistent event flow from all foreground/background charge observations.

- [ ] **Step 1: Write failing integration-level unit tests**

Use the actor recorder from Task 6 and add these named cases with the exact terminal assertions below:

| Test method | Required terminal assertions |
| --- | --- |
| testDashboardChargingPublishesPartialSnapshotAndAllowsStart | selected vehicle snapshot is phase .charging, quality .partial, battery 67; calls equal [.startOrUpdate(carId: 7)]; reloaded kinds equal [CarStatusWidget, CurrentChargeWidget] |
| testDashboardStatusFailureMarksPriorSnapshotOfflineWithoutEnding | battery, energy, and updatedAt equal the seeded prior value; quality is .offline; calls equal []; reloaded kinds equal [CurrentChargeWidget] |
| testCurrentChargeDetailUpgradesPartialSnapshotToComplete | phase is .charging, quality .complete, energy 18.4; calls equal [.startOrUpdate(carId: 7)]; reloaded kinds equal [CurrentChargeWidget] |
| testCurrentChargeDetailFailurePublishesPartialWithoutEnding | status remains authoritative; phase is .charging and quality .partial; calls equal [.startOrUpdate(carId: 7)]; no .end call appears |
| testCurrentChargeStatusFailurePreservesActivityAndNeverEnds | seeded snapshot becomes .offline with its original battery, energy, and updatedAt; calls equal []; no .end call appears |
| testAuthoritativeIdleClearsMetricsAndEndsActivity | phase .idle and quality .complete; current battery remains 55 while chargerPowerKW, energyAddedKWh, and timeToFullMinutes are nil; calls equal [.end(carId: 7)] |
| testBackgroundChargingUpdatesExistingActivityOnly | calls equal [.updateExisting(carId: 7)]; no .startOrUpdate call appears |
| testTwoVehiclesRemainIsolated | calls equal [.startOrUpdate(carId: 7), .startOrUpdate(carId: 8)]; the two opaque snapshot IDs differ; each stored battery value matches only its source vehicle |

Before each assertion, read actor state into a local constant; do not place await inside an XCTest autoclosure. Give every test its own UserDefaults suite and clear it with defer.

- [ ] **Step 2: Run the three focused suites and verify RED**

Run DashboardViewModelTests, CurrentChargeViewModelTests, and BackgroundRefreshWorkRunnerTests. Expected: new initializer dependencies and event assertions fail.

- [ ] **Step 3: Add a shared event factory**

In ChargeLiveActivityCoordinator.swift add:

~~~swift
public enum ChargeLiveActivityEventFactory {
    public static func event(
        currentCharge: WidgetCurrentChargeData?,
        carName: String,
        vehicleIdentifier: String,
        displayLanguage: WidgetDisplayLanguage
    ) -> ChargeLiveActivityEvent {
        guard let currentCharge else { return .indeterminate }
        guard currentCharge.quality != .offline else { return .indeterminate }
        guard currentCharge.phase != .idle else { return .idle }
        return .charging(ChargeLiveActivitySnapshot(
            carName: carName,
            vehicleIdentifier: vehicleIdentifier,
            batteryLevel: currentCharge.batteryLevel,
            chargeLimitSoc: currentCharge.chargeLimitSoc,
            chargerPowerKW: currentCharge.chargerPowerKW,
            energyAddedKWh: currentCharge.energyAddedKWh,
            timeToFullMinutes: currentCharge.timeToFullMinutes,
            isDC: currentCharge.isDC == true,
            isCharging: true,
            displayLanguage: displayLanguage,
            quality: currentCharge.quality,
            updatedAt: currentCharge.updatedAt
        ))
    }
}
~~~

- [ ] **Step 4: Publish from Dashboard only in the foreground-owned instance**

DashboardViewModel gains widgetTimelineReloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(), liveActivityCoordinator: ChargeLiveActivityCoordinator = .disabled, and liveActivityActivationPolicy: ChargeLiveActivityActivationPolicy = .existingOnly. The RootView-owned instance explicitly supplies the system coordinator and .allowStart; test and background-owned instances retain the non-starting defaults.

After each selected-car status result:

1. derive the opaque ID from the loaded settings and selected car ID;
2. read the previous currentCharge before mutating the store;
3. call WidgetCurrentChargeSnapshotBuilder with currentChargeResult nil, including on status failure;
4. on success, save Dashboard data first so existing trends and currentCharge remain intact;
5. update currentCharge only when the builder returned a value;
6. reload CarStatusWidget only when Dashboard data changed and CurrentChargeWidget only when updateCurrentCharge returned true;
7. reconcile the event with the injected policy; an offline result maps to indeterminate and therefore cannot end an activity.

The DashboardViewModel created inside BackgroundRefreshWorkRunner keeps disabled defaults so it cannot start a Live Activity.

- [ ] **Step 5: Publish complete results from CurrentChargeViewModel**

Add these initializer dependencies with safe defaults: widgetSnapshotStore: WidgetSnapshotStore = .shared, widgetTimelineReloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(), liveActivityCoordinator: ChargeLiveActivityCoordinator = .disabled, vehicleIdentifier: String? = nil, displayLanguage: WidgetDisplayLanguage = .system, and now: @Sendable () -> Date = Date.init. Remove the direct liveActivityManager dependency after its existing tests have moved to the coordinator recorder. RootView passes the opaque ID derived from the current server and car, the App-selected language, and the shared system coordinator.

Replace direct manager decisions with:

~~~swift
let previous = vehicleIdentifier.flatMap {
    widgetSnapshotStore.vehicleSnapshot(vehicleIdentifier: $0)?.currentCharge
}
let currentCharge = WidgetCurrentChargeSnapshotBuilder.build(
    statusResult: statusResult,
    currentChargeResult: currentChargeResult,
    previous: previous,
    now: now()
)
if let vehicleIdentifier, let currentCharge {
    let didChange = widgetSnapshotStore.updateCurrentCharge(
        currentCharge,
        vehicleIdentifier: vehicleIdentifier
    )
    if didChange {
        await widgetTimelineReloader.reloadTimelines(
            ofKind: WidgetConstants.currentChargeKind
        )
    }
    await liveActivityCoordinator.reconcile(
        carId: carId,
        event: ChargeLiveActivityEventFactory.event(
            currentCharge: currentCharge,
            carName: statusPayload?.status?.displayName ?? "MateDrive",
            vehicleIdentifier: vehicleIdentifier,
            displayLanguage: displayLanguage
        ),
        policy: .allowStart
    )
}
~~~

If statusResult fails and no previous snapshot exists, emit indeterminate and do not write a fake value.

- [ ] **Step 6: Reconcile from background preload with existingOnly**

Inject ChargeLiveActivityCoordinator into AppDataPreloader with a disabled default. After each per-car current-charge value is built, reconcile with existingOnly. MateDriveApp injects the system coordinator; RootView injects the same system coordinator into its Dashboard and Current Charge models.

- [ ] **Step 7: Run focused suites and verify GREEN**

Expected:

- foreground charging starts or updates;
- background charging only updates an existing activity;
- idle ends;
- failure never ends;
- snapshots and calls remain isolated by vehicle.

- [ ] **Step 8: Run the complete non-UI suite**

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests test
~~~

Expected: zero failures; only existing intentional external-environment skips.

- [ ] **Step 9: Record the uncommitted checkpoint**

Run git diff --check and inspect all three integration call sites for duplicate ActivityKit decisions.

---

### Task 8: Finish localization, accessibility, privacy guards, and visual fixtures

**Files:**
- Modify: MateDriveApp/Resources/Localizable.xcstrings
- Modify: MateDriveApp/Resources/CompiledLocalizations/en.lproj/Localizable.strings
- Modify: MateDriveApp/Resources/CompiledLocalizations/zh-Hans.lproj/Localizable.strings
- Modify: MateDriveApp/Resources/CompiledLocalizations/zh-Hant.lproj/Localizable.strings
- Modify: MateDriveWidget/CurrentChargeWidget.swift
- Modify: MateDriveWidget/ChargeLiveActivityWidget.swift
- Create: scripts/audit_native_entry_boundaries.py
- Create: scripts/test_audit_native_entry_boundaries.py
- Modify: Makefile
- Modify: docs/parity/manual-test-checklist.md

**Interfaces:**
- Consumes: presentation models from Tasks 4 and 6.
- Produces: complete three-language resources and release-protected read-only behavior.

- [ ] **Step 1: Write failing audit behavior tests**

Create script behavior tests using unittest, subprocess.run, and tempfile.TemporaryDirectory. Each test writes a minimal synthetic MateDriveWidget tree, executes audit_native_entry_boundaries.py --root <temp>, and asserts:

1. a safe CurrentChargeWidget, WidgetNavigation, ChargeLiveActivityWidget, and MateDriveWidgetBundle exits 0;
2. adding URLSession.shared to CurrentChargeWidget exits 1 and reports CurrentChargeWidget.swift;
3. adding Button(intent:) exits 1 and reports a read-only boundary violation;
4. adding DC Charging to ChargeLiveActivityWidget exits 1 and reports a hardcoded localization violation;
5. adding a token query name to WidgetNavigation exits 1 and reports a sensitive navigation parameter.

The tests exercise the audit executable against controlled inputs; do not add XCTest methods that merely load production source and search for strings. WidgetCurrentChargePresentationTests, ChargeLiveActivityPresentationTests, WidgetNavigationRouterTests, and the Task 1 serialization-boundary test remain the real product-behavior evidence.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

~~~bash
python3 scripts/test_audit_native_entry_boundaries.py
~~~

Expected: the script test fails because audit_native_entry_boundaries.py does not exist.

- [ ] **Step 3: Implement the independent native-entry audit**

The audit accepts --root, resolves only these four files below that root, and emits one line per finding plus a final finding count:

- MateDriveWidget/CurrentChargeWidget.swift: forbid URLSession, TeslamateAPI, Keychain, Button(intent:, and vehicle-control terms unlock, lockVehicle, climate, honk, vent, or trunk;
- MateDriveWidget/ChargeLiveActivityWidget.swift: forbid the visible English literals DC Charging, AC Charging, Battery, Limit --, %dh, and %02dm;
- MateDriveWidget/WidgetNavigation.swift: forbid case-insensitive sensitive parameter identifiers token, password, serverURL, basicAuth, authorization, vin, latitude, longitude, address, and location;
- MateDriveWidget/MateDriveWidgetBundle.swift: require CurrentChargeWidget().

Missing required files are findings. Exit 0 only when the finding count is zero, otherwise exit 1. Add python3 scripts/test_audit_native_entry_boundaries.py to Makefile's test-scripts target.

- [ ] **Step 4: Add or reuse exact localization keys**

Reuse existing Battery, Charging, and Current Charge keys. Add these exact values where missing:

| English key | Simplified Chinese | Traditional Chinese |
| --- | --- | --- |
| Shows current read-only charging status. | 显示当前只读充电状态。 | 顯示目前唯讀充電狀態。 |
| Preparing to charge | 正在准备充电 | 正在準備充電 |
| Not charging | 当前未充电 | 目前未充電 |
| Offline | 离线 | 離線 |
| Update pending | 等待更新 | 等待更新 |
| Data may be out of date | 数据可能已过期 | 資料可能已過期 |
| Partial data | 部分数据待更新 | 部分資料待更新 |
| Open MateDrive to sync | 打开 MateDrive 同步 | 開啟 MateDrive 同步 |
| AC charging | 交流充电 | 交流充電 |
| DC charging | 直流充电 | 直流充電 |
| Limit %@ | 目标 %@ | 目標 %@ |
| Updated %@ | 更新于 %@ | 更新於 %@ |
| %@ remaining | 剩余 %@ | 剩餘 %@ |

Generate compiled resources:

~~~bash
python3 scripts/generate_strings_resources.py
~~~

- [ ] **Step 5: Complete accessibility semantics**

- One combined accessibility element per small widget.
- A logical ordered group for the medium widget.
- Decorative battery rings, bars, and bolt icons hidden.
- Status plus trust state spoken before secondary metrics.
- Missing metrics omitted from the accessibility sentence.
- Long car names limited without shrinking battery/status below legibility.
- No tap target smaller than the entire widget or Live Activity surface.

- [ ] **Step 6: Add deterministic preview fixtures**

Add Preview entries for:

- small charging;
- medium charging;
- starting;
- idle;
- offline;
- stale;
- unavailable;
- long Traditional Chinese vehicle name.

Use fixed dates and synthetic vehicle names only. Do not add a new runtime debug route.

- [ ] **Step 7: Update the manual test checklist**

Add exact checks for:

- configuring two Current Charge widgets for different vehicles;
- six display states;
- all three languages;
- small/medium, light/dark, high contrast, and accessibility text;
- minimum/compact/expanded/Lock Screen Live Activity;
- widget and Live Activity deep links;
- foreground start, background existing-only update, offline preservation, recovery, and authoritative end.

- [ ] **Step 8: Run focused and static gates**

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests/AppStoreReadinessTests -only-testing:MateDriveTests/WidgetCurrentChargePresentationTests -only-testing:MateDriveTests/ChargeLiveActivityPresentationTests test
python3 scripts/audit_localization.py
python3 scripts/audit_native_entry_boundaries.py --root .
python3 scripts/audit_vehicle_fixture_privacy.py --root .
python3 scripts/audit_app_store_submission.py --technical-only
git diff --check
~~~

Expected: all focused tests pass, localization reports zero gaps/hardcoded SwiftUI English, privacy reports zero findings, and technical blockers are zero.

- [ ] **Step 9: Capture and inspect visual evidence**

Use Xcode Widget previews and the iPhone 17 iOS 26.5 audit simulator. Save accepted screenshots under:

build/design-audit/2026-08-10-native-entry/

Inspect every accepted screenshot at original resolution. Reject clipping, overlap, ambiguous stale/offline states, illegible text, or a wrong deep-link destination. Do not use screenshots alone to claim full accessibility compliance.

- [ ] **Step 10: Record the uncommitted checkpoint**

Run git diff --check and verify no sensitive fixture values entered source or screenshots.

---

### Task 9: Run full regression and prepare an unuploaded Build 20 candidate

**Files:**
- Modify: project.yml
- Modify: MateDrive.xcodeproj/project.pbxproj
- Modify: docs/release/app-store-submission.md
- Modify: docs/release/app-store-publishing-zh.md
- Modify: docs/release/continuous-product-readiness.md

**Interfaces:**
- Consumes: all prior tasks.
- Produces: full regression evidence, static gate evidence, a local Build 20 archive, and updated release records.

- [ ] **Step 1: Run focused feature regression one final time**

Create one unique evidence directory and keep the same terminal session for Steps 1–3:

~~~bash
MATEDRIVE_NATIVE_ENTRY_RESULTS="$(mktemp -d /tmp/matedrive-native-entry-results.XXXXXX)"
echo "$MATEDRIVE_NATIVE_ENTRY_RESULTS"
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:MateDriveTests/WidgetDisplayDataTests \
  -only-testing:MateDriveTests/WidgetCurrentChargeSnapshotBuilderTests \
  -only-testing:MateDriveTests/BackgroundRefreshWorkRunnerTests \
  -only-testing:MateDriveTests/WidgetCurrentChargePresentationTests \
  -only-testing:MateDriveTests/WidgetNavigationRouterTests \
  -only-testing:MateDriveTests/ChargeLiveActivityCoordinatorTests \
  -only-testing:MateDriveTests/ChargeLiveActivityPresentationTests \
  -only-testing:MateDriveTests/DashboardViewModelTests \
  -only-testing:MateDriveTests/CurrentChargeViewModelTests \
  -only-testing:MateDriveTests/AppStoreReadinessTests \
  -resultBundlePath "$MATEDRIVE_NATIVE_ENTRY_RESULTS/focused.xcresult" test
~~~

Expected: zero failures.

- [ ] **Step 2: Run the complete unit suite**

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveTests -resultBundlePath "$MATEDRIVE_NATIVE_ENTRY_RESULTS/full-unit.xcresult" test
~~~

Expected: zero failures; record exact pass and intentional-skip counts.

- [ ] **Step 3: Run the complete UI suite**

Run:

~~~bash
xcodebuild -project MateDrive.xcodeproj -scheme MateDrive -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MateDriveUITests -resultBundlePath "$MATEDRIVE_NATIVE_ENTRY_RESULTS/full-ui.xcresult" test
~~~

Expected: zero failures; transient simulator infrastructure exits do not count as product evidence and must be rerun to a completed bundle.

- [ ] **Step 4: Run every local release gate**

Run:

~~~bash
make test-scripts
python3 scripts/audit_localization.py
python3 scripts/audit_native_entry_boundaries.py --root .
python3 scripts/audit_independent_release.py --root .
python3 scripts/audit_regional_tariffs.py
python3 scripts/audit_vehicle_fixture_privacy.py --root .
python3 scripts/validate_app_store_screenshots.py
python3 scripts/audit_app_store_submission.py
git diff --check
~~~

Expected: zero blockers/findings and all script tests pass.

- [ ] **Step 5: Increment to Build 20 and regenerate**

Only after Steps 1–4 are green, change CURRENT_PROJECT_VERSION from 19 to 20 in project.yml and run xcodegen generate. Verify App and Widget both report 1.0 (20).

- [ ] **Step 6: Create and audit a unique local archive**

Run:

~~~bash
MATEDRIVE_NATIVE_ENTRY_ARCHIVE_ROOT="$(mktemp -d /tmp/matedrive-build20-native-entry.XXXXXX)"
xcodebuild archive -project MateDrive.xcodeproj -scheme MateDrive -destination 'generic/platform=iOS' -archivePath "$MATEDRIVE_NATIVE_ENTRY_ARCHIVE_ROOT/MateDrive.xcarchive" CODE_SIGNING_ALLOWED=NO
python3 scripts/audit_release_archive.py "$MATEDRIVE_NATIVE_ENTRY_ARCHIVE_ROOT/MateDrive.xcarchive"
echo "$MATEDRIVE_NATIVE_ENTRY_ARCHIVE_ROOT/MateDrive.xcarchive"
~~~

Expected: archive succeeds and release archive blockers are zero. Do not delete or overwrite the Build 19 archive.

- [ ] **Step 7: Update release records with exact evidence**

Record:

- exact unit/UI counts and result-bundle paths;
- focused result path;
- localization key count;
- all static gate results;
- archive path and audit result;
- accepted visual-audit screenshot paths;
- explicit statement that Build 20 has not been uploaded, installed through TestFlight, or submitted;
- remaining authorized-only physical iPhone checks.

- [ ] **Step 8: Final repository safety review**

Run:

~~~bash
git diff --check
git status --short
~~~

Review every changed/untracked file in this plan, preserve all unrelated user changes, and confirm no credentials, public server tokens, VINs, real locations, or private vehicle data are present.

- [ ] **Step 9: Record the final uncommitted checkpoint**

Do not stage, commit, push, upload, or install. Report the local Build 20 candidate, regression evidence, visual evidence, remaining physical-device gate, and one highest-priority next action.
