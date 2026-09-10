import SwiftUI
import WidgetKit

@main
struct MateDriveWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarStatusWidget()
        BatteryTrendWidget()
        ChargingTrendWidget()
        CurrentChargeWidget()
        ChargeLiveActivityWidget()
    }
}
