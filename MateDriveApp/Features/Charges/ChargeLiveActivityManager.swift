import ActivityKit
import Foundation

public struct ChargeLiveActivitySnapshot: Equatable, Sendable {
    public let carName: String
    public let batteryLevel: Int?
    public let chargeLimitSoc: Int?
    public let chargerPowerKW: Int?
    public let energyAddedKWh: Double?
    public let timeToFullMinutes: Int?
    public let isDC: Bool
    public let isCharging: Bool
    public let vehicleIdentifier: String?
    public let displayLanguage: WidgetDisplayLanguage
    public let quality: WidgetChargeDataQuality
    public let updatedAt: Date

    public init(
        carName: String = "MateDrive",
        batteryLevel: Int? = nil,
        chargeLimitSoc: Int? = nil,
        chargerPowerKW: Int? = nil,
        energyAddedKWh: Double? = nil,
        timeToFullMinutes: Int? = nil,
        isDC: Bool = false,
        isCharging: Bool = true,
        vehicleIdentifier: String? = nil,
        displayLanguage: WidgetDisplayLanguage = .system,
        quality: WidgetChargeDataQuality = .complete,
        updatedAt: Date = Date()
    ) {
        self.carName = carName
        self.batteryLevel = batteryLevel
        self.chargeLimitSoc = chargeLimitSoc
        self.chargerPowerKW = chargerPowerKW
        self.energyAddedKWh = energyAddedKWh
        self.timeToFullMinutes = timeToFullMinutes
        self.isDC = isDC
        self.isCharging = isCharging
        self.vehicleIdentifier = vehicleIdentifier
        self.displayLanguage = displayLanguage
        self.quality = quality
        self.updatedAt = updatedAt
    }

    public var staleDate: Date {
        updatedAt.addingTimeInterval(120)
    }

    var contentState: ChargeLiveActivityAttributes.ContentState {
        ChargeLiveActivityAttributes.ContentState(
            batteryLevel: batteryLevel,
            chargeLimitSoc: chargeLimitSoc,
            chargerPowerKW: chargerPowerKW,
            energyAddedKWh: energyAddedKWh,
            timeToFullMinutes: timeToFullMinutes,
            isDC: isDC,
            isCharging: isCharging,
            displayLanguage: displayLanguage,
            quality: quality,
            updatedAt: updatedAt
        )
    }
}

public protocol ChargeLiveActivityManaging: Sendable {
    func update(carId: Int, snapshot: ChargeLiveActivitySnapshot) async
    func updateExisting(carId: Int, snapshot: ChargeLiveActivitySnapshot) async
    func end(carId: Int) async
    func end(carId: Int, vehicleIdentifier: String?) async
}

public extension ChargeLiveActivityManaging {
    func end(carId: Int, vehicleIdentifier: String?) async {
        guard vehicleIdentifier == nil else { return }
        await end(carId: carId)
    }
}

public struct DisabledChargeLiveActivityManager: ChargeLiveActivityManaging {
    public init() {}
    public func update(carId _: Int, snapshot _: ChargeLiveActivitySnapshot) async {}
    public func updateExisting(carId _: Int, snapshot _: ChargeLiveActivitySnapshot) async {}
    public func end(carId _: Int) async {}
    public func end(carId _: Int, vehicleIdentifier _: String?) async {}
}

struct ChargeLiveActivityReference: Equatable, Sendable {
    let id: String
    let carID: Int?
    let vehicleIdentifier: String?
}

protocol ChargeLiveActivityGateway: Sendable {
    var areActivitiesEnabled: Bool { get }

    func activityReferences() -> [ChargeLiveActivityReference]
    func request(
        attributes: ChargeLiveActivityAttributes,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) throws
    func update(
        activityID: String,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) async
    func end(
        activityID: String,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) async
}

