import SwiftUI

public struct WeatherAlongTheWayView: View {
    @Environment(\.appLanguage) private var appLanguage

    let points: [DriveWeatherPoint]
    let units: UnitPreferences?
    let isLoading: Bool

    public init(points: [DriveWeatherPoint], units: UnitPreferences?, isLoading: Bool) {
        self.points = points
        self.units = units
        self.isLoading = isLoading
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Weather Along The Way", "沿途天气"))
                .font(.headline)

            if isLoading {
                LoadingStateView(title: t("Loading weather", "正在加载天气"), showsProgress: true)
                    .frame(minHeight: 90)
            } else if points.isEmpty {
                LoadingStateView(title: t("No weather samples", "暂无天气采样"), systemImage: "cloud.sun")
                    .frame(minHeight: 90)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(points) { point in
                            VStack(spacing: 6) {
                                Image(systemName: iconName(for: point.weatherCode))
                                    .font(.title3)
                                Text(MateDroidUnitFormatter.formatTemperature(point.temperatureCelsius, units: units))
                                    .font(.headline.monospacedDigit())
                                Text(coordinateText(point))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(width: 96)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                        }
                    }
                }
            }
        }
    }

    private func iconName(for code: Int) -> String {
        switch code {
        case 0:
            return "sun.max"
        case 1...3:
            return "cloud.sun"
        case 45...48:
            return "cloud.fog"
        case 51...67, 80...82:
            return "cloud.rain"
        case 71...77, 85...86:
            return "cloud.snow"
        case 95...99:
            return "cloud.bolt.rain"
        default:
            return "cloud"
        }
    }

    private func coordinateText(_ point: DriveWeatherPoint) -> String {
        String(format: "%.2f, %.2f", point.latitude, point.longitude)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
