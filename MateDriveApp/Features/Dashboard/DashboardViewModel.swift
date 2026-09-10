import Combine
import Foundation
import WidgetKit

public protocol DashboardAPIProviding: Sendable {
    func cars() async -> APIResult<[CarData]>
    func carStatus(carId: Int) async -> APIResult<CarStatusPayload>
}

extension TeslamateAPI: DashboardAPIProviding {}

public struct SettingsBackedDashboardAPI: DashboardAPIProviding {
    private let apiFactory: SettingsBackedTeslamateAPIFactory

    public init(
        settingsStore: any SettingsStoring,
        secretStore: any SecretStoring,
        networkPolicy: APIRequestNetworkPolicy = .online
    ) {
        self.apiFactory = SettingsBackedTeslamateAPIFactory(
            settingsStore: settingsStore,
            secretStore: secretStore,
            networkPolicy: networkPolicy
        )
    }

    public func cars() async -> APIResult<[CarData]> {
        await apiFactory.request { api in
            await api.cars()
        }
    }

    public func carStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        await apiFactory.request { api in
            await api.carStatus(carId: carId)
        }
    }
}

public struct DashboardCarOption: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DashboardState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var cars: [DashboardCarOption]
    public var selectedCarId: Int?
    public var carName: String
    public var vehicleModelName: String?
    public var batteryLevel: Int?
    public var isCharging: Bool
    public var isLocked: Bool?
    public var sentryModeActive: Bool
    public var outsideTemperature: Double?
    public var insideTemperature: Double?
    public var ratedRange: Double?
    public var odometer: Double?
    public var locationText: String?
    public var latitude: Double?
    public var longitude: Double?
    public var currentGeofence: GeofenceRule?
    public var softwareVersion: String?
    public var tpmsDetails: TpmsDetails?
    public var exteriorColor: String?
    public var wheelType: String?
    public var trimBadging: String?
    public var units: UnitPreferences?
    public var currencyCode: String
    public var totalCharges: Int?
    public var totalDrives: Int?
    public var totalUpdates: Int?
    public var vehicleState: String?
    public var vehicleStateSince: Date?
    public var currentSleepDuration: TimeInterval?
    public var latestDrive: DashboardLatestDrive?
    public var latestCharge: DashboardLatestCharge?
    public var sleepSummaries: [SleepDurationPeriod: SleepDurationSummary]
    public var errorMessage: String?
    public var isUsingCachedData: Bool
    public var cachedAt: Date?

    public init(
        isLoading: Bool = true,
        isRefreshing: Bool = false,
        cars: [DashboardCarOption] = [],
        selectedCarId: Int? = nil,
        carName: String = "Tesla",
        vehicleModelName: String? = nil,
        batteryLevel: Int? = nil,
        isCharging: Bool = false,
        isLocked: Bool? = nil,
        sentryModeActive: Bool = false,
        outsideTemperature: Double? = nil,
        insideTemperature: Double? = nil,
        ratedRange: Double? = nil,
        odometer: Double? = nil,
        locationText: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        currentGeofence: GeofenceRule? = nil,
        softwareVersion: String? = nil,
        tpmsDetails: TpmsDetails? = nil,
        exteriorColor: String? = nil,
        wheelType: String? = nil,
        trimBadging: String? = nil,
        units: UnitPreferences? = nil,
        currencyCode: String = MateDriveCurrencyFormatter.systemCurrencyCode(),
        totalCharges: Int? = nil,
        totalDrives: Int? = nil,
        totalUpdates: Int? = nil,
        vehicleState: String? = nil,
        vehicleStateSince: Date? = nil,
        currentSleepDuration: TimeInterval? = nil,
        latestDrive: DashboardLatestDrive? = nil,
        latestCharge: DashboardLatestCharge? = nil,
        sleepSummaries: [SleepDurationPeriod: SleepDurationSummary] = [:],
        errorMessage: String? = nil,
        isUsingCachedData: Bool = false,
        cachedAt: Date? = nil
    ) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.cars = cars
        self.selectedCarId = selectedCarId
        self.carName = carName
        self.vehicleModelName = vehicleModelName
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isLocked = isLocked
        self.sentryModeActive = sentryModeActive
        self.outsideTemperature = outsideTemperature
        self.insideTemperature = insideTemperature
        self.ratedRange = ratedRange
        self.odometer = odometer
        self.locationText = locationText
        self.latitude = latitude
        self.longitude = longitude
        self.currentGeofence = currentGeofence
        self.softwareVersion = softwareVersion
        self.tpmsDetails = tpmsDetails
        self.exteriorColor = exteriorColor
        self.wheelType = wheelType
        self.trimBadging = trimBadging
        self.units = units
        self.currencyCode = currencyCode
        self.totalCharges = totalCharges
        self.totalDrives = totalDrives
        self.totalUpdates = totalUpdates
        self.vehicleState = vehicleState
        self.vehicleStateSince = vehicleStateSince
        self.currentSleepDuration = currentSleepDuration
        self.latestDrive = latestDrive
        self.latestCharge = latestCharge
        self.sleepSummaries = sleepSummaries
        self.errorMessage = errorMessage
        self.isUsingCachedData = isUsingCachedData
        self.cachedAt = cachedAt
    }

}

