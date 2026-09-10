import Foundation

public struct TeslamateAPI: Sendable {
    public let baseURL: URL
    public let bearerToken: String?
    public let basicAuth: BasicAuth?
    public let authenticator: RequestAuthenticator
    public let client: HTTPClient

    public init(
        baseURL: URL,
        bearerToken: String? = nil,
        basicAuth: BasicAuth? = nil,
        cloudflareAccess: CloudflareAccessAuth? = nil,
        aksk: AKSKCredentials? = nil,
        authenticator: RequestAuthenticator? = nil,
        client: HTTPClient = URLSessionHTTPClient()
    ) {
        let resolvedAuthenticator = authenticator ?? RequestAuthenticator(
            bearerToken: bearerToken,
            basicAuth: basicAuth,
            cloudflareAccess: cloudflareAccess,
            aksk: aksk
        )
        self.baseURL = baseURL
        self.bearerToken = resolvedAuthenticator.bearerToken
        self.basicAuth = resolvedAuthenticator.basicAuth
        self.authenticator = resolvedAuthenticator
        self.client = client
    }

    public func version() async -> APIResult<TeslaMateVersionInfo> {
        await decode(
            TeslaMateVersionResponse.self,
            endpoint: endpoint("api/v1/version")
        ) { response in
            response.info
        }
    }

