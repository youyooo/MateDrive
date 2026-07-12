import XCTest
@testable import MateDroidIOS

final class SettingsBackedNotificationServiceTests: XCTestCase {
    func testAuthorizationDelegatesToCoordinator() async throws {
        let coordinator = CapturingNotificationCoordinator(status: .provisional)
        let service = SettingsBackedNotificationService(
            settingsStore: StaticNotificationSettingsStore(settings: AppSettings()),
            coordinator: coordinator
        )

        let status = await service.authorizationStatus()
        let granted = try await service.requestAuthorization()
        XCTAssertEqual(status, .provisional)
        XCTAssertTrue(granted)
        XCTAssertEqual(coordinator.authorizationRequestCount, 1)
    }

    func testDeliverChargingUsesSavedChineseLanguage() async throws {
        let coordinator = CapturingNotificationCoordinator()
        let service = SettingsBackedNotificationService(
            settingsStore: StaticNotificationSettingsStore(settings: AppSettings(appLanguage: .chinese)),
            coordinator: coordinator
        )

        try await service.deliverCharging(
            carName: "Model Y",
            chargerPowerKW: 11,
            isDC: false,
            batteryLevel: 68,
            chargeLimit: 80,
            identifier: "charging"
        )

        XCTAssertEqual(coordinator.deliveries, [
            CapturedNotification(
                identifier: "charging",
                title: "Model Y - 11 kW 交流",
                body: "电量 68%，上限 80%",
                categoryIdentifier: "charging_status"
            )
        ])
    }

    func testDeliverSentryUsesSavedChineseLanguage() async throws {
        let coordinator = CapturingNotificationCoordinator()
        let service = SettingsBackedNotificationService(
            settingsStore: StaticNotificationSettingsStore(settings: AppSettings(appLanguage: .chinese)),
            coordinator: coordinator
        )

        try await service.deliverSentry(
            carName: "Model 3",
            alertCount: 2,
            locationText: "车库",
            identifier: "sentry"
        )

        XCTAssertEqual(coordinator.deliveries, [
            CapturedNotification(
                identifier: "sentry",
                title: "Model 3 - 哨兵警报 #2",
                body: "检测位置：车库",
                categoryIdentifier: "sentry_alert"
            )
        ])
    }

    func testDeliverTyrePressureUsesSavedChineseLanguage() async throws {
        let coordinator = CapturingNotificationCoordinator()
        let service = SettingsBackedNotificationService(
            settingsStore: StaticNotificationSettingsStore(settings: AppSettings(appLanguage: .chinese)),
            coordinator: coordinator
        )

        try await service.deliverTyrePressure(
            carName: "Model S",
            tyreName: "Front left",
            pressure: 2.1,
            unit: "bar",
            threshold: 2.4,
            identifier: "tyre"
        )

        XCTAssertEqual(coordinator.deliveries, [
            CapturedNotification(
                identifier: "tyre",
                title: "Model S - 胎压",
                body: "左前轮 当前 2.1 bar，低于 2.4 bar",
                categoryIdentifier: "tyre_pressure_alert"
            )
        ])
    }
}

private struct CapturedNotification: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let categoryIdentifier: String?
}

private final class CapturingNotificationCoordinator: NotificationCoordinating, @unchecked Sendable {
    private(set) var deliveries: [CapturedNotification] = []
    private(set) var authorizationRequestCount = 0
    private let status: AppNotificationAuthorizationStatus

    init(status: AppNotificationAuthorizationStatus = .authorized) {
        self.status = status
    }

    func authorizationStatus() async -> AppNotificationAuthorizationStatus { status }

    func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return true
    }

    func deliver(identifier: String, title: String, body: String, categoryIdentifier: String?) async throws {
        deliveries.append(
            CapturedNotification(
                identifier: identifier,
                title: title,
                body: body,
                categoryIdentifier: categoryIdentifier
            )
        )
    }
}

private struct StaticNotificationSettingsStore: SettingsStoring {
    let settings: AppSettings

    func load() async -> AppSettings {
        settings
    }

    func save(_ settings: AppSettings) async {}
}
