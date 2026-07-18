import MapKit
import SwiftUI

public struct ActivityTimelineView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.appDisplayUnitSystem) private var appDisplayUnitSystem
    @ObservedObject private var viewModel: ActivityTimelineViewModel
    @State private var mode: ListMapViewMode = .list
    @State private var mapPosition: MapCameraPosition = .automatic

    private let carId: Int
    private let cacheRevision: Int
    private let navigate: (AppRoute) -> Void

    public init(
        carId: Int,
        cacheRevision: Int,
        viewModel: ActivityTimelineViewModel,
        navigate: @escaping (AppRoute) -> Void
    ) {
        self.carId = carId
        self.cacheRevision = cacheRevision
        self.viewModel = viewModel
        self.navigate = navigate
    }

    public var body: some View {
        Group {
            if viewModel.filteredSessions.isEmpty {
                emptyState
            } else if mode == .map {
                if mappableSessions.isEmpty {
                    ContentUnavailableView(
                        t("No recorded locations", "暂无已记录位置"),
                        systemImage: "mappin.slash"
                    )
                } else {
                    sessionMap
                }
            } else {
                sessionList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            filterBar
        }
        .navigationTitle(t("Activity", "动态"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ListMapToolbarButton(
                    mode: $mode,
                    showListLabel: t("Show list", "显示列表"),
                    showMapLabel: t("Show map", "显示地图")
                )
            }
        }
        .task(id: ActivityTimelineLoadKey(carId: carId, cacheRevision: cacheRevision)) {
            await viewModel.load(carId: carId, cacheRevision: cacheRevision)
        }
        .onChange(of: carId) {
            resetMapPosition()
        }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            Picker(t("Activity filter", "动态筛选"), selection: Binding(
                get: { viewModel.state.filter },
                set: { viewModel.setFilter($0) }
            )) {
                ForEach(ActivityTimelineFilter.allCases, id: \.self) { filter in
                    Text(filterTitle(filter)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
        }
        .background(.bar)
    }

    private var sessionList: some View {
        List {
            if let errorMessage = viewModel.state.errorMessage {
                Label(
                    UserFacingErrorLocalizer.localized(errorMessage, language: appLanguage),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                .listRowSeparator(.hidden)
            }

            ForEach(viewModel.daySections) { section in
                Section {
                    ForEach(section.sessions) { session in
                        Button {
                            open(session)
                        } label: {
                            ActivitySessionCard(
                                session: session,
                                language: appLanguage,
                                units: resolvedUnits
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(section.day.formatted(date: .complete, time: .omitted))
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
    }

    private var sessionMap: some View {
        MapGestureGate(onAutoLock: resetMapPosition) { isMapInteractionEnabled in
            Map(
                position: $mapPosition,
                interactionModes: isMapInteractionEnabled ? .all : []
            ) {
                ForEach(mappableSessions) { item in
                    Annotation(item.presentation.title, coordinate: item.coordinate) {
                        Button {
                            open(item.session)
                        } label: {
                            Image(systemName: item.presentation.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(markerColor(item.presentation.semanticColor), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                                .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
                        }
                        .accessibilityLabel(item.presentation.accessibilityLabel)
                        .accessibilityValue(item.presentation.accessibilityValue)
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            emptyTitle,
            systemImage: "clock.arrow.circlepath",
            description: viewModel.state.errorMessage.map {
                Text(UserFacingErrorLocalizer.localized($0, language: appLanguage))
            }
        )
    }

    private var emptyTitle: String {
        viewModel.state.errorMessage == nil
            ? t("No cached activity", "暂无缓存动态")
            : t("Cached activity unavailable", "缓存动态不可用")
    }

    private var mappableSessions: [ActivityTimelineMapItem] {
        viewModel.filteredSessions.compactMap { session in
            guard let location = GeoCoordinateValidator.location(
                latitude: session.latitude,
                longitude: session.longitude
            ) else { return nil }
            return ActivityTimelineMapItem(
                session: session,
                coordinate: CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude
                ),
                presentation: ActivitySessionCardBuilder.presentation(
                    session: session,
                    language: appLanguage,
                    units: resolvedUnits
                )
            )
        }
    }

    private var resolvedUnits: UnitPreferences? {
        UnitPreferences.resolved(nil, for: appDisplayUnitSystem)
    }

    private func open(_ session: SmartActivitySession) {
        navigate(.activitySession(carId: carId, sessionId: session.id))
    }

    private func resetMapPosition() {
        withAnimation(.easeOut(duration: 0.25)) {
            mapPosition = .automatic
        }
    }

    private func filterTitle(_ filter: ActivityTimelineFilter) -> String {
        switch filter {
        case .all: return t("All", "全部")
        case .drive: return t("Drive", "行程")
        case .charge: return t("Charge", "充电")
        case .park: return t("Park", "停车")
        }
    }

    private func markerColor(_ semanticColor: ActivitySessionCardSemanticColor) -> Color {
        switch semanticColor {
        case .neutral: return .gray
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .indigo: return .indigo
        }
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }
}

private struct ActivityTimelineLoadKey: Equatable {
    let carId: Int
    let cacheRevision: Int
}

private struct ActivityTimelineMapItem: Identifiable {
    let session: SmartActivitySession
    let coordinate: CLLocationCoordinate2D
    let presentation: ActivitySessionCardPresentation

    var id: String { session.id }
}
