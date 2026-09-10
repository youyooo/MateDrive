import Combine
import Foundation

public protocol HistoricalGeographyEnriching: Sendable {
    func resolveUnknownLocations(carId: Int, drives: [DriveData], charges: [ChargeData]) async -> GeographyEnrichmentResult
}

public struct GeographyEnrichmentResult: Equatable, Sendable {
    public let locations: [String: GeocodedLocation]
    public let candidateCount: Int
    public let cachedCount: Int
    public let requestedCount: Int
    public let failedCount: Int

    public init(locations: [String: GeocodedLocation], candidateCount: Int, cachedCount: Int, requestedCount: Int, failedCount: Int) {
        self.locations = locations
        self.candidateCount = candidateCount
        self.cachedCount = cachedCount
        self.requestedCount = requestedCount
        self.failedCount = failedCount
    }
}

public struct HistoricalGeographyEnricher: HistoricalGeographyEnriching {
    private let api: any AnalyticsAPIProviding
    private let geocoder: GeocodingService
    private let maximumAddresses: Int
    private let maximumCandidates: Int
    private let maximumDetailRequests: Int

    public init(
        api: any AnalyticsAPIProviding,
        geocoder: GeocodingService,
        maximumAddresses: Int = 12,
        maximumCandidates: Int = 100,
        maximumDetailRequests: Int = 24
    ) {
        self.api = api
        self.geocoder = geocoder
        self.maximumAddresses = max(maximumAddresses, 0)
        self.maximumCandidates = max(maximumCandidates, 0)
        self.maximumDetailRequests = max(maximumDetailRequests, 0)
    }

    public func resolveUnknownLocations(carId: Int, drives: [DriveData], charges: [ChargeData]) async -> GeographyEnrichmentResult {
        var candidates: [(String, GeocodeLocation)] = []
        var seen: Set<String> = []
        var detailRequests = 0
        for charge in charges where candidates.count < maximumCandidates {
            guard !Task.isCancelled, detailRequests < maximumDetailRequests else { break }
            guard let address = charge.address, CountryISOResolver.resolve(addressToken(address)) == nil, seen.insert(address).inserted,
                  let id = charge.chargeId else { continue }
            detailRequests += 1
            guard case let .success(detail) = await api.chargeDetail(carId: carId, chargeId: id),
                  let location = GeoCoordinateValidator.location(latitude: detail.latitude, longitude: detail.longitude) else { continue }
            candidates.append((address, location))
        }
        for drive in drives where candidates.count < maximumCandidates {
            guard !Task.isCancelled, detailRequests < maximumDetailRequests else { break }
            guard let address = drive.endAddress ?? drive.startAddress, CountryISOResolver.resolve(addressToken(address)) == nil, seen.insert(address).inserted,
                  let id = drive.driveId else { continue }
            detailRequests += 1
            guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: id),
                  let position = (detail.positions ?? []).last,
                  let location = GeoCoordinateValidator.location(latitude: position.latitude, longitude: position.longitude) else { continue }
            candidates.append((address, location))
        }
        var resolved: [String: GeocodedLocation] = [:]
        var externalRequests = 0
        var cachedCount = 0
        var failedCount = 0
        for (address, coordinate) in candidates {
            guard !Task.isCancelled else { break }
            if let cached = await geocoder.cachedLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), cached.countryCode != nil {
                resolved[address] = cached
                cachedCount += 1
                continue
            }
            guard externalRequests < maximumAddresses else { continue }
            externalRequests += 1
            if case let .success(location) = await geocoder.reverseGeocode(latitude: coordinate.latitude, longitude: coordinate.longitude),
               location.countryCode != nil {
                resolved[address] = location
            } else {
                failedCount += 1
            }
        }
        return GeographyEnrichmentResult(
            locations: resolved,
            candidateCount: candidates.count,
            cachedCount: cachedCount,
            requestedCount: externalRequests,
            failedCount: failedCount
        )
    }

    private func addressToken(_ address: String) -> String {
        address.split(separator: ",").last.map(String.init) ?? address
    }
}

public enum CountrySortOrder: String, CaseIterable, Sendable {
    case firstVisit = "First Visit"
    case alphabetical = "A-Z"
    case driveCount = "Drives"
    case distance = "Distance"
    case energy = "Energy"
    case charges = "Charges"
}

