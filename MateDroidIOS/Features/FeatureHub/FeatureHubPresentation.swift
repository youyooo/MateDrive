import Foundation

struct FeatureHubPresentation: Equatable, Sendable {
    let vehicleName: String
    let showsVehiclePicker: Bool
    let sections: [FeatureHubSection]
    let isAvailable: Bool

    init(state: DashboardState) {
        vehicleName = state.carName
        showsVehiclePicker = state.cars.count > 1 && state.selectedCarId != nil
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
