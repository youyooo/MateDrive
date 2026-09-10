public enum ChargeLiveActivityActivationPolicy: Equatable, Sendable {
    case allowStart
    case existingOnly
}

public enum ChargeLiveActivityEvent: Equatable, Sendable {
    case charging(ChargeLiveActivitySnapshot)
    case idle(vehicleIdentifier: String?)
    case indeterminate
}

public enum ChargeLiveActivityEventFactory {
    public static func event(
        currentCharge: WidgetCurrentChargeData?,
        carName: String,
        vehicleIdentifier: String,
        displayLanguage: WidgetDisplayLanguage
    ) -> ChargeLiveActivityEvent {
        guard let currentCharge else { return .indeterminate }
        guard currentCharge.quality != .offline else { return .indeterminate }
        guard currentCharge.phase != .idle else {
            return .idle(vehicleIdentifier: vehicleIdentifier)
        }
        return .charging(ChargeLiveActivitySnapshot(
            carName: carName,
            batteryLevel: currentCharge.batteryLevel,
            chargeLimitSoc: currentCharge.chargeLimitSoc,
            chargerPowerKW: currentCharge.chargerPowerKW,
            energyAddedKWh: currentCharge.energyAddedKWh,
            timeToFullMinutes: currentCharge.timeToFullMinutes,
            isDC: currentCharge.isDC == true,
            isCharging: true,
            vehicleIdentifier: vehicleIdentifier,
            displayLanguage: displayLanguage,
            quality: currentCharge.quality,
            updatedAt: currentCharge.updatedAt
        ))
    }
}

public struct ChargeLiveActivityCoordinator: Sendable {
    private let manager: any ChargeLiveActivityManaging

    public static let disabled = ChargeLiveActivityCoordinator(
        manager: DisabledChargeLiveActivityManager()
    )

    public init(manager: any ChargeLiveActivityManaging) {
        self.manager = manager
    }

    public func reconcile(
        carId: Int,
        event: ChargeLiveActivityEvent,
        policy: ChargeLiveActivityActivationPolicy
    ) async {
        switch (event, policy) {
        case let (.charging(snapshot), .allowStart):
            await manager.update(carId: carId, snapshot: snapshot)
        case let (.charging(snapshot), .existingOnly):
            await manager.updateExisting(carId: carId, snapshot: snapshot)
        case let (.idle(vehicleIdentifier), _):
            await manager.end(
                carId: carId,
                vehicleIdentifier: vehicleIdentifier
            )
        case (.indeterminate, _):
            return
        }
    }
}
