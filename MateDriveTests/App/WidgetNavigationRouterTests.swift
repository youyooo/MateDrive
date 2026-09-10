import XCTest
@testable import MateDriveApp

final class WidgetNavigationRouterTests: XCTestCase {
    func testWidgetURLRoundTripContainsOnlyOpaqueVehicleIdentity() throws {
        let identifier = String(repeating: "a", count: 64)
        let url = try XCTUnwrap(MateDriveWidgetNavigation.url(
            destination: .currentCharge,
            vehicleIdentifier: identifier
        ))

        XCTAssertEqual(
            url.absoluteString,
            "matedrive://widget/current-charge?vehicle=\(identifier)"
        )
        XCTAssertEqual(
            MateDriveWidgetNavigation.parse(url),
            MateDriveWidgetRequest(
                destination: .currentCharge,
                vehicleIdentifier: identifier
            )
        )
    }

    func testWidgetURLSupportsOnlyTheFourAllowListedDestinations() throws {
        let expected: [(MateDriveWidgetDestination, String)] = [
            (.dashboard, "dashboard"),
            (.currentCharge, "current-charge"),
            (.battery, "battery"),
            (.charges, "charges")
        ]

        for (destination, path) in expected {
            let url = try XCTUnwrap(MateDriveWidgetNavigation.url(
                destination: destination,
                vehicleIdentifier: nil
            ))
            XCTAssertEqual(url.absoluteString, "matedrive://widget/\(path)")
            XCTAssertEqual(
                MateDriveWidgetNavigation.parse(url),
                MateDriveWidgetRequest(
                    destination: destination,
                    vehicleIdentifier: nil
                )
            )
        }
    }

    func testWidgetLinkRequiresCanonicalSnapshotVehicleIdentityForEveryDestination() throws {
        let identifier = String(repeating: "e", count: 64)

        let destinations: [MateDriveWidgetDestination] = [
            .dashboard,
            .currentCharge,
            .battery,
            .charges
        ]

        for destination in destinations {
            XCTAssertNil(MateDriveWidgetNavigation.widgetURL(
                destination: destination,
                snapshotVehicleIdentifier: nil
            ))
            XCTAssertNil(MateDriveWidgetNavigation.widgetURL(
                destination: destination,
                snapshotVehicleIdentifier: "7"
            ))
            XCTAssertEqual(
                MateDriveWidgetNavigation.widgetURL(
                    destination: destination,
                    snapshotVehicleIdentifier: identifier
                ),
                MateDriveWidgetNavigation.url(
                    destination: destination,
                    vehicleIdentifier: identifier
                )
            )
        }
    }

    func testWidgetURLGeneratorRejectsInvalidOpaqueVehicleIdentity() {
        let invalidIdentifiers = [
            "7",
            String(repeating: "a", count: 63),
            String(repeating: "a", count: 65),
            String(repeating: "A", count: 64),
            String(repeating: "g", count: 64)
        ]

        for identifier in invalidIdentifiers {
            XCTAssertNil(MateDriveWidgetNavigation.url(
                destination: .currentCharge,
                vehicleIdentifier: identifier
            ))
        }
    }

    func testParserRejectsUnknownRouteRawVehicleIDAndExtraQuery() throws {
        let identifier = String(repeating: "a", count: 64)
        let invalidURLs = [
            "matedrive://widget/delete?vehicle=\(identifier)",
            "matedrive://widget/current-charge?vehicle=7",
            "matedrive://widget/current-charge?vehicle=\(identifier)&token=secret"
        ]

        for value in invalidURLs {
            XCTAssertNil(MateDriveWidgetNavigation.parse(try XCTUnwrap(URL(string: value))))
        }
    }

