import SwiftUI
import UIKit

public struct TripShareCardOptions: Equatable, Sendable {
    public var includesExactDateRange: Bool
    public var includesLocations: Bool
    public var includesRouteShape: Bool
    public var includesCosts: Bool

    public init(
        includesExactDateRange: Bool = false,
        includesLocations: Bool = false,
        includesRouteShape: Bool = false,
        includesCosts: Bool = false
    ) {
        self.includesExactDateRange = includesExactDateRange
        self.includesLocations = includesLocations
        self.includesRouteShape = includesRouteShape
        self.includesCosts = includesCosts
    }

    public var includesSensitiveDetails: Bool {
        includesExactDateRange || includesLocations || includesRouteShape || includesCosts
    }
}

public struct TripShareMetric: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let systemImage: String
}

public struct TripShareRoutePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
}

public struct TripShareRouteSegment: Equatable, Identifiable, Sendable {
    public let id: Int
    public let points: [TripShareRoutePoint]
}

public struct TripShareCardContent: Equatable, Sendable {
    public let title: String
    public let headline: String
    public let headlineLabel: String
    public let exactDateRangeText: String?
    public let locationText: String?
    public let hiddenDetailsLabel: String?
    public let routeSegments: [TripShareRouteSegment]
    public let metrics: [TripShareMetric]
    public let coverageNotes: [String]
    public let optionsIncludeSensitiveDetails: Bool
}

public enum TripShareCardBuilder {
    public static func content(
        trip: DetectedTrip,
        routeSegments: [SavedTripRouteSegment],
        countryCount: Int,
        units: UnitPreferences?,
        currencySymbol: String,
        language: AppLanguage,
        options: TripShareCardOptions
    ) -> TripShareCardContent {
        var metrics = [
            TripShareMetric(
                id: "drivingTime",
                title: localized("Driving Time", "驾驶时长", language: language),
                value: MateDriveUnitFormatter.formatDuration(minutes: trip.totalDrivingDurationMin, language: language),
                systemImage: "clock"
            ),
            TripShareMetric(
                id: "driveCount",
                title: localized("Drives", "行程", language: language),
                value: "\(trip.drives.count)",
                systemImage: "road.lanes"
            ),
            TripShareMetric(
                id: "chargeStops",
                title: localized("Charge Stops", "充电次数", language: language),
                value: "\(trip.charges.count)",
                systemImage: "bolt.car"
            ),
            TripShareMetric(
                id: "maxSpeed",
                title: localized("Max Speed", "最高速度", language: language),
                value: trip.maxSpeed.map { MateDriveUnitFormatter.formatSpeed($0, units: units) } ?? "--",
                systemImage: "speedometer"
            ),
            TripShareMetric(
                id: "drivingEnergy",
                title: localized("Driving Energy", "行驶能量", language: language),
                value: TripEnergyPresentation.text(trip.totalEnergyConsumed, isComplete: trip.drivingEnergyIsComplete),
                systemImage: "leaf"
            ),
            TripShareMetric(
                id: "chargedEnergy",
                title: localized("Charged Energy", "充入能量", language: language),
                value: TripEnergyPresentation.text(trip.totalEnergyCharged, isComplete: trip.chargedEnergyIsComplete),
                systemImage: "bolt.fill"
            ),
            TripShareMetric(
                id: "countries",
                title: localized("Countries", "国家或地区", language: language),
                value: "\(countryCount)",
                systemImage: "globe.asia.australia"
            )
        ]

        if options.includesCosts {
            let cost = trip.totalChargeCost.map {
                (trip.chargeCostIsComplete ? "" : "≥") + currencySymbol + String(format: "%.2f", $0)
            } ?? "--"
            metrics.append(TripShareMetric(
                id: "chargeCost",
                title: localized("Known Charge Cost", "已知充电费用", language: language),
                value: cost,
                systemImage: "creditcard"
            ))
        }

        return TripShareCardContent(
            title: localized("Trip Report", "路程报告", language: language),
            headline: MateDriveUnitFormatter.formatDistance(trip.totalDistance, units: units, decimals: 0),
            headlineLabel: localized("Total Distance", "总距离", language: language),
            exactDateRangeText: options.includesExactDateRange
                ? exactDateRange(start: trip.startDate, end: trip.endDate, language: language)
                : nil,
            locationText: options.includesLocations
                ? locationText(start: trip.startAddress, end: trip.endAddress)
                : nil,
            hiddenDetailsLabel: hiddenDetailsLabel(options: options, language: language),
            routeSegments: options.includesRouteShape ? normalizedRoute(routeSegments) : [],
            metrics: metrics,
            coverageNotes: coverageNotes(trip: trip, language: language),
            optionsIncludeSensitiveDetails: options.includesSensitiveDetails
        )
    }

