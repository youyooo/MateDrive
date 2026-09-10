import Foundation

public final class WidgetNavigationVehicleRegistry: @unchecked Sendable {
    public static let shared = WidgetNavigationVehicleRegistry()

    private static let lock = NSLock()
    private static let storageKey = "MateDrive.WidgetNavigationVehicleRegistry.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func replace(serverURL: String, carIDs: [Int]) {
        guard let serverIdentity = Self.serverIdentity(for: serverURL) else { return }
        Self.lock.withLock {
            var records = recordsLocked()
            records[serverIdentity] = Array(Set(carIDs)).sorted()
            defaults.set(records, forKey: Self.storageKey)
        }
    }

    public func resolve(serverURL: String, vehicleIdentifier: String) -> Int? {
        guard let serverIdentity = Self.serverIdentity(for: serverURL) else { return nil }
        return Self.lock.withLock {
            let carIDs = recordsLocked()[serverIdentity] ?? []
            return carIDs.first {
                WidgetVehicleIdentity.identifier(serverURL: serverURL, carID: $0)
                    == vehicleIdentifier
            }
        }
    }

    private func recordsLocked() -> [String: [Int]] {
        guard let rawRecords = defaults.dictionary(forKey: Self.storageKey) else {
            return [:]
        }
        return rawRecords.reduce(into: [:]) { result, element in
            if let carIDs = element.value as? [Int] {
                result[element.key] = carIDs
            } else if let numbers = element.value as? [NSNumber] {
                result[element.key] = numbers.map(\.intValue)
            }
        }
    }

    private static func serverIdentity(for serverURL: String) -> String? {
        let normalized = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized),
              let scheme = url.scheme,
              !scheme.isEmpty,
              let host = url.host,
              !host.isEmpty
        else { return nil }
        return TeslaMateServerIdentity.key(for: url)
    }
}

public enum WidgetNavigationRouter {
    public static func route(
        request: MateDriveWidgetRequest,
        settings: AppSettings,
        resolvedCarID: Int?,
        fallbackCarID: Int?
    ) -> AppRoute {
        guard settings.isConfigured else { return .settings }
        guard request.destination != .dashboard else { return .dashboard }
        guard let carID = resolvedCarID ?? settings.lastSelectedCarId ?? fallbackCarID else {
            return .dashboard
        }

        switch request.destination {
        case .dashboard:
            return .dashboard
        case .currentCharge:
            return .currentCharge(carId: carID, exteriorColor: nil)
        case .battery:
            return .battery(carId: carID, efficiency: nil, exteriorColor: nil)
        case .charges:
            return .charges(carId: carID, exteriorColor: nil)
        }
    }
}