    func testParserRejectsEveryNonCanonicalURLEnvelope() throws {
        let identifier = String(repeating: "b", count: 64)
        let invalidURLs = [
            "https://widget/current-charge?vehicle=\(identifier)",
            "MATEDRIVE://widget/current-charge?vehicle=\(identifier)",
            "matedrive://other/current-charge?vehicle=\(identifier)",
            "matedrive://WIDGET/current-charge?vehicle=\(identifier)",
            "matedrive://widget/current%2Dcharge?vehicle=\(identifier)",
            "matedrive://widget/current-charge?vehicle=\(identifier)#fragment",
            "matedrive://user@widget/current-charge?vehicle=\(identifier)",
            "matedrive://widget:443/current-charge?vehicle=\(identifier)",
            "matedrive://widget/current-charge?vehicle=\(identifier)&vehicle=\(identifier)",
            "matedrive://widget/current-charge?token=secret",
            "matedrive://widget/current-charge?veh%69cle=\(identifier)",
            "matedrive://widget/current-charge?vehicle=\(String(repeating: "%62", count: 64))",
            "matedrive://widget/current-charge?vehicle=",
            "matedrive://widget/current-charge?vehicle",
            "matedrive://widget/current-charge?",
            "matedrive://widget/current-charge?vehicle=\(String(repeating: "B", count: 64))",
            "matedrive://widget/current-charge?vehicle=\(String(repeating: "b", count: 63))",
            "matedrive://widget/current-charge?vehicle=\(String(repeating: "b", count: 65))"
        ]

        for value in invalidURLs {
            XCTAssertNil(
                MateDriveWidgetNavigation.parse(try XCTUnwrap(URL(string: value))),
                value
            )
        }
    }

    func testParserRejectsPercentEncodedWidgetHost() throws {
        let identifier = String(repeating: "b", count: 64)
        let url = try XCTUnwrap(URL(string:
            "matedrive://%77idget/current-charge?vehicle=\(identifier)"
        ))

        XCTAssertNil(MateDriveWidgetNavigation.parse(url))
    }

    func testRegistryResolvesOpaqueVehicleWithoutPersistingServerURL() throws {
        let suiteName = "WidgetNavigationRegistry.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = WidgetNavigationVehicleRegistry(defaults: defaults)
        registry.replace(serverURL: "https://teslamate.example", carIDs: [7, 8])
        let identifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://teslamate.example",
            carID: 8
        ))

        XCTAssertEqual(
            registry.resolve(
                serverURL: "https://teslamate.example",
                vehicleIdentifier: identifier
            ),
            8
        )
        XCTAssertFalse(
            defaults.dictionaryRepresentation().description.contains("teslamate.example")
        )
    }

    func testRegistryKeepsServersIsolatedAcrossReplacements() throws {
        let suiteName = "WidgetNavigationServerIsolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = WidgetNavigationVehicleRegistry(defaults: defaults)
        registry.replace(serverURL: "https://first.example", carIDs: [7])
        registry.replace(serverURL: "https://second.example/base", carIDs: [8])
        let firstIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://first.example",
            carID: 7
        ))
        let secondIdentifier = try XCTUnwrap(WidgetVehicleIdentity.identifier(
            serverURL: "https://second.example/base",
            carID: 8
        ))

        XCTAssertEqual(
            registry.resolve(
                serverURL: "https://first.example",
                vehicleIdentifier: firstIdentifier
            ),
            7
        )
        XCTAssertEqual(
            registry.resolve(
                serverURL: "https://second.example/base",
                vehicleIdentifier: secondIdentifier
            ),
            8
        )
        XCTAssertNil(registry.resolve(
            serverURL: "https://second.example/base",
            vehicleIdentifier: firstIdentifier
        ))
    }

    func testBatteryWidgetRouteUsesResolvedVehicle() {
        let request = MateDriveWidgetRequest(
            destination: .battery,
            vehicleIdentifier: String(repeating: "b", count: 64)
        )

        XCTAssertEqual(
            WidgetNavigationRouter.route(
                request: request,
                settings: AppSettings(
                    serverURL: "https://teslamate.example",
                    lastSelectedCarId: 6
                ),
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

    func testWidgetRouterMapsEveryAllowListedDestination() {
        let settings = AppSettings(serverURL: "https://teslamate.example")
        let identifier = String(repeating: "d", count: 64)

        XCTAssertEqual(
            WidgetNavigationRouter.route(
                request: MateDriveWidgetRequest(
                    destination: .dashboard,
                    vehicleIdentifier: identifier
                ),
                settings: settings,
                resolvedCarID: 8,
                fallbackCarID: 7
            ),
            .dashboard
        )
        XCTAssertEqual(
            WidgetNavigationRouter.route(
                request: MateDriveWidgetRequest(
                    destination: .charges,
                    vehicleIdentifier: identifier
                ),
                settings: settings,
                resolvedCarID: 8,
                fallbackCarID: nil
            ),
            .charges(carId: 8, exteriorColor: nil)
        )
        XCTAssertEqual(
            WidgetNavigationRouter.route(
                request: MateDriveWidgetRequest(
                    destination: .currentCharge,
                    vehicleIdentifier: identifier
                ),
                settings: settings,
                resolvedCarID: 8,
                fallbackCarID: nil
            ),
            .currentCharge(carId: 8, exteriorColor: nil)
        )
    }
}
