import Foundation

public struct NominatimAPI: Sendable {
    public let baseURL: URL
    public let client: HTTPClient

    public init(baseURL: URL = URL(string: "https://nominatim.openstreetmap.org")!, client: HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.client = client
    }

    public func reverse(latitude: Double, longitude: Double) async -> APIResult<NominatimReverseResponse> {
        let endpoint = Endpoint(
            baseURL: baseURL,
            path: "reverse",
            queryItems: [
                URLQueryItem(name: "format", value: "jsonv2"),
                URLQueryItem(name: "lat", value: String(latitude)),
                URLQueryItem(name: "lon", value: String(longitude))
            ]
        )
        return await decode(NominatimReverseResponse.self, endpoint: endpoint)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, endpoint: Endpoint) async -> APIResult<Value> {
        do {
            var request = try endpoint.request()
            request.setValue("MateDrive/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("zh-CN,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            let (data, response) = try await client.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                return .failure(.httpStatus(response.statusCode))
            }
            return .success(try JSONDecoder.teslamate.decode(type, from: data))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}

public struct NominatimReverseResponse: Decodable, Equatable, Sendable {
    public let displayName: String?
    public let address: NominatimAddress?
}

public struct NominatimAddress: Decodable, Equatable, Sendable {
    public let country: String?
    public let countryCode: String?
    public let state: String?
    public let county: String?
    public let city: String?
    public let town: String?
    public let village: String?
}

extension NominatimAPI: ReverseGeocodingAPI {
    public func reverseGeocode(latitude: Double, longitude: Double) async -> APIResult<GeocodedLocation> {
        switch await reverse(latitude: latitude, longitude: longitude) {
        case let .success(response):
            return .success(GeocodedLocation(
                address: response.displayName,
                countryCode: response.address?.countryCode?.uppercased(),
                countryName: response.address?.country,
                regionName: response.address?.state ?? response.address?.county,
                city: response.address?.city ?? response.address?.town ?? response.address?.village
            ))
        case let .failure(error):
            return .failure(error)
        }
    }
}
