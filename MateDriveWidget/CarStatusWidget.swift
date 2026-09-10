import AppIntents
import SwiftUI
import WidgetKit

struct WidgetVehicleEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Vehicle"))
    static let defaultQuery = WidgetVehicleEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetVehicleEntityQuery: EntityQuery {
    private let store: WidgetSnapshotStore

    init() {
        self.store = .shared
    }

    init(store: WidgetSnapshotStore) {
        self.store = store
    }

    func entities(for identifiers: [WidgetVehicleEntity.ID]) async throws -> [WidgetVehicleEntity] {
        let requested = Set(identifiers)
        return store.vehicleSnapshots().compactMap { snapshot in
            guard requested.contains(snapshot.id) else { return nil }
            return WidgetVehicleEntity(id: snapshot.id, name: snapshot.data.carName)
        }
    }

    func suggestedEntities() async throws -> [WidgetVehicleEntity] {
        store.vehicleSnapshots().map {
            WidgetVehicleEntity(id: $0.id, name: $0.data.carName)
        }
    }

    func defaultResult() async -> WidgetVehicleEntity? {
        guard let snapshot = store.preferredVehicleSnapshot() ?? store.vehicleSnapshots().first else { return nil }
        return WidgetVehicleEntity(id: snapshot.id, name: snapshot.data.carName)
    }
}

struct CarStatusConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "MateDrive Vehicle"
    static let description = IntentDescription("Choose the vehicle shown by this widget.")

    @Parameter(title: "Vehicle")
    var vehicle: WidgetVehicleEntity?
}

struct CarStatusWidget: Widget {
    let kind = WidgetConstants.carStatusKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CarStatusConfigurationIntent.self,
            provider: CarStatusTimelineProvider()
        ) { entry in
            CarStatusWidgetView(entry: entry)
        }
        .configurationDisplayName("MateDrive")
        .description(LocalizedStringResource("Shows the latest read-only car status."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CarStatusEntry: TimelineEntry {
    let date: Date
    let data: WidgetDisplayData
    let vehicleIdentifier: String?
}

struct CarStatusTimelineProvider: AppIntentTimelineProvider {
    private let store: WidgetSnapshotStore

    init(store: WidgetSnapshotStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> CarStatusEntry {
        CarStatusEntry(
            date: Date(),
            data: .fixture(carName: "Model Y", isCharging: true),
            vehicleIdentifier: nil
        )
    }

    func snapshot(for configuration: CarStatusConfigurationIntent, in context: Context) async -> CarStatusEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CarStatusConfigurationIntent, in context: Context) async -> Timeline<CarStatusEntry> {
        let entry = entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: CarStatusConfigurationIntent) -> CarStatusEntry {
        if let vehicle = configuration.vehicle {
            let snapshot = store.vehicleSnapshot(vehicleIdentifier: vehicle.id)
            return CarStatusEntry(
                date: Date(),
                data: snapshot?.data ?? WidgetDisplayData(
                    carName: vehicle.name,
                    isReadOnly: true,
                    displayLanguage: .system
                ),
                vehicleIdentifier: snapshot?.id
            )
        }
        let snapshot = store.preferredVehicleSnapshot() ?? store.vehicleSnapshots().first
        return CarStatusEntry(
            date: Date(),
            data: snapshot?.data ?? store.load() ?? .fixture(),
            vehicleIdentifier: snapshot?.id
        )
    }
}

struct CarStatusWidgetView: View {
    let entry: CarStatusEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WidgetBatteryRing(data: entry.data)
                .opacity(0.14)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.data.carName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: entry.data.isReadOnly ? "eye" : "bolt.car")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(entry.data.batteryText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 8) {
                    Label {
                        Text(verbatim: entry.data.statusText)
                    } icon: {
                        Image(systemName: entry.data.isCharging ? "bolt.fill" : "circle.fill")
                    }
                    if let lockText = entry.data.lockText, let isLocked = entry.data.isLocked {
                        Label {
                            Text(verbatim: lockText)
                        } icon: {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(entry.data.rangeText)
                    if !entry.data.temperatureText.isEmpty {
                        Text(entry.data.temperatureText)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let location = entry.data.locationText {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(MateDriveWidgetNavigation.widgetURL(
            destination: .dashboard,
            snapshotVehicleIdentifier: entry.vehicleIdentifier
        ))
    }
}

private struct WidgetBatteryRing: View {
    let data: WidgetDisplayData

    var body: some View {
        let level = data.batteryLevel.map { min(max($0, 0), 100) }
        let progress = Double(level ?? 0) / 100
        let batteryGreen = Color(red: 0.10, green: 0.68, blue: 0.32)
        let tint: Color = if let level, level <= 10 {
            .red
        } else if let level, level <= 20 {
            .orange
        } else {
            batteryGreen
        }

        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.35), lineWidth: 11)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: data.isCharging ? "bolt.fill" : "battery.75percent")
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 118, height: 118)
        .offset(x: 24, y: -24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(Text(data.batteryText))
    }
}
