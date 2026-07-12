import SwiftUI
import WidgetKit

struct CarStatusWidget: Widget {
    let kind = WidgetConstants.carStatusKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarStatusTimelineProvider()) { entry in
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
}

struct CarStatusTimelineProvider: TimelineProvider {
    private let store: WidgetSnapshotStore

    init(store: WidgetSnapshotStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> CarStatusEntry {
        CarStatusEntry(date: Date(), data: .fixture(carName: "Model Y", isCharging: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (CarStatusEntry) -> Void) {
        completion(CarStatusEntry(date: Date(), data: store.load() ?? .fixture()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarStatusEntry>) -> Void) {
        let entry = CarStatusEntry(date: Date(), data: store.load() ?? .fixture())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct CarStatusWidgetView: View {
    let entry: CarStatusEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let imageName = entry.data.carImageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

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
                        Image(systemName: entry.data.isCharging ? "bolt.fill" : "car")
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
    }
}
