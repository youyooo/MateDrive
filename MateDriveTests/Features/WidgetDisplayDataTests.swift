import XCTest
@testable import MateDriveApp

final class WidgetDisplayDataTests: XCTestCase {
    func testOldWidgetPayloadDecodesWithCurrentDefaults() throws {
        let json = #"{"carName":"Model 3","isCharging":false,"sentryModeActive":false,"isReadOnly":true,"displayLanguage":"english"}"#

        let data = try JSONDecoder().decode(WidgetDisplayData.self, from: Data(json.utf8))

        XCTAssertEqual(data.displayLanguage, .english)
    }

    func testOldVehicleSnapshotDecodesWithoutTrendPayloads() throws {
        let json = #"{"id":"opaque","data":{"carName":"Model 3","isCharging":false,"sentryModeActive":false,"isReadOnly":true,"displayLanguage":"chinese"},"updatedAt":0}"#

        let snapshot = try JSONDecoder().decode(WidgetVehicleSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.batteryTrend)
        XCTAssertNil(snapshot.chargingTrend)
    }

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

    func testUpdateCurrentChargeMissingVehicleReturnsFalseWithoutChangingSnapshots() throws {
        let suiteName = "WidgetCurrentChargeMissing.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        store.replaceVehicleSnapshots([
            .fixture(id: "one", data: .fixture(carName: "One"), currentCharge: .fixture(phase: .idle)),
            .fixture(id: "two", data: .fixture(carName: "Two"), currentCharge: .fixture(phase: .charging))
        ], preferredIdentifier: "one")
        let before = store.vehicleSnapshots()

        let changed = store.updateCurrentCharge(
            .fixture(phase: .starting),
            vehicleIdentifier: "missing"
        )

        XCTAssertFalse(changed)
        XCTAssertEqual(store.vehicleSnapshots(), before)
    }

    func testUpdateCurrentChargeReturnsFalseForIdenticalCharge() throws {
        let suiteName = "WidgetCurrentChargeIdentical.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let charge = WidgetCurrentChargeData.fixture(
            phase: .charging,
            batteryLevel: 64,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        store.replaceVehicleSnapshots([
            .fixture(id: "opaque", currentCharge: charge)
        ], preferredIdentifier: "opaque")

        XCTAssertFalse(store.updateCurrentCharge(charge, vehicleIdentifier: "opaque"))
    }

    func testUpdateCurrentChargePreservesSelectedSnapshotMetadataAndOtherVehicle() throws {
        let suiteName = "WidgetCurrentChargeMetadata.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let selected = WidgetVehicleSnapshot.fixture(
            id: "opaque-selected",
            data: .fixture(carName: "Model 3", batteryLevel: 48),
            batteryTrend: WidgetBatteryTrendData(metric: .capacity, samples: [75, 72]),
            chargingTrend: WidgetChargingTrendData(
                sessionCount: 2,
                energyKWh: 18.4,
                energyKnownCount: 2,
                currencyCode: "CNY",
                energyBuckets: [0, 0, 0, 0, 8, 10.4]
            ),
            currentCharge: .fixture(phase: .idle, batteryLevel: 48),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let other = WidgetVehicleSnapshot.fixture(
            id: "opaque-other",
            data: .fixture(carName: "Model Y", batteryLevel: 82),
            currentCharge: .fixture(phase: .charging, batteryLevel: 82),
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let replacement = WidgetCurrentChargeData.fixture(
            phase: .charging,
            quality: .partial,
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: true,
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        store.replaceVehicleSnapshots([selected, other], preferredIdentifier: selected.id)

        XCTAssertTrue(store.updateCurrentCharge(replacement, vehicleIdentifier: selected.id))

        let updated = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: selected.id))
        XCTAssertEqual(updated.id, selected.id)
        XCTAssertEqual(updated.data, selected.data)
        XCTAssertEqual(updated.batteryTrend, selected.batteryTrend)
        XCTAssertEqual(updated.chargingTrend, selected.chargingTrend)
        XCTAssertEqual(updated.updatedAt, selected.updatedAt)
        XCTAssertEqual(updated.currentCharge, replacement)
        XCTAssertEqual(store.vehicleSnapshot(vehicleIdentifier: other.id), other)
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

    func testBatteryTrendDistinguishesAbsoluteHealthFromRecordedRetention() {
        let absolute = WidgetBatteryTrendData(
            healthPercent: 91.24,
            showsAbsoluteHealth: true,
            metric: .capacity,
            samples: [75, .nan, -1, 72],
            currentValue: 72,
            recordedDays: 180,
            qualityScore: 120,
            displayLanguage: .chinese
        )
        let recorded = WidgetBatteryTrendData(
            healthPercent: 94,
            showsAbsoluteHealth: false,
            metric: .range,
            samples: [500, 480],
            currentValue: 480,
            displayLanguage: .chinese,
            displayUnitSystem: .metric
        )

        XCTAssertEqual(absolute.headlineText, "91.2%")
        XCTAssertEqual(absolute.headlineLabel, "电池健康度")
        XCTAssertEqual(absolute.samples, [75, 72])
        XCTAssertEqual(absolute.qualityScore, 100)
        XCTAssertEqual(recorded.headlineLabel, "记录期保持率")
        XCTAssertEqual(recorded.currentValueText, "480 km")
    }

    func testChargingTrendKeepsMissingCostCoverageExplicit() {
        let trend = WidgetChargingTrendData(
            sessionCount: 4,
            energyKWh: 81.25,
            energyKnownCount: 3,
            cost: 32.5,
            costKnownCount: 2,
            currencyCode: "CNY",
            energyBuckets: [0, 12, .nan, 20, -5, 49.25],
            displayLanguage: .chinese
        )

        XCTAssertEqual(trend.energyText, "81.2 kWh")
        XCTAssertEqual(trend.costLabel, "已知费用 2/4")
        XCTAssertEqual(trend.energyBuckets, [0, 12, 0, 20, 0, 49.25])
        XCTAssertNotEqual(trend.costText, "¥0.00")
    }

    func testWidgetDisplayDataIncludesReadOnlyBatteryAndStatusFields() {
        let data = WidgetDisplayData.fixture(
            carName: "Model Y",
            batteryLevel: 68,
            ratedRange: 320,
            isCharging: true,
            isLocked: true,
            sentryModeActive: false,
            insideTemperature: 21,
            outsideTemperature: 8,
            displayLanguage: .english
        )

        XCTAssertEqual(data.carName, "Model Y")
        XCTAssertEqual(data.batteryLevel, 68)
        XCTAssertTrue(data.isCharging)
        XCTAssertTrue(data.isReadOnly)
        XCTAssertEqual(data.batteryText, "68%")
        XCTAssertEqual(data.statusText, "Charging")
        XCTAssertEqual(data.lockText, "Locked")
        XCTAssertEqual(data.rangeText, "199 mi")
        XCTAssertEqual(data.temperatureText, "70°F / 46°F")
    }

    func testWidgetDisplayDataUsesChineseStatusAndLockTextWhenRequested() {
        let charging = WidgetDisplayData.fixture(
            ratedRange: 320,
            isCharging: true,
            isLocked: true,
            insideTemperature: 21,
            outsideTemperature: 8,
            displayLanguage: .chinese
        )
        let sentry = WidgetDisplayData.fixture(
            isCharging: false,
            isLocked: false,
            sentryModeActive: true,
            displayLanguage: .chinese
        )
        let parked = WidgetDisplayData.fixture(
            isCharging: false,
            isLocked: true,
            sentryModeActive: false,
            displayLanguage: .chinese
        )

        XCTAssertEqual(charging.statusText, "正在充电")
        XCTAssertEqual(charging.lockText, "已锁定")
        XCTAssertEqual(charging.rangeText, "320 km")
        XCTAssertEqual(charging.temperatureText, "21°C / 8°C")
        XCTAssertEqual(sentry.statusText, "哨兵")
        XCTAssertEqual(sentry.lockText, "已解锁")
        XCTAssertEqual(parked.statusText, "已停车")
    }

    func testWidgetDisplayDataUsesTraditionalChineseTextWhenRequested() {
        let charging = WidgetDisplayData.fixture(
            isCharging: true,
            isLocked: true,
            displayLanguage: .traditionalChinese,
            displayUnitSystem: .metric
        )
        let parked = WidgetDisplayData.fixture(
            isCharging: false,
            isLocked: false,
            displayLanguage: .traditionalChinese,
            displayUnitSystem: .metric
        )

        XCTAssertEqual(charging.statusText, "正在充電")
        XCTAssertEqual(charging.lockText, "已鎖定")
        XCTAssertEqual(parked.statusText, "已解鎖")
    }

    func testWidgetDisplayDataUsesExplicitUnitSystemOverLanguageDefault() {
        let data = WidgetDisplayData.fixture(
            ratedRange: 320,
            insideTemperature: 21,
            outsideTemperature: 8,
            displayLanguage: .english,
            displayUnitSystem: .metric
        )

        XCTAssertEqual(data.rangeText, "320 km")
        XCTAssertEqual(data.temperatureText, "21°C / 8°C")
    }

    func testWidgetDisplayDataOmitsLockTextWhenLockStateIsUnknown() {
        let data = WidgetDisplayData.fixture(isLocked: nil)

        XCTAssertNil(data.lockText)
    }

    func testWidgetDisplayDataCodableRoundTripPreservesDisplayLanguage() throws {
        let original = WidgetDisplayData.fixture(
            carName: "Model 3",
            batteryLevel: 51,
            isCharging: false,
            isLocked: false,
            sentryModeActive: true,
            displayLanguage: .chinese
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetDisplayData.self, from: encoded)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.statusText, "哨兵")
        XCTAssertEqual(decoded.lockText, "已解锁")
    }

    func testWidgetSnapshotStorePersistsLatestDisplayData() throws {
        let suiteName = "WidgetDisplayDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = WidgetSnapshotStore(defaults: defaults)
        let data = WidgetDisplayData.fixture(
            carName: "Model Y",
            batteryLevel: 78,
            isCharging: true,
            displayLanguage: .chinese
        )

        store.save(data)

        XCTAssertEqual(store.load(), data)
        XCTAssertEqual(store.load()?.statusText, "正在充电")

        store.remove()
        XCTAssertNil(store.load())
    }

    func testWidgetVehicleIdentityIsStableOpaqueAndScopedByServerAndCar() throws {
        let first = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://TeslaMate.Example:443/api/",
            carID: 7
        ))
        let normalized = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://teslamate.example/api",
            carID: 7
        ))
        let otherCar = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://teslamate.example/api",
            carID: 8
        ))
        let otherServer = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://other.example/api",
            carID: 7
        ))

        XCTAssertEqual(first, normalized)
        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, otherCar)
        XCTAssertNotEqual(first, otherServer)
        XCTAssertFalse(first.contains("teslamate"))
        XCTAssertNotEqual(first, "7")
    }

    func testWidgetSnapshotStoreKeepsConfiguredVehiclesIsolatedAndLatestCompatible() throws {
        let suiteName = "WidgetVehicleStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let first = WidgetDisplayData.fixture(carName: "Model 3", batteryLevel: 61)
        let second = WidgetDisplayData.fixture(carName: "Model Y", batteryLevel: 82)

        store.save(first, vehicleIdentifier: "opaque-first", makeLatest: true)
        store.save(second, vehicleIdentifier: "opaque-second", makeLatest: false)

        XCTAssertEqual(store.load(vehicleIdentifier: "opaque-first"), first)
        XCTAssertEqual(store.load(vehicleIdentifier: "opaque-second"), second)
        XCTAssertNil(store.load(vehicleIdentifier: "missing"))
        XCTAssertEqual(store.load(), first)
        XCTAssertEqual(store.preferredVehicleSnapshot()?.id, "opaque-first")
        XCTAssertEqual(store.vehicleSnapshots().map(\.data.carName), ["Model 3", "Model Y"])
    }

    func testStatusRefreshPreservesVehicleTrendSnapshots() throws {
        let suiteName = "WidgetTrendPreservationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        let original = WidgetVehicleSnapshot(
            id: "opaque",
            data: .fixture(carName: "Model 3", batteryLevel: 40),
            batteryTrend: WidgetBatteryTrendData(metric: .capacity, samples: [75, 72]),
            chargingTrend: WidgetChargingTrendData(
                sessionCount: 2,
                energyKWh: 50,
                energyKnownCount: 2,
                currencyCode: "CNY",
                energyBuckets: [0, 0, 0, 10, 20, 20]
            )
        )
        store.replaceVehicleSnapshots([original], preferredIdentifier: "opaque")

        store.save(.fixture(carName: "Model 3", batteryLevel: 55), vehicleIdentifier: "opaque")

        let updated = try XCTUnwrap(store.vehicleSnapshot(vehicleIdentifier: "opaque"))
        XCTAssertEqual(updated.data.batteryLevel, 55)
        XCTAssertEqual(updated.batteryTrend, original.batteryTrend)
        XCTAssertEqual(updated.chargingTrend, original.chargingTrend)
    }

    func testReplacingVehicleSnapshotsRemovesOldServerWithoutCrossVehicleFallback() throws {
        let suiteName = "WidgetVehicleReplacementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WidgetSnapshotStore(defaults: defaults)
        store.save(.fixture(carName: "Old server"), vehicleIdentifier: "old")
        let replacement = WidgetVehicleSnapshot(
            id: "new",
            data: .fixture(carName: "New server", batteryLevel: 72)
        )

        store.replaceVehicleSnapshots([replacement], preferredIdentifier: "new")

        XCTAssertNil(store.load(vehicleIdentifier: "old"))
        XCTAssertEqual(store.load(vehicleIdentifier: "new")?.batteryLevel, 72)
        XCTAssertEqual(store.load()?.carName, "New server")
        XCTAssertEqual(store.preferredVehicleSnapshot()?.id, "new")
    }
}
