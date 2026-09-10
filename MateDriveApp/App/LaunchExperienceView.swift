import SwiftUI

enum LaunchExperienceTiming {
    static let minimumDisplayDuration: Duration = .seconds(3)
}

enum MateDriveMotion {
    static func animationsEnabled(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}

struct LaunchExperienceSnapshot: Equatable, Sendable {
    let carName: String?
    let batteryLevel: Int?
    let ratedRangeKm: Double?
    let chargingEnergyKWh: Double?
    let outsideTemperatureCelsius: Double?
    let isCharging: Bool
    let usesImperialUnits: Bool

    init(snapshot: WidgetVehicleSnapshot?) {
        let data = snapshot?.data
        let normalizedName = data?.carName.trimmingCharacters(in: .whitespacesAndNewlines)
        carName = normalizedName.flatMap { $0.isEmpty ? nil : $0 }
        batteryLevel = data?.batteryLevel.flatMap { (0 ... 100).contains($0) ? $0 : nil }
        ratedRangeKm = Self.nonnegativeFinite(data?.ratedRange)
        chargingEnergyKWh = Self.nonnegativeFinite(snapshot?.chargingTrend?.energyKWh)
        outsideTemperatureCelsius = Self.finite(data?.outsideTemperature)
        isCharging = data?.isCharging == true
        usesImperialUnits = data?.displayUnitSystem?.usesImperial == true
    }

    var batteryText: String {
        batteryLevel.map { "\($0)%" } ?? "--"
    }

    var rangeText: String {
        guard let ratedRangeKm else { return "--" }
        return MateDriveUnitFormatter.formatDistance(
            ratedRangeKm,
            units: usesImperialUnits ? .imperial : .metric,
            decimals: 0
        )
    }

    var energyText: String {
        guard let chargingEnergyKWh else { return "--" }
        return String(format: "%.1f kWh", locale: Locale(identifier: "en_US_POSIX"), chargingEnergyKWh)
    }

    var outsideTemperatureText: String {
        guard let outsideTemperatureCelsius else { return "--" }
        return MateDriveUnitFormatter.formatTemperature(
            outsideTemperatureCelsius,
            units: usesImperialUnits ? .imperial : .metric
        )
    }

    var batteryProgress: Double {
        Double(batteryLevel ?? 0) / 100
    }

    private static func nonnegativeFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}

struct LaunchExperienceView: View {
    let snapshot: LaunchExperienceSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedBatteryProgress = 0.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image("LaunchBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Color.white.opacity(0.08)

                VStack(spacing: 0) {
                    header

                    Spacer(minLength: max(52, proxy.size.height * 0.09))

                    batteryGauge(size: min(158, proxy.size.width * 0.4))

                    Spacer(minLength: max(46, proxy.size.height * 0.07))

                    metricGrid

                    Spacer(minLength: max(18, proxy.safeAreaInsets.bottom + 8))
                }
                .padding(.horizontal, 24)
                .padding(.top, max(72, proxy.safeAreaInsets.top + 18))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .light)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MateDrive")
        .onAppear {
            if MateDriveMotion.animationsEnabled(reduceMotion: reduceMotion) {
                withAnimation(.easeOut(duration: 0.85)) {
                    animatedBatteryProgress = snapshot.batteryProgress
                }
            } else {
                animatedBatteryProgress = snapshot.batteryProgress
            }
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("MateDrive")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.black)

            if let carName = snapshot.carName {
                Text(carName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func batteryGauge(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)

            Circle()
                .stroke(Color.black.opacity(0.07), lineWidth: 12)

            Circle()
                .trim(from: 0, to: animatedBatteryProgress)
                .stroke(
                    Color(red: 0.12, green: 0.72, blue: 0.35),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text(snapshot.batteryText)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.black)
                    .contentTransition(.numericText())

                Text("Battery")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Circle().stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            LaunchMetricCard(label: "Range", icon: "road.lanes", tint: .cyan) {
                Text(snapshot.rangeText)
            }
            LaunchMetricCard(label: "Energy", icon: "bolt.fill", tint: .green) {
                Text(snapshot.energyText)
            }
            LaunchMetricCard(label: "Outside", icon: "thermometer.medium", tint: .orange) {
                Text(snapshot.outsideTemperatureText)
            }
            LaunchMetricCard(label: "Vehicle", icon: "car.fill", tint: .black.opacity(0.65)) {
                if snapshot.isCharging {
                    Text("Charging")
                } else {
                    Text("Parked")
                }
            }
        }
    }
}

private struct LaunchMetricCard<Value: View>: View {
    let label: LocalizedStringKey
    let icon: String
    let tint: Color
    let value: Value

    init(
        label: LocalizedStringKey,
        icon: String,
        tint: Color,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.icon = icon
        self.tint = tint
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20, height: 20)

                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            value
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.76), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.055), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}
