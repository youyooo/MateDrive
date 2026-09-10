import Foundation

enum MateDriveFeature: String, CaseIterable, Sendable {
    case vehicleOverview
    case driveHistory
    case chargeHistory
    case batteryHealth
    case cloudBackup
    case advancedAnalytics

    var futureTier: FeatureAccessTier {
        switch self {
        case .vehicleOverview, .driveHistory, .chargeHistory:
            .free
        case .batteryHealth, .cloudBackup, .advancedAnalytics:
            .pro
        }
    }
}

enum FeatureAccessTier: Sendable {
    case free
    case pro
}

enum MonetizationLaunchMode: Sendable {
    case freeForEveryone
    case proEnabled
}

enum ProEntitlementStatus: Equatable, Sendable {
    case none
    case subscription
    case lifetime
}

struct ProEntitlementSnapshot: Equatable, Sendable {
    let hasLifetime: Bool
    let hasActiveSubscription: Bool

    static let none = ProEntitlementSnapshot(
        hasLifetime: false,
        hasActiveSubscription: false
    )

    init(hasLifetime: Bool = false, hasActiveSubscription: Bool = false) {
        self.hasLifetime = hasLifetime
        self.hasActiveSubscription = hasActiveSubscription
    }

    var status: ProEntitlementStatus {
        if hasLifetime {
            return .lifetime
        }
        return hasActiveSubscription ? .subscription : .none
    }
}

struct MonetizationPolicy: Sendable {
    static let firstRelease = MonetizationPolicy(launchMode: .freeForEveryone)

    let launchMode: MonetizationLaunchMode

    func canAccess(
        _ feature: MateDriveFeature,
        entitlement: ProEntitlementStatus
    ) -> Bool {
        guard launchMode == .proEnabled else {
            return true
        }
        guard feature.futureTier == .pro else {
            return true
        }
        return entitlement != .none
    }
}
