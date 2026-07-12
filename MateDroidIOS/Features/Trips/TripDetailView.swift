import MapKit
import SwiftUI

public struct TripDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TripDetailViewModel
    @State private var hasLoaded = false
    @State private var renameDraft = ""
    @State private var showsAddLegs = false
    @State private var selectedLegs: Set<TripLegReference> = []
    @State private var confirmsDeletion = false
    @State private var showsMergeTrips = false
    @State private var mergeCandidate: TripMergeCandidate?

    private let carId: Int
    private let tripStartDate: String
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        tripStartDate: String,
        exteriorColor: String?,
        viewModel: TripDetailViewModel,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.tripStartDate = tripStartDate
        self.exteriorColor = exteriorColor
        self.navigate = navigate
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if viewModel.state.isLoading {
                LoadingStateView(title: t("Loading trip", "正在加载路程"), showsProgress: true)
            } else if let trip = viewModel.state.trip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(trip)
                        routeMap
                        countryStats
                        TripTimelineView(segments: viewModel.state.timeline, language: appLanguage)
                        legList(trip)
                        actions
                    }
                    .padding(16)
                }
            } else {
                LoadingStateView(title: t("Trip not found", "未找到路程"), systemImage: "map")
            }
        }
        .navigationTitle(t("Trip Detail", "路程详情"))
        .sheet(isPresented: $showsAddLegs) {
            addLegSheet
        }
        .sheet(isPresented: $showsMergeTrips) { mergeTripSheet }
        .confirmationDialog(
            t("Merge these trips?", "合并这两条路程？"),
            isPresented: Binding(get: { mergeCandidate != nil }, set: { if !$0 { mergeCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button(t("Merge Trips", "合并路程")) {
                guard let candidate = mergeCandidate else { return }
                Task {
                    await viewModel.merge(with: candidate)
                    mergeCandidate = nil
                }
            }
            Button(t("Cancel", "取消"), role: .cancel) { mergeCandidate = nil }
        } message: {
            Text(t("Records between both trips will be included automatically. The original groupings will be replaced.", "两条路程之间的记录会自动纳入，原来的两个分组将被替换。"))
        }
        .confirmationDialog(
            t("Delete this trip?", "删除这条路程？"),
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button(t("Delete Trip", "删除路程"), role: .destructive) {
                Task { await viewModel.deleteTrip() }
            }
            Button(t("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t("This only deletes the saved trip grouping. TeslaMate records remain unchanged.", "只会删除已保存的路程分组，不会删除 TeslaMate 原始记录。"))
        }
        .onChange(of: viewModel.state.justDeleted) { _, deleted in
            if deleted { dismiss() }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId, tripStartDate: tripStartDate)
            renameDraft = viewModel.state.trip?.name ?? ""
        }
    }

    private func header(_ trip: DetectedTrip) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            Text(trip.displayName(language: appLanguage))
                .font(.title3.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                MetricCard(title: t("Distance", "距离"), value: MateDroidUnitFormatter.formatDistance(trip.totalDistance, units: resolvedUnits, decimals: 0), systemImage: "road.lanes")
                MetricCard(title: t("Duration", "时长"), value: MateDroidUnitFormatter.formatDuration(minutes: trip.totalDurationMin, language: appLanguage), systemImage: "clock")
                MetricCard(title: t("Charged", "已充电"), value: String(format: "%.1f kWh", trip.totalEnergyCharged), systemImage: "bolt.fill")
                MetricCard(title: t("Max Speed", "最高速度"), value: MateDroidUnitFormatter.formatSpeed(trip.maxSpeed, units: resolvedUnits), systemImage: "speedometer")
                if !trip.charges.isEmpty {
                    MetricCard(
                        title: t("Known Charge Cost", "已知充电费用"),
                        value: chargeCostText(trip),
                        subtitle: t("Price coverage: \(trip.pricedChargeCount)/\(trip.charges.count)", "价格覆盖：\(trip.pricedChargeCount)/\(trip.charges.count)"),
                        systemImage: "creditcard"
                    )
                }
            }
        }
    }

    private func chargeCostText(_ trip: DetectedTrip) -> String {
        guard let cost = trip.totalChargeCost else { return "--" }
        let lowerBound = trip.chargeCostIsComplete ? "" : "≥"
        return lowerBound + viewModel.state.currencySymbol + String(format: "%.2f", cost)
    }

    @ViewBuilder
    private var routeMap: some View {
        let segments = viewModel.state.routeSegments
        let coordinates = segments.flatMap { segment in
            segment.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        if coordinates.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Route", "路线"))
                    .font(.headline)
                Map(initialPosition: .region(routeRegion(coordinates))) {
                    ForEach(segments) { segment in
                        let points = segment.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                        MapPolyline(coordinates: points)
                            .stroke(.blue, lineWidth: 5)
                    }
                    if let first = coordinates.first {
                        Marker(t("Start", "开始"), systemImage: "flag", coordinate: first)
                    }
                    if let last = coordinates.last {
                        Marker(t("End", "结束"), systemImage: "flag.checkered", coordinate: last)
                    }
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func routeRegion(_ coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLatitude = latitudes.min() ?? 0
        let maxLatitude = latitudes.max() ?? 0
        let minLongitude = longitudes.min() ?? 0
        let maxLongitude = longitudes.max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLatitude - minLatitude) * 1.35, 0.01),
                longitudeDelta: max((maxLongitude - minLongitude) * 1.35, 0.01)
            )
        )
    }

    @ViewBuilder
    private var countryStats: some View {
        if let summary = viewModel.state.countrySummary, summary.totalRecordCount > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t("Countries", "到访国家"))
                        .font(.headline)
                    Spacer()
                    Text(countryCoverageText(summary))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(summary.unclassifiedRecordCount == 0 ? Color.secondary : Color.orange)
                }
                if summary.countries.isEmpty {
                    Label(
                        t("Country data unavailable", "国家信息不可用"),
                        systemImage: "location.slash"
                    )
                    .font(.body.weight(.semibold))
                } else {
                    ForEach(summary.countries) { country in
                        Button {
                            navigate(.regionsVisited(
                                carId: carId,
                                countryCode: country.countryCode,
                                countryName: country.canonicalName,
                                exteriorColor: exteriorColor,
                                year: tripYear(country.firstVisitDate)
                            ))
                        } label: {
                            countryRow(country)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if summary.unclassifiedRecordCount > 0 {
                    let unclassified = summary.unclassifiedRecordCount
                    Label(
                        t(
                            "\(unclassified) records have no verifiable country",
                            "\(unclassified) 条记录无法确认国家"
                        ),
                        systemImage: "location.slash"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func countryRow(_ country: TripCountryStat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizedCountryName(code: country.countryCode, fallback: country.canonicalName))
                    .font(.body.weight(.semibold))
                Text(countryActivityText(country))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(MateDroidUnitFormatter.formatDistance(country.distanceKm, units: resolvedUnits))
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(String(format: "%.1f kWh", country.chargedEnergyKWh))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func countryCoverageText(_ summary: TripCountrySummary) -> String {
        let classified = summary.classifiedRecordCount
        let total = summary.totalRecordCount
        return t(
            "Location coverage: \(classified)/\(total)",
            "位置覆盖：\(classified)/\(total)"
        )
    }

    private func countryActivityText(_ country: TripCountryStat) -> String {
        let drives = country.driveCount
        let charges = country.chargeCount
        return t(
            "\(drives) drives · \(charges) charges",
            "\(drives) 次行程 · \(charges) 次充电"
        )
    }

    private func localizedCountryName(code: String, fallback: String) -> String {
        let locale = Locale(identifier: MateDroidUnitFormatter.usesChineseLabels(language: appLanguage) ? "zh_Hans" : "en_US")
        return locale.localizedString(forRegionCode: code) ?? fallback
    }

    private func tripYear(_ dateString: String) -> Int? {
        guard let date = DomainDateParser.date(from: dateString) else { return nil }
        return Calendar(identifier: .gregorian).component(.year, from: date)
    }

    private func legList(_ trip: DetectedTrip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Legs", "分段"))
                .font(.headline)
            ForEach(viewModel.state.timeline) { segment in
                if let destination = segment.destination(carId: carId, exteriorColor: exteriorColor) {
                    Button { navigate(destination) } label: {
                        segmentRow(segment, showsDisclosure: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    segmentRow(segment, showsDisclosure: false)
                }
            }
        }
    }

    private func segmentRow(_ segment: TripTimelineSegment, showsDisclosure: Bool) -> some View {
        HStack {
                    Image(systemName: icon(for: segment.kind))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(segment.displayLabel(language: appLanguage))
                            .font(.body.weight(.semibold))
                        Text(segment.kind.title(language: appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(MateDroidUnitFormatter.formatDuration(minutes: segment.durationMin, language: appLanguage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if showsDisclosure {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
        }
        .contentShape(Rectangle())
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Edit", "编辑"))
                .font(.headline)
            if let error = viewModel.state.errorMessage {
                Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            ForEach(viewModel.state.editableLegs) { leg in
                HStack(spacing: 10) {
                    Image(systemName: legIcon(leg.reference))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(displayTitle(for: leg))
                            .lineLimit(1)
                        Text(verbatim: "\(dateText(leg.startDate)) · \(legDetail(leg))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        Task { await viewModel.removeLeg(leg.reference) }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .accessibilityLabel(Text(t("Remove leg", "移除分段")))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            }
            Button {
                selectedLegs = []
                showsAddLegs = true
            } label: {
                Label(t("Add Legs", "添加分段"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.state.availableLegs.isEmpty)
            Button {
                showsMergeTrips = true
            } label: {
                Label(t("Merge Trip", "合并路程"), systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.state.mergeCandidates.isEmpty)
            HStack {
                TextField(t("Trip name", "路程名称"), text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                Button(t("Rename", "重命名")) {
                    Task { await viewModel.rename(renameDraft) }
                }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) {
                confirmsDeletion = true
            } label: {
                Label(t("Delete Trip", "删除路程"), systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    private var addLegSheet: some View {
        NavigationStack {
            Group {
                if viewModel.state.availableLegs.isEmpty {
                    ContentUnavailableView(t("No available legs", "没有可添加的分段"), systemImage: "checkmark.circle")
                } else {
                    List(viewModel.state.availableLegs) { leg in
                        Button {
                            if selectedLegs.contains(leg.reference) {
                                selectedLegs.remove(leg.reference)
                            } else {
                                selectedLegs.insert(leg.reference)
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedLegs.contains(leg.reference) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedLegs.contains(leg.reference) ? Color.accentColor : Color.secondary)
                                Image(systemName: legIcon(leg.reference))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayTitle(for: leg))
                                        .foregroundStyle(.primary)
                                    Text(verbatim: "\(dateText(leg.startDate)) · \(legDetail(leg))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(t("Add Legs", "添加分段"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { showsAddLegs = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Add", "添加")) {
                        Task {
                            await viewModel.addLegs(selectedLegs)
                            showsAddLegs = false
                        }
                    }
                    .disabled(selectedLegs.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var mergeTripSheet: some View {
        NavigationStack {
            List(viewModel.state.mergeCandidates) { candidate in
                Button {
                    showsMergeTrips = false
                    mergeCandidate = candidate
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(candidate.trip.displayName(language: appLanguage))
                            .foregroundStyle(.primary)
                        Text("\(dateText(candidate.snapshot.startDate)) · \(MateDroidUnitFormatter.formatDistance(candidate.trip.totalDistance, units: resolvedUnits, decimals: 0))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(t("Select Trip", "选择路程"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Cancel", "取消")) { showsMergeTrips = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func icon(for kind: TripTimelineSegmentKind) -> String {
        switch kind {
        case .drive:
            return "car"
        case .dcCharge, .acCharge:
            return "bolt.fill"
        case .parking:
            return "parkingsign.circle"
        }
    }

    private func legIcon(_ leg: TripLegReference) -> String {
        switch leg {
        case .drive: "car"
        case .charge: "bolt.fill"
        }
    }

    private func displayTitle(for leg: TripEditableLeg) -> String {
        guard leg.title.isEmpty else { return leg.title }
        switch leg.reference {
        case .drive:
            return t("Drive", "驾驶")
        case .charge:
            return leg.isDC ? t("DC charging", "直流充电") : t("Charging", "充电")
        }
    }

    private var resolvedUnits: UnitPreferences? { viewModel.state.units.resolved(for: appDisplayUnitSystem) }

    private func legDetail(_ leg: TripEditableLeg) -> String {
        if let distance = leg.distanceKm {
            return MateDroidUnitFormatter.formatDistance(distance, units: resolvedUnits)
        }
        if let energy = leg.energyKWh {
            return String(format: "+%.1f kWh", energy)
        }
        return "--"
    }

    private func dateText(_ value: String) -> String {
        DomainDateParser.date(from: value)?.formatted(date: .abbreviated, time: .shortened) ?? value
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}
