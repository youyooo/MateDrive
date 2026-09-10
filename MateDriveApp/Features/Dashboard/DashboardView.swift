import MapKit
import SwiftUI

struct DashboardVehicleTitlePresentation: Equatable {
    let title: String
    let showsPerformanceUnderline: Bool

    var accessibilityLabel: String {
        showsPerformanceUnderline ? "\(title) Performance" : title
    }

    init(name: String, trimBadging: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let performanceSuffix = " Performance"
        let nameIdentifiesPerformance = trimmedName.lowercased().hasSuffix(performanceSuffix.lowercased())
        let normalizedTrim = trimBadging?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber } ?? ""
        let trimIdentifiesPerformance = normalizedTrim == "p"
            || normalizedTrim.contains("performance")
            || (normalizedTrim.hasPrefix("p") && normalizedTrim.dropFirst().contains(where: \.isNumber))

        showsPerformanceUnderline = nameIdentifiesPerformance || trimIdentifiesPerformance
        title = nameIdentifiesPerformance
            ? String(trimmedName.dropLast(performanceSuffix.count))
            : trimmedName
    }
}

public struct DashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var viewModel: DashboardViewModel
    @State private var hasLoaded = false
    @State private var isShowingRange = false

    private let navigate: (AppRoute) -> Void

    public init(viewModel: DashboardViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.viewModel = viewModel
        self.navigate = navigate
    }

    public var body: some View {
        let state = viewModel.state
        let palette = MateDrivePalettes.forColorScheme(darkTheme: colorScheme == .dark)

        Group {
            if state.isLoading, state.cars.isEmpty {
                LoadingStateView(title: t("Loading dashboard", "正在加载首页"), showsProgress: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(state: state, palette: palette)
                        carSelector(state: state)
                        locationMap(state: state, palette: palette)
                        vehicleOverviewCards(state: state)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .contentMargins(.bottom, 96, for: .scrollContent)
                .modifier(DashboardBottomScrollEdgeModifier())
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .background(palette.surfaceColor.ignoresSafeArea())
        .foregroundStyle(palette.onSurfaceColor)
        .mateDrivePalette(palette)
        .tint(palette.accentColor)
        .navigationTitle("MateDrive")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .accessibilityIdentifier("dashboard_view")
        .onAppear {
            AppLaunchPerformanceMonitor.shared.cachedContentPresented()
        }
        .task {
            guard !hasLoaded else {
                return
            }
            hasLoaded = true
            await viewModel.load()
        }
        .onChange(of: state.selectedCarId) {
            isShowingRange = false
        }
    }

    @ViewBuilder
    private func header(state: DashboardState, palette: MateDrivePalette) -> some View {
        let vehicleTitle = DashboardVehicleTitlePresentation(name: state.carName, trimBadging: state.trimBadging)
        let softwareVersion = state.softwareVersion ?? "--"

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: vehicleTitle.title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)

                    if vehicleTitle.showsPerformanceUnderline {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(red: 0.91, green: 0.03, blue: 0.10))
                            .frame(width: 48, height: 4)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(vehicleTitle.accessibilityLabel))

                HStack(spacing: 12) {
                    Label(softwareVersion, systemImage: "shippingbox")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.onSurfaceVariantColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(t("Software version \(softwareVersion)", "软件版本 \(softwareVersion)")))

                    Label(statusLine(for: state), systemImage: statusIcon(for: state))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(statusTint(for: state))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }

            batteryHero(state: state, palette: palette)

            if let error = state.errorMessage, !isStoreScreenshotMode {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(readableWarningColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("dashboard_error_banner")
            }
            if state.isUsingCachedData, let cachedAt = state.cachedAt, !isStoreScreenshotMode {
                Label(
                    t("Offline snapshot from \(cachedAt.formatted(date: .abbreviated, time: .shortened))", "离线数据，更新于 \(cachedAt.formatted(date: .abbreviated, time: .shortened))"),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(readableWarningColor)
                .accessibilityIdentifier("dashboard_offline_banner")
            }
        }
    }

    private var isStoreScreenshotMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MATEDRIVE_STORE_SCREENSHOT_MODE"] == "1"
        #else
        false
        #endif
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

    private func vehicleOverviewCards(state: DashboardState) -> some View {
        let presentation = DashboardOverviewPresentation(
            state: state,
            units: state.units.resolved(for: appDisplayUnitSystem),
            language: appLanguage
        )

        return VStack(alignment: .leading, spacing: 9) {
            Text(t("Vehicle Overview", "车辆概览"))
                .font(.headline)

            DashboardOverviewCards(items: presentation.items, onSelect: navigate)
        }
    }

    @ViewBuilder
    private func locationMap(state: DashboardState, palette: MateDrivePalette) -> some View {
        let location = GeoCoordinateValidator.location(latitude: state.latitude, longitude: state.longitude)
        if let location {
            let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let vehicleTitle = DashboardVehicleTitlePresentation(name: state.carName, trimBadging: state.trimBadging)
            Button {
                guard let carId = state.selectedCarId else { return }
                navigate(.recentDrivingMap(carId: carId, exteriorColor: state.exteriorColor))
            } label: {
                ZStack(alignment: .bottom) {
                    DashboardLocationMap(coordinate: coordinate, title: vehicleTitle.title, tint: batteryGreen)
                        .allowsHitTesting(false)

                    HStack(spacing: 10) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(batteryGreen)
                        Text(verbatim: state.currentGeofence?.name ?? state.locationText ?? t("Current vehicle location", "车辆当前位置"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.onSurfaceColor)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.onSurfaceVariantColor)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.regularMaterial)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(t("Vehicle location", "车辆位置")))
            .accessibilityValue(Text(state.currentGeofence?.name ?? state.locationText ?? t("Current vehicle location", "车辆当前位置")))
            .accessibilityHint(Text(t("Open recent driving map", "打开近期行驶地图")))
            .id("\(location.latitude),\(location.longitude)")
        } else {
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.title3)
                    .foregroundStyle(palette.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Vehicle location", "车辆位置"))
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: state.locationText ?? t("Location unavailable", "暂无位置数据"))
                        .font(.footnote)
                        .foregroundStyle(palette.onSurfaceVariantColor)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private func batteryHero(state: DashboardState, palette: MateDrivePalette) -> some View {
        let level = state.batteryLevel.map { min(max($0, 0), 100) }
        let progress = Double(level ?? 0) / 100
        let units = state.units.resolved(for: appDisplayUnitSystem)
        let rangeText = state.ratedRange.map {
            MateDriveUnitFormatter.formatDistance($0, units: units, decimals: 0)
        } ?? "--"

        return ZStack {
            Button {
                if reduceMotion {
                    isShowingRange.toggle()
                } else {
                    withAnimation(.spring(response: 0.56, dampingFraction: 0.78)) {
                        isShowingRange.toggle()
                    }
                }
            } label: {
                ZStack {
                    batteryRingFace(
                        level: level,
                        progress: progress,
                        isCharging: state.isCharging,
                        palette: palette
                    )
                    .opacity(isShowingRange ? 0 : 1)
                    .rotation3DEffect(
                        .degrees(isShowingRange ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )

                    rangeRingFace(rangeText: rangeText, progress: progress, palette: palette)
                        .opacity(isShowingRange ? 1 : 0)
                        .rotation3DEffect(
                            .degrees(isShowingRange ? 0 : -180),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.55
                        )
                }
                .frame(width: 142, height: 142)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(isShowingRange ? t("Rated range", "额定续航") : t("Battery level", "电池电量")))
            .accessibilityValue(Text(isShowingRange ? rangeText : (level.map { "\($0)%" } ?? t("Unavailable", "暂无数据"))))
            .accessibilityHint(Text(isShowingRange ? t("Show battery level", "显示电池电量") : t("Show rated range", "显示额定续航")))

            if let tpms = state.tpmsDetails, tpms.hasAnyData {
                DashboardTyrePressureView(tpms: tpms, units: state.units, palette: palette)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: state.tpmsDetails?.hasAnyData == true ? 184 : 154)
    }

    private func batteryRingFace(
        level: Int?,
        progress: Double,
        isCharging: Bool,
        palette: MateDrivePalette
    ) -> some View {
        let tint = batteryTint(level: level)

        return ZStack {
            progressRing(progress: progress, tint: tint, isCharging: isCharging)

            VStack(spacing: 4) {
                Image(systemName: isCharging ? "bolt.fill" : "battery.75percent")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                Text(level.map { "\($0)%" } ?? "--")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(palette.onSurfaceColor)
                Text(t("Battery", "电量"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurfaceVariantColor)
            }
        }
    }

    private func rangeRingFace(rangeText: String, progress: Double, palette: MateDrivePalette) -> some View {
        ZStack {
            progressRing(progress: progress, tint: rangeBlue, isCharging: false)

            VStack(spacing: 4) {
                Image(systemName: "road.lanes")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(rangeBlue)
                Text(verbatim: rangeText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                    .foregroundStyle(palette.onSurfaceColor)
                Text(t("Range", "续航"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurfaceVariantColor)
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private func progressRing(progress: Double, tint: Color, isCharging: Bool) -> some View {
        Circle()
            .stroke(tint.opacity(colorScheme == .dark ? 0.20 : 0.14), lineWidth: 11)

        Circle()
            .trim(from: 0, to: progress)
            .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(
                MateDriveMotion.animationsEnabled(reduceMotion: reduceMotion)
                    ? .easeInOut(duration: 0.35)
                    : nil,
                value: progress
            )

        if isCharging, progress > 0 {
            if reduceMotion {
                chargingHighlight(progress: progress, tint: tint, phase: 35)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let cycle = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1.6) / 1.6
                    chargingHighlight(progress: progress, tint: tint, phase: cycle * 360)
                }
            }
        }
    }

    private func chargingHighlight(progress: Double, tint: Color, phase: Double) -> some View {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .clear, location: 0.58),
                .init(color: .white.opacity(0.95), location: 0.72),
                .init(color: tint.opacity(0.90), location: 0.80),
                .init(color: .clear, location: 0.94),
                .init(color: .clear, location: 1.00)
            ]),
            center: .center,
            startAngle: .degrees(phase),
            endAngle: .degrees(phase + 360)
        )
        .mask {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .shadow(color: tint.opacity(0.55), radius: 6)
    }

    private func statusLine(for state: DashboardState) -> String {
        if state.vehicleState?.lowercased() == "asleep" {
            guard let duration = state.currentSleepDuration else {
                return t("Sleeping", "休眠中")
            }
            let formatted = MateDriveUnitFormatter.formatDuration(
                minutes: max(Int(duration / 60), 1),
                language: appLanguage
            )
            return t("Sleeping · \(formatted)", "休眠中 · \(formatted)")
        }
        return DashboardTextFormatter.statusLine(isCharging: state.isCharging, sentryModeActive: state.sentryModeActive, language: appLanguage)
    }

    private func statusIcon(for state: DashboardState) -> String {
        if state.isCharging { return "bolt.fill" }
        if state.sentryModeActive { return "shield.fill" }
        return "circle.fill"
    }

    private func statusTint(for state: DashboardState) -> Color {
        if state.isCharging, let level = state.batteryLevel {
            if level <= 10 { return .red }
            if level <= 20 {
                return colorScheme == .dark
                    ? .orange
                    : Color(red: 0.62, green: 0.29, blue: 0.00)
            }
        }
        return readableStatusGreen
    }

    private func batteryTint(level: Int?) -> Color {
        guard let level else { return batteryGreen }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return batteryGreen
    }

    private var batteryGreen: Color {
        Color(red: 0.10, green: 0.68, blue: 0.32)
    }

    private var readableStatusGreen: Color {
        colorScheme == .dark
            ? Color(red: 0.26, green: 0.84, blue: 0.49)
            : Color(red: 0.02, green: 0.43, blue: 0.17)
    }

    private var readableWarningColor: Color {
        colorScheme == .dark
            ? Color(red: 1.00, green: 0.69, blue: 0.28)
            : Color(red: 0.56, green: 0.27, blue: 0.00)
    }

    private var rangeBlue: Color {
        Color(red: 0.08, green: 0.48, blue: 0.93)
    }

}

private struct DashboardLocationMap: View {
    let coordinate: CLLocationCoordinate2D
    let title: String
    let tint: Color

    var body: some View {
        MapGestureGate { isMapInteractionEnabled in
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                    )
                ),
                interactionModes: isMapInteractionEnabled ? .all : []
            ) {
                Annotation(title, coordinate: coordinate, anchor: .bottom) {
                    Image(systemName: "car.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(tint, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.85), lineWidth: 2)
                        }
                        .shadow(color: .black.opacity(0.20), radius: 4, y: 2)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        }
    }
}

private struct DashboardBottomScrollEdgeModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            content
        }
    }
}

