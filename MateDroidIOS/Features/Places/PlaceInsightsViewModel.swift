import Combine
import Foundation

public struct PlaceInsight: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let latitude: Double?
    public let longitude: Double?
    public let departureCount: Int
    public let arrivalCount: Int
    public let chargeCount: Int
    public let parkingCount: Int
    public let chargedEnergyKWh: Double
    public let parkingMinutes: Double
    public let parkingCost: Double
    public let lastVisitedAt: Date?
    public let firstVisitedAt: Date?
    public let visitCount: Int?
    public let activeDays: Int?
    public let role: String?
    public let roleConfidence: String?
    public let radiusMeters: Double?
    public let driveDistanceKm: Double?
    public let driveMinutes: Double?
    public let chargeCost: Double?
    public let missingChargeCostCount: Int?
    public let longestParkingMinutes: Double?
    public let parkingRangeLossKm: Double?
    public let parkingCostAvailable: Bool
    public let chargedEnergyAvailable: Bool
    public let parkingMinutesAvailable: Bool

    public init(
        id: String, name: String, latitude: Double?, longitude: Double?, departureCount: Int,
        arrivalCount: Int, chargeCount: Int, parkingCount: Int, chargedEnergyKWh: Double,
        parkingMinutes: Double, parkingCost: Double, lastVisitedAt: Date?, firstVisitedAt: Date? = nil,
        visitCount: Int? = nil, activeDays: Int? = nil, role: String? = nil, roleConfidence: String? = nil,
        radiusMeters: Double? = nil, driveDistanceKm: Double? = nil, driveMinutes: Double? = nil,
        chargeCost: Double? = nil, missingChargeCostCount: Int? = nil, longestParkingMinutes: Double? = nil,
        parkingRangeLossKm: Double? = nil, parkingCostAvailable: Bool = true,
        chargedEnergyAvailable: Bool = true, parkingMinutesAvailable: Bool = true
    ) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.departureCount = departureCount; self.arrivalCount = arrivalCount; self.chargeCount = chargeCount
        self.parkingCount = parkingCount; self.chargedEnergyKWh = chargedEnergyKWh; self.parkingMinutes = parkingMinutes
        self.parkingCost = parkingCost; self.lastVisitedAt = lastVisitedAt; self.firstVisitedAt = firstVisitedAt
        self.visitCount = visitCount; self.activeDays = activeDays; self.role = role; self.roleConfidence = roleConfidence
        self.radiusMeters = radiusMeters; self.driveDistanceKm = driveDistanceKm; self.driveMinutes = driveMinutes
        self.chargeCost = chargeCost; self.missingChargeCostCount = missingChargeCostCount
        self.longestParkingMinutes = longestParkingMinutes; self.parkingRangeLossKm = parkingRangeLossKm
        self.parkingCostAvailable = parkingCostAvailable
        self.chargedEnergyAvailable = chargedEnergyAvailable; self.parkingMinutesAvailable = parkingMinutesAvailable
    }

    public var totalEvents: Int { departureCount + arrivalCount + chargeCount + parkingCount }

    public var pricedChargeCount: Int? {
        missingChargeCostCount.map { max(chargeCount - $0, 0) }
    }

    public var chargeCostIsComplete: Bool? {
        missingChargeCostCount.map { $0 == 0 }
    }
}

public struct PlaceInsightsState: Equatable, Sendable {
    public var isLoading = true
    public var errorMessage: String?
    public var places: [PlaceInsight] = []
    public var query = ""
    public var activityCount = 0
    public var historyFullyLoaded = false
    public var historyLoadCapped = false
    public var currencyCode = MateDroidCurrencyFormatter.systemCurrencyCode()
    public var usesServerPlaces = false
    public var serverRecordCount: Int?
    public var serverUnits: TeslaMateServerStatsUnits?

    public init() {}
}

@MainActor
public final class PlaceInsightsViewModel: ObservableObject {
    @Published public private(set) var state: PlaceInsightsState

    private let api: any ActivityAPIProviding
    private let settingsStore: (any SettingsStoring)?
    private let placesAPI: (any ServerPlacesAPIProviding)?

    public init(api: any ActivityAPIProviding, placesAPI: (any ServerPlacesAPIProviding)? = nil, settingsStore: (any SettingsStoring)? = nil, initialState: PlaceInsightsState = PlaceInsightsState()) {
        self.api = api
        self.placesAPI = placesAPI
        self.settingsStore = settingsStore
        state = initialState
    }

