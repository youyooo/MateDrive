import MapKit
import SwiftUI

public struct ActivitySessionDetailView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: ActivitySessionDetailViewModel
    @State private var selectedParkingActivity: TeslaMateActivity?
    @State private var isShowingLabelEditor = false
    @State private var selectedChargePricingContext: ActivityChargePricingContext?
    @State private var presentsMap = false

    private let carId: Int
    private let sessionId: String
    private let standbyDrainAPI: any ActivityAPIProviding
    private let labelStore: any ActivityLabelOverrideStoring
    private let pricingService: any ChargePricingObservationServicing
    private let currencyCode: String
    private let smartActivityIndexer: any SmartActivityIndexing
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        sessionId: String,
        viewModel: ActivitySessionDetailViewModel,
        standbyDrainAPI: any ActivityAPIProviding,
        labelStore: any ActivityLabelOverrideStoring,
        pricingService: any ChargePricingObservationServicing,
        currencyCode: String,
        smartActivityIndexer: any SmartActivityIndexing,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.sessionId = sessionId
        self.standbyDrainAPI = standbyDrainAPI
        self.labelStore = labelStore
        self.pricingService = pricingService
        self.currencyCode = currencyCode
        self.smartActivityIndexer = smartActivityIndexer
        self.navigate = navigate
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if let session = viewModel.session {
                detail(session)
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    t("Activity detail unavailable", "动态详情不可用"),
                    systemImage: "clock.badge.exclamationmark",
                    description: Text(UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage))
                )
            } else {
                Color.clear
            }
        }
        .navigationTitle(t("Activity Detail", "动态详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let session = viewModel.session {
                    Menu {
                        Button {
                            isShowingLabelEditor = true
                        } label: {
                            Label(t("Edit activity label", "编辑动态标签"), systemImage: "tag")
                        }
                        if let reference = session.eventReferences.first(where: { $0.kind == .charge }) {
                            Button {
                                selectedChargePricingContext = ActivityChargePricingContext(reference: reference)
                            } label: {
                                Label(t("Confirm charging price", "确认充电价格"), systemImage: "creditcard")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(t("Activity actions", "动态操作"))
                }
            }
        }
        .task(id: ActivitySessionDetailLoadKey(carId: carId, sessionId: sessionId)) {
            await viewModel.load(carId: carId, sessionId: sessionId)
        }
        .task(id: ActivitySessionDetailLoadKey(carId: carId, sessionId: sessionId)) {
            presentsMap = false
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            presentsMap = true
        }
        .sheet(item: $selectedParkingActivity) { activity in
            NavigationStack {
                ParkingActivityDetailView(
                    activity: activity,
                    carId: carId,
                    standbyDrainAPI: standbyDrainAPI,
                    units: resolvedUnits
                )
            }
            .environment(\.appLanguage, appLanguage)
            .environment(\.appDisplayUnitSystem, appDisplayUnitSystem)
        }
        .sheet(isPresented: $isShowingLabelEditor) {
            if let session = viewModel.session {
                NavigationStack {
                    ActivityLabelEditorView(
                        context: ActivityLabelEditorContext(
                            carId: carId,
                            sessionId: sessionId,
                            placeKey: session.placeKey
                        ),
                        existingOverride: viewModel.labelOverride,
                        labelStore: labelStore,
                        onSaved: { _ in refreshAfterLabelChange() }
                    )
                }
                .environment(\.appLanguage, appLanguage)
            }
        }
        .sheet(item: $selectedChargePricingContext) { context in
            let activity = context.reference.sourceActivity
            ChargePriceConfirmationView(
                confirmation: priceConfirmation(activity),
                stationName: cleaned(activity.startAddress)
                    ?? cleaned(activity.endAddress)
                    ?? t("Recorded charging location", "已记录充电地点"),
                service: pricingService,
                onSaved: { _ in
                    selectedChargePricingContext = nil
                    refreshAfterPriceChange()
                },
                onCancel: { selectedChargePricingContext = nil }
            )
            .environment(\.appLanguage, appLanguage)
        }
        .accessibilityIdentifier("activity_session_detail_view")
    }

    private func detail(_ session: SmartActivitySession) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                header(session)
                if let classification = session.classification {
                    classificationSection(classification)
                }
                if let coordinate = coordinate(session) {
                    if presentsMap {
                        sessionMap(session, coordinate: coordinate)
                    } else {
                        deferredMapPlaceholder
                    }
                }
                if hasEnergyData(session) {
                    energySection(session)
                }
                eventTimeline(session)
            }
            .padding(16)
        }
    }

    private var deferredMapPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.secondarySystemBackground))
            .frame(height: 220)
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
            .accessibilityHidden(true)
    }

    private func header(_ session: SmartActivitySession) -> some View {
        let presentation = ActivitySessionCardBuilder.presentation(
            session: session,
            language: appLanguage,
            units: resolvedUnits
        )
        return VStack(alignment: .leading, spacing: 8) {
            Label(detailTitle(session, fallback: presentation.title), systemImage: presentation.systemImage)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            Text(presentation.placeText)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.timeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func classificationSection(_ result: ActivityClassificationResult) -> some View {
        let explanation = ActivityClassificationExplanationBuilder.build(
            result,
            language: appLanguage
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(t("Why MateDrive classified this activity", "动态判断依据"), systemImage: "sparkles")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(explanation.confidenceText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(explanation.isUserConfirmed ? Color.green : Color.blue)
            }

            Text(explanation.status)
                .font(.subheadline.weight(.semibold))

            Text(explanation.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(explanation.evidence, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !explanation.isUserConfirmed {
                Text(t(
                    "This is a suggestion. Use Edit activity label to correct it; your choice will take priority.",
                    "这是智能建议。可通过“编辑动态标签”纠正，你的选择会被优先采用。"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity_classification_explanation")
    }

    private func sessionMap(
        _ session: SmartActivitySession,
        coordinate: CLLocationCoordinate2D
    ) -> some View {
        MapGestureGate { isMapInteractionEnabled in
            Map(
                initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
                )),
                interactionModes: isMapInteractionEnabled ? .all : []
            ) {
                Marker(mapTitle(session), coordinate: coordinate)
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(t("Activity location", "动态位置"))
    }

    private func energySection(_ session: SmartActivitySession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("Energy", "能量"), systemImage: "bolt.fill")
                .font(.headline)
                .foregroundStyle(.green)

            if let value = vehicleReportedEnergy(session) {
                energyRow(
                    title: t("Vehicle-reported energy", "车辆上报电量"),
                    value: energyText(value),
                    systemImage: "car.side.fill"
                )
            }
            if let value = billedEnergy(session) {
                energyRow(
                    title: t("Pricing basis energy", "计价采用电量"),
                    value: energyText(value),
                    systemImage: "receipt.fill"
                )
            }
            if let value = session.parkingMetrics?.chargeGainPercent {
                energyRow(
                    title: t("Battery percentage gain", "电池电量增加"),
                    value: signedPercent(value),
                    systemImage: "battery.75percent"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func energyRow(title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func eventTimeline(_ session: SmartActivitySession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(t("Timeline", "时间线"), systemImage: "list.bullet.indent")
                .font(.headline)

            ForEach(Array(sortedReferences(session).enumerated()), id: \.element.timelineID) { index, reference in
                eventRow(
                    reference,
                    isLast: index == session.eventReferences.count - 1
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ reference: SmartActivityEventReference, isLast: Bool) -> some View {
        Button {
            open(reference)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 0) {
                    Image(systemName: eventIcon(reference.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(eventColor(reference.kind), in: Circle())
                    if !isLast {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 2, height: 46)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(eventTitle(reference.kind))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        if isActionable(reference.kind) {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Text(eventDate(reference))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let location = eventLocation(reference) {
                        Text(location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, isLast ? 0 : 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable(reference.kind))
        .accessibilityLabel(eventAccessibilityLabel(reference))
    }

    private func open(_ reference: SmartActivityEventReference) {
        switch reference.kind {
        case .drive:
            navigate(.driveDetail(carId: carId, driveId: reference.sourceID, exteriorColor: nil))
        case .charge:
            navigate(.chargeDetail(carId: carId, chargeId: reference.sourceID, exteriorColor: nil))
        case .park:
            selectedParkingActivity = reference.sourceActivity
        case .unknown:
            break
        }
    }

    private func sortedReferences(_ session: SmartActivitySession) -> [SmartActivityEventReference] {
        session.eventReferences.sorted {
            let lhs = $0.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
            let rhs = $1.startDate.flatMap(DomainDateParser.date(from:)) ?? .distantPast
            if lhs == rhs { return $0.timelineID < $1.timelineID }
            return lhs < rhs
        }
    }

    private func coordinate(_ session: SmartActivitySession) -> CLLocationCoordinate2D? {
        GeoCoordinateValidator.location(latitude: session.latitude, longitude: session.longitude).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private func hasEnergyData(_ session: SmartActivitySession) -> Bool {
        vehicleReportedEnergy(session) != nil
            || billedEnergy(session) != nil
            || session.parkingMetrics?.chargeGainPercent != nil
    }

    private func vehicleReportedEnergy(_ session: SmartActivitySession) -> Double? {
        guard let value = session.parkingMetrics?.vehicleReportedChargeEnergyKWh,
              value.isFinite,
              value >= 0
        else { return nil }
        return value
    }

    private func billedEnergy(_ session: SmartActivitySession) -> Double? {
        let values = session.chargeCost?.components.compactMap { component -> Double? in
            guard let value = component.energyKWh, value.isFinite, value >= 0 else { return nil }
            return value
        } ?? []
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func detailTitle(_ session: SmartActivitySession, fallback: String) -> String {
        if let customName = viewModel.labelOverride?.customName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customName.isEmpty {
            return customName
        }
        return fallback
    }

    private func mapTitle(_ session: SmartActivitySession) -> String {
        ActivitySessionCardBuilder.presentation(
            session: session,
            language: appLanguage,
            units: resolvedUnits
        ).placeText
    }

    private func eventTitle(_ kind: TeslaMateActivityKind) -> String {
        switch kind {
        case .drive: return t("Drive", "行程")
        case .charge: return t("Charge", "充电")
        case .park: return t("Park", "停车")
        case .unknown: return t("Recorded event", "已记录事件")
        }
    }

    private func eventIcon(_ kind: TeslaMateActivityKind) -> String {
        switch kind {
        case .drive: return "car.fill"
        case .charge: return "bolt.fill"
        case .park: return "parkingsign"
        case .unknown: return "circle.dotted"
        }
    }

    private func eventColor(_ kind: TeslaMateActivityKind) -> Color {
        switch kind {
        case .drive: return .blue
        case .charge: return .green
        case .park: return .orange
        case .unknown: return .gray
        }
    }

    private func isActionable(_ kind: TeslaMateActivityKind) -> Bool {
        kind != .unknown
    }

    private func eventDate(_ reference: SmartActivityEventReference) -> String {
        let start = reference.startDate.flatMap(DomainDateParser.date(from:))
        let end = reference.endDate.flatMap(DomainDateParser.date(from:))
        guard let start else { return t("Time unavailable", "时间不可用") }
        if let end, end >= start {
            return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return start.formatted(date: .abbreviated, time: .shortened)
    }

    private func eventLocation(_ reference: SmartActivityEventReference) -> String? {
        let locations = [
            reference.sourceActivity.startAddress,
            reference.sourceActivity.endAddress
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        return locations.isEmpty ? nil : locations.joined(separator: " → ")
    }

    private func eventAccessibilityLabel(_ reference: SmartActivityEventReference) -> String {
        [eventTitle(reference.kind), eventDate(reference), eventLocation(reference)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private func energyText(_ value: Double) -> String {
        String(format: "%.2f kWh", value)
    }

    private func signedPercent(_ value: Int) -> String {
        "\(value > 0 ? "+" : "")\(value)%"
    }

    private func priceConfirmation(_ activity: TeslaMateActivity) -> ChargePricingConfirmation {
        let coordinates = GeoCoordinateValidator.location(
            latitude: activity.startLatitude ?? activity.endLatitude,
            longitude: activity.startLongitude ?? activity.endLongitude
        ).map { GeocodeLocation(latitude: $0.latitude, longitude: $0.longitude) }
        return ChargePricingConfirmation(
            carId: carId,
            chargeId: activity.id,
            stationKey: viewModel.session?.placeKey ?? "",
            scope: coordinates == nil ? .sessionOnly : .futureAtStation,
            finalAmount: viewModel.session?.chargeCost?.amount ?? activity.cost ?? 0,
            billedEnergyKWh: nil,
            pricePerKWh: nil,
            serviceFeePerKWh: nil,
            fixedFee: nil,
            currencyCode: currencyCode,
            coordinates: coordinates,
            chargerIdentity: .ac,
            startMinute: nil,
            endMinute: nil
        )
    }

    private func refreshAfterLabelChange() {
        Task {
            _ = await smartActivityIndexer.rebuild(carIds: [carId])
            await viewModel.load(carId: carId, sessionId: sessionId)
        }
    }

    private func refreshAfterPriceChange() {
        NotificationCenter.default.post(name: .chargeCostOverrideDidChange, object: nil)
        Task {
            _ = await smartActivityIndexer.rebuild(carIds: [carId])
            await viewModel.load(carId: carId, sessionId: sessionId)
        }
    }

    private func cleaned(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private var resolvedUnits: UnitPreferences? {
        UnitPreferences.resolved(nil, for: appDisplayUnitSystem)
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ActivitySessionDetailLoadKey: Equatable {
    let carId: Int
    let sessionId: String
}

private struct ActivityChargePricingContext: Identifiable {
    let reference: SmartActivityEventReference
    var id: Int { reference.sourceID }
}

private extension SmartActivityEventReference {
    var timelineID: String { "\(kind.rawValue)-\(sourceID)" }
}