    public func probe(
        path: String,
        queryItems: [URLQueryItem] = [],
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) async -> APIResult<TeslaMateProbeResponse> {
        do {
            var request = try endpoint(path, queryItems: queryItems).request()
            request.httpMethod = "GET"
            request.cachePolicy = cachePolicy
            let (data, response) = try await client.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            return .success(TeslaMateProbeResponse(statusCode: response.statusCode, data: data))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.from(error))
        }
    }

    public func cars() async -> APIResult<[CarData]> {
        await decode(
            CarsResponse.self,
            endpoint: endpoint("api/v1/cars")
        ) { response in
            response.data?.cars ?? []
        }
    }

    public func currentCharge(carId: Int) async -> APIResult<CurrentChargeOutcome> {
        await currentCharge(carId: carId, cachePolicy: .useProtocolCachePolicy)
    }

    public func refreshCurrentCharge(carId: Int) async -> APIResult<CurrentChargeOutcome> {
        await currentCharge(carId: carId, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func currentCharge(
        carId: Int,
        cachePolicy: URLRequest.CachePolicy
    ) async -> APIResult<CurrentChargeOutcome> {
        do {
            let endpoint = endpoint("api/v1/cars/\(carId)/charges/current")
            var request = try endpoint.request()
            request.cachePolicy = cachePolicy
            let (data, response) = try await client.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            if response.statusCode == 204 {
                return .success(.noActiveCharge)
            }
            let decoded = try JSONDecoder.teslamate.decode(ChargeDetailResponse.self, from: data)
            if let detail = decoded.data?.charge {
                return .success(.active(detail))
            }
            if decoded.error != nil || decoded.data == nil {
                return .success(.noActiveCharge)
            }
            return .failure(.emptyBody)
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.from(error))
        }
    }

    public func carStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        await carStatus(carId: carId, cachePolicy: .useProtocolCachePolicy)
    }

    public func refreshCarStatus(carId: Int) async -> APIResult<CarStatusPayload> {
        await carStatus(carId: carId, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func carStatus(
        carId: Int,
        cachePolicy: URLRequest.CachePolicy
    ) async -> APIResult<CarStatusPayload> {
        await decode(
            CarStatusResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/status"),
            cachePolicy: cachePolicy
        ) { response in
            response.data
        }
    }

    public func charges(carId: Int, startDate: String? = nil, endDate: String? = nil, page: Int? = nil, show: Int? = nil) async -> APIResult<[ChargeData]> {
        await charges(
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            page: page,
            show: show,
            cachePolicy: .useProtocolCachePolicy
        )
    }

    public func refreshCharges(carId: Int, startDate: String? = nil, endDate: String? = nil, page: Int? = nil, show: Int? = nil) async -> APIResult<[ChargeData]> {
        await charges(
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            page: page,
            show: show,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    private func charges(
        carId: Int,
        startDate: String?,
        endDate: String?,
        page: Int?,
        show: Int?,
        cachePolicy: URLRequest.CachePolicy
    ) async -> APIResult<[ChargeData]> {
        let queryItems: [URLQueryItem] = [
            startDate.map { URLQueryItem(name: "startDate", value: $0) },
            endDate.map { URLQueryItem(name: "endDate", value: $0) },
            page.map { URLQueryItem(name: "page", value: "\($0)") },
            show.map { URLQueryItem(name: "show", value: "\($0)") }
        ].compactMap { $0 }

        return await decode(
            ChargesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/charges", queryItems: queryItems),
            cachePolicy: cachePolicy
        ) { response in
            response.data?.charges ?? []
        }
    }

    public func chargeDetail(carId: Int, chargeId: Int) async -> APIResult<ChargeDetail> {
        await decode(
            ChargeDetailResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/charges/\(chargeId)")
        ) { response in
            response.data?.charge
        }
    }

    public func updateChargeCost(chargeId: Int, cost: Double?) async -> APIResult<Void> {
        do {
            var request = try endpoint("api/v1/charging-processes/\(chargeId)/cost").request()
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(ChargeCostUpdateRequest(cost: cost))
            request = try authenticator.authenticated(request)
            let (data, response) = try await client.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            guard !data.isEmpty else {
                return .success(())
            }
            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.invalidResponse("Charge cost update returned malformed JSON"))
            }
            if let error = payload["error"] as? String, !error.isEmpty {
                return .failure(.invalidResponse(error))
            }
            return .success(())
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.from(error))
        }
    }

    public func drives(carId: Int, startDate: String? = nil, endDate: String? = nil, page: Int? = nil, show: Int? = nil) async -> APIResult<[DriveData]> {
        await drives(
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            page: page,
            show: show,
            cachePolicy: .useProtocolCachePolicy
        )
    }

    public func refreshDrives(carId: Int, startDate: String? = nil, endDate: String? = nil, page: Int? = nil, show: Int? = nil) async -> APIResult<[DriveData]> {
        await drives(
            carId: carId,
            startDate: startDate,
            endDate: endDate,
            page: page,
            show: show,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    private func drives(
        carId: Int,
        startDate: String?,
        endDate: String?,
        page: Int?,
        show: Int?,
        cachePolicy: URLRequest.CachePolicy
    ) async -> APIResult<[DriveData]> {
        let queryItems: [URLQueryItem] = [
            startDate.map { URLQueryItem(name: "startDate", value: $0) },
            endDate.map { URLQueryItem(name: "endDate", value: $0) },
            page.map { URLQueryItem(name: "page", value: "\($0)") },
            show.map { URLQueryItem(name: "show", value: "\($0)") }
        ].compactMap { $0 }

        return await decode(
            DrivesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/drives", queryItems: queryItems),
            cachePolicy: cachePolicy
        ) { response in
            response.data?.drives ?? []
        }
    }

    public func driveDetail(carId: Int, driveId: Int) async -> APIResult<DriveDetail> {
        await decode(
            DriveDetailResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/drives/\(driveId)")
        ) { response in
            response.data?.drive
        }
    }

    public func vehicleStateHistory(
        carId: Int,
        startDate: String,
        endDate: String
    ) async -> APIResult<[VehicleStateInterval]> {
        let queryItems = [
            URLQueryItem(name: "startDate", value: startDate),
            URLQueryItem(name: "endDate", value: endDate)
        ]
        return await decode(
            VehicleStateHistoryResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/states", queryItems: queryItems)
        ) { $0.intervals }
    }

    public func battery(carId: Int) async -> APIResult<BatteryData?> {
        await decodeOptional(
            BatteryResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/battery")
        ) { response in
            response.data?.battery
        }
    }

    public func batteryHealth(carId: Int) async -> APIResult<BatteryHealth> {
        await batteryHealth(carId: carId, cachePolicy: .useProtocolCachePolicy)
    }

    public func refreshBatteryHealth(carId: Int) async -> APIResult<BatteryHealth> {
        await batteryHealth(carId: carId, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func batteryHealth(carId: Int, cachePolicy: URLRequest.CachePolicy) async -> APIResult<BatteryHealth> {
        await decode(
            BatteryHealthResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/battery-health"),
            cachePolicy: cachePolicy
        ) { response in
            response.data?.batteryHealth
        }
    }

    public func batteryHistory(carId: Int) async -> APIResult<BatteryHistoryData> {
        await batteryHistory(carId: carId, cachePolicy: .useProtocolCachePolicy)
    }

    public func refreshBatteryHistory(carId: Int) async -> APIResult<BatteryHistoryData> {
        await batteryHistory(carId: carId, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func batteryHistory(carId: Int, cachePolicy: URLRequest.CachePolicy) async -> APIResult<BatteryHistoryData> {
        await decode(
            BatteryHistoryResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/battery-health/history"),
            cachePolicy: cachePolicy
        ) { $0.data }
    }

    public func serverStats(carId: Int) async -> APIResult<TeslaMateServerStatsResponse> {
        await decode(
            TeslaMateServerStatsResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/stats")
        ) { $0 }
    }

    public func costReview(carId: Int, startDate: Date, endDate: Date) async -> APIResult<CostReviewResponse> {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return await decode(
            CostReviewResponse.self,
            endpoint: endpoint(
                "api/v1/cars/\(carId)/stats/cost-charging-detail",
                queryItems: [
                    URLQueryItem(name: "start_date", value: formatter.string(from: startDate)),
                    URLQueryItem(name: "end_date", value: formatter.string(from: endDate))
                ]
            )
        ) { $0 }
    }

    public func activities(carId: Int, page: Int, show: Int = 20) async -> APIResult<TeslaMateActivitiesResponse> {
        await activities(carId: carId, page: page, show: show, cachePolicy: .useProtocolCachePolicy)
    }

    public func refreshActivities(carId: Int, page: Int, show: Int = 20) async -> APIResult<TeslaMateActivitiesResponse> {
        await activities(carId: carId, page: page, show: show, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    private func activities(
        carId: Int,
        page: Int,
        show: Int,
        cachePolicy: URLRequest.CachePolicy
    ) async -> APIResult<TeslaMateActivitiesResponse> {
        await decode(
            TeslaMateActivitiesResponse.self,
            endpoint: endpoint(
                "api/v1/cars/\(carId)/activities",
                queryItems: [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "show", value: "\(show)")
                ]
            ),
            cachePolicy: cachePolicy
        ) { $0 }
    }

    public func driveInsights(carId: Int) async -> APIResult<TeslaMateDriveInsightsData> {
        await decode(
            TeslaMateDriveInsightsResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/drive-stats")
        ) { $0.data }
    }

    public func environmentHistory(carId: Int, range: String, grain: String) async -> APIResult<EnvironmentHistoryResponse> {
        await decode(
            EnvironmentHistoryResponse.self,
            endpoint: endpoint(
                "api/v1/cars/\(carId)/environment-history",
                queryItems: [
                    URLQueryItem(name: "range", value: range),
                    URLQueryItem(name: "grain", value: grain)
                ]
            )
        ) { $0 }
    }

    public func standbyDrain(carId: Int, latitude: Double, longitude: Double) async -> APIResult<StandbyDrainResponse> {
        await decode(
            StandbyDrainResponse.self,
            endpoint: endpoint(
                "api/v1/cars/\(carId)/standby-drain",
                queryItems: [
                    URLQueryItem(name: "lat", value: String(latitude)),
                    URLQueryItem(name: "lng", value: String(longitude))
                ]
            )
        ) { $0 }
    }

    public func topDrainLocations(carId: Int) async -> APIResult<TopDrainLocationsResponse> {
        await decode(
            TopDrainLocationsResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/top-drain-locations")
        ) { $0 }
    }

    public func commuteRoutes(carId: Int) async -> APIResult<CommuteRoutesResponse> {
        await decode(
            CommuteRoutesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/commute-routes")
        ) { $0 }
    }

    public func statsExtremes(carId: Int) async -> APIResult<StatsExtremesResponse> {
        await decode(
            StatsExtremesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/stats/extremes")
        ) { $0 }
    }

    public func drivingCoordinates(carId: Int) async -> APIResult<DrivingCoordinatesResponse> {
        await decode(
            DrivingCoordinatesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/driving-coordinates")
        ) { $0 }
    }

    public func places(carId: Int, page: Int = 1, show: Int = 100) async -> APIResult<ServerPlacesResponse> {
        await decode(
            ServerPlacesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/places", queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "show", value: String(show))
            ])
        ) { $0 }
    }

    public func achievements(carId: Int) async -> APIResult<AchievementsPayload> {
        await decode(
            AchievementsResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/achievements")
        ) { $0.data }
    }

    public func updates(carId: Int, page: Int? = nil, show: Int? = nil) async -> APIResult<[UpdateData]> {
        let queryItems: [URLQueryItem] = [
            page.map { URLQueryItem(name: "page", value: "\($0)") },
            show.map { URLQueryItem(name: "show", value: "\($0)") }
        ].compactMap { $0 }

        return await decode(
            UpdatesResponse.self,
            endpoint: endpoint("api/v1/cars/\(carId)/updates", queryItems: queryItems)
        ) { response in
            response.data?.updates ?? []
        }
    }

    public func globalSettings() async -> APIResult<GlobalSettingsData?> {
        await decodeOptional(
            GlobalSettingsResponse.self,
            endpoint: endpoint("api/v1/globalsettings")
        ) { response in
            response.data?.settings
        }
    }

    private func endpoint(_ path: String, queryItems: [URLQueryItem] = []) -> Endpoint {
        Endpoint(
            baseURL: baseURL,
            path: path,
            queryItems: queryItems,
            authenticator: authenticator
        )
    }

    private func decode<Response: Decodable, Value>(
        _ type: Response.Type,
        endpoint: Endpoint,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        map: (Response) -> Value?
    ) async -> APIResult<Value> {
        do {
            var request = try endpoint.request()
            request.cachePolicy = cachePolicy
            let (data, response) = try await client.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            let decoded = try JSONDecoder.teslamate.decode(type, from: data)
            guard let value = map(decoded) else {
                return .failure(.emptyBody)
            }
            return .success(value)
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.from(error))
        }
    }

    private func decodeOptional<Response: Decodable, Value>(
        _ type: Response.Type,
        endpoint: Endpoint,
        map: (Response) -> Value?
    ) async -> APIResult<Value?> {
        do {
            let request = try endpoint.request()
            let (data, response) = try await client.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            let decoded = try JSONDecoder.teslamate.decode(type, from: data)
            return .success(map(decoded))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(APIError.from(error))
        }
    }
}

private struct ChargeCostUpdateRequest: Encodable {
    let cost: Double?

    enum CodingKeys: String, CodingKey {
        case cost
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let cost {
            try container.encode(cost, forKey: .cost)
        } else {
            try container.encodeNil(forKey: .cost)
        }
    }
}
