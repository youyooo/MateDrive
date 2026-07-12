import Foundation

public struct OpenMeteoAPI: Sendable {
    public let baseURL: URL
    public let client: HTTPClient

    public init(baseURL: URL = URL(string: "https://api.open-meteo.com")!, client: HTTPClient = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.client = client
    }

    public func forecast(latitude: Double, longitude: Double) async -> APIResult<OpenMeteoForecastResponse> {
        let endpoint = Endpoint(
            baseURL: baseURL,
            path: "v1/forecast",
            queryItems: [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,weather_code")
            ]
        )
        return await decode(OpenMeteoForecastResponse.self, endpoint: endpoint)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, endpoint: Endpoint) async -> APIResult<Value> {
        do {
            let request = try endpoint.request()
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

extension OpenMeteoAPI: WeatherAPIProviding {
    public func weather(latitude: Double, longitude: Double, date _: String?) async -> APIResult<WeatherPoint> {
        switch await forecast(latitude: latitude, longitude: longitude) {
        case let .success(response):
            guard let temperature = response.current?.temperature2m,
                  let code = response.current?.weatherCode
            else {
                return .failure(.emptyBody)
            }
            return .success(
                WeatherPoint(
                    latitude: response.latitude ?? latitude,
                    longitude: response.longitude ?? longitude,
                    temperatureCelsius: temperature,
                    weatherCode: code
                )
            )
        case let .failure(error):
            return .failure(error)
        }
    }
}

public struct OpenMeteoForecastResponse: Decodable, Equatable, Sendable {
    public let latitude: Double?
    public let longitude: Double?
    public let current: OpenMeteoCurrent?
}

public struct OpenMeteoCurrent: Decodable, Equatable, Sendable {
    public let temperature2m: Double?
    public let weatherCode: Int?
}
