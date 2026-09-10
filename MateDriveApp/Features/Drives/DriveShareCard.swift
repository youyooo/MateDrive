import SwiftUI
import UIKit

public struct DriveShareCardOptions: Equatable, Sendable {
    public var includesDateAndTime: Bool
    public var includesLocations: Bool
    public var includesRouteShape: Bool
    public var includesClassification: Bool

    public init(
        includesDateAndTime: Bool = false,
        includesLocations: Bool = false,
        includesRouteShape: Bool = false,
        includesClassification: Bool = false
    ) {
        self.includesDateAndTime = includesDateAndTime
        self.includesLocations = includesLocations
        self.includesRouteShape = includesRouteShape
        self.includesClassification = includesClassification
    }

    public var includesSensitiveDetails: Bool {
        includesDateAndTime || includesLocations || includesRouteShape || includesClassification
    }
}

public struct DriveShareMetric: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let value: String
    public let systemImage: String
}

public struct DriveShareRoutePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
}

public struct DriveShareCardContent: Equatable, Sendable {
    public let title: String
    public let routeTitle: String
    public let hiddenLocationsLabel: String?
    public let dateText: String?
    public let classificationText: String?
    public let routeShapeTitle: String
    public let routePoints: [DriveShareRoutePoint]
    public let metrics: [DriveShareMetric]
}

public enum DriveShareCardBuilder {
    public static func content(
        detail: DriveDetail,
        stats: DriveDetailStats?,
        annotation: DriveAnnotation,
        units: UnitPreferences?,
        language: AppLanguage,
        options: DriveShareCardOptions
    ) -> DriveShareCardContent {
        let start = cleaned(detail.startAddress) ?? localized("Start", "开始", language: language)
        let end = cleaned(detail.endAddress) ?? localized("End", "结束", language: language)
        let routeTitle = options.includesLocations
            ? "\(start) → \(end)"
            : localized("Private route", "隐私行程", language: language)

        let dateText: String?
        if options.includesDateAndTime,
           let rawDate = detail.startDate,
           let date = DomainDateParser.date(from: rawDate) {
            let locale = language.localeIdentifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
            dateText = date.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
            )
        } else {
            dateText = nil
        }

        let routePoints = options.includesRouteShape
            ? normalizedRoutePoints(from: detail.positions ?? [])
            : []
        let metrics = [
            DriveShareMetric(
                id: "distance",
                title: localized("Distance", "里程", language: language),
                value: DriveDetailPresentation.distanceText(stats?.distance ?? detail.distance, units: units),
                systemImage: "road.lanes"
            ),
            DriveShareMetric(
                id: "duration",
                title: localized("Duration", "时长", language: language),
                value: DriveDetailPresentation.durationText(stats?.durationMin ?? detail.durationMin, language: language),
                systemImage: "clock"
            ),
            DriveShareMetric(
                id: "averageSpeed",
                title: localized("Average Speed", "平均速度", language: language),
                value: DriveDetailPresentation.speedText(stats?.speedAvg ?? detail.speedAvg, units: units),
                systemImage: "gauge.with.dots.needle.33percent"
            ),
            DriveShareMetric(
                id: "energy",
                title: localized("Energy", "能量", language: language),
                value: stats?.energyUsed.map { String(format: "%.1f kWh", $0) } ?? "--",
                systemImage: "bolt.fill"
            ),
            DriveShareMetric(
                id: "efficiency",
                title: localized("Efficiency", "效率", language: language),
                value: stats?.efficiency.map {
                    MateDriveUnitFormatter.formatEfficiency($0, units: units, decimals: 0)
                } ?? "--",
                systemImage: "leaf"
            ),
            DriveShareMetric(
                id: "battery",
                title: localized("Battery", "电量", language: language),
                value: DriveDetailPresentation.batteryText(
                    start: stats?.batteryStart ?? detail.startBatteryLevel,
                    end: stats?.batteryEnd ?? detail.endBatteryLevel
                ),
                systemImage: "battery.75percent"
            )
        ]

        return DriveShareCardContent(
            title: localized("Drive Summary", "行程摘要", language: language),
            routeTitle: routeTitle,
            hiddenLocationsLabel: options.includesLocations
                ? nil
                : localized("Locations hidden", "地点已隐藏", language: language),
            dateText: dateText,
            classificationText: options.includesClassification
                ? annotation.displayLabel(language: language)
                : nil,
            routeShapeTitle: localized("Route shape", "路线形状", language: language),
            routePoints: routePoints,
            metrics: metrics
        )
    }

    public static func normalizedRoutePoints(from positions: [DrivePosition]) -> [DriveShareRoutePoint] {
        let samples = DriveReplayBuilder.samples(from: positions)
        guard samples.count >= 2 else { return [] }

        let latitudes = samples.map(\.latitude)
        let longitudes = samples.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max()
        else { return [] }

        let latitudeSpan = max(maxLatitude - minLatitude, 0.000_001)
        let longitudeSpan = max(maxLongitude - minLongitude, 0.000_001)
        let scale = max(latitudeSpan, longitudeSpan)
        let horizontalInset = (1 - longitudeSpan / scale) / 2
        let verticalInset = (1 - latitudeSpan / scale) / 2

        return samples.map { sample in
            DriveShareRoutePoint(
                x: horizontalInset + (sample.longitude - minLongitude) / scale,
                y: verticalInset + (maxLatitude - sample.latitude) / scale
            )
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func localized(_ english: String, _ chinese: String, language: AppLanguage) -> String {
        AppText.localized(english, chinese, language: language)
    }
}

public struct DriveShareCardView: View {
    public static let size = CGSize(width: 540, height: 675)

    let content: DriveShareCardContent

    public init(content: DriveShareCardContent) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.063, blue: 0.071)

            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                routeHeader
                if !content.routePoints.isEmpty {
                    routeShape
                        .padding(.top, 26)
                }
                metricsGrid
                    .padding(.top, content.routePoints.isEmpty ? 38 : 28)
                Spacer(minLength: 18)
                footer
            }
            .padding(42)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var brandHeader: some View {
        HStack {
            HStack(spacing: 10) {
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.25, green: 0.84, blue: 0.48))
                Text("MateDrive")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text(content.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var routeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.routeTitle)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)

            HStack(spacing: 10) {
                if let dateText = content.dateText {
                    Label(dateText, systemImage: "calendar")
                }
                if let hiddenLocationsLabel = content.hiddenLocationsLabel {
                    Label(hiddenLocationsLabel, systemImage: "location.slash.fill")
                }
                if let classificationText = content.classificationText {
                    Label(classificationText, systemImage: "tag.fill")
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
            .lineLimit(1)
        }
        .padding(.top, 34)
    }

    private var routeShape: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.routeShapeTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .textCase(.uppercase)

            DriveShareRouteShapeView(points: content.routePoints)
                .frame(height: 116)
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 24) {
            ForEach(content.metrics) { metric in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.25, green: 0.84, blue: 0.48))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(metric.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                        Text(metric.value)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
            Text("MateDrive")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
    }
}