public struct CountryVisitRecord: Equatable, Identifiable, Sendable {
    public var id: String { countryCode }
    public let countryCode: String
    public let countryName: String
    public let firstVisitDate: String
    public let driveCount: Int
    public let chargeCount: Int
    public let totalDistanceKm: Double
    public let totalChargeEnergyKwh: Double
    public let missingDriveDistanceCount: Int
    public let missingChargeEnergyCount: Int
}

public struct CountriesVisitedState: Equatable, Sendable {
    public var isLoading: Bool
    public var isRefreshing: Bool
    public var countries: [CountryVisitRecord]
    public var sortOrder: CountrySortOrder
    public var units: UnitPreferences?
    public var errorMessage: String?
    public var unclassifiedLocationCount: Int
    public var isEnrichingLocations: Bool
    public var enrichmentResult: GeographyEnrichmentResult?

    public init(isLoading: Bool = true, isRefreshing: Bool = false, countries: [CountryVisitRecord] = [], sortOrder: CountrySortOrder = .firstVisit, units: UnitPreferences? = nil, errorMessage: String? = nil, unclassifiedLocationCount: Int = 0, isEnrichingLocations: Bool = false, enrichmentResult: GeographyEnrichmentResult? = nil) {
        self.isLoading = isLoading
        self.isRefreshing = isRefreshing
        self.countries = countries
        self.sortOrder = sortOrder
        self.units = units
        self.errorMessage = errorMessage
        self.unclassifiedLocationCount = unclassifiedLocationCount
        self.isEnrichingLocations = isEnrichingLocations
        self.enrichmentResult = enrichmentResult
    }
}

@MainActor
public final class CountriesVisitedViewModel: ObservableObject {
    private static let sharedStateCache = VehiclePageStateCache<CountriesVisitedState>()

    @Published public private(set) var state: CountriesVisitedState

    private let api: any AnalyticsAPIProviding
    private let geographyEnricher: (any HistoricalGeographyEnriching)?
    private let historyProvider: (any MileageDataProviding)?
    private let cacheKey: VehiclePageCacheKey?
    private let stateCache: VehiclePageStateCache<CountriesVisitedState>
    private var originalCountries: [CountryVisitRecord] = []
    private var lastDrives: [DriveData] = []
    private var lastCharges: [ChargeData] = []
    private var lastCarId: Int?
    private var lastYear: Int?

    public init(
        api: any AnalyticsAPIProviding,
        geographyEnricher: (any HistoricalGeographyEnriching)? = nil,
        historyProvider: (any MileageDataProviding)? = nil,
        cacheKey: VehiclePageCacheKey? = nil,
        stateCache: VehiclePageStateCache<CountriesVisitedState>? = nil,
        initialState: CountriesVisitedState = CountriesVisitedState()
    ) {
        let resolvedStateCache = stateCache ?? Self.sharedStateCache
        let restoredState = cacheKey.flatMap { resolvedStateCache.state(for: $0) } ?? initialState
        self.api = api
        self.geographyEnricher = geographyEnricher
        self.historyProvider = historyProvider
        self.cacheKey = cacheKey
        self.stateCache = resolvedStateCache
        self.state = restoredState
        self.originalCountries = restoredState.countries
    }