@MainActor
public final class DashboardViewModel: ObservableObject {
    @Published public private(set) var state: DashboardState

    private let api: any DashboardAPIProviding
    private let settingsStore: any SettingsStoring
    private let widgetSnapshotStore: WidgetSnapshotStore
    private let widgetTimelineReloader: any WidgetTimelineReloading
    private let liveActivityCoordinator: ChargeLiveActivityCoordinator
    private let liveActivityActivationPolicy: ChargeLiveActivityActivationPolicy
    private let dashboardSnapshotStore: any DashboardSnapshotStoring
    private let notificationService: any AppNotificationServicing
    private let sentryAlertStore: any SentryAlertLogStoring
    private let summaryProvider: any DashboardSummaryProviding
    private let locationResolver: (any DashboardLocationResolving)?
    private let now: @Sendable () -> Date
    private var loadedCars: [CarData] = []
    private var serverURL = ""

    public init(
        api: any DashboardAPIProviding,
        settingsStore: any SettingsStoring,
        widgetSnapshotStore: WidgetSnapshotStore = .shared,
        widgetTimelineReloader: any WidgetTimelineReloading = SystemWidgetTimelineReloader(),
        liveActivityCoordinator: ChargeLiveActivityCoordinator = .disabled,
        liveActivityActivationPolicy: ChargeLiveActivityActivationPolicy = .existingOnly,
        dashboardSnapshotStore: any DashboardSnapshotStoring = DashboardSnapshotStore.shared,
        notificationService: any AppNotificationServicing = DisabledAppNotificationService(),
        sentryAlertStore: any SentryAlertLogStoring = EmptySentryAlertLogStore(),
        summaryProvider: any DashboardSummaryProviding = EmptyDashboardSummaryProvider(),
        locationResolver: (any DashboardLocationResolving)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        initialState: DashboardState = DashboardState()
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.widgetSnapshotStore = widgetSnapshotStore
        self.widgetTimelineReloader = widgetTimelineReloader
        self.liveActivityCoordinator = liveActivityCoordinator
        self.liveActivityActivationPolicy = liveActivityActivationPolicy
        self.dashboardSnapshotStore = dashboardSnapshotStore
        self.notificationService = notificationService
        self.sentryAlertStore = sentryAlertStore
        self.summaryProvider = summaryProvider
        self.locationResolver = locationResolver
        self.now = now
        self.state = initialState
    }

