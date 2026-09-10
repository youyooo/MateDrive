import Combine
import Foundation

public enum RegionSortOrder: String, CaseIterable, Sendable {
    case firstVisit = "First Visit"
    case alphabetical = "A-Z"
    case driveCount = "Drives"
    case distance = "Distance"
    case energy = "Energy"
    case charges = "Charges"
}

public struct RegionVisitRecord: Equatable, Identifiable, Sendable {
    public var id: String { regionName }
    public let regionName: String
    public let firstVisitDate: String
    public let driveCount: Int
    public let chargeCount: Int
    public let totalDistanceKm: Double
    public let totalChargeEnergyKwh: Double
    public let missingDriveDistanceCount: Int
    public let missingChargeEnergyCount: Int
}

public struct RegionsVisitedState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var regions: [RegionVisitRecord]
    public var sortOrder: RegionSortOrder
    public var units: UnitPreferences?
    public var errorMessage: String?
    public var isEnrichingLocations: Bool
    public var enrichmentResult: GeographyEnrichmentResult?

    public init(isLoading: Bool = true, isRefreshing: Bool = false, regions: [RegionVisitRecord] = [], sortOrder: RegionSortOrder = .firstVisit, units: UnitPreferences? = nil, errorMessage: String? = nil, isEnrichingLocations: Bool = false, enrichmentResult: GeographyEnrichmentResult? = nil) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.regions = regions
        self.sortOrder = sortOrder
        self.units = units
        self.errorMessage = errorMessage
        self.isEnrichingLocations = isEnrichingLocations
        self.enrichmentResult = enrichmentResult
    }
}

