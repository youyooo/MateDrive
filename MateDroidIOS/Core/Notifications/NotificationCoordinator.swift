@preconcurrency import UserNotifications
import Foundation

public enum AppNotificationAuthorizationStatus: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    public var canDeliver: Bool {
        self == .authorized || self == .provisional || self == .ephemeral
    }
}

public protocol NotificationCoordinating: Sendable {
    func authorizationStatus() async -> AppNotificationAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func deliver(identifier: String, title: String, body: String, categoryIdentifier: String?) async throws
}

public extension NotificationCoordinating {
    func authorizationStatus() async -> AppNotificationAuthorizationStatus { .notDetermined }
}

public struct NotificationCoordinator: NotificationCoordinating, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func authorizationStatus() async -> AppNotificationAuthorizationStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        @unknown default: .notDetermined
        }
    }

    public func deliver(identifier: String, title: String, body: String, categoryIdentifier: String? = nil) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await center.add(request)
    }

    public func deliverCharging(_ content: ChargingNotificationContent, identifier: String) async throws {
        try await deliver(
            identifier: identifier,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier
        )
    }

    public func deliverSentry(_ content: SentryNotificationContent, identifier: String) async throws {
        try await deliver(
            identifier: identifier,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier
        )
    }

    public func deliverTyrePressure(_ content: TyrePressureNotificationContent, identifier: String) async throws {
        try await deliver(
            identifier: identifier,
            title: content.title,
            body: content.body,
            categoryIdentifier: content.categoryIdentifier
        )
    }
}
