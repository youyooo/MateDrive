import AppIntents
import SwiftUI
import WidgetKit

struct CurrentChargeWidget: Widget {
    let kind = WidgetConstants.currentChargeKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CarStatusConfigurationIntent.self,
            provider: CurrentChargeTimelineProvider()
        ) { entry in
            CurrentChargeWidgetView(entry: entry)
        }
        .configurationDisplayName(LocalizedStringResource("Current Charge"))
        .description(LocalizedStringResource("Shows current read-only charging status."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CurrentChargeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetVehicleSnapshot?
    let configuredVehicleName: String?
    let vehicleIdentifier: String?
}

struct CurrentChargeTimelineProvider: AppIntentTimelineProvider {
    private let store: WidgetSnapshotStore

    init(store: WidgetSnapshotStore = .shared) {
        self.store = store
    }

    func placeholder(in context: Context) -> CurrentChargeEntry {
        CurrentChargeEntry(
            date: Date(),
            snapshot: .currentChargeFixture,
            configuredVehicleName: nil,
            vehicleIdentifier: nil
        )
    }

    func snapshot(
        for configuration: CarStatusConfigurationIntent,
        in context: Context
    ) async -> CurrentChargeEntry {
        entry(for: configuration)
    }

    func timeline(
        for configuration: CarStatusConfigurationIntent,
        in context: Context
    ) async -> Timeline<CurrentChargeEntry> {
        let entry = entry(for: configuration)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(15 * 60))
        )
    }

    private func entry(for configuration: CarStatusConfigurationIntent) -> CurrentChargeEntry {
        let snapshot: WidgetVehicleSnapshot?
        if let vehicle = configuration.vehicle {
            snapshot = store.vehicleSnapshot(vehicleIdentifier: vehicle.id)
        } else {
            snapshot = store.preferredVehicleSnapshot() ?? store.vehicleSnapshots().first
        }
        return CurrentChargeEntry(
            date: Date(),
            snapshot: snapshot,
            configuredVehicleName: configuration.vehicle?.name,
            vehicleIdentifier: snapshot?.id
        )
    }
}

private struct CurrentChargeWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: CurrentChargeEntry

    var body: some View {
        let presentation = WidgetCurrentChargePresentation.make(
            snapshot: entry.snapshot,
            configuredVehicleName: entry.configuredVehicleName,
            now: entry.date
        )

        Group {
            switch family {
            case .systemMedium:
                mediumView(presentation)
            default:
                smallView(presentation)
            }
        }
        .containerBackground(.background, for: .widget)
        .widgetURL(MateDriveWidgetNavigation.widgetURL(
            destination: .currentCharge,
            snapshotVehicleIdentifier: entry.vehicleIdentifier
        ))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: presentation.accessibilityText))
    }

    private func smallView(_ presentation: WidgetCurrentChargePresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(presentation.carName)
                .font(.headline)
                .lineLimit(1)

            statusLabel(presentation)
                .font(.caption.weight(.semibold))
                .lineLimit(2)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(presentation.batteryText)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.75)
                if let limit = presentation.limitText {
                    Text(limit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            if let detail = presentation.remainingText ?? presentation.powerText {
                Label {
                    Text(verbatim: detail)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } icon: {
                    Image(systemName: presentation.remainingText == nil ? "bolt.fill" : "clock")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let updated = presentation.updatedText, presentation.state != .unavailable {
                Text(verbatim: updated)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func mediumView(_ presentation: WidgetCurrentChargePresentation) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(presentation.carName)
                    .font(.headline)
                    .lineLimit(1)

                statusLabel(presentation)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(presentation.batteryText)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()

                if let progress = presentation.progress {
                    ProgressView(value: Double(progress.current), total: Double(progress.total))
                        .tint(.green)
                        .accessibilityHidden(true)
                } else if let limit = presentation.limitText {
                    Text(verbatim: limit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                if let chargeType = presentation.chargeTypeText {
                    metricLabel(chargeType, systemImage: "bolt.car")
                }
                if let power = presentation.powerText {
                    metricLabel(power, systemImage: "bolt.fill")
                }
                if let energy = presentation.energyText {
                    metricLabel(energy, systemImage: "battery.100percent.bolt")
                }
                if let remaining = presentation.remainingText {
                    metricLabel(remaining, systemImage: "clock")
                }

                Spacer(minLength: 0)

                if let trust = presentation.trustText {
                    Text(verbatim: trust)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
                if let updated = presentation.updatedText {
                    Text(verbatim: updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusLabel(_ presentation: WidgetCurrentChargePresentation) -> some View {
        Label {
            Text(verbatim: presentation.statusText)
        } icon: {
            Image(systemName: statusSymbol(for: presentation.state))
                .accessibilityHidden(true)
        }
        .foregroundStyle(statusColor(for: presentation.state))
    }

    private func metricLabel(_ text: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
        }
        .font(.caption)
    }

    private func statusSymbol(for state: WidgetChargeVisualState) -> String {
        switch state {
        case .charging:
            return "bolt.fill"
        case .starting:
            return "bolt.circle"
        case .idle:
            return "powerplug"
        case .offline:
            return "wifi.slash"
        case .stale:
            return "clock"
        case .unavailable:
            return "arrow.clockwise.circle"
        }
    }

    private func statusColor(for state: WidgetChargeVisualState) -> Color {
        switch state {
        case .charging:
            return .green
        case .starting, .offline, .stale, .unavailable:
            return .blue
        case .idle:
            return .secondary
        }
    }
}

private extension WidgetVehicleSnapshot {
    static let currentChargeFixture = WidgetVehicleSnapshot(
        id: "fixture",
        data: .fixture(
            carName: "Model 3",
            isCharging: true,
            displayLanguage: .english
        ),
        currentCharge: WidgetCurrentChargeData(
            phase: .charging,
            quality: .complete,
            batteryLevel: 64,
            chargeLimitSoc: 80,
            chargerPowerKW: 72,
            energyAddedKWh: 18.4,
            timeToFullMinutes: 65,
            isDC: true,
            updatedAt: Date()
        )
    )
}