    private static func exactDateRange(start: String, end: String, language: AppLanguage) -> String? {
        guard let startDate = DomainDateParser.date(from: start), let endDate = DomainDateParser.date(from: end) else {
            return nil
        }
        let locale = language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        return "\(startDate.formatted(style)) – \(endDate.formatted(style))"
    }

    private static func locationText(start: String?, end: String?) -> String {
        let startText = shortLocation(start) ?? "--"
        let endText = shortLocation(end) ?? "--"
        return "\(startText) → \(endText)"
    }

    private static func shortLocation(_ value: String?) -> String? {
        value?
            .split(separator: ",", maxSplits: 1)
            .first
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func hiddenDetailsLabel(options: TripShareCardOptions, language: AppLanguage) -> String? {
        var hidden: [String] = []
        if !options.includesExactDateRange { hidden.append(localized("dates", "日期", language: language)) }
        if !options.includesLocations { hidden.append(localized("locations", "地点", language: language)) }
        if !options.includesRouteShape { hidden.append(localized("route", "路线", language: language)) }
        if !options.includesCosts { hidden.append(localized("costs", "费用", language: language)) }
        guard !hidden.isEmpty else { return nil }
        return String(
            format: localized("%@ hidden", "%@ 已隐藏", language: language),
            hidden.joined(separator: localized(", ", "、", language: language))
        )
    }

    private static func coverageNotes(trip: DetectedTrip, language: AppLanguage) -> [String] {
        var notes: [String] = []
        if !trip.drivingEnergyIsComplete {
            notes.append(String(
                format: localized("Driving energy coverage: %d/%d", "行驶能量覆盖：%d/%d", language: language),
                trip.drivingEnergyKnownCount,
                trip.drives.count
            ))
        }
        if !trip.chargedEnergyIsComplete {
            notes.append(String(
                format: localized("Charge energy coverage: %d/%d", "充电能量覆盖：%d/%d", language: language),
                trip.chargedEnergyKnownCount,
                trip.charges.count
            ))
        }
        return notes
    }

    private static func normalizedRoute(_ segments: [SavedTripRouteSegment]) -> [TripShareRouteSegment] {
        let allPoints = segments.flatMap(\.points)
        guard !allPoints.isEmpty else { return [] }
        let minLatitude = allPoints.map(\.latitude).min() ?? 0
        let maxLatitude = allPoints.map(\.latitude).max() ?? minLatitude
        let minLongitude = allPoints.map(\.longitude).min() ?? 0
        let maxLongitude = allPoints.map(\.longitude).max() ?? minLongitude
        let latitudeSpan = max(maxLatitude - minLatitude, 0.000_001)
        let longitudeSpan = max(maxLongitude - minLongitude, 0.000_001)

        return segments.compactMap { segment in
            let points = segment.points.map {
                TripShareRoutePoint(
                    x: ($0.longitude - minLongitude) / longitudeSpan,
                    y: 1 - (($0.latitude - minLatitude) / latitudeSpan)
                )
            }
            return points.count >= 2 ? TripShareRouteSegment(id: segment.driveId, points: points) : nil
        }
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct TripShareCardView: View {
    public static let size = CGSize(width: 540, height: 675)

    let content: TripShareCardContent

    public init(content: TripShareCardContent) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.063, blue: 0.071)
            VStack(alignment: .leading, spacing: 0) {
                header
                summary.padding(.top, 26)
                routePanel.padding(.top, 24)
                metricsGrid.padding(.top, 22)
                Spacer(minLength: 12)
                footer
            }
            .padding(40)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Label("MateDrive", systemImage: "bolt.car.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text(content.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(content.headlineLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(content.headline)
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let date = content.exactDateRangeText {
                Label(date, systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            if let location = content.locationText {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    private var routePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.09, green: 0.115, blue: 0.12))
            if content.routeSegments.isEmpty {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(Color(red: 0.28, green: 0.82, blue: 0.52).opacity(0.7))
            } else {
                GeometryReader { proxy in
                    ForEach(content.routeSegments) { segment in
                        Path { path in
                            guard let first = segment.points.first else { return }
                            path.move(to: routePoint(first, size: proxy.size))
                            for point in segment.points.dropFirst() {
                                path.addLine(to: routePoint(point, size: proxy.size))
                            }
                        }
                        .stroke(
                            Color(red: 0.28, green: 0.82, blue: 0.52),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
                .padding(18)
            }
        }
        .frame(height: 115)
        .clipped()
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(content.metrics.prefix(8)) { metric in
                HStack(spacing: 10) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.28, green: 0.82, blue: 0.52))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                        Text(metric.value)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hidden = content.hiddenDetailsLabel {
                Label(hidden, systemImage: "eye.slash.fill")
                    .foregroundStyle(.white.opacity(0.52))
            }
            ForEach(content.coverageNotes, id: \.self) { note in
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }

    private func routePoint(_ point: TripShareRoutePoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

public struct TripShareComposerView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var options = TripShareCardOptions()
    @State private var sharedImage: TripSharedImage?
    @State private var renderError: String?

    let trip: DetectedTrip
    let routeSegments: [SavedTripRouteSegment]
    let countryCount: Int
    let units: UnitPreferences?
    let currencySymbol: String

    public init(
        trip: DetectedTrip,
        routeSegments: [SavedTripRouteSegment],
        countryCount: Int,
        units: UnitPreferences?,
        currencySymbol: String
    ) {
        self.trip = trip
        self.routeSegments = routeSegments
        self.countryCount = countryCount
        self.units = units
        self.currencySymbol = currencySymbol
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Form {
                    Section {
                        Toggle(t("Include exact dates", "包含精确日期"), isOn: $options.includesExactDateRange)
                        Toggle(t("Include start and destination", "包含起点和终点"), isOn: $options.includesLocations)
                        Toggle(t("Include route shape", "包含路线轮廓"), isOn: $options.includesRouteShape)
                            .disabled(routeSegments.isEmpty)
                        Toggle(t("Include costs", "包含费用"), isOn: $options.includesCosts)
                    }
                    if options.includesSensitiveDetails {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Sensitive details selected", "已选择敏感信息")).font(.headline)
                                    Text(t(
                                        "Anyone receiving this image can see the selected trip details.",
                                        "收到图片的人都能看到已选择的路程信息。"
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)

                Button(action: shareImage) {
                    Label(t("Share Image", "分享图片"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(t("Share Trip Report", "分享路程报告"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { dismiss() }
                }
            }
        }
        .sheet(item: $sharedImage) { payload in
            TripShareActivityView(activityItems: [payload.image])
        }
        .alert(t("Unable to create share image.", "无法生成分享图片。"), isPresented: Binding(
            get: { renderError != nil },
            set: { if !$0 { renderError = nil } }
        )) {
            Button(t("OK", "确定"), role: .cancel) {}
        }
    }

    private var preview: some View {
        GeometryReader { proxy in
            let widthScale = max((proxy.size.width - 32) / TripShareCardView.size.width, 0.1)
            let heightScale = max((proxy.size.height - 24) / TripShareCardView.size.height, 0.1)
            let scale = min(widthScale, heightScale)
            TripShareCardView(content: cardContent)
                .scaleEffect(scale)
                .frame(width: TripShareCardView.size.width * scale, height: TripShareCardView.size.height * scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 310)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Trip Report Share Card", "路程报告分享卡片"))
    }

    private var cardContent: TripShareCardContent {
        TripShareCardBuilder.content(
            trip: trip,
            routeSegments: routeSegments,
            countryCount: countryCount,
            units: units,
            currencySymbol: currencySymbol,
            language: appLanguage,
            options: options
        )
    }

    @MainActor
    private func shareImage() {
        let renderer = ImageRenderer(content: TripShareCardView(content: cardContent))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            renderError = t("Unable to create share image.", "无法生成分享图片。")
            return
        }
        sharedImage = TripSharedImage(image: image)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct TripSharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct TripShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