    public var filteredPlaces: [PlaceInsight] {
        let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.places }
        return state.places.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public func setQuery(_ query: String) {
        state.query = query
    }

    public func load(carId: Int) async {
        state.isLoading = true
        state.errorMessage = nil
        if let placesAPI, let serverResult = await loadServerPlaces(carId: carId, api: placesAPI), !serverResult.places.isEmpty {
            let settings = await settingsStore?.load()
            state.currencyCode = settings?.resolvedCurrencyCode() ?? MateDroidCurrencyFormatter.systemCurrencyCode()
            state.places = serverResult.places.map(Self.mapServerPlace).sorted { ($0.visitCount ?? 0) > ($1.visitCount ?? 0) }
            state.activityCount = 0
            state.historyFullyLoaded = true
            state.historyLoadCapped = false
            state.usesServerPlaces = true
            state.serverRecordCount = serverResult.places.count
            state.serverUnits = serverResult.units
            state.isLoading = false
            return
        }
        state.usesServerPlaces = false
        state.serverRecordCount = nil
        state.serverUnits = nil
        let activities = ActivitiesViewModel(api: api)
        await activities.load(carId: carId)
        if activities.state.hasMore {
            await activities.loadCompleteHistory()
        }
        if let error = activities.state.errorMessage, activities.state.items.isEmpty {
            state.errorMessage = error
            state.places = []
        } else {
            let settings = await settingsStore?.load()
            state.currencyCode = settings?.resolvedCurrencyCode() ?? MateDroidCurrencyFormatter.systemCurrencyCode()
            state.places = Self.aggregate(activities.state.items, parkingFeeRules: settings?.parkingFeeRules ?? [])
        }
        state.activityCount = activities.state.items.count
        state.historyFullyLoaded = activities.state.historyFullyLoaded
        state.historyLoadCapped = activities.state.historyLoadCapped
        state.isLoading = false
    }

    private func loadServerPlaces(carId: Int, api: any ServerPlacesAPIProviding) async -> (places: [ServerPlace], units: TeslaMateServerStatsUnits?)? {
        var page = 1
        var all: [ServerPlace] = []
        var units: TeslaMateServerStatsUnits?
        while page <= 100 {
            switch await api.places(carId: carId, page: page, show: 100) {
            case let .success(response):
                all.append(contentsOf: response.data)
                units = response.units ?? units
                let totalPages = max(response.pagination?.totalPages ?? page, page)
                if page >= totalPages { return (all, units) }
                page += 1
            case .failure:
                return nil
            }
        }
        return nil
    }

    nonisolated private static func mapServerPlace(_ place: ServerPlace) -> PlaceInsight {
        PlaceInsight(
            id: "server-\(place.id)", name: place.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Place \(place.id)",
            latitude: place.latitude, longitude: place.longitude, departureCount: place.driveStartCount ?? 0,
            arrivalCount: place.driveEndCount ?? 0, chargeCount: place.chargeCount ?? 0, parkingCount: place.parkCount ?? 0,
            chargedEnergyKWh: place.totalChargeKwh ?? 0, parkingMinutes: place.totalParkingDurationMin ?? 0,
            parkingCost: 0, lastVisitedAt: place.lastSeen.flatMap(DomainDateParser.date(from:)),
            firstVisitedAt: place.firstSeen.flatMap(DomainDateParser.date(from:)), visitCount: place.visitCount,
            activeDays: place.activeDays, role: place.role, roleConfidence: place.roleConfidence,
            radiusMeters: place.radiusMeters, driveDistanceKm: place.totalDriveDistanceKm,
            driveMinutes: place.totalDriveDurationMin, chargeCost: place.totalChargeCost,
            missingChargeCostCount: place.missingChargeCostCount, longestParkingMinutes: place.longestParkingDurationMin,
            parkingRangeLossKm: place.parkingRangeLossKm, parkingCostAvailable: false,
            chargedEnergyAvailable: place.totalChargeKwh != nil, parkingMinutesAvailable: place.totalParkingDurationMin != nil
        )
    }