    public func load() async {
        state.isLoading = true
        state.errorMessage = nil

        let settings = await settingsStore.load()
        serverURL = settings.serverURL
        state.currencyCode = settings.resolvedCurrencyCode()
        if let carId = settings.lastSelectedCarId {
            state.selectedCarId = carId
            await loadCachedSummary(for: carId)
        }
        switch await api.cars() {
        case let .success(cars):
            loadedCars = cars
            let selectedCar = selectInitialCar(from: cars, lastSelectedCarId: settings.lastSelectedCarId)
            let options = cars.map { DashboardCarOption(id: $0.carId, name: $0.dashboardDisplayName) }
            if let selectedCar {
                apply(car: selectedCar, options: options, settings: settings, isLoading: false)
                await loadCachedSummary(for: selectedCar.carId)
                if settings.lastSelectedCarId != selectedCar.carId {
                    await saveSelectedCarId(selectedCar.carId)
                }
                await loadStatus(for: selectedCar)
            } else {
                state = DashboardState(
                    isLoading: false,
                    cars: options,
                    carName: "Tesla",
                    errorMessage: "No TeslaMate cars were returned."
                )
            }

        case let .failure(error):
            guard error != .cancelled else {
                state.isLoading = false
                return
            }
            if let carId = settings.lastSelectedCarId,
               let snapshot = await dashboardSnapshotStore.load(serverURL: serverURL, carId: carId, now: now()) {
                state = snapshot.state(errorMessage: error.dashboardMessage, now: now())
                await loadCachedSummary(for: carId)
            } else {
                state.isLoading = false
                state.errorMessage = error.dashboardMessage
            }
        }
    }

    public func resetForServerChange() {
        loadedCars = []
        serverURL = ""
        state = DashboardState()
    }

    public func refresh() async {
        guard let car = currentCar else {
            await load()
            return
        }

        state.isRefreshing = true
        state.errorMessage = nil
        await loadCachedSummary(for: car.carId)
        await loadStatus(for: car)
        state.isRefreshing = false
    }

    public func selectCar(id carId: Int) async {
        guard let car = loadedCars.first(where: { $0.carId == carId }) else {
            return
        }

        let options = loadedCars.map { DashboardCarOption(id: $0.carId, name: $0.dashboardDisplayName) }
        let settings = await settingsStore.load()
        apply(car: car, options: options, settings: settings, isLoading: false)
        await loadCachedSummary(for: carId)
        await saveSelectedCarId(carId)
        await loadStatus(for: car)
    }

    private var currentCar: CarData? {
        guard let selectedCarId = state.selectedCarId else {
            return nil
        }
        return loadedCars.first { $0.carId == selectedCarId }
    }

    private func selectInitialCar(from cars: [CarData], lastSelectedCarId: Int?) -> CarData? {
        if let lastSelectedCarId, let saved = cars.first(where: { $0.carId == lastSelectedCarId }) {
            return saved
        }
        return cars.first
    }

    private func apply(car: CarData, options: [DashboardCarOption], settings: AppSettings, isLoading: Bool) {
        state = DashboardState(
            isLoading: isLoading,
            cars: options,
            selectedCarId: car.carId,
            carName: car.dashboardPrimaryName,
            vehicleModelName: car.vehicleModelDescription,
            exteriorColor: car.carExterior?.exteriorColor,
            wheelType: car.carExterior?.wheelType,
            trimBadging: car.carDetails?.trimBadging,
            currencyCode: settings.resolvedCurrencyCode(),
            totalCharges: car.teslamateStats?.totalCharges,
            totalDrives: car.teslamateStats?.totalDrives,
            totalUpdates: car.teslamateStats?.totalUpdates
        )
    }

    private func loadCachedSummary(for carId: Int) async {
        guard let summary = try? await summaryProvider.summary(carId: carId) else { return }
        state.latestDrive = summary.latestDrive
        state.latestCharge = summary.latestCharge
        state.sleepSummaries = summary.sleepSummaries
        if let completedDriveCount = summary.completedDriveCount {
            state.totalDrives = completedDriveCount
        }
        if let completedChargeCount = summary.completedChargeCount {
            state.totalCharges = completedChargeCount
        }
        if state.odometer == nil {
            state.odometer = summary.odometerKm
        }
        state.currentSleepDuration = SleepDurationCalculator.currentDuration(
            state: state.vehicleState,
            stateSince: state.vehicleStateSince,
            now: now()
        )
    }

