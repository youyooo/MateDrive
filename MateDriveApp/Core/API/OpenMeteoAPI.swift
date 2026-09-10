import Foundation

public struct OpenMeteoAPI: Sendable {
    public let baseURL: URL
    public let historicalBaseURL: URL
    public let client: HTTPClient

    public init(
        baseURL: URL = URL(string: "https://api.open-meteo.com")!,
        historicalBaseURL: URL = URL(string: "https://historical-forecast-api.open-meteo.com")!,
        client: HTTPClient = URLSessionHTTPClient()
    ) {
        self.baseURL = baseURL
        self.historicalBaseURL = historicalBaseURL
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

    public func historicalForecast(latitude: Double, longitude: Double, date: Date) async -> APIResult<OpenMeteoForecastResponse> {
        let day = Self.utcDayString(from: date)
        let endpoint = Endpoint(
            baseURL: historicalBaseURL,
            path: "v1/forecast",
            queryItems: [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "start_date", value: day),
                URLQueryItem(name: "end_date", value: day),
                URLQueryItem(
                    name: "hourly",
                    value: "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,precipitation,visibility"
                ),
                URLQueryItem(name: "timeformat", value: "unixtime"),
                URLQueryItem(name: "timezone", value: "GMT")
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

    private static func utcDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func historicalDate(from value: String) -> Date? {
        if let date = DomainDateParser.date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

extension OpenMeteoAPI: WeatherAPIProviding {
    public func weather(latitude: Double, longitude: Double, date: String?) async -> APIResult<WeatherPoint> {
        if let date, let requestedDate = Self.historicalDate(from: date) {
            return await historicalWeather(latitude: latitude, longitude: longitude, date: requestedDate)
        }

        switch await forecast(latitude: latitude, longitude: longitude) {
        case let .success(response):
            guard let temperature = response.current?.temperature2M,
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

    private func historicalWeather(latitude: Double, longitude: Double, date: Date) async -> APIResult<WeatherPoint> {
        switch await historicalForecast(latitude: latitude, longitude: longitude, date: date) {
        case let .success(response):
            guard let hourly = response.hourly,
                  let times = hourly.time,
                  let temperatures = hourly.temperature2M,
                  let codes = hourly.weatherCode,
                  let nearestIndex = times.indices.min(by: {
                      abs(Double(times[$0]) - date.timeIntervalSince1970) < abs(Double(times[$1]) - date.timeIntervalSince1970)
                  }),
                  nearestIndex < temperatures.count,
                  nearestIndex < codes.count,
                  let temperature = temperatures[nearestIndex],
                  let code = codes[nearestIndex]
            else {
                return .failure(.emptyBody)
            }
            return .success(
                WeatherPoint(
                    latitude: response.latitude ?? latitude,
                    longitude: response.longitude ?? longitude,
                    temperatureCelsius: temperature,
                    weatherCode: code,
                    windSpeedKph: hourly.windSpeed10M?[safe: nearestIndex] ?? nil,
                    windDirectionDegrees: hourly.windDirection10M?[safe: nearestIndex] ?? nil,
                    precipitationMillimeters: hourly.precipitation?[safe: nearestIndex] ?? nil,
                    visibilityMeters: hourly.visibility?[safe: nearestIndex] ?? nil
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
    public let hourly: OpenMeteoHourly?
}

public struct OpenMeteoCurrent: Decodable, Equatable, Sendable {
    public let temperature2M: Double?
    public let weatherCode: Int?
}

public struct OpenMeteoHourly: Decodable, Equatable, Sendable {
    public let time: [Int64]?
    public let temperature2M: [Double?]?
    public let weatherCode: [Int?]?
    public let windSpeed10M: [Double?]?
    public let windDirection10M: [Double?]?
    public let precipitation: [Double?]?
    public let visibility: [Double?]?
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
