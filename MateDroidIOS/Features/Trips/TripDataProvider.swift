import Foundation

public protocol TripDataProviding: Sendable {
    func sourceData(carId: Int) async -> APIResult<TripSourceData>
    func routeSegments(carId: Int, driveIds: [Int]) async -> [SavedTripRouteSegment]
}

public extension TripDataProviding {
    func routeSegments(carId _: Int, driveIds _: [Int]) async -> [SavedTripRouteSegment] { [] }
}

public struct APITripDataProvider: TripDataProviding {
    private let api: any AnalyticsAPIProviding
    private let routeCache: (any TripRouteCaching)?

    public init(api: any AnalyticsAPIProviding, routeCache: (any TripRouteCaching)? = nil) {
        self.api = api
        self.routeCache = routeCache
    }

    public func sourceData(carId: Int) async -> APIResult<TripSourceData> {
        async let drivesResult = api.drives(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000)
        async let chargesResult = api.charges(carId: carId, startDate: nil, endDate: nil, page: 1, show: 50_000)
        async let statusResult = api.carStatus(carId: carId)

        let status = await statusResult
        switch await (drivesResult, chargesResult) {
        case let (.success(drives), .success(charges)):
            let tripDrives = drives.compactMap(Self.tripDrive(from:))
            let tripCharges = charges.compactMap(Self.tripCharge(from:))
            let dcChargeIds = Set(charges.compactMap { charge -> Int? in
                guard let id = charge.chargeId else { return nil }
                return ChargeStatsCalculator.isDcCharge(
                    chargeId: id,
                    energyAddedKwh: charge.chargeEnergyAdded,
                    durationMin: charge.durationMin,
                    dcChargeIds: [],
                    processedChargeIds: []
                ) ? id : nil
            })
            let units: UnitPreferences?
            if case let .success(payload) = status {
                units = UnitPreferences(
                    unitOfLength: payload.units?.unitOfLength,
                    unitOfTemperature: payload.units?.unitOfTemperature,
                    unitOfPressure: payload.units?.unitOfPressure
                )
            } else {
                units = nil
            }
            return .success(TripSourceData(drives: tripDrives, charges: tripCharges, dcChargeIds: dcChargeIds, units: units))
        case let (.failure(error), _), let (_, .failure(error)):
            return .failure(error)
        }
    }

    public func routeSegments(carId: Int, driveIds: [Int]) async -> [SavedTripRouteSegment] {
        await withTaskGroup(of: SavedTripRouteSegment?.self) { group in
            for driveId in driveIds {
                group.addTask {
                    if let routeCache,
                       let cached = try? await routeCache.points(carId: carId, driveId: driveId),
                       cached.count >= 2 {
                        return SavedTripRouteSegment(driveId: driveId, points: cached)
                    }
                    guard case let .success(detail) = await api.driveDetail(carId: carId, driveId: driveId) else {
                        return nil
                    }
                    let segment = SavedTripRouteSegment(driveId: driveId, positions: detail.positions ?? [])
                    if segment.points.count >= 2 {
                        try? await routeCache?.save(points: segment.points, carId: carId, driveId: driveId)
                    }
                    return segment
                }
            }

            var segmentsById: [Int: SavedTripRouteSegment] = [:]
            for await segment in group {
                if let segment { segmentsById[segment.driveId] = segment }
            }
            return driveIds.compactMap { segmentsById[$0] }
        }
    }

    private static func tripDrive(from drive: DriveData) -> TripDrive? {
        guard
            let id = drive.driveId,
            let startDate = drive.startDate,
            let endDate = drive.endDate,
            let distance = drive.distance,
            let durationMin = drive.durationMin
        else {
            return nil
        }
        return TripDrive(
            id: id,
            startDate: startDate,
            endDate: endDate,
            distance: distance,
            durationMin: durationMin,
            energyConsumed: drive.energyConsumedNet,
            speedMax: Double(drive.speedMax ?? Int(drive.speedAvg ?? 0)),
            startAddress: drive.startAddress,
            endAddress: drive.endAddress,
            startBatteryLevel: drive.startBatteryLevel,
            endBatteryLevel: drive.endBatteryLevel
        )
    }

    private static func tripCharge(from charge: ChargeData) -> TripCharge? {
        guard
            let id = charge.chargeId,
            let startDate = charge.startDate,
            let endDate = charge.endDate
        else {
            return nil
        }
        return TripCharge(
            id: id,
            startDate: startDate,
            endDate: endDate,
            energyAdded: charge.chargeEnergyAdded ?? 0,
            cost: charge.cost,
            durationMin: charge.durationMin,
            address: charge.address
        )
    }
}
