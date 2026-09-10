import AppIntents
import SwiftUI
import WidgetKit

struct BatteryTrendWidget: Widget {
    let kind = WidgetConstants.batteryTrendKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CarStatusConfigurationIntent.self,
            provider: BatteryTrendTimelineProvider()
        ) { entry in
            BatteryTrendWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("Battery Trend"))
        .description(LocalizedStringResource("Shows a privacy-safe battery capacity or range trend."))
        .supportedFamilies([.systemMedium])
    }
}

struct ChargingTrendWidget: Widget {
    let kind = WidgetConstants.chargingTrendKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CarStatusConfigurationIntent.self,
            provider: ChargingTrendTimelineProvider()
        ) { entry in
            ChargingTrendWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("Charging Trend"))
        .description(LocalizedStringResource("Shows 30-day charging energy and known cost totals."))
        .supportedFamilies([.systemMedium])
    }
}

struct TrendWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetVehicleSnapshot?
    let configuredVehicleName: String?
    let vehicleIdentifier: String?
}

struct BatteryTrendTimelineProvider: AppIntentTimelineProvider {
    private let store: WidgetSnapshotStore

    init(store: WidgetSnapshotStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> TrendWidgetEntry {
        TrendWidgetEntry(
            date: Date(),
            snapshot: .batteryFixture,
            configuredVehicleName: nil,
            vehicleIdentifier: nil
        )
    }

    func snapshot(for configuration: CarStatusConfigurationIntent, in context: Context) async -> TrendWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CarStatusConfigurationIntent, in context: Context) async -> Timeline<TrendWidgetEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: CarStatusConfigurationIntent) -> TrendWidgetEntry {
        let snapshot = configuration.vehicle.flatMap { store.vehicleSnapshot(vehicleIdentifier: $0.id) }
            ?? (configuration.vehicle == nil ? store.preferredVehicleSnapshot() ?? store.vehicleSnapshots().first : nil)
        return TrendWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            configuredVehicleName: configuration.vehicle?.name,
            vehicleIdentifier: snapshot?.id
        )
    }
}

struct ChargingTrendTimelineProvider: AppIntentTimelineProvider {
    private let store: WidgetSnapshotStore

    init(store: WidgetSnapshotStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> TrendWidgetEntry {
        TrendWidgetEntry(
            date: Date(),
            snapshot: .chargingFixture,
            configuredVehicleName: nil,
            vehicleIdentifier: nil
        )
    }

    func snapshot(for configuration: CarStatusConfigurationIntent, in context: Context) async -> TrendWidgetEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CarStatusConfigurationIntent, in context: Context) async -> Timeline<TrendWidgetEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func entry(for configuration: CarStatusConfigurationIntent) -> TrendWidgetEntry {
        let snapshot = configuration.vehicle.flatMap { store.vehicleSnapshot(vehicleIdentifier: $0.id) }
            ?? (configuration.vehicle == nil ? store.preferredVehicleSnapshot() ?? store.vehicleSnapshots().first : nil)
        return TrendWidgetEntry(
            date: Date(),
            snapshot: snapshot,
            configuredVehicleName: configuration.vehicle?.name,
            vehicleIdentifier: snapshot?.id
        )
    }
}

private struct BatteryTrendWidgetView: View {
    let entry: TrendWidgetEntry

    var body: some View {
        let language = entry.snapshot?.data.displayLanguage ?? .system
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text(verbatim: language.value(
                        english: "Battery trend", chinese: "电池趋势", traditionalChinese: "電池趨勢"
                    ))
                } icon: {
                    Image(systemName: "battery.75percent")
                }
                .font(.headline)
                .foregroundStyle(.green)

