import SwiftUI

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .system
}

public extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}
