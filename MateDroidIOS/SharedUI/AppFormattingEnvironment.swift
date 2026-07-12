import SwiftUI

private struct AppDisplayUnitSystemKey: EnvironmentKey {
    static let defaultValue = DisplayUnitSystem.teslamate
}

public extension EnvironmentValues {
    var appDisplayUnitSystem: DisplayUnitSystem {
        get { self[AppDisplayUnitSystemKey.self] }
        set { self[AppDisplayUnitSystemKey.self] = newValue }
    }
}