private struct DriveShareRouteShapeView: View {
    let points: [DriveShareRoutePoint]

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 8
            let size = CGSize(
                width: max(proxy.size.width - inset * 2, 1),
                height: max(proxy.size.height - inset * 2, 1)
            )

            ZStack {
                Path { path in
                    for (index, point) in points.enumerated() {
                        let target = CGPoint(
                            x: inset + CGFloat(point.x) * size.width,
                            y: inset + CGFloat(point.y) * size.height
                        )
                        index == 0 ? path.move(to: target) : path.addLine(to: target)
                    }
                }
                .stroke(
                    Color(red: 0.25, green: 0.84, blue: 0.48),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )

                if let first = points.first, let last = points.last {
                    endpoint(first, size: size, inset: inset, fill: .white)
                    endpoint(last, size: size, inset: inset, fill: Color(red: 0.25, green: 0.84, blue: 0.48))
                }
            }
        }
    }

    private func endpoint(_ point: DriveShareRoutePoint, size: CGSize, inset: CGFloat, fill: Color) -> some View {
        Circle()
            .fill(fill)
            .overlay(Circle().stroke(Color(red: 0.055, green: 0.063, blue: 0.071), lineWidth: 3))
            .frame(width: 14, height: 14)
            .position(
                x: inset + CGFloat(point.x) * size.width,
                y: inset + CGFloat(point.y) * size.height
            )
    }
}

public struct DriveShareComposerView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.dismiss) private var dismiss
    @State private var options = DriveShareCardOptions()
    @State private var sharedImage: DriveSharedImage?
    @State private var renderError: String?

    let detail: DriveDetail
    let stats: DriveDetailStats?
    let annotation: DriveAnnotation
    let units: UnitPreferences?

    public init(detail: DriveDetail, stats: DriveDetailStats?, annotation: DriveAnnotation, units: UnitPreferences?) {
        self.detail = detail
        self.stats = stats
        self.annotation = annotation
        self.units = units
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                Form {
                    Section {
                        Toggle(t("Include date and time", "包含日期和时间"), isOn: $options.includesDateAndTime)
                        Toggle(t("Include start and end locations", "包含起点和终点"), isOn: $options.includesLocations)
                        Toggle(t("Include route shape", "包含路线形状"), isOn: $options.includesRouteShape)
                            .disabled(!hasRoute)
                        Toggle(t("Include classification", "包含行程分类"), isOn: $options.includesClassification)
                    }

                    if options.includesSensitiveDetails {
                        Section {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(t("Sensitive details selected", "已选择敏感信息"))
                                        .font(.headline)
                                    Text(t(
                                        "Anyone receiving this image can see the selected trip details.",
                                        "收到图片的人都能看到已选择的行程信息。"
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .foregroundStyle(.orange)
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
            .navigationTitle(t("Share Drive", "分享行程"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { dismiss() }
                }
            }
        }
        .sheet(item: $sharedImage) { payload in
            DriveShareActivityView(activityItems: [payload.image])
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
            let widthScale = max((proxy.size.width - 32) / DriveShareCardView.size.width, 0.1)
            let heightScale = max((proxy.size.height - 24) / DriveShareCardView.size.height, 0.1)
            let scale = min(widthScale, heightScale)

            DriveShareCardView(content: cardContent)
                .scaleEffect(scale)
                .frame(width: DriveShareCardView.size.width * scale, height: DriveShareCardView.size.height * scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .frame(height: 310)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("Share Card", "分享卡片"))
    }

    private var cardContent: DriveShareCardContent {
        DriveShareCardBuilder.content(
            detail: detail,
            stats: stats,
            annotation: annotation,
            units: units,
            language: appLanguage,
            options: options
        )
    }

    private var hasRoute: Bool {
        DriveShareCardBuilder.normalizedRoutePoints(from: detail.positions ?? []).count >= 2
    }

    @MainActor
    private func shareImage() {
        let renderer = ImageRenderer(content: DriveShareCardView(content: cardContent))
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            renderError = t("Unable to create share image.", "无法生成分享图片。")
            return
        }
        sharedImage = DriveSharedImage(image: image)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct DriveSharedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct DriveShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
