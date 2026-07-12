import Foundation

public protocol AppNotificationServicing: Sendable {
    func authorizationStatus() async -> AppNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool

    func deliverCharging(
        carName: String,
        chargerPowerKW: Double,
        isDC: Bool,
        batteryLevel: Int?,
        chargeLimit: Int?,
        identifier: String
    ) async throws

    func deliverSentry(
        carName: String,
        alertCount: Int,
        locationText: String?,
        identifier: String
    ) async throws

    func deliverTyrePressure(
        carName: String,
        tyreName: String,
        pressure: Double,
        unit: String,
        threshold: Double,
        identifier: String
    ) async throws
}

public struct DisabledAppNotificationService: AppNotificationServicing {
    public init() {}
    public func authorizationStatus() async -> AppNotificationAuthorizationStatus { .denied }
    public func requestAuthorization() async throws -> Bool { false }
    public func deliverCharging(carName: String, chargerPowerKW: Double, isDC: Bool, batteryLevel: Int?, chargeLimit: Int?, identifier: String) async throws {}
    public func deliverSentry(carName: String, alertCount: Int, locationText: String?, identifier: String) async throws {}
    public func deliverTyrePressure(carName: String, tyreName: String, pressure: Double, unit: String, threshold: Double, identifier: String) async throws {}
}

public struct SettingsBackedNotificationService: AppNotificationServicing {
    private let settingsStore: any SettingsStoring
    private let coordinator: any NotificationCoordinating

    public init(settingsStore: any SettingsStoring, coordinator: any NotificationCoordinating = NotificationCoordinator()) {
        self.settingsStore = settingsStore
        self.coordinator = coordinator
    }

    public func authorizationStatus() async -> AppNotificationAuthorizationStatus {
        await coordinator.authorizationStatus()
    }

    public func requestAuthorization() async throws -> Bool {
        try await coordinator.requestAuthorization()
    }

    public func deliverCharging(
        carName: String,
        chargerPowerKW: Double,
        isDC: Bool,
        batteryLevel: Int?,
        chargeLimit: Int?,
        identifier: String
    ) async throws {
        let language = await settingsStore.load().appLanguage
        let content = ChargingNotificationContent(
            carName: carName,
            chargerPowerKW: chargerPowerKW,
            isDC: isDC,
            batteryLevel: batteryLevel,
            chargeLimit: chargeLimit,
            language: language
        )
        try await coordinator.deliver(
            identifier: identifier,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier
        )
    }

    public func deliverSentry(
        carName: String,
        alertCount: Int,
        locationText: String?,
        identifier: String
    ) async throws {
        let language = await settingsStore.load().appLanguage
        let content = SentryNotificationContent(
            carName: carName,
            alertCount: alertCount,
            locationText: locationText,
            language: language
        )
        try await coordinator.deliver(
            identifier: identifier,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier
        )
    }

    public func deliverTyrePressure(
        carName: String,
        tyreName: String,
        pressure: Double,
        unit: String,
        threshold: Double,
        identifier: String
    ) async throws {
        let language = await settingsStore.load().appLanguage
        let content = TyrePressureNotificationContent(
            carName: carName,
            tyreName: tyreName,
            pressure: pressure,
            unit: unit,
            threshold: threshold,
            language: language
        )
        try await coordinator.deliver(
            identifier: identifier,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier
        )
    }
}
