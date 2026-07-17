import Foundation

public protocol TeslaMateCapabilityDiscovering: Sendable {
    func discover(api: TeslamateAPI, carId: Int, force: Bool) async -> TeslaMateServerProfile
}

public struct TeslaMateCapabilityService: TeslaMateCapabilityDiscovering, Sendable {
    private let profileStore: any TeslaMateServerProfileStoring
    private let now: @Sendable () -> Date
    private let cacheTTL: TimeInterval = 24 * 60 * 60

    public init(
        profileStore: any TeslaMateServerProfileStoring = EmptyTeslaMateServerProfileStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.profileStore = profileStore
        self.now = now
    }

    public func discover(api: TeslamateAPI, carId: Int, force: Bool = false) async -> TeslaMateServerProfile {
        let checkedAt = now()
        let serverKey = TeslaMateServerIdentity.key(for: api.baseURL)
        let cached = try? await profileStore.profile(serverKey: serverKey, carId: carId)
        if !force, let cached, checkedAt.timeIntervalSince(cached.checkedAt) < cacheTTL {
            return cached
        }

        let version: TeslaMateVersionInfo
        switch await api.version() {
        case let .success(value): version = value
        case .failure: version = TeslaMateVersionInfo(apiVersion: nil, mtAPIVersion: nil, buildInfo: nil)
        }

        var statuses = Dictionary(uniqueKeysWithValues: TeslaMateCapability.allCases.map { capability in
            (capability, TeslaMateCapabilityStatus(
                state: .unknown,
                reason: capability == .standbyDrain ? .parametersRequired : .notProbed,
                source: .endpointProbe,
                checkedAt: checkedAt,
                lastSuccessfulAt: cached?.status(for: capability)?.lastSuccessfulAt
            ))
        })
        var connectionIssue: TeslaMateConnectionIssue?

        for spec in Self.probeSpecs(carId: carId, checkedAt: checkedAt) {
            let classified = Self.classify(
                capability: spec.capability,
                result: await api.probe(path: spec.path, queryItems: spec.queryItems),
                checkedAt: checkedAt,
                previousSuccess: cached?.status(for: spec.capability)?.lastSuccessfulAt
            )
            statuses[spec.capability] = classified.status
            connectionIssue = connectionIssue ?? classified.connectionIssue
        }

        let coreSucceeded = statuses[.coreCars].map { $0.state == .available || $0.state == .degraded } == true
        let profile = TeslaMateServerProfile(
            serverKey: serverKey,
            carId: carId,
            version: version,
            capabilities: statuses,
            connectionIssue: connectionIssue,
            checkedAt: checkedAt,
            lastSuccessfulCheckAt: coreSucceeded ? checkedAt : cached?.lastSuccessfulCheckAt
        )
        try? await profileStore.save(profile)
        return profile
    }
}

private struct ProbeSpec {
    let capability: TeslaMateCapability
    let path: String
    let queryItems: [URLQueryItem]
}

