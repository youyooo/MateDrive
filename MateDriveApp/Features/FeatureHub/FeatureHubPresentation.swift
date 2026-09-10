import Foundation

enum FeatureHubHeaderMode: Equatable, Sendable {
    case none
    case vehiclePicker
}

struct FeatureHubPresentation: Equatable, Sendable {
    let headerMode: FeatureHubHeaderMode
    let sections: [FeatureHubSection]
    let isAvailable: Bool

    init(state: DashboardState) {
        headerMode = state.cars.count > 1 && state.selectedCarId != nil ? .vehiclePicker : .none
        isAvailable = state.selectedCarId != nil
        sections = state.selectedCarId.map {
            FeatureHubCatalog.sections(carId: $0, exteriorColor: state.exteriorColor)
                .compactMap { section in
                    let items = section.items.filter { $0.id != "activities" }
                    guard !items.isEmpty else { return nil }
                    return FeatureHubSection(
                        id: section.id,
                        titleEnglish: section.titleEnglish,
                        titleChinese: section.titleChinese,
                        items: items
                    )
                }
        } ?? []
    }
}
