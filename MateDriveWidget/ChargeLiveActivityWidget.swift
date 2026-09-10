import ActivityKit
import SwiftUI
import WidgetKit

struct ChargeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargeLiveActivityAttributes.self) { context in
            let presentation = ChargeLiveActivityPresentation.make(
                attributes: context.attributes,
                state: context.state,
                isStale: context.isStale
            )
            ChargeLiveActivityLockScreenView(presentation: presentation)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(MateDriveWidgetNavigation.widgetURL(
                destination: .currentCharge,
                snapshotVehicleIdentifier: context.attributes.vehicleIdentifier
            ))
        } dynamicIsland: { context in
            let presentation = ChargeLiveActivityPresentation.make(
                attributes: context.attributes,
                state: context.state,
                isStale: context.isStale
            )
            let dynamicIsland = DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    BatteryValue(presentation: presentation)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PowerValue(presentation: presentation)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(presentation.carName)
                            .font(.headline)
                            .lineLimit(1)
                        Text(presentation.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(presentation.accessibilityText))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ChargeProgress(presentation: presentation)
                        HStack {
                            if let remainingText = presentation.remainingText {
                                Text(remainingText)
                            }
                            Spacer(minLength: 8)
                            Text(presentation.updatedText)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityHidden(true)
                }
            } compactLeading: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            } compactTrailing: {
                Text(presentation.batteryText)
                    .monospacedDigit()
                    .opacity(presentation.isStale ? 0.55 : 1)
                    .accessibilityLabel(Text(presentation.accessibilityText))
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text(presentation.accessibilityText))
            }
            .keylineTint(.green)

            if let url = MateDriveWidgetNavigation.widgetURL(
                destination: .currentCharge,
                snapshotVehicleIdentifier: context.attributes.vehicleIdentifier
            ) {
                return dynamicIsland.widgetURL(url)
            }
            return dynamicIsland
        }
    }
}

private struct ChargeLiveActivityLockScreenView: View {
    let presentation: ChargeLiveActivityPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.carName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(presentation.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
                BatteryValue(presentation: presentation)
            }

            ChargeProgress(presentation: presentation)

            HStack(spacing: 18) {
                PowerValue(presentation: presentation)
                if let energyText = presentation.energyText {
                    MetricValue(icon: "bolt.badge.clock", text: energyText)
                }
                Spacer(minLength: 0)
                if let remainingText = presentation.remainingText {
                    MetricValue(icon: "clock", text: remainingText)
                }
            }
            .opacity(presentation.isStale ? 0.55 : 1)

            Text(presentation.updatedText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.accessibilityText))
    }
}

private struct ChargeProgress: View {
    let presentation: ChargeLiveActivityPresentation

    var body: some View {
        VStack(spacing: 5) {
            if let progress = presentation.progress {
                ProgressView(
                    value: Double(progress.current),
                    total: Double(progress.total)
                )
                .tint(.green)
            }
            HStack {
                Text(presentation.batteryLabelText)
                if let limitText = presentation.limitText {
                    Spacer()
                    Text(limitText)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .opacity(presentation.isStale ? 0.55 : 1)
    }
}

private struct BatteryValue: View {
    let presentation: ChargeLiveActivityPresentation

    var body: some View {
        Text(presentation.batteryText)
            .font(.title3.bold())
            .monospacedDigit()
            .foregroundStyle(.green)
            .opacity(presentation.isStale ? 0.55 : 1)
    }
}

private struct PowerValue: View {
    let presentation: ChargeLiveActivityPresentation

    var body: some View {
        if let powerText = presentation.powerText {
            MetricValue(
                icon: "gauge.with.dots.needle.67percent",
                text: powerText
            )
            .opacity(presentation.isStale ? 0.55 : 1)
        }
    }
}

private struct MetricValue: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.monospacedDigit())
            .lineLimit(1)
    }
}