@MainActor
public final class RegionsVisitedViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<RegionsVisitedState>()

    @Published public private(set) var state: RegionsVisitedState

    private let api: any AnalyticsAPIProviding
    private let geographyEnricher: (any HistoricalGeographyEnriching)?
    private let historyProvider: (any MileageDataProviding)?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<RegionsVisitedState>
    private var originalRegions: [RegionVisitRecord] = []
    private var lastContext: (carId: Int, countryName: String, year: Int?, drives: [DriveData], charges: [ChargeData])?

    public init(
        api: any AnalyticsAPIProviding,
        geographyEnricher: (any HistoricalGeographyEnriching)? = nil,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<RegionsVisitedState>? = nil,
        initialState: RegionsVisitedState = RegionsVisitedState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let restoredState = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
        self.api = api
        self.geographyEnricher = geographyEnricher
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = restoredState
        self.originalRegions = restoredState.regions
    }

    public func load(carId: Int, countryName: String, year: Int?) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.regions.isEmpty
        state.errorMessage = nil
        state.isEnrichingLocations = false
        defer {
            state.isLoading = false
            state.isRefreshing = false
        }
        async let drivesResult = loadDrives(carId: carId)
        async let chargesResult = loadCharges(carId: carId)
        async let unitsResult = loadUnits(carId: carId)

        if case let .success(units) = await unitsResult {
            state.units = units
        }

        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            lastContext = (carId, countryName, year, drives, charges)
            originalRegions = Self.aggregate(
                drives: drives,
                charges: charges,
                countryName: countryName,
                year: year,
                resolvedLocations: state.enrichmentResult?.locations ?? [:]
            )
            applySort()
            saveCachedState()
            guard let geographyEnricher else { return }
            await enrich(context: (carId, countryName, year, drives, charges), enricher: geographyEnricher)
        case let (.failure(error), _), let (_, .failure(error)):
            state.errorMessage = error.analyticsMessage
        }
    }

    private func loadDrives(carId: Int) async -> APIResult<[DriveData]> {
        if let historyProvider {
            return await historyProvider.mileageDrives(carId: carId)
        }
        return await VehicleHistoryPaginator.drives(loadPage: { page, show in
            await self.api.drives(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private func loadCharges(carId: Int) async -> APIResult<[ChargeData]> {
        if let historyProvider {
            return await historyProvider.mileageCharges(carId: carId)
        }
        return await VehicleHistoryPaginator.charges(loadPage: { page, show in
            await self.api.charges(carId: carId, startDate: nil, endDate: nil, page: page, show: show)
        })
    }

    private func loadUnits(carId: Int) async -> APIResult<UnitPreferences?> {
        if let historyProvider {
            return await historyProvider.mileageUnits(carId: carId)
        }
        switch await api.carStatus(carId: carId) {
        case let .success(payload):
            return .success(UnitPreferences(
                unitOfLength: payload.units?.unitOfLength,
                unitOfTemperature: payload.units?.unitOfTemperature,
                unitOfPressure: payload.units?.unitOfPressure
            ))
        case let .failure(error):
            return .failure(error)
        }
    }

    public func retryLocationEnrichment() async {
        guard !state.isEnrichingLocations, let context = lastContext, let geographyEnricher else { return }
        await enrich(context: context, enricher: geographyEnricher)
    }

    private func enrich(
        context: (carId: Int, countryName: String, year: Int?, drives: [DriveData], charges: [ChargeData]),
        enricher: any HistoricalGeographyEnriching
    ) async {
        state.isEnrichingLocations = true
        let result = await enricher.resolveUnknownLocations(carId: context.carId, drives: context.drives, charges: context.charges)
        state.enrichmentResult = result
        if !result.locations.isEmpty {
            originalRegions = Self.aggregate(drives: context.drives, charges: context.charges, countryName: context.countryName, year: context.year, resolvedLocations: result.locations)
            applySort()
        }
        state.isEnrichingLocations = false
        saveCachedState()
    }

    public func setSortOrder(_ order: RegionSortOrder) {
        state.sortOrder = order
        applySort()
        saveCachedState()
    }

    private func saveCachedState() {
        guard let cacheKey else { return }
        var snapshot = state
        snapshot.isLoading = false
        snapshot.isRefreshing = false
        snapshot.isEnrichingLocations = false
        snapshot.errorMessage = nil
        stateCache.save(snapshot, for: cacheKey)
    }

    private func applySort() {
        switch state.sortOrder {
        case .firstVisit:
            state.regions = originalRegions.sorted { $0.firstVisitDate < $1.firstVisitDate }
        case .alphabetical:
            state.regions = originalRegions.sorted { $0.regionName < $1.regionName }
        case .driveCount:
            state.regions = originalRegions.sorted { $0.driveCount > $1.driveCount }
        case .distance:
            state.regions = originalRegions.sorted { $0.totalDistanceKm > $1.totalDistanceKm }
        case .energy:
            state.regions = originalRegions.sorted { $0.totalChargeEnergyKwh > $1.totalChargeEnergyKwh }
        case .charges:
            state.regions = originalRegions.sorted { $0.chargeCount > $1.chargeCount }
        }
    }

    public static func aggregate(drives: [DriveData], charges: [ChargeData], countryName: String, year: Int?, resolvedLocations: [String: GeocodedLocation] = [:]) -> [RegionVisitRecord] {
        var records: [String: RegionVisitAccumulator] = [:]
        for drive in drives where CountriesVisitedViewModel.matches(drive.startDate, year: year) {
            let address = drive.endAddress ?? drive.startAddress
            guard CountriesVisitedViewModel.country(from: address, resolvedLocations: resolvedLocations)?.name == countryName,
                  let region = resolvedLocations[address ?? ""]?.regionName ?? regionName(from: address)
            else { continue }
            records[region, default: RegionVisitAccumulator(name: region)].addDrive(drive)
        }
        for charge in charges where CountriesVisitedViewModel.matches(charge.startDate, year: year) {
            guard CountriesVisitedViewModel.country(from: charge.address, resolvedLocations: resolvedLocations)?.name == countryName,
                  let region = resolvedLocations[charge.address ?? ""]?.regionName ?? regionName(from: charge.address)
            else { continue }
            records[region, default: RegionVisitAccumulator(name: region)].addCharge(charge)
        }
        return records.values.map(\.record)
    }

    static func regionName(from address: String?) -> String? {
        guard let parts = address?.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              parts.count >= 2
        else { return nil }
        return parts[parts.count - 2]
    }
}

private struct RegionVisitAccumulator {
    let name: String
    var firstVisitDate = "9999-12-31T23:59:59Z"
    var driveCount = 0
    var chargeCount = 0
    var distance = 0.0
    var energy = 0.0
    var missingDriveDistanceCount = 0
    var missingChargeEnergyCount = 0

    mutating func addDrive(_ drive: DriveData) {
        driveCount += 1
        if let value = drive.distance { distance += value } else { missingDriveDistanceCount += 1 }
        firstVisitDate = min(firstVisitDate, drive.startDate ?? firstVisitDate)
    }

    mutating func addCharge(_ charge: ChargeData) {
        chargeCount += 1
        if let value = charge.chargeEnergyAdded { energy += value } else { missingChargeEnergyCount += 1 }
        firstVisitDate = min(firstVisitDate, charge.startDate ?? firstVisitDate)
    }

    var record: RegionVisitRecord {
        RegionVisitRecord(
            regionName: name,
            firstVisitDate: firstVisitDate == "9999-12-31T23:59:59Z" ? "" : firstVisitDate,
            driveCount: driveCount,
            chargeCount: chargeCount,
            totalDistanceKm: distance,
            totalChargeEnergyKwh: energy,
            missingDriveDistanceCount: missingDriveDistanceCount,
            missingChargeEnergyCount: missingChargeEnergyCount
        )
    }
}