    public func load(carId: Int, year: Int?) async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        state.isLoading = state.countries.isEmpty
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
            lastDrives = drives
            lastCharges = charges
            lastCarId = carId
            lastYear = year
            let resolvedLocations = state.enrichmentResult?.locations ?? [:]
            originalCountries = Self.aggregate(
                drives: drives,
                charges: charges,
                year: year,
                resolvedLocations: resolvedLocations
            )
            state.unclassifiedLocationCount = Self.unclassifiedCount(
                drives: drives,
                charges: charges,
                year: year,
                resolvedLocations: resolvedLocations
            )
            applySort()
            saveCachedState()
            guard state.unclassifiedLocationCount > 0, let geographyEnricher else { return }
            await enrich(carId: carId, year: year, drives: drives, charges: charges, enricher: geographyEnricher)
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
        guard !state.isEnrichingLocations, let carId = lastCarId, let geographyEnricher else { return }
        await enrich(carId: carId, year: lastYear, drives: lastDrives, charges: lastCharges, enricher: geographyEnricher)
    }

    private func enrich(carId: Int, year: Int?, drives: [DriveData], charges: [ChargeData], enricher: any HistoricalGeographyEnriching) async {
        state.isEnrichingLocations = true
        let result = await enricher.resolveUnknownLocations(carId: carId, drives: drives, charges: charges)
        state.enrichmentResult = result
        if !result.locations.isEmpty {
            originalCountries = Self.aggregate(drives: drives, charges: charges, year: year, resolvedLocations: result.locations)
            state.unclassifiedLocationCount = Self.unclassifiedCount(drives: drives, charges: charges, year: year, resolvedLocations: result.locations)
            applySort()
        }
        state.isEnrichingLocations = false
        saveCachedState()
    }

    static func unclassifiedCount(drives: [DriveData], charges: [ChargeData], year: Int?, resolvedLocations: [String: GeocodedLocation] = [:]) -> Int {
        let driveCount = drives.filter { drive in
            let address = drive.endAddress ?? drive.startAddress
            return matches(drive.startDate, year: year) && country(from: address, resolvedLocations: resolvedLocations) == nil
        }.count
        let chargeCount = charges.filter { charge in
            matches(charge.startDate, year: year) && country(from: charge.address, resolvedLocations: resolvedLocations) == nil
        }.count
        return driveCount + chargeCount
    }

    public func setSortOrder(_ order: CountrySortOrder) {
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
            state.countries = originalCountries.sorted { $0.firstVisitDate < $1.firstVisitDate }
        case .alphabetical:
            state.countries = originalCountries.sorted { $0.countryName < $1.countryName }
        case .driveCount:
            state.countries = originalCountries.sorted { $0.driveCount > $1.driveCount }
        case .distance:
            state.countries = originalCountries.sorted { $0.totalDistanceKm > $1.totalDistanceKm }
        case .energy:
            state.countries = originalCountries.sorted { $0.totalChargeEnergyKwh > $1.totalChargeEnergyKwh }
        case .charges:
            state.countries = originalCountries.sorted { $0.chargeCount > $1.chargeCount }
        }
    }

    public static func aggregate(drives: [DriveData], charges: [ChargeData], year: Int?, resolvedLocations: [String: GeocodedLocation] = [:]) -> [CountryVisitRecord] {
        var records: [String: CountryVisitAccumulator] = [:]
        for drive in drives where matches(drive.startDate, year: year) {
            guard let country = country(from: drive.endAddress ?? drive.startAddress, resolvedLocations: resolvedLocations) else { continue }
            records[country.code, default: CountryVisitAccumulator(code: country.code, name: country.name)].addDrive(drive)
        }
        for charge in charges where matches(charge.startDate, year: year) {
            guard let country = country(from: charge.address, resolvedLocations: resolvedLocations) else { continue }
            records[country.code, default: CountryVisitAccumulator(code: country.code, name: country.name)].addCharge(charge)
        }
        return records.values.map(\.record)
    }

    static func matches(_ dateString: String?, year: Int?) -> Bool {
        guard let year else { return true }
        guard let date = dateString.flatMap(DomainDateParser.date(from:)) else { return false }
        return Calendar(identifier: .gregorian).component(.year, from: date) == year
    }

    nonisolated static func country(from address: String?, resolvedLocations: [String: GeocodedLocation] = [:]) -> (code: String, name: String)? {
        if let address, let resolved = resolvedLocations[address], let code = resolved.countryCode?.uppercased() {
            return (code, resolved.countryName ?? Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code)
        }
        guard
            let token = address?
                .split(separator: ",")
                .last?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            return nil
        }
        return CountryISOResolver.resolve(token)
    }
}

private struct CountryVisitAccumulator {
    let code: String
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

    var record: CountryVisitRecord {
        CountryVisitRecord(
            countryCode: code,
            countryName: name,
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

enum CountryISOResolver {
    private static let aliases: [String: (code: String, name: String)] = {
        var result: [String: (String, String)] = [:]
        let english = Locale(identifier: "en_US")
        let chinese = Locale(identifier: "zh_Hans")
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2 else { continue }
            let canonical = english.localizedString(forRegionCode: code) ?? code
            for value in [code, canonical, chinese.localizedString(forRegionCode: code)] .compactMap({ $0 }) {
                result[normalize(value)] = (code, canonical)
            }
        }
        result[normalize("中国")] = ("CN", english.localizedString(forRegionCode: "CN") ?? "China")
        result[normalize("中华人民共和国")] = ("CN", english.localizedString(forRegionCode: "CN") ?? "China")
        result[normalize("中国大陆")] = ("CN", english.localizedString(forRegionCode: "CN") ?? "China")
        result[normalize("USA")] = ("US", english.localizedString(forRegionCode: "US") ?? "United States")
        result[normalize("UK")] = ("GB", english.localizedString(forRegionCode: "GB") ?? "United Kingdom")
        return result
    }()

    static func resolve(_ value: String) -> (code: String, name: String)? {
        aliases[normalize(value)]
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