    private func loadStatus(for car: CarData) async {
        let statusResult = await api.carStatus(carId: car.carId)
        switch statusResult {
        case let .success(payload):
            let status = payload.status
            state.carName = Self.resolvedCarName(
                statusName: status?.displayName,
                fallback: car.dashboardPrimaryName,
                modelName: car.vehicleModelDescription
            )
            state.batteryLevel = status?.batteryLevel
            state.isCharging = status?.isCharging ?? false
            state.isLocked = status?.locked
            state.vehicleState = status?.state
            state.vehicleStateSince = status?.stateSince.flatMap(DomainDateParser.date(from:))
            state.currentSleepDuration = SleepDurationCalculator.currentDuration(
                state: state.vehicleState,
                stateSince: state.vehicleStateSince,
                now: now()
            )
            state.sentryModeActive = status?.sentryMode ?? false
            state.outsideTemperature = status?.outsideTemp
            state.insideTemperature = status?.insideTemp
            state.ratedRange = status?.ratedBatteryRangeKm
            state.odometer = status?.odometer
            let settings = await settingsStore.load()
            let currentGeofence = GeofenceRuleEngine.matchingRule(
                latitude: status?.latitude,
                longitude: status?.longitude,
                carId: car.carId,
                rules: settings.geofenceRules
            )
            let resolvedAddress = await resolveAddress(status: status, carId: car.carId)
            state.locationText = currentGeofence?.name ?? resolvedAddress ?? status?.locationSummary
            state.latitude = status?.latitude
            state.longitude = status?.longitude
            state.softwareVersion = status?.version
            state.tpmsDetails = status?.tpmsDetails
            state.units = UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            )
            state.errorMessage = nil
            state.isUsingCachedData = false
            state.cachedAt = nil
            state.currentGeofence = currentGeofence
            await deliverStatusNotifications(status: status, carId: car.carId, resolvedAddress: resolvedAddress, settings: settings)
            if let snapshot = DashboardSnapshot(state: state, savedAt: now()) {
                await dashboardSnapshotStore.save(snapshot, serverURL: settings.serverURL)
            }
            await publishWidgetObservation(
                statusResult: statusResult,
                carId: car.carId,
                settings: settings,
                dashboardDataChanged: true
            )

        case let .failure(error):
            guard error != .cancelled else { return }
            if let snapshot = await dashboardSnapshotStore.load(serverURL: serverURL, carId: car.carId, now: now()) {
                state = snapshot.state(errorMessage: error.dashboardMessage, now: now())
                await loadCachedSummary(for: car.carId)
            } else {
                state.errorMessage = error.dashboardMessage
            }
            let settings = await settingsStore.load()
            await publishWidgetObservation(
                statusResult: statusResult,
                carId: car.carId,
                settings: settings,
                dashboardDataChanged: false
            )
        }
    }

    private func deliverStatusNotifications(status: CarStatus?, carId: Int, resolvedAddress: String?, settings: AppSettings) async {
        guard let status else { return }
        var updated = settings
        let canDeliver = await notificationService.authorizationStatus().canDeliver
        await captureSentryAlert(status: status, carId: carId, resolvedAddress: resolvedAddress, canDeliver: canDeliver, settings: &updated)

        guard canDeliver else {
            if updated.notificationEventSignatures != settings.notificationEventSignatures {
                await settingsStore.save(updated)
            }
            return
        }
        let chargingKey = "\(carId):charging"
        if status.isCharging {
            let level = status.batteryLevel ?? -1
            let bucket = level >= 0 ? level / 5 : -1
            let signature = "\(bucket):\(status.chargeLimitSoc ?? -1)"
            if updated.notificationEventSignatures[chargingKey] != signature {
                do {
                    try await notificationService.deliverCharging(
                        carName: state.carName,
                        chargerPowerKW: Double(status.chargerPower ?? 0),
                        isDC: status.isDcCharging,
                        batteryLevel: status.batteryLevel,
                        chargeLimit: status.chargeLimitSoc,
                        identifier: "matedrive.\(carId).charging"
                    )
                    updated.notificationEventSignatures[chargingKey] = signature
                } catch {}
            }
        } else {
            updated.notificationEventSignatures.removeValue(forKey: chargingKey)
        }

        let tyreKey = "\(carId):tyres"
        let warnings = Self.tyreWarnings(status.tpmsDetails)
        let signature = warnings.map(\.name).joined(separator: ",")
        if !warnings.isEmpty, updated.notificationEventSignatures[tyreKey] != signature {
            let displayUnits = state.units.resolved(for: settings.displayUnitSystem)
            var deliveredAll = true
            for warning in warnings {
                do {
                    try await notificationService.deliverTyrePressure(
                        carName: state.carName,
                        tyreName: warning.name,
                        pressure: MateDriveUnitFormatter.pressureValue(warning.pressure, units: displayUnits),
                        unit: MateDriveUnitFormatter.pressureUnit(units: displayUnits),
                        threshold: MateDriveUnitFormatter.pressureValue(2.4, units: displayUnits),
                        identifier: "matedrive.\(carId).tyre.\(warning.name)"
                    )
                } catch {
                    deliveredAll = false
                }
            }
            if deliveredAll { updated.notificationEventSignatures[tyreKey] = signature }
        } else if warnings.isEmpty {
            updated.notificationEventSignatures.removeValue(forKey: tyreKey)
        }
        if updated.notificationEventSignatures != settings.notificationEventSignatures {
            await settingsStore.save(updated)
        }
    }

    private func publishWidgetObservation(
        statusResult: APIResult<CarStatusPayload>,
        carId: Int,
        settings: AppSettings,
        dashboardDataChanged: Bool
    ) async {
        guard let vehicleIdentifier = WidgetVehicleIdentity.identifier(
            serverURL: settings.serverURL,
            carID: carId
        ) else { return }

        let previousSnapshot = widgetSnapshotStore.vehicleSnapshot(
            vehicleIdentifier: vehicleIdentifier
        )
        let previousCurrentCharge = previousSnapshot?.currentCharge
        let currentCharge = WidgetCurrentChargeSnapshotBuilder.build(
            statusResult: statusResult,
            currentChargeResult: nil,
            previous: previousCurrentCharge,
            now: now()
        )

        if dashboardDataChanged {
            let data = WidgetDisplayData(
                dashboardState: state,
                language: settings.appLanguage,
                displayUnitSystem: settings.displayUnitSystem
            )
            widgetSnapshotStore.save(data, vehicleIdentifier: vehicleIdentifier)
            if previousSnapshot?.data != data {
                await widgetTimelineReloader.reloadTimelines(
                    ofKind: WidgetConstants.carStatusKind
                )
            }
        }

        if let currentCharge {
            let didChange = widgetSnapshotStore.updateCurrentCharge(
                currentCharge,
                vehicleIdentifier: vehicleIdentifier
            )
            if didChange {
                await widgetTimelineReloader.reloadTimelines(
                    ofKind: WidgetConstants.currentChargeKind
                )
            }
        }

        await liveActivityCoordinator.reconcile(
            carId: carId,
            event: ChargeLiveActivityEventFactory.event(
                currentCharge: currentCharge,
                carName: state.carName,
                vehicleIdentifier: vehicleIdentifier,
                displayLanguage: WidgetDisplayLanguage(appLanguage: settings.appLanguage)
            ),
            policy: liveActivityActivationPolicy
        )
    }

    private func captureSentryAlert(
        status: CarStatus,
        carId: Int,
        resolvedAddress: String?,
        canDeliver: Bool,
        settings: inout AppSettings
    ) async {
        let key = "\(carId):sentry"
        guard status.isSentryAlerted else {
            settings.notificationEventSignatures.removeValue(forKey: key)
            return
        }
        guard settings.notificationEventSignatures[key] == nil else { return }

        let detectedAtMillis = Int64(now().timeIntervalSince1970 * 1_000)
        let record = SentryAlertLogRecord(
            id: "\(carId):\(detectedAtMillis)",
            carId: carId,
            detectedAtMillis: detectedAtMillis,
            latitude: status.latitude,
            longitude: status.longitude,
            address: status.geofence ?? resolvedAddress
        )
        do {
            let previousCount = try await sentryAlertStore.alertLogs(carId: carId).count
            try await sentryAlertStore.upsert(record)
            settings.notificationEventSignatures[key] = "active"
            if canDeliver {
                try? await notificationService.deliverSentry(
                    carName: state.carName,
                    alertCount: previousCount + 1,
                    locationText: status.geofence ?? resolvedAddress ?? status.locationSummary,
                    identifier: "matedrive.\(carId).sentry.\(detectedAtMillis)"
                )
            }
        } catch {}
    }

    private func resolveAddress(status: CarStatus?, carId: Int) async -> String? {
        guard status?.geofence == nil,
              let latitude = status?.latitude,
              let longitude = status?.longitude,
              let locationResolver
        else { return status?.geofence }
        return await locationResolver.address(carId: carId, latitude: latitude, longitude: longitude)
    }

    private static func tyreWarnings(_ details: TpmsDetails?) -> [(name: String, pressure: Double)] {
        guard let details else { return [] }
        return [
            ("Front left", details.pressureFl, details.warningFl),
            ("Front right", details.pressureFr, details.warningFr),
            ("Rear left", details.pressureRl, details.warningRl),
            ("Rear right", details.pressureRr, details.warningRr)
        ].compactMap { name, pressure, warning in
            guard warning == true, let pressure, pressure.isFinite, pressure > 0 else { return nil }
            return (name, pressure)
        }
    }

    private func saveSelectedCarId(_ carId: Int) async {
        var settings = await settingsStore.load()
        settings.lastSelectedCarId = carId
        await settingsStore.save(settings)
    }

    private static func resolvedCarName(statusName: String?, fallback: String, modelName: String?) -> String {
        let trimmed = statusName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty, !CarData.isLegacyAppDisplayName(trimmed) {
            return trimmed
        }
        if !CarData.isLegacyAppDisplayName(fallback) {
            return fallback
        }
        return modelName ?? "Tesla"
    }
}

