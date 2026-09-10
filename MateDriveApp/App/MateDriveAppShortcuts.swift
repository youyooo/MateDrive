import AppIntents
import Foundation

public enum MateDriveShortcutDestination: String, AppEnum, Codable, CaseIterable, Sendable {
    case dashboard
    case currentCharge
    case charges
    case drives
    case activities

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "MateDrive Page"
    public static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .dashboard: "MateDrive",
        .currentCharge: "Current Charge",
        .charges: "Charges",
        .drives: "Drives",
        .activities: "Activities"
    ]
}

public struct OpenMateDriveIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open MateDrive Page"
    public static let description = IntentDescription("Opens a selected MateDrive page for the current vehicle.")
    public static let openAppWhenRun = true

    @Parameter(title: "Page")
    public var destination: MateDriveShortcutDestination

    public static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$destination)")
    }

    public init() {
        destination = .dashboard
    }

    public init(destination: MateDriveShortcutDestination) {
        self.destination = destination
    }

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            PendingShortcutNavigationStore.live.store(destination)
            NotificationCenter.default.post(name: .mateDriveShortcutNavigationRequested, object: nil)
        }
        return .result()
    }
}

public struct MateDriveAppShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenMateDriveIntent(destination: .dashboard),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "MateDrive",
            systemImageName: "car.fill"
        )
        AppShortcut(
            intent: OpenMateDriveIntent(destination: .currentCharge),
            phrases: ["Open current charge in \(.applicationName)"],
            shortTitle: "Current Charge",
            systemImageName: "bolt.car.fill"
        )
        AppShortcut(
            intent: OpenMateDriveIntent(destination: .charges),
            phrases: ["Open charging history in \(.applicationName)"],
            shortTitle: "Charges",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: OpenMateDriveIntent(destination: .drives),
            phrases: ["Open drive history in \(.applicationName)"],
            shortTitle: "Drives",
            systemImageName: "road.lanes"
        )
        AppShortcut(
            intent: OpenMateDriveIntent(destination: .activities),
            phrases: ["Open activities in \(.applicationName)"],
            shortTitle: "Activities",
            systemImageName: "clock.arrow.circlepath"
        )
    }

    public static let shortcutTileColor: ShortcutTileColor = .lime
}

@MainActor
public struct PendingShortcutNavigationStore {
    public static let live = PendingShortcutNavigationStore(
        defaults: UserDefaults(suiteName: WidgetConstants.appGroupIdentifier) ?? .standard
    )

    private static let destinationKey = "matedrive.pendingShortcutDestination"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func store(_ destination: MateDriveShortcutDestination) {
        defaults.set(destination.rawValue, forKey: Self.destinationKey)
    }

    public func consume() -> MateDriveShortcutDestination? {
        guard let rawValue = defaults.string(forKey: Self.destinationKey),
              let destination = MateDriveShortcutDestination(rawValue: rawValue)
        else {
            defaults.removeObject(forKey: Self.destinationKey)
            return nil
        }
        defaults.removeObject(forKey: Self.destinationKey)
        return destination
    }
}

public enum MateDriveShortcutRouter {
    public static func route(
        destination: MateDriveShortcutDestination,
        settings: AppSettings,
        fallbackCarId: Int? = nil
    ) -> AppRoute {
        guard settings.isConfigured else { return .settings }
        guard destination != .dashboard else { return .dashboard }
        guard let carId = settings.lastSelectedCarId ?? fallbackCarId else { return .dashboard }

        switch destination {
        case .dashboard:
            return .dashboard
        case .currentCharge:
            return .currentCharge(carId: carId, exteriorColor: nil)
        case .charges:
            return .charges(carId: carId, exteriorColor: nil)
        case .drives:
            return .drives(carId: carId, exteriorColor: nil)
        case .activities:
            return .activities(carId: carId, exteriorColor: nil)
        }
    }
}

public extension Notification.Name {
    static let mateDriveShortcutNavigationRequested = Notification.Name(
        "com.matedrive.ios.shortcut-navigation-requested"
    )
}
