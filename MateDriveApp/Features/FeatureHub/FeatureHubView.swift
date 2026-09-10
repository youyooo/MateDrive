import SwiftUI

public struct FeatureHubView: View {
    @Environment(\.appLanguage) private var appLanguage
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var viewModel: DashboardViewModel

    private let navigate: (AppRoute) -> Void

    public init(viewModel: DashboardViewModel, navigate: @escaping (AppRoute) -> Void) {
        self.viewModel = viewModel
        self.navigate = navigate
    }

    public var body: some View {
        let presentation = FeatureHubPresentation(state: viewModel.state)

        Group {
            if presentation.isAvailable {
                featureContent(presentation: presentation)
            } else {
                ContentUnavailableView {
                    Label(t("No vehicle", "暂无车辆"), systemImage: "car.side")
                } description: {
                    Text(t("Configure TeslaMate or select a vehicle in Settings.", "请在设置中配置 TeslaMate 或选择车辆。"))
                } actions: {
                    Button(t("Open Settings", "打开设置")) {
                        navigate(.settings)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(t("Features", "功能"))
        .navigationBarTitleDisplayMode(.large)
        .background(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("feature_hub_view")
    }

    private func featureContent(presentation: FeatureHubPresentation) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if presentation.headerMode == .vehiclePicker {
                    vehiclePicker
                }

                ForEach(presentation.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.title(language: appLanguage))
                            .font(.headline)

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(section.items) { item in
                                featureButton(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var vehiclePicker: some View {
        if let selectedCarId = viewModel.state.selectedCarId {
            Picker(
                t("Vehicle", "车辆"),
                selection: Binding(
                    get: { selectedCarId },
                    set: { carId in
                        Task { await viewModel.selectCar(id: carId) }
                    }
                )
            ) {
                ForEach(viewModel.state.cars) { car in
                    Text(car.name).tag(car.id)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func featureButton(_ item: FeatureHubItem) -> some View {
        Button {
            navigate(item.route)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: item.systemImage)
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .frame(width: 24, height: 24)
                        .accessibilityHidden(true)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(supportingTextColor)
                        .accessibilityHidden(true)
                }

                Text(item.title(language: appLanguage))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.subtitle(language: appLanguage))
                    .font(.caption)
                    .foregroundStyle(supportingTextColor)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title(language: appLanguage))
        .accessibilityHint(item.subtitle(language: appLanguage))
        .accessibilityIdentifier("feature_item_\(item.id)")
    }

    private func t(_ english: String, _ chinese: String) -> String {
        AppText.localized(english, chinese, language: appLanguage)
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var supportingTextColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.76 : 0.72)
    }
}
