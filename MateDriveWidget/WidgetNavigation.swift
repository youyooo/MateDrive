import Foundation

public enum MateDriveWidgetDestination: String, Codable, Equatable, Sendable {
    case dashboard
    case currentCharge = "current-charge"
    case battery
    case charges
}

public struct MateDriveWidgetRequest: Codable, Equatable, Sendable {
    public let destination: MateDriveWidgetDestination
    public let vehicleIdentifier: String?

    public init(
        destination: MateDriveWidgetDestination,
        vehicleIdentifier: String?
    ) {
        self.destination = destination
        self.vehicleIdentifier = vehicleIdentifier
    }
}

public enum MateDriveWidgetNavigation {
    public static func widgetURL(
        destination: MateDriveWidgetDestination,
        snapshotVehicleIdentifier: String?
    ) -> URL? {
        guard let snapshotVehicleIdentifier else { return nil }
        return url(
            destination: destination,
            vehicleIdentifier: snapshotVehicleIdentifier
        )
    }

    public static func url(
        destination: MateDriveWidgetDestination,
        vehicleIdentifier: String?
    ) -> URL? {
        if let vehicleIdentifier,
           !WidgetVehicleIdentity.isCanonicalIdentifier(vehicleIdentifier) {
            return nil
        }

        var components = URLComponents()
        components.scheme = "matedrive"
        components.host = "widget"
        components.path = "/\(destination.rawValue)"
        if let vehicleIdentifier {
            components.queryItems = [URLQueryItem(name: "vehicle", value: vehicleIdentifier)]
        }
        return components.url
    }

    public static func parse(_ url: URL) -> MateDriveWidgetRequest? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "matedrive",
              components.host == "widget",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              components.percentEncodedPath == components.path,
              components.path.first == "/",
              let destination = MateDriveWidgetDestination(
                rawValue: String(components.path.dropFirst())
              )
        else { return nil }

        let vehicleIdentifier: String?
        if let queryItems = components.queryItems {
            guard queryItems.count == 1,
                  queryItems[0].name == "vehicle",
                  let value = queryItems[0].value,
                  WidgetVehicleIdentity.isCanonicalIdentifier(value),
                  components.percentEncodedQuery == "vehicle=\(value)"
            else { return nil }
            vehicleIdentifier = value
        } else {
            vehicleIdentifier = nil
        }
        let request = MateDriveWidgetRequest(
            destination: destination,
            vehicleIdentifier: vehicleIdentifier
        )
        guard self.url(
            destination: destination,
            vehicleIdentifier: vehicleIdentifier
        )?.absoluteString == url.absoluteString else { return nil }
        return request
    }
}
