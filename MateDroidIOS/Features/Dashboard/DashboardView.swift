import SwiftUI

public struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: DashboardViewModel
    @State private var hasLoaded = false

    private let navigate: (AppRoute) -> Void

    public init(viewModel: DashboardViewModel, navigate: @escaping (AppRoute) -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigate = navigate
    }

    public var body: some View {
        let state = viewModel.state
        let palette = CarColorPalettes.forExteriorColor(state.exteriorColor, darkTheme: colorScheme == .dark)

        Group {
            if state.isLoading, state.cars.isEmpty {
                LoadingStateView(title: t("Loading dashboard", "正在加载首页"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(state: state, palette: palette)
                        carSelector(state: state)
                        metrics(state: state, palette: palette)
                        tyrePressureSection(state: state, palette: palette)
                        navigationGrid(state: state, palette: palette)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .background(palette.surfaceColor.ignoresSafeArea())
        .foregroundStyle(palette.onSurfaceColor)
        .carPalette(palette)
        .tint(palette.accentColor)
        .navigationTitle("MateDrive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    navigate(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text(t("Settings", "设置")))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Image(systemName: state.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                }
                .disabled(state.isRefreshing)
                .accessibilityLabel(Text(t("Refresh", "刷新")))
            }
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func header(state: DashboardState, palette: CarColorPalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: state.carName)
                        .font(.largeTitle.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let modelName = modelLine(for: state) {
                        Text(verbatim: modelName)
                            .font(.subheadline)
                            .foregroundStyle(palette.onSurfaceVariantColor)
                    }
                    Text(verbatim: statusLine(for: state))
                        .font(.subheadline)
                        .foregroundStyle(palette.onSurfaceVariantColor)
                }
                Spacer()
                batteryBadge(state: state, palette: palette)
                    .fixedSize()
            }

            CarImageView(assetPath: state.carImagePath, scaleFactor: CGFloat(state.carImageScaleFactor), displayScale: 1.18)
                .padding(.horizontal, -16)

            if let error = state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.isUsingCachedData, let cachedAt = state.cachedAt {
                Label(
                    t("Offline snapshot from \(cachedAt.formatted(date: .abbreviated, time: .shortened))", "离线数据，更新于 \(cachedAt.formatted(date: .abbreviated, time: .shortened))"),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func carSelector(state: DashboardState) -> some View {
        if state.cars.count > 1, let selectedCarId = state.selectedCarId {
            Picker(t("Vehicle", "车辆"), selection: Binding(
                get: { selectedCarId },
                set: { newValue in
                    Task { await viewModel.selectCar(id: newValue) }
                }
            )) {
                ForEach(state.cars) { car in
                    Text(car.name).tag(car.id)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func metrics(state: DashboardState, palette: CarColorPalette) -> some View {
        let units = state.units.resolved(for: appDisplayUnitSystem)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
            MetricCard(
                title: DashboardTextFormatter.title("Charging", language: appLanguage),
                value: DashboardTextFormatter.chargingValue(isCharging: state.isCharging, language: appLanguage),
                subtitle: DashboardTextFormatter.currentChargeSubtitle(isCharging: state.isCharging, language: appLanguage),
                systemImage: state.isCharging ? "bolt.fill" : "bolt.slash",
                tint: state.isCharging ? palette.accentColor : palette.onSurfaceVariantColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("Lock", language: appLanguage),
                value: DashboardTextFormatter.lockText(state.isLocked, language: appLanguage),
                systemImage: state.isLocked == true ? "lock.fill" : "lock.open",
                tint: palette.accentColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("Sentry", language: appLanguage),
                value: DashboardTextFormatter.sentryValue(isActive: state.sentryModeActive, language: appLanguage),
                systemImage: state.sentryModeActive ? "shield.fill" : "shield",
                tint: palette.accentColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("Outside", language: appLanguage),
                value: temperatureText(state.outsideTemperature, units: units),
                systemImage: "thermometer.sun",
                tint: palette.accentColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("Inside", language: appLanguage),
                value: temperatureText(state.insideTemperature, units: units),
                systemImage: "thermometer.medium",
                tint: palette.accentColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("History", language: appLanguage),
                value: DashboardTextFormatter.historyText(charges: state.totalCharges, drives: state.totalDrives, language: appLanguage),
                subtitle: DashboardTextFormatter.updatesText(state.totalUpdates, language: appLanguage),
                systemImage: "chart.bar.xaxis",
                tint: palette.accentColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("Location", language: appLanguage),
                value: state.locationText ?? "--",
                systemImage: "location.fill",
                tint: palette.accentColor,
                valueLineLimit: 2
            )
            MetricCard(
                title: DashboardTextFormatter.title("Odometer", language: appLanguage),
                value: odometerText(state.odometer, units: units),
                systemImage: "gauge.with.dots.needle.50percent",
                tint: palette.accentColor
            )
            MetricCard(
                title: DashboardTextFormatter.title("Software", language: appLanguage),
                value: state.softwareVersion ?? "--",
                systemImage: "shippingbox",
                tint: palette.accentColor
            )
        }
    }

    @ViewBuilder
    private func tyrePressureSection(state: DashboardState, palette: CarColorPalette) -> some View {
        if let tpms = state.tpmsDetails, tpms.hasAnyData {
            DashboardTyrePressureView(tpms: tpms, units: state.units, palette: palette)
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private func navigationGrid(state: DashboardState, palette: CarColorPalette) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(routes(for: state)) { item in
                Button {
                    navigate(item.route)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .frame(width: 22)
                        Text(verbatim: DashboardTextFormatter.title(item.title, language: appLanguage))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.onSurfaceVariantColor)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func batteryBadge(state: DashboardState, palette: CarColorPalette) -> some View {
        Text(state.batteryLevel.map { "\($0)%" } ?? "--")
            .font(.title3.weight(.bold))
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(palette.accentDimColor)
            )
            .foregroundStyle(palette.onSurfaceColor)
    }

    private func routes(for state: DashboardState) -> [DashboardRouteItem] {
        guard let carId = state.selectedCarId else {
            return [
                DashboardRouteItem(title: "Settings", systemImage: "gearshape", route: .settings),
                DashboardRouteItem(title: "Palette", systemImage: "paintpalette", route: .palettePreview)
            ]
        }

        return DashboardNavigation.items(carId: carId, exteriorColor: state.exteriorColor)
    }

    private func statusLine(for state: DashboardState) -> String {
        return DashboardTextFormatter.statusLine(isCharging: state.isCharging, sentryModeActive: state.sentryModeActive, language: appLanguage)
    }

    private func modelLine(for state: DashboardState) -> String? {
        guard let modelName = state.vehicleModelName?.trimmingCharacters(in: .whitespacesAndNewlines), !modelName.isEmpty else {
            return nil
        }
        let carName = state.carName.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelName.hasSuffix(carName) {
            let prefix = modelName.dropLast(carName.count).trimmingCharacters(in: .whitespacesAndNewlines)
            return prefix.isEmpty ? nil : prefix
        }
        return modelName == carName ? nil : modelName
    }

    private func temperatureText(_ value: Double?, units: UnitPreferences?) -> String {
        guard let value else {
            return "--"
        }
        return MateDroidUnitFormatter.formatTemperature(value, units: units)
    }

    private func odometerText(_ value: Double?, units: UnitPreferences?) -> String {
        guard let value else { return "--" }
        return MateDroidUnitFormatter.formatDistance(value, units: units, decimals: 0)
    }
}

public struct DashboardTyrePressureView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let tpms: TpmsDetails
    let units: UnitPreferences?
    let palette: CarColorPalette

    public var body: some View {
        let resolvedUnits = units.resolved(for: appDisplayUnitSystem)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(t("Tyre Pressure", "胎压"), systemImage: "tire").font(.headline)
                Spacer()
                Label(
                    tpms.hasWarning ? t("Check tyres", "请检查轮胎") : t("Normal", "正常"),
                    systemImage: tpms.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tpms.hasWarning ? .red : .green)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tyreCell(t("Front Left", "左前"), pressure: tpms.pressureFl, warning: tpms.warningFl, units: resolvedUnits)
                tyreCell(t("Front Right", "右前"), pressure: tpms.pressureFr, warning: tpms.warningFr, units: resolvedUnits)
                tyreCell(t("Rear Left", "左后"), pressure: tpms.pressureRl, warning: tpms.warningRl, units: resolvedUnits)
                tyreCell(t("Rear Right", "右后"), pressure: tpms.pressureRr, warning: tpms.warningRr, units: resolvedUnits)
            }
        }
    }

    private func tyreCell(_ title: String, pressure: Double?, warning: Bool?, units: UnitPreferences?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: warning == true ? "exclamationmark.circle.fill" : "circle.fill")
                .foregroundStyle(warning == true ? .red : palette.accentColor)
                .font(.caption)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(palette.onSurfaceVariantColor)
                Text(pressure.map { MateDroidUnitFormatter.formatPressure($0, units: units) } ?? "--")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

struct DashboardRouteItem: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let route: AppRoute
}

enum DashboardNavigation {
    static func items(carId: Int, exteriorColor: String?) -> [DashboardRouteItem] {
        [
            DashboardRouteItem(title: "Current Charge", systemImage: "bolt.car", route: .currentCharge(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Activities", systemImage: "clock.arrow.circlepath", route: .activities(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Place Insights", systemImage: "mappin.and.ellipse", route: .places(carId: carId)),
            DashboardRouteItem(title: "Achievements", systemImage: "trophy", route: .achievements(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Charges", systemImage: "bolt.fill", route: .charges(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Drives", systemImage: "road.lanes", route: .drives(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Recent Driving Map", systemImage: "map", route: .recentDrivingMap(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Trips", systemImage: "map", route: .trips(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Stats", systemImage: "chart.xyaxis.line", route: .stats(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Drive Insights", systemImage: "chart.line.text.clipboard", route: .driveInsights(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Environment History", systemImage: "thermometer.variable.and.figure", route: .environmentHistory(carId: carId)),
            DashboardRouteItem(title: "Standby Hotspots", systemImage: "moon.zzz", route: .topDrainLocations(carId: carId)),
            DashboardRouteItem(title: "Commute Routes", systemImage: "arrow.triangle.swap", route: .commuteRoutes(carId: carId)),
            DashboardRouteItem(title: "Battery", systemImage: "battery.75percent", route: .battery(carId: carId, efficiency: nil, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Mileage", systemImage: "speedometer", route: .mileage(carId: carId, exteriorColor: exteriorColor, targetDay: nil)),
            DashboardRouteItem(title: "Updates", systemImage: "arrow.down.circle", route: .updates(carId: carId, exteriorColor: exteriorColor)),
            DashboardRouteItem(title: "Sentry", systemImage: "shield.lefthalf.filled", route: .sentryHistory(carId: carId, exteriorColor: exteriorColor))
        ]
    }
}
