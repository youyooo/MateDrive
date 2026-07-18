import Combine
import Foundation

public struct ChargePricingRulesHealth: Equatable, Sendable {
    public let activeCount: Int
    public let disabledCount: Int
    public let invalidCount: Int

    public var totalCount: Int { activeCount + disabledCount + invalidCount }
    public var needsAttention: Bool { invalidCount > 0 }
}

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var isSaving = false
    @Published public private(set) var isTestingConnection = false
    @Published public private(set) var connectionReport: TeslaMateDiagnosticReport?
    @Published public private(set) var geographyCacheHealth: GeographyCacheHealth?
    @Published public private(set) var geographyHealthError: String?
    @Published public private(set) var isRefreshingGeographyHealth = false
    @Published public private(set) var isProcessingGeographyQueue = false
    @Published public private(set) var geographyProcessingReport: GeocodeQueueProcessingReport?
    @Published public private(set) var historySyncHealth: HistorySyncHealth?
    @Published public private(set) var historySyncHealthError: String?
    @Published public private(set) var isRefreshingHistorySyncHealth = false
    @Published public private(set) var isSyncingHistory = false
    @Published public private(set) var lastHistorySyncReport: HistorySyncReport?
    @Published public private(set) var notificationAuthorizationStatus: AppNotificationAuthorizationStatus = .notDetermined
    @Published public private(set) var isRequestingNotificationAuthorization = false
    @Published public private(set) var notificationMessage: String?

    public var chargePricingRulesHealth: ChargePricingRulesHealth {
        settings.chargePricingRules.reduce(into: ChargePricingRulesHealth(activeCount: 0, disabledCount: 0, invalidCount: 0)) { health, rule in
            let isValid = ChargePricingRuleValidator.issues(for: rule).isEmpty
            health = ChargePricingRulesHealth(
                activeCount: health.activeCount + (isValid && rule.isEnabled ? 1 : 0),
                disabledCount: health.disabledCount + (isValid && !rule.isEnabled ? 1 : 0),
                invalidCount: health.invalidCount + (isValid ? 0 : 1)
            )
        }
    }

    private let settingsStore: any SettingsStoring
    private let secretStore: any SecretStoring
    private let connectionDiagnostic: any TeslaMateConnectionDiagnosing
    private let serverProfileStore: any TeslaMateServerProfileStoring
    private let geographyHealthProvider: any GeographyCacheHealthProviding
    private let geographyQueueProcessor: any GeocodeQueueProcessing
    private let historySyncHealthProvider: any HistorySyncHealthProviding
    private let historySyncRunner: any HistorySyncRunning
    private let notificationService: any AppNotificationServicing

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        connectionDiagnostic: any TeslaMateConnectionDiagnosing = TeslaMateConnectionDiagnostic(),
        serverProfileStore: any TeslaMateServerProfileStoring = EmptyTeslaMateServerProfileStore(),
        geographyHealthProvider: any GeographyCacheHealthProviding = EmptyGeographyCacheHealthProvider(),
        geographyQueueProcessor: any GeocodeQueueProcessing = EmptyGeocodeQueueProcessor(),
        historySyncHealthProvider: any HistorySyncHealthProviding = EmptyHistorySyncHealthProvider(),
        historySyncRunner: any HistorySyncRunning = EmptyHistorySyncRunner(),
        notificationService: any AppNotificationServicing = DisabledAppNotificationService(),
        initial: AppSettings = AppSettings()
    ) {
        self.settingsStore = settingsStore
        self.secretStore = secretStore
        self.connectionDiagnostic = connectionDiagnostic
        self.serverProfileStore = serverProfileStore
        self.geographyHealthProvider = geographyHealthProvider
        self.geographyQueueProcessor = geographyQueueProcessor
        self.historySyncHealthProvider = historySyncHealthProvider
        self.historySyncRunner = historySyncRunner
        self.notificationService = notificationService
        self.settings = initial
    }

    public func load() async {
        settings = await settingsStore.load()
        await refreshNotificationAuthorizationStatus()
        await refreshGeographyHealth()
        await refreshHistorySyncHealth()
    }

    public func refreshNotificationAuthorizationStatus() async {
        notificationAuthorizationStatus = await notificationService.authorizationStatus()
    }

    public func requestNotificationAuthorization() async {
        guard !isRequestingNotificationAuthorization else { return }
        isRequestingNotificationAuthorization = true
        defer { isRequestingNotificationAuthorization = false }
        do {
            _ = try await notificationService.requestAuthorization()
            var updated = await settingsStore.load()
            updated.notificationPermissionAsked = true
            await settingsStore.save(updated)
            settings = updated
            await refreshNotificationAuthorizationStatus()
            notificationMessage = notificationAuthorizationStatus.canDeliver
                ? localized("Notifications enabled.", "通知已开启。")
                : localized("Notifications are disabled in system settings.", "通知已在系统设置中关闭。")
        } catch {
            notificationMessage = error.localizedDescription
        }
    }

    public func sendTestNotification() async {
        guard notificationAuthorizationStatus.canDeliver else {
            notificationMessage = localized("Enable notifications before sending a test.", "请先开启通知，再发送测试。")
            return
        }
        do {
            try await notificationService.deliverCharging(carName: "MateDrive", chargerPowerKW: 11, isDC: false, batteryLevel: 68, chargeLimit: 80, identifier: "matedrive.test.charging")
            notificationMessage = localized("Test notification sent.", "测试通知已发送。")
        } catch {
            notificationMessage = error.localizedDescription
        }
    }

    public func sendTestSentryNotification() async {
        guard notificationAuthorizationStatus.canDeliver else {
            notificationMessage = localized("Enable notifications before sending a test.", "请先开启通知，再发送测试。")
            return
        }
        do {
            try await notificationService.deliverSentry(carName: "MateDrive", alertCount: 1, locationText: localized("Test location", "测试位置"), identifier: "matedrive.test.sentry")
            notificationMessage = localized("Test notification sent.", "测试通知已发送。")
        } catch {
            notificationMessage = error.localizedDescription
        }
    }

    public func sendTestTyrePressureNotification() async {
        guard notificationAuthorizationStatus.canDeliver else {
            notificationMessage = localized("Enable notifications before sending a test.", "请先开启通知，再发送测试。")
            return
        }
        do {
            let usesChinese = MateDroidUnitFormatter.usesChineseLabels(language: settings.appLanguage)
            try await notificationService.deliverTyrePressure(
                carName: "MateDrive",
                tyreName: "Front left",
                pressure: usesChinese ? 2.1 : MateDroidUnitFormatter.pressureValue(2.1, units: .imperial),
                unit: usesChinese ? "bar" : "psi",
                threshold: usesChinese ? 2.4 : MateDroidUnitFormatter.pressureValue(2.4, units: .imperial),
                identifier: "matedrive.test.tyre"
            )
            notificationMessage = localized("Test notification sent.", "测试通知已发送。")
        } catch {
            notificationMessage = error.localizedDescription
        }
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: settings.appLanguage)
    }

    public func save(
        serverURL: String,
        secondaryServerURL: String,
        apiToken: String,
        basicUsername: String,
        basicPassword: String,
        cloudflareClientID: String = "",
        cloudflareClientSecret: String = "",
        apiAccessKey: String = "",
        apiSecretKey: String = "",
        acceptInvalidCerts: Bool,
        currencyCode: String,
        displayUnitSystem: DisplayUnitSystem = .teslamate,
        appLanguage: AppLanguage,
        batteryReferenceRangeKm: Double?,
        batteryReferenceCapacityKWh: Double? = nil,
        batteryRecordingStartOdometerKm: Double?
    ) async {
        isSaving = true
        defer { isSaving = false }

        let previousServerKey = Self.serverKey(settings.serverURL)
        let previousLanguage = settings.appLanguage
        var updated = settings
        updated.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.secondaryServerURL = secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.acceptInvalidCerts = acceptInvalidCerts
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        updated.currencyCode = normalizedCurrency.isEmpty
            ? MateDroidCurrencyFormatter.automaticCode
            : normalizedCurrency == "RMB" ? "CNY" : normalizedCurrency
        updated.displayUnitSystem = displayUnitSystem
        updated.appLanguage = appLanguage
        updated.batteryReferenceRangeKm = batteryReferenceRangeKm
        updated.batteryRecordingStartOdometerKm = batteryRecordingStartOdometerKm
        if let carId = updated.lastSelectedCarId {
            updated.setBatteryCalibration(
                BatteryCalibration(referenceRangeKm: batteryReferenceRangeKm, referenceCapacityKWh: batteryReferenceCapacityKWh, recordingStartOdometerKm: batteryRecordingStartOdometerKm),
                for: carId
            )
        }

        await settingsStore.save(updated)
        let updatedServerKey = Self.serverKey(updated.serverURL)
        if let previousServerKey, previousServerKey != updatedServerKey {
            try? await serverProfileStore.delete(serverKey: previousServerKey)
        }
        await persistSecretIfProvided(apiToken, key: "apiToken")
        await persistSecretIfProvided(basicUsername, key: "httpBasicAuthUsername")
        await persistSecretIfProvided(basicPassword, key: "httpBasicAuthPassword")
        await persistSecretIfProvided(cloudflareClientID, key: "cloudflareAccessClientID")
        await persistSecretIfProvided(cloudflareClientSecret, key: "cloudflareAccessClientSecret")
        await persistSecretIfProvided(apiAccessKey, key: "apiAccessKey")
        await persistSecretIfProvided(apiSecretKey, key: "apiSecretKey")
        settings = updated
        if previousLanguage != appLanguage {
            connectionReport = nil
        }
    }

    public func saveAppLanguage(_ appLanguage: AppLanguage) async {
        guard settings.appLanguage != appLanguage else {
            return
        }

        var updated = settings
        updated.appLanguage = appLanguage
        await settingsStore.save(updated)
        settings = updated
        connectionReport = nil
    }

    public func saveChargePricingRules(_ rules: [ChargePricingRule]) async {
        var updated = settings
        updated.chargePricingRules = rules
        await settingsStore.save(updated)
        settings = updated
    }

    public func saveResidentialTariffRegionCode(_ regionCode: String?) async {
        var updated = settings
        let normalizedRegionCode = regionCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        updated.residentialTariffRegionCode = normalizedRegionCode?.isEmpty == false
            ? normalizedRegionCode
            : nil
        await settingsStore.save(updated)
        settings = updated
    }

    public func saveHomeTariffRegionCode(_ regionCode: String?) async {
        await saveResidentialTariffRegionCode(regionCode)
    }

    public func saveParkingFeeRules(_ rules: [ParkingFeeRule]) async {
        var updated = settings
        updated.parkingFeeRules = rules
        await settingsStore.save(updated)
        settings = updated
    }

    public func testConnection(
        serverURL: String? = nil,
        secondaryServerURL: String? = nil,
        acceptInvalidCerts: Bool? = nil,
        apiToken: String? = nil,
        basicUsername: String? = nil,
        basicPassword: String? = nil,
        cloudflareClientID: String? = nil,
        cloudflareClientSecret: String? = nil,
        apiAccessKey: String? = nil,
        apiSecretKey: String? = nil
    ) async {
        isTestingConnection = true
        defer { isTestingConnection = false }

        var diagnosticSettings = settings
        if let serverURL {
            diagnosticSettings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let secondaryServerURL {
            diagnosticSettings.secondaryServerURL = secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let acceptInvalidCerts {
            diagnosticSettings.acceptInvalidCerts = acceptInvalidCerts
        }

        let token: String?
        if let formToken = Self.nonEmpty(apiToken) {
            token = formToken
        } else {
            token = try? await secretStore.get("apiToken")
        }

        let username: String?
        if let formUsername = Self.nonEmpty(basicUsername) {
            username = formUsername
        } else {
            username = try? await secretStore.get("httpBasicAuthUsername")
        }

        let password: String?
        if let formPassword = Self.nonEmpty(basicPassword) {
            password = formPassword
        } else {
            password = try? await secretStore.get("httpBasicAuthPassword")
        }
        let basicAuth: BasicAuth?
        if let username, let password, !username.isEmpty, !password.isEmpty {
            basicAuth = BasicAuth(username: username, password: password)
        } else {
            basicAuth = nil
        }

        let resolvedCloudflareClientID: String?
        if let formValue = Self.nonEmpty(cloudflareClientID) {
            resolvedCloudflareClientID = formValue
        } else {
            resolvedCloudflareClientID = try? await secretStore.get("cloudflareAccessClientID")
        }
        let resolvedCloudflareClientSecret: String?
        if let formValue = Self.nonEmpty(cloudflareClientSecret) {
            resolvedCloudflareClientSecret = formValue
        } else {
            resolvedCloudflareClientSecret = try? await secretStore.get("cloudflareAccessClientSecret")
        }
        let cloudflareAccess = Self.nonEmpty(resolvedCloudflareClientID).flatMap { clientID in
            Self.nonEmpty(resolvedCloudflareClientSecret).map {
                CloudflareAccessAuth(clientID: clientID, clientSecret: $0)
            }
        }
        let resolvedAccessKey: String?
        if let formValue = Self.nonEmpty(apiAccessKey) {
            resolvedAccessKey = formValue
        } else {
            resolvedAccessKey = Self.nonEmpty(try? await secretStore.get("apiAccessKey"))
        }
        let resolvedSecretKey: String?
        if let formValue = Self.nonEmpty(apiSecretKey) {
            resolvedSecretKey = formValue
        } else {
            resolvedSecretKey = Self.nonEmpty(try? await secretStore.get("apiSecretKey"))
        }
        let aksk = resolvedAccessKey.flatMap { accessKey in
            resolvedSecretKey.map { AKSKCredentials(accessKey: accessKey, secretKey: $0) }
        }
        let authenticator = RequestAuthenticator(
            bearerToken: token,
            basicAuth: basicAuth,
            cloudflareAccess: cloudflareAccess,
            aksk: aksk
        )

        connectionReport = await connectionDiagnostic.run(
            settings: diagnosticSettings,
            authenticator: authenticator,
            language: diagnosticSettings.appLanguage
        )
        await refreshGeographyHealth()
    }

    public func refreshGeographyHealth() async {
        guard !isRefreshingGeographyHealth else { return }
        isRefreshingGeographyHealth = true
        defer { isRefreshingGeographyHealth = false }
        do {
            geographyCacheHealth = try await geographyHealthProvider.health()
            geographyHealthError = nil
        } catch {
            geographyHealthError = error.localizedDescription
        }
    }

    public func processPendingGeography() async {
        guard !isProcessingGeographyQueue else { return }
        isProcessingGeographyQueue = true
        geographyProcessingReport = await geographyQueueProcessor.processPending(limit: 6)
        isProcessingGeographyQueue = false
        await refreshGeographyHealth()
    }

    public func refreshHistorySyncHealth() async {
        guard !isRefreshingHistorySyncHealth else { return }
        isRefreshingHistorySyncHealth = true
        defer { isRefreshingHistorySyncHealth = false }
        do {
            historySyncHealth = try await historySyncHealthProvider.health(carId: settings.lastSelectedCarId)
            historySyncHealthError = nil
        } catch {
            historySyncHealthError = error.localizedDescription
        }
    }

    public func syncHistoryNow() async {
        guard !isSyncingHistory else { return }
        isSyncingHistory = true
        defer { isSyncingHistory = false }
        lastHistorySyncReport = await historySyncRunner.run()
        geographyProcessingReport = await geographyQueueProcessor.processPending(limit: 6)
        await refreshGeographyHealth()
        await refreshHistorySyncHealth()
    }

    private func persistSecretIfProvided(_ value: String, key: String) async {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try? await secretStore.set(trimmed, for: key)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func serverKey(_ rawURL: String) -> String? {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme != nil, url.host != nil else { return nil }
        return TeslaMateServerIdentity.key(for: url)
    }
}
