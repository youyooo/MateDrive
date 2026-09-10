import SwiftUI

public struct CreateTripView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @StateObject private var viewModel: CreateTripViewModel

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
        Group {
            if viewModel.state.isLoading, !viewModel.state.hasLoadedData {
                LoadingStateView(title: t("Loading trip builder", "正在加载路程编辑器"), showsProgress: true)
            } else if !viewModel.state.hasLoadedData, let error = viewModel.state.errorMessage {
                LoadingStateView(
                    title: t("Trip builder unavailable", "路程编辑器不可用"),
                    message: UserFacingErrorLocalizer.localized(error, language: appLanguage),
                    systemImage: "map"
                )
            } else {
                editor
            }
        }
        .navigationTitle(t("Create Trip", "创建路程"))
        .accessibilityIdentifier("create_trip_view")
        .task {
            await viewModel.load(carId: carId)
        }
    }

    private var editor: some View {
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
                        .accessibilityIdentifier("create_trip_refresh_warning")
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
        .refreshable {
            await viewModel.load(carId: carId)
        }
    }

    private var legSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Drives", "行程"))
                .font(.headline)
            if viewModel.state.availableDrives.isEmpty,
               viewModel.state.availableCharges.isEmpty {
                ContentUnavailableView(
                    t("No unused records", "没有可用的未归档记录"),
                    systemImage: "checkmark.circle",
                    description: Text(t(
                        "All available drives and charges are already assigned to trips.",
                        "所有可用行程和充电记录都已归入路程。"
                    ))
                )
            }
            ForEach(viewModel.state.availableDrives) { drive in
                legToggle(
                    title: drive.startAddress ?? t("Drive \(drive.id)", "行程 \(drive.id)"),
                    subtitle: "\(drive.startDate) - \(MateDriveUnitFormatter.formatDistance(drive.distance, units: resolvedUnits))",
                    leg: .drive(drive.id)
                )
            }

            Text(t("Charges", "充电"))
                .font(.headline)
                .padding(.top, 8)
            ForEach(viewModel.state.availableCharges) { charge in
                legToggle(
                    title: charge.address ?? t("Charge \(charge.id)", "充电 \(charge.id)"),
                    subtitle: "\(charge.startDate) - \(TripEnergyPresentation.text(charge.energyAdded, isComplete: charge.energyAdded != nil))",
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
                Label(MateDriveUnitFormatter.formatDistance(trip.totalDistance, units: resolvedUnits), systemImage: "road.lanes")
                Label(MateDriveUnitFormatter.formatDuration(minutes: trip.totalDrivingDurationMin, language: appLanguage), systemImage: "clock")
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
