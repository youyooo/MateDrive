import Foundation
import XCTest
@testable import MateDriveApp

final class OpenMeteoAPITests: XCTestCase {
    func testHistoricalWeatherRequestsEnvironmentFieldsAndMapsNearestHour() async throws {
        let coordinate = SyntheticCoordinates.point()
        let requestedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-18T09:20:00Z"))
        let nineAM = Int64(requestedDate.timeIntervalSince1970) - 20 * 60
        let tenAM = nineAM + 3_600
        let client = OpenMeteoRecordingHTTPClient(json: """
        {
          "hourly": {
            "time": [\(nineAM), \(tenAM)],
            "temperature_2m": [22.5, 24.0],
            "weather_code": [2, 3],
            "wind_speed_10m": [12.0, 14.0],
            "wind_direction_10m": [225, 240],
            "precipitation": [0.1, 0.4],
            "visibility": [18000, 16000]
          }
        }
        """)
        let api = OpenMeteoAPI(
            historicalBaseURL: URL(string: "https://historical.example")!,
            client: client
        )

        let result = await api.weather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: "2026-07-18T09:20:00Z"
        )

        guard case let .success(point) = result else {
            return XCTFail("Expected historical weather")
        }
        XCTAssertEqual(point.temperatureCelsius, 22.5)
        XCTAssertEqual(point.weatherCode, 2)
        XCTAssertEqual(point.windSpeedKph, 12.0)
        XCTAssertEqual(point.windDirectionDegrees, 225)
        XCTAssertEqual(point.precipitationMillimeters, 0.1)
        XCTAssertEqual(point.visibilityMeters, 18_000)

        let recordedURL = await client.requestedURL()
        let url = try XCTUnwrap(recordedURL)
        XCTAssertEqual(url.host, "historical.example")
        XCTAssertEqual(url.path, "/v1/forecast")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(query["start_date"], "2026-07-18")
        XCTAssertEqual(query["end_date"], "2026-07-18")
        XCTAssertEqual(query["timeformat"], "unixtime")
        XCTAssertEqual(query["timezone"], "GMT")
        XCTAssertEqual(
            Set(query["hourly"]?.split(separator: ",").map(String.init) ?? []),
            Set([
                "temperature_2m",
                "weather_code",
                "wind_speed_10m",
                "wind_direction_10m",
                "precipitation",
                "visibility"
            ])
        )
    }

    func testHistoricalWeatherKeepsOptionalEnvironmentFieldsOptional() async {
        let coordinate = SyntheticCoordinates.point()
        let client = OpenMeteoRecordingHTTPClient(json: """
        {
          "hourly": {
            "time": [1784365200],
            "temperature_2m": [22.5],
            "weather_code": [2]
          }
        }
        """)
        let api = OpenMeteoAPI(client: client)

        let result = await api.weather(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: "2026-07-18T09:00:00Z"
        )

        guard case let .success(point) = result else {
            return XCTFail("Expected base historical weather")
        }
        XCTAssertNil(point.windSpeedKph)
        XCTAssertNil(point.windDirectionDegrees)
        XCTAssertNil(point.precipitationMillimeters)
        XCTAssertNil(point.visibilityMeters)
    }
}

private actor OpenMeteoRequestRecorder {
    private var url: URL?

    func record(_ url: URL?) {
        self.url = url
    }

    func snapshot() -> URL? {
        url
    }
}

private struct OpenMeteoRecordingHTTPClient: HTTPClient {
    let json: String
    private let recorder = OpenMeteoRequestRecorder()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url ?? URL(string: "https://missing.example")!
        await recorder.record(url)
        return (
            Data(json.utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        )
    }

    func requestedURL() async -> URL? {
        await recorder.snapshot()
    }
}
