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
    @Published public private(set) var saveErrorMessage: String?
    @Published public private(set) var connectionConfigurationRevision = 0
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
    private let syncController: (any AppDataSyncSuspending)?
    private var settingsMutationGeneration = 0

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
        syncController: (any AppDataSyncSuspending)? = nil,
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
        self.syncController = syncController
        self.settings = initial
    }

    public func load() async {
        await loadEssentials()
        await refreshOperationalState()
    }

    public func loadEssentials() async {
        settings = await settingsStore.load()
    }

    public func refreshOperationalState() async {
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
            let didPersist = await updateSettingsAtomically { current in
                var updated = current
                updated.notificationPermissionAsked = true
                return updated
            }
            await refreshNotificationAuthorizationStatus()
            if didPersist {
                notificationMessage = notificationAuthorizationStatus.canDeliver
                    ? localized("Notifications enabled.", "通知已开启。")
                    : localized("Notifications are disabled in system settings.", "通知已在系统设置中关闭。")
            } else {
                notificationMessage = localized(
                    "Notification permission changed, but MateDrive could not save the preference. Try again.",
                    "通知权限已变更，但 MateDrive 无法保存该偏好。请重试。"
                )
            }
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
            let usesChinese = MateDriveUnitFormatter.usesChineseLabels(language: settings.appLanguage)
            try await notificationService.deliverTyrePressure(
                carName: "MateDrive",
                tyreName: "Front left",
                pressure: usesChinese ? 2.1 : MateDriveUnitFormatter.pressureValue(2.1, units: .imperial),
                unit: usesChinese ? "bar" : "psi",
                threshold: usesChinese ? 2.4 : MateDriveUnitFormatter.pressureValue(2.4, units: .imperial),
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
        authenticationMode: ServerAuthenticationMode? = nil,
        usesCloudflareAccess: Bool? = nil,
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
    ) async -> Bool {
        guard !isSaving else { return false }
        settingsMutationGeneration &+= 1
        let mutationGeneration = settingsMutationGeneration
        isSaving = true
        defer { isSaving = false }
        saveErrorMessage = nil

        let candidateURLs = [
            serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
            secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ].filter { !$0.isEmpty }
        guard candidateURLs.allSatisfy({ TeslaMateServerURLPolicy.evaluate($0).isUsable }) else {
            saveErrorMessage = localized(
                "Use HTTPS for public servers. Server URLs cannot contain usernames, passwords, query parameters, or fragments.",
                "公网服务器必须使用安全加密连接；服务器地址不能包含用户名、密码、查询参数或片段。"
            )
            return false
        }

        let persistedSettings = await settingsStore.load()
        let previousServerKey = Self.serverKey(persistedSettings.serverURL)
        let previousLanguage = persistedSettings.appLanguage
        var updated = persistedSettings
        updated.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.secondaryServerURL = secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.authenticationMode = authenticationMode ?? updated.authenticationMode
        updated.usesCloudflareAccess = usesCloudflareAccess ?? updated.usesCloudflareAccess
        updated.acceptInvalidCerts = acceptInvalidCerts && [updated.serverURL, updated.secondaryServerURL]
            .contains(where: TeslaMateServerURLPolicy.permitsInvalidCertificateBypass)
        let normalizedCurrency = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        updated.currencyCode = normalizedCurrency.isEmpty
            ? MateDriveCurrencyFormatter.automaticCode
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
        let updatedServerKey = Self.serverKey(updated.serverURL)
        let didChangeServer = previousServerKey != updatedServerKey
        let hasCredentialDraft = [
            apiToken,
            basicUsername,
            basicPassword,
            cloudflareClientID,
            cloudflareClientSecret,
            apiAccessKey,
            apiSecretKey
        ].contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let didChangeConnectionConfiguration = didChangeServer
            || persistedSettings.secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
                != updated.secondaryServerURL
            || persistedSettings.authenticationMode != updated.authenticationMode
            || persistedSettings.usesCloudflareAccess != updated.usesCloudflareAccess
            || persistedSettings.acceptInvalidCerts != updated.acceptInvalidCerts
            || hasCredentialDraft

        let previousSecrets: [String: String?]
        do {
            previousSecrets = try await authenticationSecretsSnapshot()
        } catch {
            saveErrorMessage = localized(
                "Could not access saved credentials. Your previous server settings were kept.",
                "无法访问已保存的认证凭据，已保留之前的服务器设置。"
            )
            return false
        }

        if didChangeConnectionConfiguration {
            await syncController?.suspendAndWait()
        }
        let committedSettings: AppSettings
        do {
            try await persistAuthenticationSecrets(
                mode: updated.authenticationMode,
                usesCloudflareAccess: updated.usesCloudflareAccess,
                apiToken: apiToken,
                basicUsername: basicUsername,
                basicPassword: basicPassword,
                cloudflareClientID: cloudflareClientID,
                cloudflareClientSecret: cloudflareClientSecret,
                apiAccessKey: apiAccessKey,
                apiSecretKey: apiSecretKey
            )
            try Task.checkCancellation()
            if let atomicSettingsStore = settingsStore as? any AtomicSettingsUpdating {
                let formSettings = updated
                committedSettings = try await atomicSettingsStore.updateAtomically { current in
                    Self.mergeFormSettings(formSettings, into: current)
                }
            } else {
                try await settingsStore.saveThrowing(updated)
                committedSettings = updated
            }
        } catch {
            let didRestoreSecrets: Bool
            do {
                try await restoreAuthenticationSecrets(previousSecrets)
                didRestoreSecrets = true
            } catch {
                didRestoreSecrets = false
            }
            if didChangeConnectionConfiguration {
                await syncController?.resume()
            }
            saveErrorMessage = didRestoreSecrets
                ? localized(
                    "Could not save the connection. Your previous server settings and credentials were restored.",
                    "无法保存连接配置，已恢复之前的服务器设置和认证凭据。"
                )
                : localized(
                    "Could not save the connection or fully restore its credentials. Re-enter the credentials before refreshing.",
                    "无法保存连接配置，也未能完整恢复认证凭据。请重新填写凭据后再刷新。"
                )
            return false
        }

        if let previousServerKey, previousServerKey != updatedServerKey {
            try? await serverProfileStore.delete(serverKey: previousServerKey)
        }
        if didChangeConnectionConfiguration {
            await syncController?.resume()
        }
        if mutationGeneration == settingsMutationGeneration {
            settings = committedSettings
        }
        if didChangeConnectionConfiguration, !didChangeServer {
            connectionConfigurationRevision &+= 1
        }
        if previousLanguage != appLanguage {
            connectionReport = nil
        }
        return true
    }

    public func clearSaveError() {
        saveErrorMessage = nil
    }

    public func saveAppLanguage(_ appLanguage: AppLanguage) async {
        guard settings.appLanguage != appLanguage else {
            return
        }

        if await updateSettingsAtomically({ current in
            var updated = current
            updated.appLanguage = appLanguage
            return updated
        }) {
            connectionReport = nil
        } else {
            recordSettingsUpdateFailure()
        }
    }

    @discardableResult
    public func saveThirdPartyRouteWeatherPermission(_ isAllowed: Bool) async -> Bool {
        guard settings.allowsThirdPartyRouteWeather != isAllowed else {
            return true
        }
        guard await updateSettingsAtomically({ current in
            var updated = current
            updated.allowsThirdPartyRouteWeather = isAllowed
            return updated
        }) else {
            recordSettingsUpdateFailure()
            return false
        }
        return true
    }

    public func saveChargePricingRules(_ rules: [ChargePricingRule]) async {
        guard await updateSettingsAtomically({ current in
            var updated = current
            updated.chargePricingRules = rules
            return updated
        }) else {
            recordSettingsUpdateFailure()
            return
        }
    }

    public func saveChargeTariffTemplates(_ templates: [ChargeTariffTemplate]) async {
        guard await updateSettingsAtomically({ current in
            var updated = current
            updated.chargeTariffTemplates = templates
            return updated
        }) else {
            recordSettingsUpdateFailure()
            return
        }
    }

    public func saveResidentialTariffRegionCode(_ regionCode: String?) async {
        let normalizedRegionCode = regionCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let resolvedRegionCode = normalizedRegionCode?.isEmpty == false
            ? normalizedRegionCode
            : nil
        guard await updateSettingsAtomically({ current in
            var updated = current
            updated.residentialTariffRegionCode = resolvedRegionCode
            return updated
        }) else {
            recordSettingsUpdateFailure()
            return
        }
    }

    public func saveHomeTariffRegionCode(_ regionCode: String?) async {
        await saveResidentialTariffRegionCode(regionCode)
    }

    public func saveParkingFeeRules(_ rules: [ParkingFeeRule]) async {
        guard await updateSettingsAtomically({ current in
            var updated = current
            updated.parkingFeeRules = rules
            return updated
        }) else {
            recordSettingsUpdateFailure()
            return
        }
    }

    public func saveGeofenceRules(
        _ rules: [GeofenceRule],
        usesForCommuteClassification: Bool? = nil
    ) async {
        guard await updateSettingsAtomically({ current in
            var updated = current
            updated.geofenceRules = rules
            if let usesForCommuteClassification {
                updated.usesGeofencesForCommuteClassification = usesForCommuteClassification
            }
            return updated
        }) else {
            recordSettingsUpdateFailure()
            return
        }
    }

    @discardableResult
    public func testConnection(
        serverURL: String? = nil,
        secondaryServerURL: String? = nil,
        authenticationMode: ServerAuthenticationMode? = nil,
        usesCloudflareAccess: Bool? = nil,
        acceptInvalidCerts: Bool? = nil,
        apiToken: String? = nil,
        basicUsername: String? = nil,
        basicPassword: String? = nil,
        cloudflareClientID: String? = nil,
        cloudflareClientSecret: String? = nil,
        apiAccessKey: String? = nil,
        apiSecretKey: String? = nil
    ) async -> TeslaMateDiagnosticReport {
        isTestingConnection = true
        defer { isTestingConnection = false }

        var diagnosticSettings = settings
        if let serverURL {
            diagnosticSettings.serverURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let secondaryServerURL {
            diagnosticSettings.secondaryServerURL = secondaryServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let authenticationMode {
            diagnosticSettings.authenticationMode = authenticationMode
        }
        if let usesCloudflareAccess {
            diagnosticSettings.usesCloudflareAccess = usesCloudflareAccess
        }
        if let acceptInvalidCerts {
            diagnosticSettings.acceptInvalidCerts = acceptInvalidCerts
        }

        let authenticator = await ServerAuthenticationResolver.resolve(
            settings: diagnosticSettings,
            secretStore: secretStore,
            draft: ServerAuthenticationDraft(
                apiToken: apiToken,
                basicUsername: basicUsername,
                basicPassword: basicPassword,
                cloudflareClientID: cloudflareClientID,
                cloudflareClientSecret: cloudflareClientSecret,
                apiAccessKey: apiAccessKey,
                apiSecretKey: apiSecretKey
            )
        )

        let report = await connectionDiagnostic.run(
            settings: diagnosticSettings,
            authenticator: authenticator,
            language: diagnosticSettings.appLanguage
        )
        connectionReport = report
        await refreshGeographyHealth()
        return report
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

    private static let authenticationSecretKeys = [
        "apiToken",
        "httpBasicAuthUsername",
        "httpBasicAuthPassword",
        "apiAccessKey",
        "apiSecretKey",
        "cloudflareAccessClientID",
        "cloudflareAccessClientSecret"
    ]

    private func authenticationSecretsSnapshot() async throws -> [String: String?] {
        var snapshot: [String: String?] = [:]
        for key in Self.authenticationSecretKeys {
            snapshot[key] = try await secretStore.get(key)
        }
        return snapshot
    }

    private func restoreAuthenticationSecrets(_ snapshot: [String: String?]) async throws {
        for key in Self.authenticationSecretKeys {
            if let value = snapshot[key] ?? nil {
                try await secretStore.set(value, for: key)
            } else {
                try await secretStore.remove(key)
            }
        }
    }

    private func persistSecretIfProvided(_ value: String, key: String) async throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            try await secretStore.set(trimmed, for: key)
        }
    }

    private func persistAuthenticationSecrets(
        mode: ServerAuthenticationMode,
        usesCloudflareAccess: Bool,
        apiToken: String,
        basicUsername: String,
        basicPassword: String,
        cloudflareClientID: String,
        cloudflareClientSecret: String,
        apiAccessKey: String,
        apiSecretKey: String
    ) async throws {
        switch mode {
        case .automatic:
            try await persistSecretIfProvided(apiToken, key: "apiToken")
            try await persistSecretIfProvided(basicUsername, key: "httpBasicAuthUsername")
            try await persistSecretIfProvided(basicPassword, key: "httpBasicAuthPassword")
            try await persistSecretIfProvided(apiAccessKey, key: "apiAccessKey")
            try await persistSecretIfProvided(apiSecretKey, key: "apiSecretKey")
        case .none:
            try await removeSecrets(["apiToken", "httpBasicAuthUsername", "httpBasicAuthPassword", "apiAccessKey", "apiSecretKey"])
        case .bearerToken:
            try await persistSecretIfProvided(apiToken, key: "apiToken")
            try await removeSecrets(["httpBasicAuthUsername", "httpBasicAuthPassword", "apiAccessKey", "apiSecretKey"])
        case .basic:
            try await persistSecretIfProvided(basicUsername, key: "httpBasicAuthUsername")
            try await persistSecretIfProvided(basicPassword, key: "httpBasicAuthPassword")
            try await removeSecrets(["apiToken", "apiAccessKey", "apiSecretKey"])
        case .apiKeys:
            try await persistSecretIfProvided(apiAccessKey, key: "apiAccessKey")
            try await persistSecretIfProvided(apiSecretKey, key: "apiSecretKey")
            try await removeSecrets(["apiToken", "httpBasicAuthUsername", "httpBasicAuthPassword"])
        }

        if mode == .automatic || usesCloudflareAccess {
            try await persistSecretIfProvided(cloudflareClientID, key: "cloudflareAccessClientID")
            try await persistSecretIfProvided(cloudflareClientSecret, key: "cloudflareAccessClientSecret")
        } else {
            try await removeSecrets(["cloudflareAccessClientID", "cloudflareAccessClientSecret"])
        }
    }

    private func removeSecrets(_ keys: [String]) async throws {
        for key in keys {
            try await secretStore.remove(key)
        }
    }

    private static func serverKey(_ rawURL: String) -> String? {
        let value = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme != nil, url.host != nil else { return nil }
        return TeslaMateServerIdentity.key(for: url)
    }

    nonisolated private static func mergeFormSettings(
        _ formSettings: AppSettings,
        into current: AppSettings
    ) -> AppSettings {
        var merged = current
        merged.serverURL = formSettings.serverURL
        merged.secondaryServerURL = formSettings.secondaryServerURL
        merged.authenticationMode = formSettings.authenticationMode
        merged.usesCloudflareAccess = formSettings.usesCloudflareAccess
        merged.acceptInvalidCerts = formSettings.acceptInvalidCerts
        merged.currencyCode = formSettings.currencyCode
        merged.displayUnitSystem = formSettings.displayUnitSystem
        merged.appLanguage = formSettings.appLanguage
        merged.batteryReferenceRangeKm = formSettings.batteryReferenceRangeKm
        merged.batteryRecordingStartOdometerKm = formSettings.batteryRecordingStartOdometerKm
        if let carId = formSettings.lastSelectedCarId {
            merged.setBatteryCalibration(formSettings.batteryCalibration(for: carId), for: carId)
        }
        return merged
    }

    @discardableResult
    private func updateSettingsAtomically(
        _ transform: @escaping @Sendable (AppSettings) -> AppSettings
    ) async -> Bool {
        settingsMutationGeneration &+= 1
        let mutationGeneration = settingsMutationGeneration
        do {
            if let atomicSettingsStore = settingsStore as? any AtomicSettingsUpdating {
                _ = try await atomicSettingsStore.updateAtomically(transform)
            } else {
                let updated = transform(await settingsStore.load())
                try await settingsStore.saveThrowing(updated)
            }
            let latest = await settingsStore.load()
            if mutationGeneration == settingsMutationGeneration {
                settings = latest
            }
            return true
        } catch {
            let latest = await settingsStore.load()
            if mutationGeneration == settingsMutationGeneration {
                settings = latest
            }
            return false
        }
    }

    private func recordSettingsUpdateFailure() {
        saveErrorMessage = localized(
            "Could not save settings. Try again.",
            "无法保存设置，请重试。"
        )
    }
}