public struct DashboardTyrePressureView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem

    let tpms: TpmsDetails
    let units: UnitPreferences?
    let palette: MateDrivePalette

    public var body: some View {
        let resolvedUnits = units.resolved(for: appDisplayUnitSystem)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                tyreValue(
                    t("Front Left", "左前"),
                    pressure: tpms.pressureFl,
                    warning: tpms.warningFl,
                    units: resolvedUnits,
                    textAlignment: .trailing,
                    frameAlignment: .trailing
                )
                Spacer(minLength: 124)
                tyreValue(
                    t("Front Right", "右前"),
                    pressure: tpms.pressureFr,
                    warning: tpms.warningFr,
                    units: resolvedUnits,
                    textAlignment: .leading,
                    frameAlignment: .leading
                )
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 0) {
                tyreValue(
                    t("Rear Left", "左后"),
                    pressure: tpms.pressureRl,
                    warning: tpms.warningRl,
                    units: resolvedUnits,
                    textAlignment: .trailing,
                    frameAlignment: .trailing
                )
                Spacer(minLength: 124)
                tyreValue(
                    t("Rear Right", "右后"),
                    pressure: tpms.pressureRr,
                    warning: tpms.warningRr,
                    units: resolvedUnits,
                    textAlignment: .leading,
                    frameAlignment: .leading
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 184, maxHeight: 184)
    }

    private func tyreValue(
        _ title: String,
        pressure: Double?,
        warning: Bool?,
        units: UnitPreferences?,
        textAlignment: HorizontalAlignment,
        frameAlignment: Alignment
    ) -> some View {
        let pressureText = pressure.map { MateDriveUnitFormatter.formatPressure($0, units: units) } ?? "--"
        let hasWarning = warning == true

        return VStack(alignment: textAlignment, spacing: 3) {
            Text(verbatim: title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(palette.onSurfaceVariantColor)
                .lineLimit(1)
            HStack(spacing: 3) {
                if hasWarning {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2.weight(.semibold))
                }
                Text(verbatim: pressureText)
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(hasWarning ? .red : palette.onSurfaceColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .frame(width: 82, alignment: frameAlignment)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: hasWarning ? "\(pressureText), \(t("Check tyres", "请检查轮胎"))" : pressureText))
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