private struct ActivityKitChargeLiveActivityGateway: ChargeLiveActivityGateway {
    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func activityReferences() -> [ChargeLiveActivityReference] {
        Activity<ChargeLiveActivityAttributes>.activities.map { activity in
            ChargeLiveActivityReference(
                id: activity.id,
                carID: activity.attributes.carID,
                vehicleIdentifier: activity.attributes.vehicleIdentifier
            )
        }
    }

    func request(
        attributes: ChargeLiveActivityAttributes,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) throws {
        _ = try Activity<ChargeLiveActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    func update(
        activityID: String,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<ChargeLiveActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return }
        await activity.update(content)
    }

    func end(
        activityID: String,
        content: ActivityContent<ChargeLiveActivityAttributes.ContentState>
    ) async {
        guard let activity = Activity<ChargeLiveActivityAttributes>.activities.first(where: {
            $0.id == activityID
        }) else { return }
        await activity.end(content, dismissalPolicy: .immediate)
    }
}

public actor SystemChargeLiveActivityManager: ChargeLiveActivityManaging {
    public static let shared = SystemChargeLiveActivityManager()
    private let gateway: any ChargeLiveActivityGateway

    public init() {
        gateway = ActivityKitChargeLiveActivityGateway()
    }

    init(gateway: any ChargeLiveActivityGateway) {
        self.gateway = gateway
    }

    public func update(carId: Int, snapshot: ChargeLiveActivitySnapshot) async {
        guard gateway.areActivitiesEnabled, snapshot.isCharging else {
            await end(
                carId: carId,
                vehicleIdentifier: snapshot.vehicleIdentifier
            )
            return
        }

        let content = ActivityContent(
            state: snapshot.contentState,
            staleDate: snapshot.staleDate
        )
        if let activity = activity(
            for: carId,
            vehicleIdentifier: snapshot.vehicleIdentifier
        ) {
            await gateway.update(activityID: activity.id, content: content)
            return
        }

        guard let vehicleIdentifier = snapshot.vehicleIdentifier,
              WidgetVehicleIdentity.isCanonicalIdentifier(vehicleIdentifier)
        else { return }

        do {
            try gateway.request(
                attributes: ChargeLiveActivityAttributes(
                    carName: snapshot.carName,
                    vehicleIdentifier: vehicleIdentifier
                ),
                content: content
            )
        } catch {
            return
        }
    }

    public func updateExisting(carId: Int, snapshot: ChargeLiveActivitySnapshot) async {
        guard gateway.areActivitiesEnabled,
              snapshot.isCharging,
              let activity = activity(
                  for: carId,
                  vehicleIdentifier: snapshot.vehicleIdentifier
              )
        else { return }

        await gateway.update(activityID: activity.id, content: ActivityContent(
            state: snapshot.contentState,
            staleDate: snapshot.staleDate
        ))
    }

    public func end(carId: Int) async {
        await end(carId: carId, vehicleIdentifier: nil)
    }

    public func end(carId: Int, vehicleIdentifier: String?) async {
        let finalState = ChargeLiveActivityAttributes.ContentState(isCharging: false)
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        let matches = gateway.activityReferences().filter {
            self.matches(
                $0,
                carId: carId,
                vehicleIdentifier: vehicleIdentifier
            )
        }
        for activity in matches {
            await gateway.end(activityID: activity.id, content: finalContent)
        }
    }

    private func activity(
        for carId: Int,
        vehicleIdentifier: String?
    ) -> ChargeLiveActivityReference? {
        gateway.activityReferences().first {
            matches(
                $0,
                carId: carId,
                vehicleIdentifier: vehicleIdentifier
            )
        }
    }

    private func matches(
        _ activity: ChargeLiveActivityReference,
        carId: Int,
        vehicleIdentifier: String?
    ) -> Bool {
        if let vehicleIdentifier {
            return activity.vehicleIdentifier == vehicleIdentifier
        }
        return activity.vehicleIdentifier == nil && activity.carID == carId
    }
}
