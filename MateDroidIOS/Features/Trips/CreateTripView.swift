import SwiftUI

public struct CreateTripView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CreateTripViewModel
    @State private var hasLoaded = false

    private let carId: Int
    private let exteriorColor: String?
    private let navigate: (AppRoute) -> Void

    public init(carId: Int, exteriorColor: String?, viewModel: CreateTripViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.carId = carId
        self.exteriorColor = exteriorColor
        self.navigate = navigate
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField(t("Trip name", "路程名称"), text: Binding(
                    get: { viewModel.state.name },
                    set: { viewModel.setName($0) }
                ))
                .textFieldStyle(.roundedBorder)

                if let preview = viewModel.state.preview {
                    previewCard(preview)
                }

                legSection

                if let error = viewModel.state.errorMessage {
                    Label(UserFacingErrorLocalizer.localized(error, language: appLanguage), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Button {
                    Task {
                        await viewModel.save(carId: carId)
                        if let start = viewModel.state.createdStartDate {
                            navigate(.tripDetail(carId: carId, tripStartDate: start, exteriorColor: exteriorColor))
                        }
                    }
                } label: {
                    Label {
                        Text(saveButtonTitle)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.state.draftLegs.isEmpty || viewModel.state.isSaving)
            }
            .padding(16)
        }
        .navigationTitle(t("Create Trip", "创建路程"))
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            await viewModel.load(carId: carId)
        }
    }

    private var legSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Drives", "行程"))
                .font(.headline)
            ForEach(viewModel.state.availableDrives) { drive in
                legToggle(
                    title: drive.startAddress ?? t("Drive \(drive.id)", "行程 \(drive.id)"),
                    subtitle: "\(drive.startDate) - \(MateDroidUnitFormatter.formatDistance(drive.distance, units: resolvedUnits))",
                    leg: .drive(drive.id)
                )
            }

            Text(t("Charges", "充电"))
                .font(.headline)
                .padding(.top, 8)
            ForEach(viewModel.state.availableCharges) { charge in
                legToggle(
                    title: charge.address ?? t("Charge \(charge.id)", "充电 \(charge.id)"),
                    subtitle: "\(charge.startDate) - \(String(format: "%.1f kWh", charge.energyAdded))",
                    leg: .charge(charge.id)
                )
            }
        }
    }

    private func legToggle(title: String, subtitle: String, leg: TripLegReference) -> some View {
        Button {
            viewModel.toggleLeg(leg)
        } label: {
            HStack {
                Image(systemName: viewModel.state.draftLegs.contains(leg) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.state.draftLegs.contains(leg) ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    private var saveButtonTitle: String {
        viewModel.state.isSaving ? t("Saving", "正在保存") : t("Save Trip", "保存路程")
    }

    private func previewCard(_ trip: DetectedTrip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(trip.displayName(language: appLanguage))
                .font(.headline)
            HStack {
                Label(MateDroidUnitFormatter.formatDistance(trip.totalDistance, units: resolvedUnits), systemImage: "road.lanes")
                Label(MateDroidUnitFormatter.formatDuration(minutes: trip.totalDrivingDurationMin, language: appLanguage), systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private var resolvedUnits: UnitPreferences? { viewModel.state.units.resolved(for: appDisplayUnitSystem) }
}