                Text(entry.snapshot?.data.carName ?? entry.configuredVehicleName ?? "MateDrive")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let trend = entry.snapshot?.batteryTrend {
                    Text(trend.headlineText)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(verbatim: trend.headlineLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text(verbatim: unavailable(language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trend = entry.snapshot?.batteryTrend {
                VStack(alignment: .trailing, spacing: 7) {
                    WidgetSparkline(samples: trend.samples, color: .green)
                        .frame(height: 58)
                    Text(trend.currentValueText)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                    Text(verbatim: trend.periodText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(MateDriveWidgetNavigation.widgetURL(
            destination: .battery,
            snapshotVehicleIdentifier: entry.vehicleIdentifier
        ))
    }

    private func unavailable(_ language: WidgetDisplayLanguage) -> String {
        language.value(
            english: "Open MateDrive to sync", chinese: "打开 MateDrive 同步", traditionalChinese: "開啟 MateDrive 同步"
        )
    }
}

private struct ChargingTrendWidgetView: View {
    let entry: TrendWidgetEntry

    var body: some View {
        let language = entry.snapshot?.data.displayLanguage ?? .system
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label {
                    Text(verbatim: entry.snapshot?.chargingTrend?.title ?? language.value(
                        english: "Charging trend", chinese: "充电趋势", traditionalChinese: "充電趨勢"
                    ))
                } icon: {
                    Image(systemName: "bolt.fill")
                }
                .font(.headline)
                .foregroundStyle(.blue)

                Text(entry.snapshot?.data.carName ?? entry.configuredVehicleName ?? "MateDrive")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let trend = entry.snapshot?.chargingTrend {
                    Text(trend.energyText)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(verbatim: trend.sessionText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("-- kWh")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(verbatim: unavailable(language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let trend = entry.snapshot?.chargingTrend {
                VStack(alignment: .trailing, spacing: 7) {
                    WidgetBarTrend(samples: trend.energyBuckets)
                        .frame(height: 54)
                    Text(trend.costText)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                    Text(verbatim: trend.costLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(verbatim: trend.periodText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(MateDriveWidgetNavigation.widgetURL(
            destination: .charges,
            snapshotVehicleIdentifier: entry.vehicleIdentifier
        ))
    }

    private func unavailable(_ language: WidgetDisplayLanguage) -> String {
        language.value(
            english: "Open MateDrive to sync", chinese: "打开 MateDrive 同步", traditionalChinese: "開啟 MateDrive 同步"
        )
    }
}

private struct WidgetSparkline: View {
    let samples: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2,
                  let minimum = samples.min(),
                  let maximum = samples.max()
            else { return }
            let span = max(maximum - minimum, maximum * 0.02, 0.1)
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(samples.count - 1)
                let y = size.height * CGFloat(1 - (sample - minimum) / span)
                let point = CGPoint(x: x, y: min(max(y, 2), size.height - 2))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct WidgetBarTrend: View {
    let samples: [Double]

    var body: some View {
        GeometryReader { proxy in
            let maximum = max(samples.max() ?? 0, 0.1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(samples.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.blue.gradient)
                        .frame(height: max(3, proxy.size.height * value / maximum))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private extension WidgetVehicleSnapshot {
    static let batteryFixture = WidgetVehicleSnapshot(
        id: "fixture",
        data: .fixture(carName: "Model 3"),
        batteryTrend: WidgetBatteryTrendData(
            healthPercent: 91.8,
            showsAbsoluteHealth: true,
            metric: .capacity,
            samples: [76.2, 75.8, 75.1, 74.9, 74.4, 74.1],
            currentValue: 74.1,
            recordedDays: 180,
            qualityScore: 88
        )
    )

    static let chargingFixture = WidgetVehicleSnapshot(
        id: "fixture",
        data: .fixture(carName: "Model 3"),
        chargingTrend: WidgetChargingTrendData(
            sessionCount: 8,
            energyKWh: 186.4,
            energyKnownCount: 8,
            cost: 126.8,
            costKnownCount: 8,
            currencyCode: "CNY",
            energyBuckets: [18, 42, 26, 51, 22, 27]
        )
    )
}