private extension APIError {
    var dashboardMessage: String {
        switch self {
        case .serverNotConfigured:
            return "Configure your TeslaMate server before loading the dashboard."
        case let .invalidURL(url):
            return "The TeslaMate server URL is invalid: \(url)"
        case let .httpStatus(status):
            return "TeslaMate returned HTTP \(status)."
        case let .sslCertificate(message):
            return "SSL certificate error: \(message)"
        case let .invalidResponse(message):
            return "Invalid TeslaMate response: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        case .cancelled:
            return "Request cancelled."
        case .emptyBody:
            return "TeslaMate returned an empty response."
        }
    }
}

public extension WidgetDisplayLanguage {
    init(appLanguage: AppLanguage) {
        switch appLanguage {
        case .system:
            self = .system
        case .english:
            self = .english
        case .chinese:
            self = .chinese
        case .traditionalChinese:
            self = .traditionalChinese
        }
    }
}

public extension WidgetDisplayUnitSystem {
    init(units: UnitPreferences?, displayUnitSystem: DisplayUnitSystem) {
        let resolved = units.resolved(for: displayUnitSystem)
        self = resolved?.isImperial == true ? .imperial : .metric
    }
}

public extension WidgetDisplayData {
    init(dashboardState state: DashboardState, language: AppLanguage, displayUnitSystem: DisplayUnitSystem) {
        self.init(
            carName: state.carName,
            batteryLevel: state.batteryLevel,
            ratedRange: state.ratedRange,
            isCharging: state.isCharging,
            isLocked: state.isLocked,
            sentryModeActive: state.sentryModeActive,
            insideTemperature: state.insideTemperature,
            outsideTemperature: state.outsideTemperature,
            locationText: state.locationText,
            isReadOnly: true,
            displayLanguage: WidgetDisplayLanguage(appLanguage: language),
            displayUnitSystem: WidgetDisplayUnitSystem(units: state.units, displayUnitSystem: displayUnitSystem)
        )
    }
}