private extension TeslaMateCapabilityService {
    static func probeSpecs(carId: Int, checkedAt: Date) -> [ProbeSpec] {
        let firstPage = [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "show", value: "1")]
        let dateFormatter = ISO8601DateFormatter()
        let stateHistoryQuery = [
            URLQueryItem(name: "startDate", value: dateFormatter.string(from: checkedAt.addingTimeInterval(-24 * 60 * 60))),
            URLQueryItem(name: "endDate", value: dateFormatter.string(from: checkedAt))
        ]
        return [
            ProbeSpec(capability: .coreCars, path: "api/v1/cars", queryItems: []),
            ProbeSpec(capability: .vehicleStatus, path: "api/v1/cars/\(carId)/status", queryItems: []),
            ProbeSpec(capability: .chargeList, path: "api/v1/cars/\(carId)/charges", queryItems: firstPage),
            ProbeSpec(capability: .currentCharge, path: "api/v1/cars/\(carId)/charges/current", queryItems: []),
            ProbeSpec(capability: .driveList, path: "api/v1/cars/\(carId)/drives", queryItems: firstPage),
            ProbeSpec(capability: .batteryHealthSummary, path: "api/v1/cars/\(carId)/battery-health", queryItems: []),
            ProbeSpec(capability: .serverStats, path: "api/v1/cars/\(carId)/stats", queryItems: []),
            ProbeSpec(capability: .costReview, path: "api/v1/cars/\(carId)/stats/cost-charging-detail", queryItems: []),
            ProbeSpec(capability: .unifiedActivities, path: "api/v1/cars/\(carId)/activities", queryItems: firstPage),
            ProbeSpec(capability: .batteryHealthHistory, path: "api/v1/cars/\(carId)/battery-health/history", queryItems: []),
            ProbeSpec(capability: .driveInsights, path: "api/v1/cars/\(carId)/drive-stats", queryItems: []),
            ProbeSpec(capability: .environmentHistory, path: "api/v1/cars/\(carId)/environment-history", queryItems: [
                URLQueryItem(name: "range", value: "7d"),
                URLQueryItem(name: "grain", value: "day")
            ]),
            ProbeSpec(capability: .stateHistory, path: "api/v1/cars/\(carId)/states", queryItems: stateHistoryQuery),
            ProbeSpec(capability: .achievements, path: "api/v1/cars/\(carId)/achievements", queryItems: []),
            ProbeSpec(capability: .geofences, path: "api/v1/geofences", queryItems: []),
            ProbeSpec(capability: .topDrainLocations, path: "api/v1/cars/\(carId)/top-drain-locations", queryItems: []),
            ProbeSpec(capability: .commuteRoutes, path: "api/v1/cars/\(carId)/commute-routes", queryItems: []),
            ProbeSpec(capability: .statsExtremes, path: "api/v1/cars/\(carId)/stats/extremes", queryItems: []),
            ProbeSpec(capability: .drivingCoordinates, path: "api/v1/cars/\(carId)/driving-coordinates", queryItems: []),
            ProbeSpec(capability: .serverPlaces, path: "api/v1/cars/\(carId)/places", queryItems: firstPage)
        ]
    }

    static func classify(
        capability: TeslaMateCapability,
        result: APIResult<TeslaMateProbeResponse>,
        checkedAt: Date,
        previousSuccess: Date?
    ) -> (status: TeslaMateCapabilityStatus, connectionIssue: TeslaMateConnectionIssue?) {
        switch result {
        case let .success(response):
            if response.statusCode != 204 && response.data.isEmpty {
                return (.init(state: .degraded, reason: .emptyPayload, source: .endpointProbe,
                              checkedAt: checkedAt, lastSuccessfulAt: checkedAt), nil)
            }
            if response.statusCode != 204, (try? JSONSerialization.jsonObject(with: response.data)) == nil {
                return (.init(state: .degraded, reason: .invalidPayload, source: .endpointProbe,
                              checkedAt: checkedAt, lastSuccessfulAt: checkedAt), nil)
            }
            if capability == .unifiedActivities, hasBrokenActivityPagination(response.data) {
                return (.init(state: .degraded, reason: .paginationMetadataInvalid, source: .endpointProbe,
                              checkedAt: checkedAt, lastSuccessfulAt: checkedAt), nil)
            }
            return (.init(state: .available, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: checkedAt), nil)
        case let .failure(.httpStatus(code)) where code == 404:
            return (.init(state: .unavailable, reason: .endpointNotFound, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), nil)
        case let .failure(.httpStatus(code)) where code == 405:
            return (.init(state: .unavailable, reason: .methodNotAllowed, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), nil)
        case let .failure(.httpStatus(code)) where code == 401 || code == 403:
            return (.init(state: .unknown, reason: .authenticationRequired, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), .authentication(statusCode: code))
        case let .failure(.httpStatus(code)) where code >= 500 || code == 408 || code == 429:
            return (.init(state: .unknown, reason: .temporaryServerFailure, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), .temporaryServerFailure(statusCode: code))
        case .failure(.network), .failure(.sslCertificate):
            return (.init(state: .unknown, reason: .networkFailure, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), .network)
        case .failure where capability == .stateHistory:
            return (.init(state: .unknown, reason: .invalidPayload, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), nil)
        case .failure:
            return (.init(state: .degraded, reason: .invalidPayload, source: .endpointProbe,
                          checkedAt: checkedAt, lastSuccessfulAt: previousSuccess), nil)
        }
    }

    static func hasBrokenActivityPagination(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return false }
        let activities = firstArray(named: ["activities"], in: root) ?? []
        let totalRecords = firstInteger(named: ["totalRecords", "total_records"], in: root)
        let totalPages = firstInteger(named: ["totalPages", "total_pages"], in: root)
        return (!activities.isEmpty && totalRecords == 0) || (totalPages ?? 0) >= 9_999
    }

    static func firstArray(named names: Set<String>, in value: Any) -> [Any]? {
        if let dictionary = value as? [String: Any] {
            for name in names where dictionary[name] is [Any] { return dictionary[name] as? [Any] }
            for child in dictionary.values {
                if let match = firstArray(named: names, in: child) { return match }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let match = firstArray(named: names, in: child) { return match }
            }
        }
        return nil
    }

    static func firstInteger(named names: Set<String>, in value: Any) -> Int? {
        if let dictionary = value as? [String: Any] {
            for name in names {
                if let number = dictionary[name] as? NSNumber { return number.intValue }
                if let text = dictionary[name] as? String, let number = Int(text) { return number }
            }
            for child in dictionary.values {
                if let match = firstInteger(named: names, in: child) { return match }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let match = firstInteger(named: names, in: child) { return match }
            }
        }
        return nil
    }
}