    nonisolated public static func aggregate(_ activities: [TeslaMateActivity], parkingFeeRules: [ParkingFeeRule] = []) -> [PlaceInsight] {
        struct Accumulator {
            var name: String
            var latitude: Double? = nil
            var longitude: Double? = nil
            var departures = 0
            var arrivals = 0
            var charges = 0
            var parking = 0
            var chargedEnergy = 0.0
            var knownChargeCost = 0.0
            var pricedCharges = 0
            var parkingMinutes = 0.0
            var parkingInputs: [ParkingFeeInput] = []
            var lastVisited: Date?
        }

        var values: [String: Accumulator] = [:]
        func add(
            address: String?, latitude: Double?, longitude: Double?, date: String?,
            departure: Int = 0, arrival: Int = 0, charge: Int = 0, parking: Int = 0,
            energy: Double = 0, chargeCost: Double? = nil, parkedMinutes: Double = 0
        ) {
            guard let raw = address?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
            let key = raw.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            var value = values[key] ?? Accumulator(name: raw)
            if GeoCoordinateValidator.location(latitude: latitude, longitude: longitude) != nil {
                value.latitude = latitude
                value.longitude = longitude
            }
            value.departures += departure
            value.arrivals += arrival
            value.charges += charge
            value.parking += parking
            value.chargedEnergy += max(energy, 0)
            if charge > 0, let chargeCost {
                value.knownChargeCost += max(chargeCost, 0)
                value.pricedCharges += 1
            }
            value.parkingMinutes += max(parkedMinutes, 0)
            if parking > 0 {
                value.parkingInputs.append(ParkingFeeInput(startDate: date, address: raw, latitude: latitude, longitude: longitude, durationMinutes: parkedMinutes))
            }
            if let parsed = date.flatMap(DomainDateParser.date(from:)), parsed > (value.lastVisited ?? .distantPast) {
                value.lastVisited = parsed
            }
            values[key] = value
        }

        for activity in activities {
            switch activity.kind {
            case .drive:
                add(address: activity.startAddress, latitude: activity.startLatitude, longitude: activity.startLongitude, date: activity.startDate, departure: 1)
                add(address: activity.endAddress, latitude: activity.endLatitude, longitude: activity.endLongitude, date: activity.endDate ?? activity.startDate, arrival: 1)
            case .charge:
                add(address: activity.startAddress, latitude: activity.startLatitude, longitude: activity.startLongitude, date: activity.startDate, charge: 1, energy: activity.kwh ?? 0, chargeCost: activity.cost)
            case .park:
                add(address: activity.startAddress, latitude: activity.startLatitude, longitude: activity.startLongitude, date: activity.startDate, parking: 1, parkedMinutes: activity.durationMin ?? 0)
            case .unknown:
                continue
            }
        }

        return values.map { key, value in
            PlaceInsight(
                id: key, name: value.name, latitude: value.latitude, longitude: value.longitude,
                departureCount: value.departures, arrivalCount: value.arrivals,
                chargeCount: value.charges, parkingCount: value.parking,
                chargedEnergyKWh: value.chargedEnergy, parkingMinutes: value.parkingMinutes,
                parkingCost: ParkingFeeRuleEngine.summarize(value.parkingInputs, rules: parkingFeeRules).totalCost,
                lastVisitedAt: value.lastVisited,
                chargeCost: value.pricedCharges > 0 ? value.knownChargeCost : nil,
                missingChargeCostCount: value.charges - value.pricedCharges
            )
        }.sorted {
            if $0.totalEvents != $1.totalEvents { return $0.totalEvents > $1.totalEvents }
            return ($0.lastVisitedAt ?? .distantPast) > ($1.lastVisitedAt ?? .distantPast)
        }
    }
}

public protocol ServerPlacesAPIProviding: Sendable {
    func places(carId: Int, page: Int, show: Int) async -> APIResult<ServerPlacesResponse>
}

extension TeslamateAPI: ServerPlacesAPIProviding {}

public struct SettingsBackedServerPlacesAPI: ServerPlacesAPIProviding {
    private let factory: SettingsBackedTeslamateAPIFactory
    public init(settingsStore: any SettingsStoring, secretStore: any SecretStoring) {
        factory = SettingsBackedTeslamateAPIFactory(settingsStore: settingsStore, secretStore: secretStore)
    }
    public func places(carId: Int, page: Int, show: Int) async -> APIResult<ServerPlacesResponse> {
        await factory.request { await $0.places(carId: carId, page: page, show: show) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
