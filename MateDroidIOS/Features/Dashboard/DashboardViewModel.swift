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

    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        self.apiFactory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
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
    public var softwareVersion: String?
    public var tpmsDetails: TpmsDetails?
    public var carImagePath: String?
    public var carImageScaleFactor: Double
    public var exteriorColor: String?
    public var wheelType: String?
    public var trimBadging: String?
    public var units: UnitPreferences?
    public var totalCharges: Int?
    public var totalDrives: Int?
    public var totalUpdates: Int?
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
        softwareVersion: String? = nil,
        tpmsDetails: TpmsDetails? = nil,
        carImagePath: String? = nil,
        carImageScaleFactor: Double = 1.0,
        exteriorColor: String? = nil,
        wheelType: String? = nil,
        trimBadging: String? = nil,
        units: UnitPreferences? = nil,
        totalCharges: Int? = nil,
        totalDrives: Int? = nil,
        totalUpdates: Int? = nil,
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
        self.softwareVersion = softwareVersion
        self.tpmsDetails = tpmsDetails
        self.carImagePath = carImagePath
        self.carImageScaleFactor = carImageScaleFactor
        self.exteriorColor = exteriorColor
        self.wheelType = wheelType
        self.trimBadging = trimBadging
        self.units = units
        self.totalCharges = totalCharges
        self.totalDrives = totalDrives
        self.totalUpdates = totalUpdates
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
    private let dashboardSnapshotStore: any DashboardSnapshotStoring
    private let notificationService: any AppNotificationServicing
    private let sentryAlertStore: any SentryAlertLogStoring
    private let locationResolver: (any DashboardLocationResolving)?
    private let now: @Sendable () -> Date
    private var loadedCars: [CarData] = []
    private var serverURL = ""

    public init(
        api: any DashboardAPIProviding,
        settingsStore: any SettingsStoring,
        widgetSnapshotStore: WidgetSnapshotStore = .shared,
        dashboardSnapshotStore: any DashboardSnapshotStoring = DashboardSnapshotStore.shared,
        notificationService: any AppNotificationServicing = DisabledAppNotificationService(),
        sentryAlertStore: any SentryAlertLogStoring = EmptySentryAlertLogStore(),
        locationResolver: (any DashboardLocationResolving)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        initialState: DashboardState = DashboardState()
    ) {
        self.api = api
        self.settingsStore = settingsStore
        self.widgetSnapshotStore = widgetSnapshotStore
        self.dashboardSnapshotStore = dashboardSnapshotStore
        self.notificationService = notificationService
        self.sentryAlertStore = sentryAlertStore
        self.locationResolver = locationResolver
        self.now = now
        self.state = initialState
    }

    public func load() async {
        state.isLoading = true
        state.errorMessage = nil

        let settings = await settingsStore.load()
        serverURL = settings.serverURL
        switch await api.cars() {
        case let .success(cars):
            loadedCars = cars
            let selectedCar = selectInitialCar(from: cars, lastSelectedCarId: settings.lastSelectedCarId)
            let options = cars.map { DashboardCarOption(id: $0.carId, name: $0.dashboardDisplayName) }
            if let selectedCar {
                apply(car: selectedCar, options: options, isLoading: false)
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
            if let carId = settings.lastSelectedCarId,
               let snapshot = await dashboardSnapshotStore.load(serverURL: serverURL, carId: carId, now: Date()) {
                state = snapshot.state(errorMessage: error.dashboardMessage)
            } else {
                state.isLoading = false
                state.errorMessage = error.dashboardMessage
            }
        }
    }

    public func refresh() async {
        guard let car = currentCar else {
            await load()
            return
        }

        state.isRefreshing = true
        state.errorMessage = nil
        await loadStatus(for: car)
        state.isRefreshing = false
    }

    public func selectCar(id carId: Int) async {
        guard let car = loadedCars.first(where: { $0.carId == carId }) else {
            return
        }

        let options = loadedCars.map { DashboardCarOption(id: $0.carId, name: $0.dashboardDisplayName) }
        apply(car: car, options: options, isLoading: false)
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

    private func apply(car: CarData, options: [DashboardCarOption], isLoading: Bool) {
        let imagePath = CarImageResolver.assetPath(
            model: car.carDetails?.model,
            exteriorColor: car.carExterior?.exteriorColor,
            wheelType: car.carExterior?.wheelType,
            trimBadging: car.carDetails?.trimBadging
        )
        let imageScale = CarImageResolver.scaleFactor(
            model: car.carDetails?.model,
            exteriorColor: car.carExterior?.exteriorColor,
            wheelType: car.carExterior?.wheelType,
            trimBadging: car.carDetails?.trimBadging
        )

        state = DashboardState(
            isLoading: isLoading,
            cars: options,
            selectedCarId: car.carId,
            carName: car.dashboardPrimaryName,
            vehicleModelName: car.vehicleModelDescription,
            carImagePath: imagePath,
            carImageScaleFactor: Double(imageScale),
            exteriorColor: car.carExterior?.exteriorColor,
            wheelType: car.carExterior?.wheelType,
            trimBadging: car.carDetails?.trimBadging,
            totalCharges: car.teslamateStats?.totalCharges,
            totalDrives: car.teslamateStats?.totalDrives,
            totalUpdates: car.teslamateStats?.totalUpdates
        )
    }

    private func loadStatus(for car: CarData) async {
        switch await api.carStatus(carId: car.carId) {
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
            state.sentryModeActive = status?.sentryMode ?? false
            state.outsideTemperature = status?.outsideTemp
            state.insideTemperature = status?.insideTemp
            state.ratedRange = status?.ratedBatteryRangeKm
            state.odometer = status?.odometer
            let resolvedAddress = await resolveAddress(status: status, carId: car.carId)
            state.locationText = resolvedAddress ?? status?.locationSummary
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
            let settings = await settingsStore.load()
            await deliverStatusNotifications(status: status, carId: car.carId, resolvedAddress: resolvedAddress, settings: settings)
            if let snapshot = DashboardSnapshot(state: state) {
                await dashboardSnapshotStore.save(snapshot, serverURL: settings.serverURL)
            }
            widgetSnapshotStore.save(WidgetDisplayData(
                dashboardState: state,
                language: settings.appLanguage,
                displayUnitSystem: settings.displayUnitSystem
            ))
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetConstants.carStatusKind)

        case let .failure(error):
            if let snapshot = await dashboardSnapshotStore.load(serverURL: serverURL, carId: car.carId, now: Date()) {
                state = snapshot.state(errorMessage: error.dashboardMessage)
            } else {
                state.errorMessage = error.dashboardMessage
            }
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
                        pressure: MateDroidUnitFormatter.pressureValue(warning.pressure, units: displayUnits),
                        unit: MateDroidUnitFormatter.pressureUnit(units: displayUnits),
                        threshold: MateDroidUnitFormatter.pressureValue(2.4, units: displayUnits),
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
        case .german, .spanish, .italian, .catalan:
            self = .english
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
            carImageName: state.carImagePath,
            isReadOnly: true,
            displayLanguage: WidgetDisplayLanguage(appLanguage: language),
            displayUnitSystem: WidgetDisplayUnitSystem(units: state.units, displayUnitSystem: displayUnitSystem)
        )
    }
}
